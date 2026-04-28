#!/bin/bash
# INT Acceptance Test
# Scenarios:
#   1. Worker running in KIND cluster
#   2. Worker registers with INT long-lived Boundary cluster
#   3. Session creation validated via authorize-session

set -euo pipefail

# ── Colours ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# ── Helpers ────────────────────────────────────────────────────────────────────
pass() { echo -e "${GREEN}✅ PASSED:${NC} $1"; }
fail() { echo -e "${RED}❌ FAILED:${NC} $1"; exit 1; }
info() { echo -e "   $1"; }
warn() { echo -e "${YELLOW}⚠️  WARN:${NC}  $1"; }

# ── Config ─────────────────────────────────────────────────────────────────────
CONTEXT="kind-acceptance"
NAMESPACE="boundary"
DEPLOY="boundary-worker-deployment"
TIMEOUT=300   # seconds to wait for registration / deployment readiness

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ -f .env ]; then
    set -o allexport
    # shellcheck disable=SC1091
    source .env
    set +o allexport
fi

echo "========================================"
echo " INT Acceptance Test Suite"
echo "========================================"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Scenario 1: Worker running in KIND cluster
# ══════════════════════════════════════════════════════════════════════════════
echo "[Scenario 1] Worker running in KIND cluster"
echo "────────────────────────────────────────────"

info "Checking KIND cluster accessibility..."
kubectl cluster-info --context "${CONTEXT}" >/dev/null 2>&1 \
    || fail "KIND cluster '${CONTEXT}' is not accessible. Run: make acceptance-setup"
pass "KIND cluster accessible"

info "Checking worker deployment..."
kubectl get deployment "${DEPLOY}" -n "${NAMESPACE}" --context "${CONTEXT}" >/dev/null 2>&1 \
    || fail "Deployment '${DEPLOY}' not found in namespace '${NAMESPACE}'. Run: make acceptance-helm"
pass "Worker deployment '${DEPLOY}' exists"

info "Waiting for deployment to be available (timeout: ${TIMEOUT}s)..."
kubectl wait --for=condition=available \
    --timeout="${TIMEOUT}s" \
    deployment/"${DEPLOY}" \
    -n "${NAMESPACE}" \
    --context "${CONTEXT}" >/dev/null 2>&1 \
    || fail "Worker deployment did not become available within ${TIMEOUT}s"
pass "Worker deployment is available"

POD=$(kubectl get pods \
    -n "${NAMESPACE}" \
    --context "${CONTEXT}" \
    -l app.kubernetes.io/name=boundary-worker \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)

[ -n "${POD}" ] || fail "No running worker pod found"
pass "Worker pod running: ${POD}"
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Scenario 2: Worker registers with INT long-lived cluster
# ══════════════════════════════════════════════════════════════════════════════
echo "[Scenario 2] Worker registers with INT long-lived cluster"
echo "──────────────────────────────────────────────────────────"

# Check required env vars
for var in BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD; do
    [ -n "${!var:-}" ] || fail "'${var}' is not set. Check your .env file."
done
pass "Required environment variables are set"
info "Boundary address: ${BOUNDARY_ADDR}"

# Authenticate with Boundary
info "Authenticating with Boundary INT cluster..."
AUTH_OUT=$(boundary authenticate password \
    -addr "${BOUNDARY_ADDR}" \
    -auth-method-id "${BOUNDARY_AUTH_METHOD_ID}" \
    -login-name "${BOUNDARY_LOGIN_NAME}" \
    -password env://BOUNDARY_PASSWORD \
    -keyring-type=none 2>&1) || fail "Boundary authentication failed:\n${AUTH_OUT}"

BOUNDARY_TOKEN=$(printf '%s\n' "${AUTH_OUT}" \
    | awk '/The token is:/ { getline; gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit }')
[ -n "${BOUNDARY_TOKEN}" ] || fail "Failed to extract auth token from authentication output"
export BOUNDARY_TOKEN
pass "Authenticated with INT cluster"

