#!/bin/bash
# Copyright IBM Corp. 2026

# OpenShift Worker Chart — Acceptance Smoke Test
# Validates the Helm chart deploys correctly on OpenShift using values.openshift.yaml.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test configuration
NAMESPACE="boundary"
HELM_RELEASE="boundary-worker"
WORKER_HCL="${WORKER_HCL:-./worker.hcl}"
TIMEOUT="${TIMEOUT:-300}"
DEPLOY="${HELM_RELEASE}-deployment"
# When SKIP_HELM_INSTALL=true the chart is already deployed (e.g. via crc-helm or
# openshift-helm). The smoke test then only verifies existing resources.
SKIP_HELM_INSTALL="${SKIP_HELM_INSTALL:-false}"

echo "OpenShift Worker Chart — Acceptance Smoke Test"

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅${NC} $2"
    else
        echo -e "${RED}❌ FAILED:${NC} $2"
        exit 1
    fi
}

# Test 1: Verify OpenShift cluster is accessible
echo "Test 1: Verifying OpenShift cluster accessibility..."
if oc cluster-info > /dev/null 2>&1; then
    print_result 0 "OpenShift cluster accessible"
else
    print_result 1 "OpenShift cluster is not accessible. Run: oc login <cluster-url>"
fi
echo ""

# Test 2: Install chart with values.openshift.yaml (skipped if SKIP_HELM_INSTALL=true)
if [ "${SKIP_HELM_INSTALL}" = "true" ]; then
    echo "Test 2: Verifying existing Helm release (SKIP_HELM_INSTALL=true)..."
    if helm status "${HELM_RELEASE}" -n "${NAMESPACE}" > /dev/null 2>&1; then
        print_result 0 "Helm release '${HELM_RELEASE}' is deployed"
    else
        print_result 1 "Helm release '${HELM_RELEASE}' not found. Deploy it first (e.g. make crc-helm or make openshift-helm)"
    fi
else
    echo "Test 2: Installing chart with values.openshift.yaml..."
    [ -f "${WORKER_HCL}" ] || { echo -e "${RED}❌ FAILED:${NC} worker.hcl not found at '${WORKER_HCL}'"; exit 1; }
    if helm upgrade --install "${HELM_RELEASE}" . \
        --namespace "${NAMESPACE}" \
        --create-namespace \
        -f values.openshift.yaml \
        --set-file worker.config="${WORKER_HCL}" \
        --wait \
        --timeout "${TIMEOUT}s" \
        > /dev/null 2>&1; then
        print_result 0 "Helm release '${HELM_RELEASE}' installed successfully"
    else
        print_result 1 "helm upgrade --install failed"
    fi
fi
echo ""

# Test 3: Verify deployment is available
echo "Test 3: Verifying deployment is available..."
if kubectl wait --for=condition=available \
    --timeout="${TIMEOUT}s" \
    deployment/"${DEPLOY}" \
    -n "${NAMESPACE}" > /dev/null 2>&1; then
    print_result 0 "Deployment '${DEPLOY}' is available"
else
    print_result 1 "Deployment '${DEPLOY}' did not become available"
fi
echo ""

# Test 4: Verify OpenShift Route exists with passthrough TLS
echo "Test 4: Verifying OpenShift Route exists..."
ROUTE_NAME="${HELM_RELEASE}-proxy-route"
if oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" > /dev/null 2>&1; then
    print_result 0 "Route '${ROUTE_NAME}' exists"
else
    print_result 1 "Route '${ROUTE_NAME}' not found"
fi
TLS_TERM=$(oc get route "${ROUTE_NAME}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.tls.termination}' 2>/dev/null || true)
if [ "${TLS_TERM}" = "passthrough" ]; then
    print_result 0 "Route TLS termination is 'passthrough'"
else
    print_result 1 "Expected TLS termination 'passthrough', got '${TLS_TERM:-empty}'"
fi
echo ""

# Test 5: Verify proxy Service type is ClusterIP
echo "Test 5: Verifying proxy Service type is ClusterIP..."
PROXY_SVC="${HELM_RELEASE}-proxy"
SVC_TYPE=$(oc get service "${PROXY_SVC}" -n "${NAMESPACE}" \
    -o jsonpath='{.spec.type}' 2>/dev/null || true)
if [ "${SVC_TYPE}" = "ClusterIP" ]; then
    print_result 0 "Proxy Service type is 'ClusterIP'"
else
    print_result 1 "Expected 'ClusterIP', got '${SVC_TYPE:-empty}'"
fi
echo ""

# Cleanup (only when this script managed the install)
if [ "${SKIP_HELM_INSTALL}" = "false" ]; then
    echo "Cleaning up..."
    if helm uninstall "${HELM_RELEASE}" -n "${NAMESPACE}" > /dev/null 2>&1; then
        echo "✅ Helm release cleaned up"
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} Failed to uninstall Helm release"
    fi
    echo ""
fi
echo "✅ OpenShift Worker Chart Smoke Test passed!"
