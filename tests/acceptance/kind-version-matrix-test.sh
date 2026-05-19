#!/bin/bash
# Copyright IBM Corp. 2026

# KIND Version Matrix Test — TCP Target Connection
# Dynamically resolves the latest stable KIND release from GitHub, then runs
# tcp-target-conn-test.sh against the two versions immediately preceding it
# (latest-1 and latest-2).  Falls back to hardcoded defaults when offline.
# For each version:
#   1. Downloads the pinned KIND binary (cached in /tmp)
#   2. Creates a fresh KIND cluster using kind-acceptance-config.yaml
#   3. Generates a new worker.hcl via `make worker-config`
#   4. Installs the Helm chart
#   5. Runs tcp-target-conn-test.sh
#   6. Tears down the cluster
# Prints a per-version pass/fail summary at the end.

set -euo pipefail

# -- Helpers --------------------------------------------------------------------
# All helpers write to stderr so they are safe to use inside $() subshells
# (e.g. download_kind) without polluting captured stdout.
pass()   { echo "   ✅ $1" >&2; }
fail()   { echo "❌ FAILED: $1" >&2; exit 1; }
info()   { echo "   $1" >&2; }
warn()   { echo "⚠️  WARN: $1" >&2; }
header() {
    echo "" >&2
    echo "  $1" >&2
}

# -- Fallback versions (used when GitHub API is unreachable) -------------------
_FALLBACK_KIND_VERSIONS=("v0.30.0" "v0.29.0")

# -- resolve_kind_versions -----------------------------------------------------
# Queries the GitHub Releases API for kubernetes-sigs/kind, sorts stable tags
# by semver descending, and returns the two versions immediately below the
# latest (latest-1 and latest-2) so the matrix always tests the two most
# recently released prior versions without any manual edits.
resolve_kind_versions() {
    local raw
    raw="$(curl -fsSL --retry 2 --connect-timeout 10 \
        "https://api.github.com/repos/kubernetes-sigs/kind/releases" 2>/dev/null)" || true

    if [ -z "${raw}" ]; then
        warn "GitHub Releases API unreachable — using fallback KIND versions: ${_FALLBACK_KIND_VERSIONS[*]}"
        echo "${_FALLBACK_KIND_VERSIONS[@]}"
        return
    fi

    local output
    output="$(printf '%s' "${raw}" | python3 -c "
import json, sys
releases = json.load(sys.stdin)
tags = sorted(
    [r['tag_name'] for r in releases
     if not r.get('prerelease', False) and r.get('tag_name', '').startswith('v')],
    key=lambda v: [int(x) for x in v.lstrip('v').split('.')],
    reverse=True
)
print(' '.join(tags[1:3]))
" 2>/dev/null)" || true

    local word_count
    word_count="$(echo "${output}" | wc -w | tr -d ' ')"
    if [ -z "${output}" ] || [ "${word_count}" -lt 2 ]; then
        warn "Could not parse KIND releases — using fallback: ${_FALLBACK_KIND_VERSIONS[*]}"
        echo "${_FALLBACK_KIND_VERSIONS[@]}"
        return
    fi

    echo "${output}"
}

# -- Configuration --------------------------------------------------------------
read -ra KIND_VERSIONS <<< "$(resolve_kind_versions)"
KIND_CLUSTER_NAME="acceptance"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/kind-acceptance-config.yaml"
TCP_TEST="${SCRIPT_DIR}/tcp-target-conn-test.sh"
KIND_CACHE_DIR="${TMPDIR:-/tmp}"

# -- OS / Architecture detection ------------------------------------------------
_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
_ARCH="$(uname -m)"
case "${_ARCH}" in
    x86_64)         _ARCH="amd64"  ;;
    arm64|aarch64)  _ARCH="arm64"  ;;
    *) fail "Unsupported architecture: ${_ARCH}" ;;
esac
KIND_PLATFORM="${_OS}-${_ARCH}"

# -- Load .env (for Boundary credentials / BOUNDARY_* vars) --------------------
if [ -f "${CHART_DIR}/.env" ]; then
    set -o allexport
    # shellcheck disable=SC1091
    source "${CHART_DIR}/.env"
    set +o allexport
fi