# ── Ops health endpoint check (port-forward to ClusterIP ops service) ────────
info "Checking worker ops health endpoint (port 9203)..."
pkill -f "port-forward.*9203" 2>/dev/null || true
sleep 1
kubectl port-forward \
    -n "${NAMESPACE}" \
    --context "${CONTEXT}" \
    "pod/${POD}" 9203:9203 >/dev/null 2>&1 &
PF_PID=$!
sleep 3

OPS_STATUS=""
if curl -sf --max-time 5 http://localhost:9203/health >/dev/null 2>&1; then
    OPS_STATUS="ok"
fi
kill "${PF_PID}" 2>/dev/null || true
wait "${PF_PID}" 2>/dev/null || true

[ "${OPS_STATUS}" = "ok" ] || fail "Ops health endpoint /health on port 9203 did not return 200."
pass "Worker ops health endpoint is healthy"

# ── Auth storage: confirm node enrollment was initiated ───────────────────────
info "Checking worker auth storage (node enrollment)..."
AUTH_FILES=$(kubectl exec -n "${NAMESPACE}" "${POD}" \
    --context "${CONTEXT}" \
    -- find /var/lib/boundary -type f 2>/dev/null | wc -l | tr -d ' ') || AUTH_FILES=0

if [ "${AUTH_FILES}" -gt 0 ]; then
    pass "Worker auth storage populated (${AUTH_FILES} file(s)) — node enrollment initiated"
else
    warn "Auth storage is empty; worker may not have started enrollment yet"
fi

# ── Boundary API: confirm worker record exists (activation token consumed) ────
info "Verifying worker record exists in Boundary..."
WORKERS_JSON=$(boundary workers list \
    -scope-id global \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN \
    -format json 2>&1) || fail "Failed to list workers from Boundary:\n${WORKERS_JSON}"

