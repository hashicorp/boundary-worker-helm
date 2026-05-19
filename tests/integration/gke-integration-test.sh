#!/bin/bash
# Copyright IBM Corp. 2026
# ============================================================================
# GKE Integration Test - Boundary Worker Helm Chart
#
# Validates that the Boundary Worker Helm chart is correctly installed and
# functioning on a Google Kubernetes Engine (GKE) cluster. The chart must be
# pre-installed via 'make gke-helm' before running this script.
#
# Required env vars:
#   GCP_PROJECT_ID          - GCP project ID
#   GCP_REGION              - GCP region (e.g. us-central1)
#   GKE_ZONE                - GKE zone (e.g. us-central1-a)
#   GKE_CLUSTER_NAME        - Name of the GKE cluster
#   BOUNDARY_ADDR           - Boundary controller/cluster address
#   BOUNDARY_AUTH_METHOD_ID - Auth method ID (ampw_...)
#   BOUNDARY_LOGIN_NAME     - Login name for authentication
#   BOUNDARY_PASSWORD       - Login password
#
# Optional env vars:
#   BOUNDARY_TARGET_ID      - Target ID to validate TCP session (skipped if unset)
#   BOUNDARY_WORKER_TAG     - Worker type tag to match in Boundary (default: worker)
#   SKIP_CLEANUP            - Set to "true" to leave resources after test
#   SKIP_HELM_UNINSTALL     - Set to "true" to skip helm uninstall
#   HELM_RELEASE            - Helm release name (default: boundary-worker)
#   K8S_NAMESPACE           - Kubernetes namespace (default: boundary)
#   WORKER_DEPLOY           - Deployment name (default: boundary-worker-deployment)
#   WAIT_TIMEOUT            - Readiness wait (sec) (default: 300)
#   LB_TIMEOUT              - LoadBalancer provisioning wait (sec) (default: 300)
# ============================================================================

set -euo pipefail

pass()   { echo "   ✅ $1" >&2; }
fail()   { echo "❌ FAILED: $1" >&2; exit 1; }
info()   { echo "   $1" >&2; }
warn()   { echo "⚠️  WARN: $1" >&2; }

section() {
    echo ""
    echo "  > $1"
    echo "  $(printf '=%.0s' {1..50})"
}

: "${GCP_PROJECT_ID:?'GCP_PROJECT_ID must be set'}"
: "${GCP_REGION:?'GCP_REGION must be set'}"
: "${GKE_ZONE:?'GKE_ZONE must be set'}"
: "${GKE_CLUSTER_NAME:?'GKE_CLUSTER_NAME must be set'}"
: "${BOUNDARY_ADDR:?'BOUNDARY_ADDR must be set'}"
: "${BOUNDARY_AUTH_METHOD_ID:?'BOUNDARY_AUTH_METHOD_ID must be set'}"
: "${BOUNDARY_LOGIN_NAME:?'BOUNDARY_LOGIN_NAME must be set'}"
: "${BOUNDARY_PASSWORD:?'BOUNDARY_PASSWORD must be set'}"

SKIP_CLEANUP="${SKIP_CLEANUP:-false}"
SKIP_HELM_UNINSTALL="${SKIP_HELM_UNINSTALL:-false}"
HELM_RELEASE="${HELM_RELEASE:-boundary-worker}"
NAMESPACE="${K8S_NAMESPACE:-boundary}"
DEPLOY="${WORKER_DEPLOY:-boundary-worker-deployment}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"
LB_TIMEOUT="${LB_TIMEOUT:-300}"
WORKER_POLL_TIMEOUT="${WORKER_POLL_TIMEOUT:-120}"
BOUNDARY_WORKER_TAG="${BOUNDARY_WORKER_TAG:-worker}"
STORAGE_CLASS="${TF_STORAGE_CLASS_NAME:-standard-rwo}"

GKE_CONTEXT="gke_${GCP_PROJECT_ID}_${GKE_ZONE}_${GKE_CLUSTER_NAME}"

TESTS_PASSED=0
TESTS_FAILED=0
FAILED_TESTS=()

record_pass() { TESTS_PASSED=$((TESTS_PASSED + 1)); pass "$1"; }
record_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILED_TESTS+=("$1")
    echo "     [FAIL] $1"
}

