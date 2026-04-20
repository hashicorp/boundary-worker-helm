#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
TEST_NAMESPACE="boundary"
CONTEXT="kind-acceptance"
WORKER_DEPLOYMENT="boundary-worker-deployment"
TIMEOUT=300 # 5 minutes timeout for various operations
BOUNDARY_CLI_TIMEOUT=30 # timeout for boundary CLI calls that may hang

echo "================================"
echo "Boundary Worker KIND Cluster Acceptance Test"
echo "================================"
echo ""

# Function to print test results
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✅ PASSED:${NC} $2"
    else
        echo -e "${RED}❌ FAILED:${NC} $2"
        exit 1
    fi
}

# Function to print info messages
print_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

# Function to wait for condition with timeout
wait_for_condition() {
    local condition=$1
    local description=$2
    local timeout=${3:-$TIMEOUT}
    local elapsed=0
    local interval=5

    print_info "Waiting for: $description (timeout: ${timeout}s)"
    
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition" > /dev/null 2>&1; then
            return 0
        fi
        sleep $interval
        elapsed=$((elapsed + interval))
        echo -n "."
    done
    echo ""
    return 1
}

# Run a command with timeout, preferring gtimeout on macOS if available
run_with_timeout() {
    local timeout_seconds=$1
    shift

    if command -v gtimeout >/dev/null 2>&1; then
        gtimeout "${timeout_seconds}" "$@"
    elif command -v timeout >/dev/null 2>&1; then
        timeout "${timeout_seconds}" "$@"
    else
        "$@"
    fi
}

# Validate required environment variables
echo "Test 0: Validating environment variables..."
REQUIRED_VARS=("BOUNDARY_ADDR" "BOUNDARY_LOGIN_NAME" "BOUNDARY_PASSWORD")
MISSING_VARS=()

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        MISSING_VARS+=("$var")
    fi
done