# -- Pre-flight checks ----------------------------------------------------------
header "Pre-flight Checks"
for cmd in kubectl helm boundary curl python3 docker; do
    command -v "${cmd}" >/dev/null 2>&1 \
        || fail "'${cmd}' is required but not installed. Run: make acceptance-setup"
    pass "${cmd} found"
done

# Confirm Docker daemon is reachable
docker info >/dev/null 2>&1 \
    || fail "Docker daemon is not running. Start Docker Desktop and retry."
pass "Docker daemon is running"

[ -f "${KIND_CONFIG}" ]  || fail "Kind config not found: ${KIND_CONFIG}"
[ -f "${TCP_TEST}" ]     || fail "TCP test not found: ${TCP_TEST}"
pass "Test scripts present"

# Check required Boundary env vars
for var in BOUNDARY_ADDR BOUNDARY_AUTH_METHOD_ID BOUNDARY_LOGIN_NAME BOUNDARY_PASSWORD BOUNDARY_CLUSTER_ID; do
    [ -n "${!var:-}" ] \
        || fail "'${var}' is not set. Add it to .env or export it before running."
done
pass "Required Boundary environment variables are set"
echo ""

# -- Result tracking ------------------------------------------------------------
declare -A RESULTS
declare -A RESULT_NOTES

# -- download_kind: fetch a pinned KIND binary, cache it in /tmp ----------------
download_kind() {
    local version="$1"
    local bin_path="${KIND_CACHE_DIR}/kind-${version}"

    if [ -x "${bin_path}" ]; then
        info "Using cached KIND ${version} at ${bin_path}"
    else
        info "Downloading KIND ${version} for ${KIND_PLATFORM}..."
        curl -fsSL \
            "https://kind.sigs.k8s.io/dl/${version}/kind-${KIND_PLATFORM}" \
            -o "${bin_path}"
        chmod +x "${bin_path}"
        pass "Downloaded KIND ${version}"
    fi

    echo "${bin_path}"
}

# -- preload_worker_image: pull image locally then load into KIND node ---------
# This avoids a cold registry pull on a fresh node, which is the main cause
# of the deployment-readiness timeout in matrix runs.
preload_worker_image() {
    local kind_bin="$1"
    # Use BOUNDARY_BYOW_IMAGE if set (enterprise/custom image), else chart default
    local image="${BOUNDARY_BYOW_IMAGE:-hashicorp/boundary-enterprise:0.21-ent}"
    info "Pre-loading worker image into KIND cluster: ${image}"

    # Pull into local Docker daemon (honours existing credentials / layer cache)
    if ! docker image inspect "${image}" >/dev/null 2>&1; then
        info "Image not in local daemon — pulling..."
        if ! docker pull "${image}" >/dev/null 2>&1; then
            warn "docker pull failed for ${image} — pod will pull from registry (may be slow)"
            return 0
        fi
    fi

    # On Apple Silicon (or any cross-arch host): the CRI image cache rejects
    # images whose architecture doesn't match the node's native architecture,
    # causing the kubelet to fall back to a registry pull even when the image
    # was successfully loaded into containerd.  Detect the mismatch and use
    # docker buildx to create a native-arch wrapper (the amd64 binaries still
    # run via Docker Desktop's QEMU/Rosetta binfmt_misc emulation at runtime).
    local img_arch
    img_arch="$(docker image inspect "${image}" --format '{{.Architecture}}' 2>/dev/null || true)"
    if [ -n "${img_arch}" ] && [ "${img_arch}" != "${_ARCH}" ]; then
        info "Image arch (${img_arch}) ≠ node arch (${_ARCH}) — building ${_ARCH} wrapper via buildx..."
        if docker buildx build \
                --platform "linux/${_ARCH}" \
                --tag "${image}" \
                --load \
                - >/dev/null 2>&1 <<EOF
FROM --platform=linux/${img_arch} ${image}
EOF
        then
            info "Platform-compatible wrapper created: ${image} (${_ARCH})"
        else
            warn "buildx wrapper failed — pod may hit ImagePullBackOff on ${_ARCH} nodes"
        fi
    fi

    # Load from local daemon into the KIND node
    if ! "${kind_bin}" load docker-image "${image}" \
            --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1; then
        warn "kind load docker-image failed — pod will pull from registry (may be slow)"
        return 0
    fi
    pass "Worker image pre-loaded: ${image}"
}

