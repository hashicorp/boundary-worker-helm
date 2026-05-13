#!/bin/bash
# Copyright IBM Corp. 2026
# ============================================================================
# AKS Integration Test — Boundary Worker Helm Chart
#
# Validates that the Boundary Worker Helm chart is correctly installed and
# functioning on an Azure AKS cluster. The chart must be pre-installed via
# 'make aks-helm' before running this script.
#
# Required env vars:
#   AZURE_LOCATION          - Azure region (e.g. eastus)
#   AZURE_RESOURCE_GROUP    - Resource group containing the AKS cluster
#   AKS_CLUSTER_NAME        - Name of the AKS cluster
#   BOUNDARY_ADDR           - Boundary controller/cluster address
#   BOUNDARY_AUTH_METHOD_ID - Auth method ID (ampw_...)
#   BOUNDARY_LOGIN_NAME     - Login name for authentication
#   BOUNDARY_PASSWORD       - Login password
#
# Optional env vars:
#   BOUNDARY_TARGET_ID      - Target ID to validate TCP session (skipped if unset)
#   SKIP_CLEANUP            - Set to "true" to leave resources after test
#   HELM_RELEASE            - Helm release name (default: boundary-worker)
#   K8S_NAMESPACE           - Kubernetes namespace  (default: boundary)
#   WORKER_DEPLOY           - Deployment name       (default: boundary-worker-deployment)
#   WAIT_TIMEOUT            - Readiness wait (sec)  (default: 300)
#   LB_TIMEOUT              - Azure LB provisioning wait (sec) (default: 300)
# ============================================================================

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
pass()    { echo "     ✅ $1"; }
fail()    { echo "  ❌ FAILED: $1"; exit 1; }
info()    { echo "     ℹ  $1"; }
warn()    { echo "     ⚠️  $1"; }
section() {
    echo ""
    echo "  ▶ $1"
    echo "  $(printf '─%.0s' {1..50})"
}

# ── Config ────────────────────────────────────────────────────────────────────
: "${AZURE_LOCATION:?'AZURE_LOCATION must be set'}"
: "${AZURE_RESOURCE_GROUP:?'AZURE_RESOURCE_GROUP must be set'}"
: "${AKS_CLUSTER_NAME:?'AKS_CLUSTER_NAME must be set'}"
: "${BOUNDARY_ADDR:?'BOUNDARY_ADDR must be set'}"
: "${BOUNDARY_AUTH_METHOD_ID:?'BOUNDARY_AUTH_METHOD_ID must be set'}"
: "${BOUNDARY_LOGIN_NAME:?'BOUNDARY_LOGIN_NAME must be set'}"
: "${BOUNDARY_PASSWORD:?'BOUNDARY_PASSWORD must be set'}"

SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
HELM_RELEASE="${HELM_RELEASE:-boundary-worker}"
NAMESPACE="${K8S_NAMESPACE:-boundary}"
DEPLOY="${WORKER_DEPLOY:-boundary-worker-deployment}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
LB_TIMEOUT="${LB_TIMEOUT:-300}"

# AKS context is the cluster name (set by az aks get-credentials)
AKS_CONTEXT="${AKS_CLUSTER_NAME}"

# Overall test tracking
TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

record_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); pass "$1"; }
record_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
    echo "     ❌ FAILED: $1"
}

# ── Cleanup trap ─────────────────────────────────────────────────────────────
_cleanup() {
    # Kill any background port-forward processes
    pkill -f "kubectl port-forward.*9203" 2>/dev/null || true

    if [[ "${SKIP_CLEANUP}" == "true" ]]; then
        warn "SKIP_CLEANUP=true — leaving namespace '${NAMESPACE}' in place"
        return
    fi
    section "Cleanup"
    info "Uninstalling Helm release '${HELM_RELEASE}'..."
    helm uninstall "${HELM_RELEASE}" \
        --namespace "${NAMESPACE}" \
        --kube-context "${AKS_CONTEXT}" \
        --wait --timeout 5m 2>/dev/null \
        | sed 's/^/     /' || true
    kubectl delete namespace "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" \
        --ignore-not-found 2>/dev/null \
        | sed 's/^/     /' || true
    info "Cleanup complete"
}
trap _cleanup EXIT