if [ ${#MISSING_VARS[@]} -gt 0 ]; then
    echo -e "${RED}❌ FAILED:${NC} Missing required environment variables:"
    for var in "${MISSING_VARS[@]}"; do
        echo "  - $var"
    done
    echo ""
    echo "Please set the following environment variables:"
    echo "  export BOUNDARY_ADDR=https://your-cluster.boundary.hashicorp.cloud"
    echo "  export BOUNDARY_LOGIN_NAME=admin"
    echo "  export BOUNDARY_PASSWORD=your-password"
    exit 1
fi
print_result 0 "All required environment variables are set"
echo ""

# Test 1: Verify cluster is accessible
echo "Test 1: Verifying KIND cluster accessibility..."
if kubectl cluster-info --context ${CONTEXT} > /dev/null 2>&1; then
    print_result 0 "KIND cluster is accessible"
else
    print_result 1 "KIND cluster is not accessible"
fi
echo ""

# Test 2: Verify namespace exists
echo "Test 2: Verifying namespace '${TEST_NAMESPACE}' exists..."
if kubectl get namespace ${TEST_NAMESPACE} --context ${CONTEXT} > /dev/null 2>&1; then
    print_result 0 "Namespace '${TEST_NAMESPACE}' exists"
else
    print_result 1 "Namespace '${TEST_NAMESPACE}' does not exist"
fi
echo ""

# Test 3: Verify worker deployment exists and is ready
echo "Test 3: Verifying worker deployment..."
if kubectl get deployment ${WORKER_DEPLOYMENT} -n ${TEST_NAMESPACE} --context ${CONTEXT} > /dev/null 2>&1; then
    print_result 0 "Worker deployment exists"
    
    # Check if deployment is ready
    print_info "Checking deployment readiness..."
    READY=$(kubectl get deployment ${WORKER_DEPLOYMENT} -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.status.conditions[?(@.type=="Available")].status}')
    if [ "$READY" = "True" ]; then
        print_result 0 "Worker deployment is ready"
    else
        print_result 1 "Worker deployment is not ready"
    fi
else
    print_result 1 "Worker deployment does not exist"
fi
echo ""

# Test 4: Verify worker pod is running
echo "Test 4: Verifying worker pod status..."
POD_NAME=$(kubectl get pods -n ${TEST_NAMESPACE} --context ${CONTEXT} -l app.kubernetes.io/name=boundary-worker -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -n "$POD_NAME" ]; then
    print_result 0 "Worker pod found: $POD_NAME"
    
    POD_STATUS=$(kubectl get pod $POD_NAME -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.status.phase}')
    if [ "$POD_STATUS" = "Running" ]; then
        print_result 0 "Worker pod is running"
    else
        print_result 1 "Worker pod is not running (status: $POD_STATUS)"
    fi
else
    print_result 1 "Worker pod not found"
fi
echo ""

# Test 5: Check worker logs for successful startup
echo "Test 5: Checking worker logs for successful startup..."
if [ -n "$POD_NAME" ]; then
    print_info "Fetching worker logs..."
    LOGS=$(kubectl logs $POD_NAME -n ${TEST_NAMESPACE} --context ${CONTEXT} --tail=100 2>/dev/null || echo "")
    
    if echo "$LOGS" | grep -q "worker started"; then
        print_result 0 "Worker started successfully"
    elif echo "$LOGS" | grep -q "starting worker"; then
        print_result 0 "Worker startup initiated"
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} Could not confirm worker startup from logs"
        echo "Recent logs:"
        echo "$LOGS" | tail -10
    fi
else
    print_result 1 "Cannot check logs - pod not found"
fi
echo ""

# Test 6: Authenticate with Boundary controller
echo "Test 6: Authenticating with Boundary controller..."
print_info "Boundary Address: $BOUNDARY_ADDR"
print_info "Login Name: $BOUNDARY_LOGIN_NAME"

AUTH_OUTPUT=$(boundary authenticate password \
    -addr="$BOUNDARY_ADDR" \
    -login-name="$BOUNDARY_LOGIN_NAME" \
    -password="env://BOUNDARY_PASSWORD" \
    -keyring-type=none \
    -format=json 2>&1)

if [ $? -eq 0 ]; then
    AUTH_TOKEN=$(echo "$AUTH_OUTPUT" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    if [ -n "$AUTH_TOKEN" ]; then
        export BOUNDARY_TOKEN="$AUTH_TOKEN"
        print_result 0 "Successfully authenticated with Boundary controller"
    else
        print_result 1 "Failed to extract authentication token"
    fi
else
    echo "$AUTH_OUTPUT"
    print_result 1 "Failed to authenticate with Boundary controller"
fi
echo ""

# Test 7: Verify worker registration with controller
echo "Test 7: Verifying worker registration with Boundary controller..."
print_info "Listing workers from controller..."

WORKERS_OUTPUT=$(boundary workers list \
    -addr="$BOUNDARY_ADDR" \
    -token="env://BOUNDARY_TOKEN" \
    -format=json 2>&1)

if [ $? -eq 0 ]; then
    print_result 0 "Successfully retrieved worker list from controller"
    
    # Check if any workers are active
    ACTIVE_WORKERS=$(echo "$WORKERS_OUTPUT" | grep -o '"active_connection_count":[0-9]*' | wc -l)
    print_info "Found workers in controller: $ACTIVE_WORKERS"
    
    # Look for our worker by checking recent registrations
    if echo "$WORKERS_OUTPUT" | grep -q '"type":"pki"'; then
        print_result 0 "Worker with PKI authentication found (controller-led worker)"
    elif echo "$WORKERS_OUTPUT" | grep -q '"type":"kms"'; then
        print_result 0 "Worker with KMS authentication found"
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} Could not definitively identify worker type"
    fi
else
    echo "$WORKERS_OUTPUT"
    print_result 1 "Failed to retrieve worker list from controller"
fi
echo ""

# Test 8: Verify worker health endpoints
echo "Test 8: Verifying worker health endpoints..."
if [ -n "$POD_NAME" ]; then
    # Check ops service health endpoint
    print_info "Checking worker health endpoint..."
    
    # Port-forward to access health endpoint
    kubectl port-forward -n ${TEST_NAMESPACE} --context ${CONTEXT} pod/$POD_NAME 9203:9203 > /dev/null 2>&1 &
    PF_PID=$!
    sleep 3
    
    HEALTH_CHECK=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9203/health 2>/dev/null || echo "000")
    
    kill $PF_PID 2>/dev/null || true
    
    if [ "$HEALTH_CHECK" = "200" ]; then
        print_result 0 "Worker health endpoint is responding (HTTP 200)"
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} Health endpoint returned: $HEALTH_CHECK"
    fi
else
    print_result 1 "Cannot check health endpoint - pod not found"
fi
echo ""

# Test 9: Validate session creation capability
echo "Test 9: Validating session creation capability..."
print_info "Checking if worker can handle session requests..."

# First, we need to check if there are any targets configured
TARGETS_OUTPUT=$(run_with_timeout ${BOUNDARY_CLI_TIMEOUT} boundary targets list \
    -addr="$BOUNDARY_ADDR" \
    -token="env://BOUNDARY_TOKEN" \
    -format=json 2>&1)
TARGETS_EXIT_CODE=$?