WORKER_ID=$(printf '%s\n' "${WORKERS_JSON}" | python3 -c "
import json, sys
data = json.load(sys.stdin)
for w in data.get('items', []):
    tags = w.get('canonical_tags', {}).get('type', [])
    if 'test' in tags and w.get('address'):
        print(w.get('id', ''))
        break
" 2>/dev/null || true)

[ -n "${WORKER_ID}" ] || fail "No worker with 'test' tag found in Boundary. Activation token may not have been consumed."
pass "Worker record exists in Boundary: ${WORKER_ID}"

# ── Log: confirm worker is reaching upstream ──────────────────────────────────
info "Checking worker is attempting upstream connection..."
if kubectl --context "${CONTEXT}" -n "${NAMESPACE}" logs "${POD}" 2>/dev/null \
    | grep -q "Setting HCP Boundary cluster address\|upstream.*address\|upstreamDialerFunc"; then
    pass "Worker is actively attempting upstream connection to INT cluster"
else
    warn "Could not confirm upstream connection attempt in logs (worker may still be initializing)"
fi
echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Scenario 3: Session creation
# ══════════════════════════════════════════════════════════════════════════════
echo "[Scenario 3] Session creation validated"
echo "────────────────────────────────────────"

[ -n "${BOUNDARY_TARGET_ID:-}" ] \
    || fail "'BOUNDARY_TARGET_ID' is not set. Add it to your .env file."
pass "Target configured: ${BOUNDARY_TARGET_ID}"

info "Authorizing session to target ${BOUNDARY_TARGET_ID}..."
SESSION_OUT=$(boundary targets authorize-session \
    -id "${BOUNDARY_TARGET_ID}" \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN \
    -format json 2>&1) || fail "authorize-session failed:\n${SESSION_OUT}"

SESSION_ID=$(printf '%s\n' "${SESSION_OUT}" \
    | grep -o '"session_id":"[^"]*"' \
    | head -1 \
    | cut -d'"' -f4)

[ -n "${SESSION_ID}" ] || fail "Failed to extract session_id from authorize-session response"
pass "Session authorized: ${SESSION_ID}"

SESSION_STATUS=$(printf '%s\n' "${SESSION_OUT}" \
    | grep -o '"status":"[^"]*"' \
    | head -1 \
    | cut -d'"' -f4 || true)
[ -n "${SESSION_STATUS}" ] && info "Session status: ${SESSION_STATUS}"

info "Cancelling authorized session ${SESSION_ID}..."
boundary sessions cancel \
    -id "${SESSION_ID}" \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN 2>&1 || true
pass "Authorized session cancelled"

echo ""

# ══════════════════════════════════════════════════════════════════════════════
# Scenario 4: TCP connection & session field validation
# ══════════════════════════════════════════════════════════════════════════════
echo "[Scenario 4] TCP connection & session field validation"
echo "───────────────────────────────────────────────────────"

info "Target:  ${BOUNDARY_TARGET_ID}"
info "Address: ${BOUNDARY_ADDR}"
info "Establishing proxy connection..."
echo ""

CONN_OUT=$(mktemp)
boundary connect \
    -target-id "${BOUNDARY_TARGET_ID}" \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN > "${CONN_OUT}" 2>&1 &
CONN_PID=$!

for i in $(seq 1 30); do
    if grep -q "Session ID:" "${CONN_OUT}" 2>/dev/null; then break; fi
    sleep 1
done

echo "================================"
echo "Session Details"
echo "================================"
cat "${CONN_OUT}"
echo ""

CONN_SESSION_ID=$(grep "Session ID:" "${CONN_OUT}" | awk '{print $NF}')
CONN_PROXY_ADDR=$(grep "Address:" "${CONN_OUT}" | awk '{print $NF}')
CONN_PROXY_PORT=$(grep "Port:" "${CONN_OUT}" | awk '{print $NF}')
CONN_PROXY_PROTO=$(grep "Protocol:" "${CONN_OUT}" | awk '{print $NF}')
CONN_PROXY_EXPIRY=$(grep "Expiration:" "${CONN_OUT}" | sed 's/.*Expiration:[[:space:]]*//')
CONN_LIMIT=$(grep "Connection Limit:" "${CONN_OUT}" | awk '{print $NF}')

echo "================================"
echo "Session Validation"
echo "================================"
CONN_PASS=1
if [ -n "${CONN_SESSION_ID}" ]; then echo "✅ Session ID:          ${CONN_SESSION_ID}"; else echo "❌ Session ID:          MISSING"; CONN_PASS=0; fi
if [ -n "${CONN_PROXY_ADDR}" ]; then echo "✅ Address:             ${CONN_PROXY_ADDR}"; else echo "❌ Address:             MISSING"; CONN_PASS=0; fi
if [ -n "${CONN_PROXY_PORT}" ]; then echo "✅ Port:                ${CONN_PROXY_PORT}"; else echo "❌ Port:                MISSING"; CONN_PASS=0; fi
if [ -n "${CONN_PROXY_PROTO}" ]; then echo "✅ Protocol:            ${CONN_PROXY_PROTO}"; else echo "❌ Protocol:            MISSING"; CONN_PASS=0; fi
if [ -n "${CONN_PROXY_EXPIRY}" ]; then echo "✅ Expiration:          ${CONN_PROXY_EXPIRY}"; else echo "❌ Expiration:          MISSING"; CONN_PASS=0; fi
if [ -n "${CONN_LIMIT}" ]; then echo "✅ Connection Limit:    ${CONN_LIMIT}"; else echo "❌ Connection Limit:    MISSING"; CONN_PASS=0; fi
echo ""

if [ -n "${CONN_SESSION_ID}" ]; then
    info "Waiting 1 minute before cancelling session..."
    sleep 60
    info "Cancelling session ${CONN_SESSION_ID}..."
    boundary sessions cancel \
        -id "${CONN_SESSION_ID}" \
        -addr "${BOUNDARY_ADDR}" \
        -token env://BOUNDARY_TOKEN 2>&1 || true
    pass "Session cancelled"
fi
kill "${CONN_PID}" 2>/dev/null || true
wait "${CONN_PID}" 2>/dev/null || true
rm -f "${CONN_OUT}"

[ "${CONN_PASS}" -eq 1 ] || fail "One or more session fields were missing"
pass "All session fields validated"
echo ""

echo "========================================"
echo " ✅ All Scenarios Passed"
echo "========================================"
echo "========================================"
echo -e "${GREEN}✅ All INT acceptance tests passed!${NC}"
echo "========================================"
