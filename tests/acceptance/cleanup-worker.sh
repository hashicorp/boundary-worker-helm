#!/bin/bash
# Copyright IBM Corp. 2026

# Cleanup Worker from Boundary Cluster
# This script deletes the worker registration from Boundary after acceptance tests

set -euo pipefail

# ── Helpers ────────────────────────────────────────────────────────────────────
pass() { echo "   ✅ $1"; }
fail() { echo "❌ FAILED: $1"; exit 1; }
info() { echo "   $1"; }
warn() { echo "⚠️ WARN: $1"; }

# ── Load .env ─────────────────────────────────────────────────────────────────
if [ -f .env ]; then
    set -o allexport
    # shellcheck disable=SC1091
    source .env
    set +o allexport
fi

echo "Boundary Worker Cleanup"
echo ""

# Check if worker ID file exists
WORKER_ID_FILE="/tmp/boundary-worker-id.txt"
if [ ! -f "${WORKER_ID_FILE}" ]; then
    warn "Worker ID file not found at ${WORKER_ID_FILE}"
    warn "Worker may not have been registered or test did not complete"
    exit 0
fi

WORKER_ID=$(cat "${WORKER_ID_FILE}" 2>/dev/null || true)
if [ -z "${WORKER_ID}" ]; then
    warn "Worker ID file is empty"
    exit 0
fi

info "Found worker ID: ${WORKER_ID}"
echo ""

# Check required env vars
for var in BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD; do
    [ -n "${!var:-}" ] || fail "'${var}' is not set. Check your .env file."
done

# Authenticate with Boundary
info "Authenticating with Boundary cluster..."
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
pass "Authenticated with Boundary cluster"
echo ""

# Delete the worker
info "Deleting worker ${WORKER_ID} from Boundary..."
DELETE_OUT=$(boundary workers delete \
    -id "${WORKER_ID}" \
    -addr "${BOUNDARY_ADDR}" \
    -token env://BOUNDARY_TOKEN 2>&1) || {
    warn "Failed to delete worker: ${DELETE_OUT}"
    warn "Worker may have already been deleted or does not exist"
    rm -f "${WORKER_ID_FILE}"
    exit 0
}

pass "Worker ${WORKER_ID} deleted from Boundary"
echo ""

# Clean up the worker ID file
rm -f "${WORKER_ID_FILE}"
info "Cleaned up worker ID file"
echo ""

echo "✅ Worker cleanup complete!"
