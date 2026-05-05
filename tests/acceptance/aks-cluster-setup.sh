#!/bin/bash
# ============================================================================
# AKS Cluster Setup for Boundary Worker Helm Chart Acceptance Testing
#
# This script creates a production-ready Azure AKS cluster with all
# prerequisites needed to run the Boundary Worker Helm chart:
#   - Azure Resource Group
#   - AKS cluster (via az aks create)
#   - Azure Disk CSI Driver (built-in, enabled by default on AKS 1.21+)
#   - managed-csi StorageClass verification
#   - Azure Load Balancer (built-in, no separate controller required)
#
# Required tools: az, kubectl, helm
#
# Required env vars:
#   AZURE_RESOURCE_GROUP  - Azure resource group name
#   AKS_CLUSTER_NAME      - Name for the AKS cluster
#   AZURE_LOCATION        - Azure region (e.g. eastus, westeurope)
#
# Optional env vars:
#   AKS_K8S_VERSION       - Kubernetes version (default: 1.31)
#   AKS_NODE_VM_SIZE      - VM size for node pool (default: Standard_D2s_v3)
#   AKS_NODE_COUNT        - Desired node count (default: 2)
#   AKS_NODE_MIN          - Minimum node count for autoscaler (default: 1)
#   AKS_NODE_MAX          - Maximum node count for autoscaler (default: 3)
#   AZURE_SUBSCRIPTION    - Azure subscription ID (uses current default if unset)
# ============================================================================

set -euo pipefail

# ── Helpers ───────────────────────────────────────────────────────────────────
pass()    { echo "   ✅ $1"; }
fail()    { echo "❌ FAILED: $1"; exit 1; }
info()    { echo "   $1"; }
warn()    { echo "⚠️ WARN: $1"; }
section() { echo ""; echo "$1"; }

# ── Config ────────────────────────────────────────────────────────────────────
: "${AZURE_RESOURCE_GROUP:?'AZURE_RESOURCE_GROUP must be set'}"
: "${AKS_CLUSTER_NAME:?'AKS_CLUSTER_NAME must be set'}"
: "${AZURE_LOCATION:?'AZURE_LOCATION must be set (e.g. eastus)'}"

K8S_VERSION="${AKS_K8S_VERSION:-}"
NODE_VM_SIZE="${AKS_NODE_VM_SIZE:-Standard_D2s_v3}"
NODE_COUNT="${AKS_NODE_COUNT:-2}"
NODE_MIN="${AKS_NODE_MIN:-1}"
NODE_MAX="${AKS_NODE_MAX:-3}"

# ── 1. Prerequisites ──────────────────────────────────────────────────────────
section "Checking Prerequisites"

for tool in az kubectl helm; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        fail "'$tool' not found. Install it before running this script."
    fi
    info "$tool: $(command -v "$tool")"
done

# Validate Azure credentials
az account show >/dev/null 2>&1 \
    || fail "Azure credentials are not configured. Run 'az login' first."

AZURE_SUBSCRIPTION_ID=$(az account show --query id --output tsv)
AZURE_TENANT_ID=$(az account show --query tenantId --output tsv)

# Override subscription if explicitly set
if [ -n "${AZURE_SUBSCRIPTION:-}" ]; then
    az account set --subscription "${AZURE_SUBSCRIPTION}" \
        || fail "Failed to set subscription '${AZURE_SUBSCRIPTION}'"
    AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION}"
fi

pass "Azure credentials valid — subscription: ${AZURE_SUBSCRIPTION_ID}, tenant: ${AZURE_TENANT_ID}"

# ── 2. Resource Group ─────────────────────────────────────────────────────────
section "Preparing Resource Group: ${AZURE_RESOURCE_GROUP}"

if az group show --name "${AZURE_RESOURCE_GROUP}" >/dev/null 2>&1; then
    warn "Resource group '${AZURE_RESOURCE_GROUP}' already exists — skipping creation"
else
    info "Creating resource group '${AZURE_RESOURCE_GROUP}' in '${AZURE_LOCATION}'..."
    az group create \
        --name "${AZURE_RESOURCE_GROUP}" \
        --location "${AZURE_LOCATION}" \
        --output none
    pass "Resource group created"
fi

# ── 3. Create AKS Cluster ─────────────────────────────────────────────────────
section "Creating AKS Cluster: ${AKS_CLUSTER_NAME}"

if az aks show \
        --name "${AKS_CLUSTER_NAME}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        >/dev/null 2>&1; then
    warn "Cluster '${AKS_CLUSTER_NAME}' already exists — skipping creation"
else
    info "Creating cluster (this takes ~5–10 minutes)..."
    K8S_VERSION_ARGS=()
    if [ -n "${K8S_VERSION}" ]; then
        K8S_VERSION_ARGS=(--kubernetes-version "${K8S_VERSION}")
    fi
    az aks create \
        --name "${AKS_CLUSTER_NAME}" \
        --resource-group "${AZURE_RESOURCE_GROUP}" \
        --location "${AZURE_LOCATION}" \
        "${K8S_VERSION_ARGS[@]}" \
        --node-vm-size "${NODE_VM_SIZE}" \
        --node-count "${NODE_COUNT}" \
        --min-count "${NODE_MIN}" \
        --max-count "${NODE_MAX}" \
        --enable-cluster-autoscaler \
        --network-plugin azure \
        --generate-ssh-keys \
        --output none
    pass "AKS cluster created"