# Prerequisites
section "Prerequisites..."

for tool in kubectl helm az boundary; do
    if command -v "$tool" >/dev/null 2>&1; then
        record_pass "Tool available: $tool"
    else
        fail "'$tool' is not installed"
    fi
done
pass "Required env vars are set"

# Azure Subscription / Login Check
section "Azure Authentication..."

AZ_ACCOUNT=$(az account show --query "{subscriptionId:id,name:name}" -o json 2>/dev/null) \
    || fail "Azure credentials not configured. Run 'az login' or set AZURE_CLIENT_ID/AZURE_CLIENT_SECRET/AZURE_TENANT_ID."

SUBSCRIPTION_ID=$(printf '%s\n' "${AZ_ACCOUNT}" | python3 -c "import json,sys; print(json.load(sys.stdin)['subscriptionId'])")
SUBSCRIPTION_NAME=$(printf '%s\n' "${AZ_ACCOUNT}" | python3 -c "import json,sys; print(json.load(sys.stdin)['name'])")
record_pass "Authenticated to Azure subscription: ${SUBSCRIPTION_NAME} (${SUBSCRIPTION_ID})"

# AKS Cluster Accessibility
section "AKS Cluster Accessibility..."

info "Fetching credentials for cluster '${AKS_CLUSTER_NAME}'..."
az aks get-credentials \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --name "${AKS_CLUSTER_NAME}" \
    --overwrite-existing >/dev/null 2>&1 \
    || fail "Failed to fetch credentials for '${AKS_CLUSTER_NAME}' in resource group '${AZURE_RESOURCE_GROUP}'"

kubectl cluster-info --context "${AKS_CONTEXT}" >/dev/null 2>&1 \
    && record_pass "AKS cluster '${AKS_CLUSTER_NAME}' is accessible" \
    || { record_fail "AKS cluster '${AKS_CLUSTER_NAME}' is not accessible"; exit 1; }

NODE_COUNT=$(kubectl get nodes --context "${AKS_CONTEXT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${NODE_COUNT}" -gt 0 ] \
    && record_pass "Cluster has ${NODE_COUNT} node(s)" \
    || { record_fail "No nodes found in cluster"; exit 1; }

READY_NODES=$(kubectl get nodes --context "${AKS_CONTEXT}" \
    --no-headers 2>/dev/null | grep -c " Ready" || true)
[ "${READY_NODES}" -eq "${NODE_COUNT}" ] \
    && record_pass "All ${READY_NODES}/${NODE_COUNT} nodes are Ready" \
    || warn "${READY_NODES}/${NODE_COUNT} nodes are Ready"


# Required Add-ons / Built-in Controllers
section "AKS Add-ons..."

# Azure Disk CSI driver (built-in since AKS 1.21, runs as csi-azuredisk-node DaemonSet)
if kubectl get daemonset csi-azuredisk-node \
        -n kube-system --context "${AKS_CONTEXT}" >/dev/null 2>&1; then
    record_pass "Azure Disk CSI driver is running"
else
    warn "Azure Disk CSI DaemonSet not found — ensure AKS version >= 1.21"
fi

# Azure Load Balancer integration is built into AKS (cloud-controller-manager).
# Validate the cloud-node-manager is healthy as a proxy for LB readiness.
if kubectl get daemonset cloud-node-manager \
        -n kube-system --context "${AKS_CONTEXT}" >/dev/null 2>&1; then
    record_pass "Azure cloud-node-manager is running (Load Balancer support active)"
else
    warn "cloud-node-manager DaemonSet not found — Load Balancer provisioning may be impaired"
fi