_cleanup() {
    if [[ -n "${PF_PID:-}" ]] && kill -0 "${PF_PID}" 2>/dev/null; then
        kill "${PF_PID}" 2>/dev/null || true
        wait "${PF_PID}" 2>/dev/null || true
    fi

    if [[ "${SKIP_CLEANUP}" == "true" ]]; then
        warn "SKIP_CLEANUP=true - leaving namespace '${NAMESPACE}' in place"
        return
    fi

    section "Cleanup"
    if [[ "${SKIP_HELM_UNINSTALL}" == "true" ]]; then
        warn "SKIP_HELM_UNINSTALL=true - leaving Helm release '${HELM_RELEASE}' in place"
    else
        info "Uninstalling Helm release '${HELM_RELEASE}'..."
        helm uninstall "${HELM_RELEASE}" \
            --namespace "${NAMESPACE}" \
            --kube-context "${GKE_CONTEXT}" \
            --wait --timeout 5m >/dev/null 2>&1 || true
    fi
    kubectl delete namespace "${NAMESPACE}" \
        --context "${GKE_CONTEXT}" \
        --ignore-not-found >/dev/null 2>&1 || true
    info "Cleanup complete"
}
trap _cleanup EXIT

section "Prerequisites"
for tool in kubectl helm gcloud boundary; do
    if command -v "$tool" >/dev/null 2>&1; then
        record_pass "Tool available: $tool"
    else
        fail "'$tool' is not installed"
    fi
done

section "GCP Authentication"
gcloud auth list --filter=status:ACTIVE --format='value(account)' | grep -q . \
    && record_pass "Authenticated to GCP" \
    || fail "No active gcloud account. Run 'gcloud auth login'."

gcloud config set project "${GCP_PROJECT_ID}" >/dev/null 2>&1 \
    && record_pass "Active project set: ${GCP_PROJECT_ID}" \
    || fail "Failed to set GCP project '${GCP_PROJECT_ID}'"

section "GKE Cluster Accessibility"
info "Fetching kubeconfig for cluster '${GKE_CLUSTER_NAME}'..."
GET_CREDS_OUT=$(gcloud container clusters get-credentials "${GKE_CLUSTER_NAME}" \
    --zone "${GKE_ZONE}" \
    --project "${GCP_PROJECT_ID}" 2>&1) \
    || fail "Failed to fetch credentials for '${GKE_CLUSTER_NAME}': ${GET_CREDS_OUT}"

kubectl cluster-info --context "${GKE_CONTEXT}" >/dev/null 2>&1 \
    && record_pass "GKE cluster '${GKE_CLUSTER_NAME}' is accessible" \
    || { record_fail "GKE cluster '${GKE_CLUSTER_NAME}' is not accessible"; exit 1; }