# -- cleanup_cluster: delete the acceptance cluster if it exists ---------------
cleanup_cluster() {
    local kind_bin="$1"
    if "${kind_bin}" get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        info "Deleting existing KIND cluster '${KIND_CLUSTER_NAME}'..."
        "${kind_bin}" delete cluster --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1
        pass "Cluster '${KIND_CLUSTER_NAME}' deleted"
    fi
}

# -- generate_worker_config: create a fresh worker.hcl activation token --------
generate_worker_config() {
    info "Generating fresh worker.hcl (new activation token)..."
    (cd "${CHART_DIR}" && make worker-config) \
        || fail "worker-config failed — verify BOUNDARY_ADDR and credentials in .env"
    [ -f "${CHART_DIR}/worker.hcl" ] || fail "worker.hcl was not created"
    pass "worker.hcl generated"
}

# -- install_helm_chart: install / upgrade the chart ---------------------------
# NOTE: deployment readiness is intentionally NOT checked here.
# tcp-target-conn-test.sh owns that wait (kubectl wait --for=condition=available
# with its own TIMEOUT), so a duplicate check here would just cause early
# failures when the worker takes longer to register with Boundary.
install_helm_chart() {
    info "Installing boundary-worker Helm chart..."

    # If BOUNDARY_BYOW_IMAGE is set (e.g. via direnv), override the chart image
    # so the preloaded image is the one actually deployed.
    local image_flags=()
    if [ -n "${BOUNDARY_BYOW_IMAGE:-}" ]; then
        if [[ "${BOUNDARY_BYOW_IMAGE}" != *:* ]]; then
            fail "BOUNDARY_BYOW_IMAGE must be in repo:tag format, got: ${BOUNDARY_BYOW_IMAGE}"
        fi
        local img_repo="${BOUNDARY_BYOW_IMAGE%:*}"
        local img_tag="${BOUNDARY_BYOW_IMAGE##*:}"
        if [ -z "${img_repo}" ] || [ -z "${img_tag}" ]; then
            fail "BOUNDARY_BYOW_IMAGE must be in repo:tag format, got: ${BOUNDARY_BYOW_IMAGE}"
        fi
        image_flags=(--set "image.repository=${img_repo}" --set "image.tag=${img_tag}")
        info "Using image override: ${BOUNDARY_BYOW_IMAGE}"
    fi

    HELM_OUT=$(mktemp)
    if ! helm install boundary-worker "${CHART_DIR}" \
        --namespace boundary \
        --create-namespace \
        --kube-context "kind-${KIND_CLUSTER_NAME}" \
        --set worker.service.proxy.type=NodePort \
        --set worker.persistence.recording.storageClass=standard \
        --set worker.persistence.authStorage.storageClass=standard \
        --set-file worker.config="${CHART_DIR}/worker.hcl" \
        "${image_flags[@]+"${image_flags[@]}"}" \
        --timeout 5m >${HELM_OUT} 2>&1; then
        echo "" >&2
        echo "❌ helm install failed. Output:" >&2
        cat "${HELM_OUT}" >&2
        rm -f "${HELM_OUT}"
        fail "Helm chart installation failed"
    fi
    rm -f "${HELM_OUT}"

    # Verify at least one pod was scheduled before handing off to the TCP test
    info "Verifying worker pod was scheduled..."
    for ((i=1; i<=30; i++)); do
        POD_COUNT=$(kubectl get pods \
            -n boundary \
            --context "kind-${KIND_CLUSTER_NAME}" \
            -l app.kubernetes.io/name=boundary-worker \
            --no-headers 2>/dev/null | wc -l | tr -d ' ')
        [ "${POD_COUNT}" -gt 0 ] && break
        sleep 2
    done
    [ "${POD_COUNT:-0}" -gt 0 ] \
        || fail "No worker pod was scheduled after helm install"
    pass "Helm chart installed — ${POD_COUNT} pod(s) scheduled (readiness handled by TCP test)"
}

# -- Main matrix loop -----------------------------------------------------------
header "KIND Version Matrix Test — TCP Target Connection"
echo "  Platform  : ${KIND_PLATFORM}"
echo "  Versions  : ${KIND_VERSIONS[*]}"
echo "  Chart dir : ${CHART_DIR}"