# managed-csi-premium StorageClass (created by Terraform, analogous to gp3 on EKS)
STORAGE_CLASS="${TF_STORAGE_CLASS_NAME:-managed-csi-premium}"
if kubectl get storageclass "${STORAGE_CLASS}" --context "${AKS_CONTEXT}" >/dev/null 2>&1; then
    record_pass "StorageClass '${STORAGE_CLASS}' is available"
else
    fail "StorageClass '${STORAGE_CLASS}' not found. Run 'make aks-setup' first."
fi

# Verify Helm release is present (installed by make aks-helm)
helm status "${HELM_RELEASE}" -n "${NAMESPACE}" \
    --kube-context "${AKS_CONTEXT}" >/dev/null 2>&1 \
    || fail "Release '${HELM_RELEASE}' not found. Run 'make aks-helm' first."


# Deployment Readiness
section "Deployment Readiness..."

info "Waiting for deployment '${DEPLOY}' (timeout: ${WAIT_TIMEOUT}s)..."
kubectl wait --for=condition=available \
    --timeout="${WAIT_TIMEOUT}s" \
    deployment/"${DEPLOY}" \
    -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" >/dev/null 2>&1 \
    && record_pass "Deployment '${DEPLOY}' is available" \
    || { record_fail "Deployment '${DEPLOY}' did not become available"; exit 1; }