NODE_COUNT=$(kubectl get nodes --context "${GKE_CONTEXT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
[ "${NODE_COUNT}" -gt 0 ] \
    && record_pass "Cluster has ${NODE_COUNT} node(s)" \
    || { record_fail "No nodes found in cluster"; exit 1; }

READY_NODES=$(kubectl get nodes --context "${GKE_CONTEXT}" --no-headers 2>/dev/null | grep -c " Ready" || true)
[ "${READY_NODES}" -eq "${NODE_COUNT}" ] \
    && record_pass "All ${READY_NODES}/${NODE_COUNT} nodes are Ready" \
    || warn "${READY_NODES}/${NODE_COUNT} nodes are Ready"

section "StorageClass and Helm Release"
if kubectl get storageclass "${STORAGE_CLASS}" --context "${GKE_CONTEXT}" >/dev/null 2>&1; then
    record_pass "StorageClass '${STORAGE_CLASS}' is available"
else
    fail "StorageClass '${STORAGE_CLASS}' not found. Run 'make gke-setup' first or set TF_STORAGE_CLASS_NAME."
fi

helm status "${HELM_RELEASE}" -n "${NAMESPACE}" --kube-context "${GKE_CONTEXT}" >/dev/null 2>&1 \
    && record_pass "Helm release '${HELM_RELEASE}' exists" \
    || fail "Release '${HELM_RELEASE}' not found. Run 'make gke-helm' first."

section "Deployment Readiness"
info "Waiting for deployment '${DEPLOY}' (timeout: ${WAIT_TIMEOUT}s)..."
kubectl wait --for=condition=available \
    --timeout="${WAIT_TIMEOUT}s" \
    deployment/"${DEPLOY}" \
    -n "${NAMESPACE}" \
    --context "${GKE_CONTEXT}" >/dev/null 2>&1 \
    && record_pass "Deployment '${DEPLOY}' is available" \
    || { record_fail "Deployment '${DEPLOY}' did not become available"; exit 1; }

POD=$(kubectl get pods \
    -n "${NAMESPACE}" \
    --context "${GKE_CONTEXT}" \
    -l app.kubernetes.io/name=boundary-worker \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

[ -n "${POD}" ] \
    && record_pass "Worker pod running: ${POD}" \
    || { record_fail "No running worker pod found"; exit 1; }

section "PersistentVolumeClaims"
PVC_COUNT=$(kubectl get pvc -n "${NAMESPACE}" --context "${GKE_CONTEXT}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [ "${PVC_COUNT}" -gt 0 ]; then
    record_pass "${PVC_COUNT} PVC(s) found"
    UNBOUND=$(kubectl get pvc -n "${NAMESPACE}" --context "${GKE_CONTEXT}" --no-headers 2>/dev/null | (grep -v "Bound" || true) | wc -l | tr -d ' ')
    [ "${UNBOUND}" -eq 0 ] \
        && record_pass "All PVCs are Bound" \
        || { record_fail "${UNBOUND} PVC(s) are not Bound"; kubectl get pvc -n "${NAMESPACE}" --context "${GKE_CONTEXT}"; }
else
    warn "No PVCs found (persistence may be disabled)"
fi

section "LoadBalancer Provisioning"
info "Waiting for external endpoint (timeout: ${LB_TIMEOUT}s)..."
LB_ENDPOINT=""
ELAPSED=0
INTERVAL=15
while [ "${ELAPSED}" -lt "${LB_TIMEOUT}" ]; do
    LB_IP=$(kubectl get svc -n "${NAMESPACE}" --context "${GKE_CONTEXT}" \
        -l app.kubernetes.io/name=boundary-worker \
        -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].ip}' \
        2>/dev/null || true)
    LB_HOSTNAME=$(kubectl get svc -n "${NAMESPACE}" --context "${GKE_CONTEXT}" \
        -l app.kubernetes.io/name=boundary-worker \
        -o jsonpath='{.items[?(@.spec.type=="LoadBalancer")].status.loadBalancer.ingress[0].hostname}' \
        2>/dev/null || true)

    if [ -n "${LB_IP}" ]; then
        LB_ENDPOINT="${LB_IP}"
        break
    fi
    if [ -n "${LB_HOSTNAME}" ]; then
        LB_ENDPOINT="${LB_HOSTNAME}"
        break
    fi

    info "Waiting for external endpoint... (${ELAPSED}s elapsed)"
    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done

if [ -n "${LB_ENDPOINT}" ]; then
    record_pass "LoadBalancer provisioned: ${LB_ENDPOINT}"
else
    record_fail "LoadBalancer endpoint not assigned within ${LB_TIMEOUT}s"
    kubectl get svc -n "${NAMESPACE}" --context "${GKE_CONTEXT}"
fi

section "Ops Health Endpoint (port 9203)"
pkill -f "kubectl port-forward.*9203" 2>/dev/null || true
sleep 1

kubectl port-forward -n "${NAMESPACE}" --context "${GKE_CONTEXT}" "pod/${POD}" 9203:9203 >/dev/null 2>&1 &
PF_PID=$!

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

section "Helm Chart Tests"
info "Cleaning stale test pods..."
kubectl delete pods -n "${NAMESPACE}" --context "${GKE_CONTEXT}" \
    -l app.kubernetes.io/component=test \
    --field-selector=status.phase=Failed \
    --ignore-not-found >/dev/null 2>&1 || true

info "Running: helm test ${HELM_RELEASE}"
helm test "${HELM_RELEASE}" \
    --namespace "${NAMESPACE}" \
    --kube-context "${GKE_CONTEXT}" \
    --timeout 10m >/dev/null 2>&1 || true

FAILED_HELM_TESTS=$(kubectl get pods -n "${NAMESPACE}" --context "${GKE_CONTEXT}" \
    -l app.kubernetes.io/component=test \
    --field-selector=status.phase=Failed \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null || true)

if [ -z "${FAILED_HELM_TESTS}" ]; then
    record_pass "All Helm tests passed"
else
    record_fail "Helm tests failed: $(echo "${FAILED_HELM_TESTS}" | tr '\n' ' ')"
fi

section "Boundary Worker Registration"
info "Authenticating with Boundary cluster: ${BOUNDARY_ADDR}"
AUTH_OUT=$(boundary authenticate password \
    -addr "${BOUNDARY_ADDR}" \
    -auth-method-id "${BOUNDARY_AUTH_METHOD_ID}" \
    -login-name "${BOUNDARY_LOGIN_NAME}" \
    -password env://BOUNDARY_PASSWORD \
    -keyring-type=none 2>&1) \
    || fail "Boundary authentication failed: ${AUTH_OUT}"

BOUNDARY_TOKEN=$(printf '%s\n' "${AUTH_OUT}" \
    | awk '/The token is:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
[ -n "${BOUNDARY_TOKEN}" ] || fail "Failed to extract auth token"
export BOUNDARY_TOKEN
record_pass "Authenticated with Boundary cluster"

AUTH_FILES=$(kubectl exec -n "${NAMESPACE}" "${POD}" --context "${GKE_CONTEXT}" -- find /var/lib/boundary -type f 2>/dev/null | wc -l | tr -d ' ') || AUTH_FILES=0
[ "${AUTH_FILES}" -gt 0 ] \
    && record_pass "Auth storage populated (${AUTH_FILES} file(s))" \
    || warn "Auth storage empty - worker may not have completed enrollment yet"

REGISTERED_WORKER_ID=""
WORKER_ELAPSED=0
WORKER_INTERVAL=15
info "Polling Boundary for connected worker with '${BOUNDARY_WORKER_TAG}' tag (timeout: ${WORKER_POLL_TIMEOUT}s)..."
while [ "${WORKER_ELAPSED}" -lt "${WORKER_POLL_TIMEOUT}" ]; do
    WORKERS_JSON=$(boundary workers list -scope-id global -addr "${BOUNDARY_ADDR}" -token env://BOUNDARY_TOKEN -format json 2>/dev/null || true)

    REGISTERED_WORKER_ID=$(printf '%s\n' "${WORKERS_JSON}" | python3 -c '
import json,sys
raw=sys.stdin.read().strip()
if not raw:
    raise SystemExit(0)
tag=sys.argv[1]
data=json.loads(raw)
for w in data.get("items", []):
    tags=w.get("canonical_tags", {}).get("type", [])
    if tag in tags and w.get("address"):
        print(w.get("id", ""))
        break
' "${BOUNDARY_WORKER_TAG}" 2>/dev/null || true)

    if [ -n "${REGISTERED_WORKER_ID}" ]; then
        break
    fi

    info "Worker not yet visible (${WORKER_ELAPSED}s elapsed), retrying..."
    sleep "${WORKER_INTERVAL}"
    WORKER_ELAPSED=$((WORKER_ELAPSED + WORKER_INTERVAL))
done

[ -n "${REGISTERED_WORKER_ID}" ] \
    && record_pass "Worker registered in Boundary: ${REGISTERED_WORKER_ID}" \
    || record_fail "No connected worker with '${BOUNDARY_WORKER_TAG}' tag found in Boundary"

section "TCP Session Validation"
if [ -z "${BOUNDARY_TARGET_ID:-}" ]; then
    warn "BOUNDARY_TARGET_ID not set - skipping TCP session test"
else
    info "Authorizing session to target: ${BOUNDARY_TARGET_ID}"
    SESSION_OUT=$(boundary targets authorize-session \
        -id "${BOUNDARY_TARGET_ID}" \
        -addr "${BOUNDARY_ADDR}" \
        -token env://BOUNDARY_TOKEN \
        -format json 2>/dev/null || true)

    SESSION_ID=$(printf '%s\n' "${SESSION_OUT}" | grep -o '"session_id":"[^"]*"' | head -1 | cut -d'"' -f4 || true)
    [ -n "${SESSION_ID}" ] \
        && record_pass "Session authorized: ${SESSION_ID}" \
        || record_fail "Failed to extract session_id"

    CONN_OUT=$(mktemp)
    boundary connect -target-id "${BOUNDARY_TARGET_ID}" -addr "${BOUNDARY_ADDR}" -token env://BOUNDARY_TOKEN > "${CONN_OUT}" 2>&1 &
    CONN_PID=$!
    sleep 5

    if kill -0 "${CONN_PID}" 2>/dev/null; then
        record_pass "TCP proxy connection established"
        if [ -n "${SESSION_ID}" ]; then
            boundary sessions cancel -id "${SESSION_ID}" -addr "${BOUNDARY_ADDR}" -token env://BOUNDARY_TOKEN -format json >/dev/null 2>&1 || true
        fi
        kill "${CONN_PID}" 2>/dev/null || true
        wait "${CONN_PID}" 2>/dev/null || true
    else
        record_fail "TCP proxy connection failed"
        cat "${CONN_OUT}" || true
    fi
    rm -f "${CONN_OUT}"
fi

section "Test Results"
echo ""
echo "  GKE Cluster:        ${GKE_CLUSTER_NAME} (${GKE_ZONE})"
echo "  Project:            ${GCP_PROJECT_ID}"
echo "  Helm Release:       ${HELM_RELEASE} / ${NAMESPACE}"
echo "  Worker Pod:         ${POD:-unknown}"
[ -n "${LB_ENDPOINT:-}" ] && echo "  External Endpoint:  ${LB_ENDPOINT}"
echo ""
echo "  Tests Passed: ${TESTS_PASSED}"

if [ "${TESTS_FAILED}" -gt 0 ]; then
    echo "  Tests Failed: ${TESTS_FAILED}"
    echo ""
    echo "  Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "    - ${t}"
    done
    exit 1
fi

echo ""
echo "  [PASS] All GKE integration tests passed"