for VERSION in "${KIND_VERSIONS[@]}"; do

    header "Testing with KIND ${VERSION}"
    echo "  --------------------------------" >&2

    # 1. Download pinned KIND binary
    KIND_BIN="$(download_kind "${VERSION}")"

    # 2. Confirm binary reports the expected version
    DETECTED="$("${KIND_BIN}" version 2>&1)"
    info "Binary reports: ${DETECTED}"
    echo ""

    # 3. Remove any leftover cluster from a previous run
    cleanup_cluster "${KIND_BIN}"

    # 4. Create a fresh cluster with this KIND version
    info "Creating KIND cluster '${KIND_CLUSTER_NAME}' using KIND ${VERSION}..."
    CREATE_OUT=$(mktemp)
    if ! "${KIND_BIN}" create cluster \
        --name "${KIND_CLUSTER_NAME}" \
        --config "${KIND_CONFIG}" >${CREATE_OUT} 2>&1; then
        echo "" >&2
        echo "❌ kind create cluster failed. Output:" >&2
        cat "${CREATE_OUT}" >&2
        rm -f "${CREATE_OUT}"
        fail "KIND cluster creation failed for ${VERSION}"
    fi
    rm -f "${CREATE_OUT}"
    pass "Cluster '${KIND_CLUSTER_NAME}' created with KIND ${VERSION}"
    echo ""

    # 5. Pre-load the worker image into the KIND node to avoid cold registry pull
    preload_worker_image "${KIND_BIN}"
    echo ""

    # 6. Generate a new worker activation token / worker.hcl
    generate_worker_config
    echo ""

    # 7. Install the Helm chart
    install_helm_chart
    echo ""

    # 8. Run the TCP target connection test with an extended timeout.
    # TIMEOUT=600 gives 10 min — enough for image load + Boundary registration.
    # tcp-target-conn-test.sh honours TIMEOUT env var (falls back to 300).
    info "Running tcp-target-conn-test.sh for KIND ${VERSION} (TIMEOUT=600s)..."
    echo ""
    set +e
    TIMEOUT=600 bash "${TCP_TEST}"
    TCP_EXIT=$?
    set -e

    if [ "${TCP_EXIT}" -eq 0 ]; then
        RESULTS["${VERSION}"]="PASS"
        RESULT_NOTES["${VERSION}"]=""
        pass "KIND ${VERSION}: TCP target connection test PASSED"
    else
        RESULTS["${VERSION}"]="FAIL"
        RESULT_NOTES["${VERSION}"]="tcp-target-conn-test.sh exited with code ${TCP_EXIT}"
        warn "KIND ${VERSION}: TCP target connection test FAILED (exit code ${TCP_EXIT})"
    fi

    # 9. Tear down the cluster
    echo ""
    info "Tearing down cluster for KIND ${VERSION}..."
    cleanup_cluster "${KIND_BIN}"
    info "Removing worker.hcl..."
    rm -f "${CHART_DIR}/worker.hcl"
    pass "Cleanup complete for KIND ${VERSION}"

done

# -- Summary --------------------------------------------------------------------
header "Matrix Test Summary"
printf "  %-14s  %-8s  %s\n" "KIND Version" "Result" "Notes"
printf "  %-14s  %-8s  %s\n" "--------------" "--------" "-----"

OVERALL_PASS=true
for VERSION in "${KIND_VERSIONS[@]}"; do
    RESULT="${RESULTS[${VERSION}]:-SKIP}"
    NOTE="${RESULT_NOTES[${VERSION}]:-}"
    if [ "${RESULT}" = "PASS" ]; then
        printf "  %-14s  ✅ %-8s  %s\n" "${VERSION}" "PASS" "${NOTE}"
    else
        printf "  %-14s  ❌ %-8s  %s\n" "${VERSION}" "${RESULT}" "${NOTE}"
        OVERALL_PASS=false
    fi
done

echo ""
if [ "${OVERALL_PASS}" = "true" ]; then
    pass "All KIND versions passed the TCP target connection test!"
    exit 0
else
    fail "One or more KIND versions failed — see summary above."
fi