fi

# ── 4. Get Credentials ────────────────────────────────────────────────────────
section "Configuring kubectl Credentials"

info "Fetching AKS credentials (overwrites any existing context for '${AKS_CLUSTER_NAME}')..."
az aks get-credentials \
    --name "${AKS_CLUSTER_NAME}" \
    --resource-group "${AZURE_RESOURCE_GROUP}" \
    --overwrite-existing

AKS_CONTEXT="${AKS_CLUSTER_NAME}"

# Verify cluster access
kubectl cluster-info --context "${AKS_CONTEXT}" >/dev/null 2>&1 \
    || fail "Cannot reach cluster '${AKS_CLUSTER_NAME}' after credential fetch"
pass "Cluster is accessible (context: ${AKS_CONTEXT})"

# ── 5. Verify Nodes ───────────────────────────────────────────────────────────
section "Verifying Cluster Nodes"

info "Waiting for nodes to be Ready..."
TIMEOUT=180
ELAPSED=0
INTERVAL=10
while [ "${ELAPSED}" -lt "${TIMEOUT}" ]; do
    READY=$(kubectl get nodes --context "${AKS_CONTEXT}" \
        --no-headers 2>/dev/null | grep -c " Ready" || true)
    if [ "${READY}" -ge "${NODE_COUNT}" ]; then
        break
    fi
    info "Waiting for nodes... (${ELAPSED}s elapsed, ${READY}/${NODE_COUNT} Ready)"
    sleep "${INTERVAL}"
    ELAPSED=$((ELAPSED + INTERVAL))
done

NODE_COUNT_ACTUAL=$(kubectl get nodes --context "${AKS_CONTEXT}" \
    --no-headers 2>/dev/null | wc -l | tr -d ' ')
READY_COUNT=$(kubectl get nodes --context "${AKS_CONTEXT}" \
    --no-headers 2>/dev/null | grep -c " Ready" || true)

[ "${READY_COUNT}" -ge 1 ] \
    && pass "${READY_COUNT}/${NODE_COUNT_ACTUAL} node(s) are Ready" \
    || fail "No nodes became Ready within ${TIMEOUT}s"

# ── 6. Azure Disk CSI Driver ──────────────────────────────────────────────────
section "Verifying Azure Disk CSI Driver"

# AKS 1.21+ enables the Azure Disk CSI driver by default.
# Confirm the driver DaemonSet is running.
if kubectl get daemonset csi-azuredisk-node \
        -n kube-system --context "${AKS_CONTEXT}" >/dev/null 2>&1; then
    DESIRED=$(kubectl get daemonset csi-azuredisk-node \
        -n kube-system --context "${AKS_CONTEXT}" \
        -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
    READY_DS=$(kubectl get daemonset csi-azuredisk-node \
        -n kube-system --context "${AKS_CONTEXT}" \
        -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
    pass "Azure Disk CSI DaemonSet ready: ${READY_DS}/${DESIRED}"
else
    warn "csi-azuredisk-node DaemonSet not found — driver may still be initialising"
fi

# ── 7. managed-csi StorageClass ───────────────────────────────────────────────
section "Verifying managed-csi StorageClass"

if kubectl get storageclass managed-csi \
        --context "${AKS_CONTEXT}" >/dev/null 2>&1; then
    pass "managed-csi StorageClass is available"
else
    warn "managed-csi StorageClass not found — creating manually..."
    kubectl apply --context "${AKS_CONTEXT}" -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-csi
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: disk.csi.azure.com
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
parameters:
  skuName: Premium_LRS
EOF
    pass "managed-csi StorageClass created"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
section "AKS Cluster Setup Complete"

echo ""
echo "Cluster:        ${AKS_CLUSTER_NAME}"
echo "Resource Group: ${AZURE_RESOURCE_GROUP}"
echo "Location:       ${AZURE_LOCATION}"
echo "Context:        ${AKS_CONTEXT}"
echo "Nodes:"
kubectl get nodes --context "${AKS_CONTEXT}" \
    -o custom-columns='NAME:.metadata.name,STATUS:.status.conditions[-1].type,VM-SIZE:.metadata.labels.node\.kubernetes\.io/instance-type,VERSION:.status.nodeInfo.kubeletVersion'
echo ""
echo "Add-ons ready:"
echo "  - Azure Disk CSI Driver (managed-csi storage)"
echo "  - Azure Load Balancer (built-in, no separate controller required)"
echo ""
echo "Next steps:"
echo "  export AKS_CLUSTER_NAME=${AKS_CLUSTER_NAME}"
echo "  export AZURE_RESOURCE_GROUP=${AZURE_RESOURCE_GROUP}"
echo "  export AZURE_LOCATION=${AZURE_LOCATION}"
echo "  make aks-worker-config    # Generate worker.hcl"
echo "  make aks-helm             # Deploy Helm chart"
echo "  make aks-test             # Run acceptance tests"