POD=$(kubectl get pods \
    -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" \
    -l app.kubernetes.io/name=boundary-worker \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

[ -n "${POD}" ] \
    && record_pass "Worker pod running: ${POD}" \
    || { record_fail "No running worker pod found"; exit 1; }


# PersistentVolumeClaims
section "PersistentVolumeClaims..."

PVC_COUNT=$(kubectl get pvc -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')

if [ "${PVC_COUNT}" -gt 0 ]; then
    record_pass "${PVC_COUNT} PVC(s) found"
    UNBOUND=$(kubectl get pvc -n "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" --no-headers 2>/dev/null \
        | (grep -v "Bound" || true) | wc -l | tr -d ' ')
    [ "${UNBOUND}" -eq 0 ] \
        && record_pass "All PVCs are Bound" \
        || { record_fail "${UNBOUND} PVC(s) are not Bound"; kubectl get pvc -n "${NAMESPACE}" --context "${AKS_CONTEXT}"; }

    # Verify the expected StorageClass is used
    SC_PVCS=$(kubectl get pvc -n "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" \
        -o jsonpath='{range .items[*]}{.spec.storageClassName}{"\n"}{end}' 2>/dev/null \
        | grep -c "^${STORAGE_CLASS}$" || true)
    [ "${SC_PVCS}" -gt 0 ] \
        && record_pass "${SC_PVCS} PVC(s) use StorageClass '${STORAGE_CLASS}'" \
        || warn "No PVCs found using '${STORAGE_CLASS}' — check storageClass configuration"
else
    warn "No PVCs found (persistence may be disabled)"
fi


# Azure Load Balancer Provisioning
# Unlike AWS NLBs (which use hostnames), Azure external Load Balancers expose
# an IP address via status.loadBalancer.ingress[0].ip.
section "Azure Load Balancer Provisioning..."

info "Waiting for Load Balancer IP to be assigned (timeout: ${LB_TIMEOUT}s)..."
LB_IP=""
ELAPSED=0
INTERVAL=15
while [ "${ELAPSED}" -lt "${LB_TIMEOUT}" ]; do
    LB_IP=$(kubectl get svc \
        -n "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" \
        -l app.kubernetes.io/name=boundary-worker \
        -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' \
        2>/dev/null || true)
    if [ -n "${LB_IP}" ]; then break; fi
    info "Waiting for Load Balancer IP... (${ELAPSED}s elapsed)"
    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ -n "${LB_IP}" ]; then
    record_pass "Azure Load Balancer provisioned: ${LB_IP}"
    # Verify the service type
    LB_SVC_COUNT=$(kubectl get svc \
        -n "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" \
        -l app.kubernetes.io/name=boundary-worker \
        -o jsonpath='{range .items[*]}{.spec.type}{"\n"}{end}' 2>/dev/null \
        | grep -c "^LoadBalancer$" || true)
    [ "${LB_SVC_COUNT}" -gt 0 ] \
        && record_pass "${LB_SVC_COUNT} LoadBalancer service(s) found" \
        || warn "No LoadBalancer-type service found"
else
    record_fail "Azure Load Balancer IP not assigned within ${LB_TIMEOUT}s"
    kubectl get svc -n "${NAMESPACE}" --context "${AKS_CONTEXT}"
fi


# Ops Health Endpoint
section "Ops Health Endpoint (port 9203)..."

pkill -f "kubectl port-forward.*9203" 2>/dev/null || true
sleep 1

kubectl port-forward \
    -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" \
    "pod/${POD}" 9203:9203 >/dev/null 2>&1 &
PF_PID=$!

# Poll until the port-forward is ready (max 15s)
HEALTH_OK=false
for _i in $(seq 1 15); do
    if curl -sf --max-time 1 http://localhost:9203/health >/dev/null 2>&1; then
        HEALTH_OK=true
        break
    fi
    sleep 1
done
kill "${PF_PID}" 2>/dev/null || true
wait "${PF_PID}" 2>/dev/null || true

${HEALTH_OK} \
    && record_pass "Ops /health endpoint returned 200" \
    || record_fail "Ops /health endpoint did not return 200"


# Helm Chart Tests
section "Helm Chart Tests..."

info "Cleaning stale test pods..."
kubectl delete pods \
    -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" \
    -l app.kubernetes.io/component=test \
    --field-selector=status.phase=Failed \
    --ignore-not-found 2>/dev/null \
    | sed 's/^/     /' || true

info "Running: helm test ${HELM_RELEASE}..."
helm test "${HELM_RELEASE}" \
    --namespace "${NAMESPACE}" \
    --kube-context "${AKS_CONTEXT}" \
    --timeout 10m \
    | sed 's/^/     /' || true

FAILED_HELM_TESTS=$(kubectl get pods \
    -n "${NAMESPACE}" \
    --context "${AKS_CONTEXT}" \
    -l app.kubernetes.io/component=test \
    --field-selector=status.phase=Failed \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

if [ -z "${FAILED_HELM_TESTS}" ]; then
    record_pass "All Helm tests passed"
else
    record_fail "Helm tests failed: $(echo "${FAILED_HELM_TESTS}" | tr '\n' ' ')"
fi


# Boundary Worker Registration
section "Boundary Worker Registration..."

info "Authenticating with Boundary cluster: ${BOUNDARY_ADDR}"
AUTH_OUT=$(boundary authenticate password \
    -addr "${BOUNDARY_ADDR}" \
    -auth-method-id "${BOUNDARY_AUTH_METHOD_ID}" \
    -login-name "${BOUNDARY_LOGIN_NAME}" \
    -password env://BOUNDARY_PASSWORD \
    -keyring-type=none 2>&1) \
    || fail "Boundary authentication failed:\n${AUTH_OUT}"

BOUNDARY_TOKEN=$(printf '%s\n' "${AUTH_OUT}" \
    | awk '/The token is:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
[ -n "${BOUNDARY_TOKEN}" ] || fail "Failed to extract auth token"
export BOUNDARY_TOKEN
record_pass "Authenticated with Boundary cluster"

# Check auth storage (node enrollment initiated)
AUTH_FILES=$(kubectl exec -n "${NAMESPACE}" "${POD}" \
    --context "${AKS_CONTEXT}" \
    -- find /var/lib/boundary -type f 2>/dev/null | wc -l | tr -d ' ') || AUTH_FILES=0

[ "${AUTH_FILES}" -gt 0 ] \
    && record_pass "Auth storage populated (${AUTH_FILES} file(s)) — node enrollment initiated" \
    || warn "Auth storage empty — worker may not have completed enrollment yet"

# Confirm worker record in Boundary
WORKERS_JSON=$(boundary workers list \
    -scope-id global \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN \
    -format json 2>&1) || fail "Failed to list workers: ${WORKERS_JSON}"

REGISTERED_WORKER_ID=$(printf '%s\n' "${WORKERS_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data.get('items', []):
    tags = w.get('canonical_tags', {}).get('type', [])
    if 'test' in tags and w.get('address'):
        print(w.get('id', ''))
        break
" 2>/dev/null || true)

[ -n "${REGISTERED_WORKER_ID}" ] \
    && record_pass "Worker registered in Boundary: ${REGISTERED_WORKER_ID}" \
    || record_fail "No worker with 'test' tag found in Boundary — activation token may not have been consumed yet"

# Verify upstream connection attempt in logs
if kubectl logs "${POD}" \
        -n "${NAMESPACE}" \
        --context "${AKS_CONTEXT}" 2>/dev/null \
        | grep -qE "Setting HCP Boundary cluster address|upstream.*address|upstreamDialerFunc"; then
    record_pass "Worker is attempting upstream connection to Boundary cluster"
fi


# TCP Session (optional — requires BOUNDARY_TARGET_ID)
section "TCP Session Validation..."

if [ -z "${BOUNDARY_TARGET_ID:-}" ]; then
    warn "BOUNDARY_TARGET_ID not set — skipping TCP session test"
else
    info "Authorizing session to target: ${BOUNDARY_TARGET_ID}"
    SESSION_OUT=$(boundary targets authorize-session \
        -id "${BOUNDARY_TARGET_ID}" \
        -addr "${BOUNDARY_ADDR}" \
        -token env://BOUNDARY_TOKEN \
        -format json 2>&1) \
        || fail "authorize-session failed:\n${SESSION_OUT}"

    SESSION_ID=$(printf '%s\n' "${SESSION_OUT}" \
        | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
    [ -n "${SESSION_ID}" ] \
        && record_pass "Session authorized: ${SESSION_ID}" \
        || record_fail "Failed to extract session_id from authorize-session response"

    info "Establishing proxy connection..."
    CONN_OUT=$(mktemp)
    boundary connect \
        -target-id "${BOUNDARY_TARGET_ID}" \
        -addr "${BOUNDARY_ADDR}" \
        -token env://BOUNDARY_TOKEN > "${CONN_OUT}" 2>&1 &
    CONN_PID=$!
    sleep 5

    if kill -0 "${CONN_PID}" 2>/dev/null; then
        record_pass "TCP proxy connection established"

        # Gracefully cancel the session on the controller before killing the proxy
        if [ -n "${SESSION_ID:-}" ]; then
            info "Cancelling session ${SESSION_ID} on Boundary controller..."
            boundary sessions cancel \
                -id "${SESSION_ID}" \
                -addr "${BOUNDARY_ADDR}" \
                -token env://BOUNDARY_TOKEN \
                -format json > /dev/null 2>&1 && \
                record_pass "Session ${SESSION_ID} cancelled gracefully" || \
                warn "Session cancel request failed (session may self-expire)"
        fi

        kill "${CONN_PID}" 2>/dev/null || true
        wait "${CONN_PID}" 2>/dev/null || true
    else
        record_fail "TCP proxy connection failed"
        cat "${CONN_OUT}" || true
    fi
    rm -f "${CONN_OUT}"
fi


# Results Summary
section "Test Results"

echo ""
echo "  AKS Cluster:        ${AKS_CLUSTER_NAME} (${AZURE_LOCATION})"
echo "  Resource Group:     ${AZURE_RESOURCE_GROUP}"
echo "  Helm Release:       ${HELM_RELEASE} / ${NAMESPACE}"
echo "  Worker Pod:         ${POD:-unknown}"
[ -n "${LB_IP:-}" ] && echo "  Load Balancer IP:   ${LB_IP}"
echo ""
echo "  Tests Passed: ${TESTS_PASSED}"
if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo "  Tests Failed: ${TESTS_FAILED}"
    echo ""
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "     ✗ ${t}"
    done
    echo ""
    exit 1
else
    echo ""
    echo "  ✅ All AKS integration tests passed!"
fi