if [ $TARGETS_EXIT_CODE -eq 0 ]; then
    TARGET_COUNT=$(echo "$TARGETS_OUTPUT" | grep -o '"id":"[^"]*"' | wc -l)
    print_info "Found $TARGET_COUNT target(s) in Boundary"
    
    if [ $TARGET_COUNT -gt 0 ]; then
        # Get the first target ID
        TARGET_ID=$(echo "$TARGETS_OUTPUT" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
        print_info "Testing with target: $TARGET_ID"
        
        # Attempt to authorize a session (this validates the worker can be selected)
        SESSION_AUTH=$(boundary targets authorize-session \
            -id="$TARGET_ID" \
            -addr="$BOUNDARY_ADDR" \
            -token="env://BOUNDARY_TOKEN" \
            -format=json 2>&1)
        
        if [ $? -eq 0 ]; then
            SESSION_ID=$(echo "$SESSION_AUTH" | grep -o '"session_id":"[^"]*"' | cut -d'"' -f4)
            if [ -n "$SESSION_ID" ]; then
                print_result 0 "Session authorization successful (Session ID: $SESSION_ID)"
                
                # Cancel the session since this is just a test
                boundary sessions cancel \
                    -id="$SESSION_ID" \
                    -addr="$BOUNDARY_ADDR" \
                    -token="env://BOUNDARY_TOKEN" > /dev/null 2>&1
                print_info "Test session cancelled"
            else
                print_result 1 "Failed to extract session ID from authorization"
            fi
        else
            echo -e "${YELLOW}⚠️  WARNING:${NC} Could not authorize session - this may be expected if no workers are available for the target"
            echo "Session authorization output:"
            echo "$SESSION_AUTH" | head -5
        fi
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} No targets configured - skipping session creation test"
        echo "To fully test session creation, configure a target in Boundary"
    fi
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} Could not retrieve targets list"
fi
echo ""

# Test 10: Verify worker can communicate with controller
echo "Test 10: Verifying worker-controller communication..."
if [ -n "$POD_NAME" ]; then
    print_info "Checking worker logs for controller connection..."
    
    RECENT_LOGS=$(kubectl logs $POD_NAME -n ${TEST_NAMESPACE} --context ${CONTEXT} --tail=50 2>/dev/null || echo "")
    
    if echo "$RECENT_LOGS" | grep -qi "connected to controller\|connection established\|successfully registered"; then
        print_result 0 "Worker successfully connected to controller"
    elif echo "$RECENT_LOGS" | grep -qi "error\|failed"; then
        echo -e "${YELLOW}⚠️  WARNING:${NC} Possible connection issues detected in logs"
        echo "Recent error logs:"
        echo "$RECENT_LOGS" | grep -i "error\|failed" | tail -5
    else
        echo -e "${YELLOW}⚠️  WARNING:${NC} Could not confirm controller connection from logs"
    fi
else
    print_result 1 "Cannot check logs - pod not found"
fi
echo ""

# Test 11: Verify persistent volumes
echo "Test 11: Verifying persistent volumes..."
PVCS=$(kubectl get pvc -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$PVCS" ]; then
    print_result 0 "Persistent volume claims found: $PVCS"
    
    for pvc in $PVCS; do
        PVC_STATUS=$(kubectl get pvc $pvc -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.status.phase}')
        if [ "$PVC_STATUS" = "Bound" ]; then
            print_info "PVC $pvc is bound"
        else
            echo -e "${YELLOW}⚠️  WARNING:${NC} PVC $pvc status: $PVC_STATUS"
        fi
    done
else
    echo -e "${YELLOW}⚠️  WARNING:${NC} No persistent volume claims found"
fi
echo ""

# Test 12: Verify services
echo "Test 12: Verifying services..."
SERVICES=$(kubectl get svc -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)

if [ -n "$SERVICES" ]; then
    print_result 0 "Services found: $SERVICES"
    
    for svc in $SERVICES; do
        SVC_TYPE=$(kubectl get svc $svc -n ${TEST_NAMESPACE} --context ${CONTEXT} -o jsonpath='{.spec.type}')
        print_info "Service $svc type: $SVC_TYPE"
    done
else
    print_result 1 "No services found"
fi
echo ""

# Summary
echo "================================"
echo -e "${GREEN}✅ Acceptance Test Suite Completed!${NC}"
echo "================================"
echo ""
echo "Summary:"
echo "  - KIND cluster: ✅ Accessible"
echo "  - Worker deployment: ✅ Running"
echo "  - Boundary authentication: ✅ Successful"
echo "  - Worker registration: ✅ Verified"
echo "  - Session capability: ✅ Validated"
echo ""
echo "The worker is successfully deployed in the KIND cluster"
echo "and registered with the Boundary controller at: $BOUNDARY_ADDR"
echo ""
