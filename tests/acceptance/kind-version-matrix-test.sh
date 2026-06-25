#!/bin/bash
# Copyright IBM Corp. 2026
# SPDX-License-Identifier: MPL-2.0

# Kubernetes Version Matrix Test — TCP Target Connection
# Tests tcp-target-conn-test.sh across configured kindest/node Kubernetes versions.
# Available tags reference: https://hub.docker.com/r/kindest/node
#
# For each Kubernetes version:
#   1. Creates a fresh KIND cluster pinned to kindest/node:<version>
#   2. Pre-loads the worker image into the node (arch-aware)
#   3. Generates a new worker.hcl via `make worker-config`
#   4. Installs the Helm chart
#   5. Runs tcp-target-conn-test.sh
#   6. Runs cleanup-worker.sh and tears down the cluster
# Prints a per-version pass/fail summary at the end.

set -euo pipefail

# -- Helpers --------------------------------------------------------------------
# All helpers write to stderr so they are safe to use inside $() subshells
# without polluting captured stdout.
pass()   { echo "   ✅ $1" >&2; }
fail()   { echo "❌ FAILED: $1" >&2; exit 1; }
info()   { echo "   $1" >&2; }
warn()   { echo "⚠️  WARN: $1" >&2; }
header() {
    echo "" >&2
    echo "  $1" >&2
}

# -- k8s_versions: resolve the Kubernetes node versions to test -----------------
# Priority:
# - K8S_VERSIONS: explicit one-off override (comma or space separated)
# - K8S_MATRIX_VERSIONS: ordered repository-configured list
k8s_versions() {
    if [ -n "${K8S_VERSIONS:-}" ]; then
        local normalized
        normalized="$(echo "${K8S_VERSIONS}" | tr ',' ' ' | xargs)"
        local count
        count="$(echo "${normalized}" | wc -w | tr -d ' ')"
        if [ "${count}" -ge 1 ]; then
            info "Using explicit versions from K8S_VERSIONS: ${normalized}"
            echo "${normalized}"
            return
        fi
    fi

    local configured="${K8S_MATRIX_VERSIONS:-}"
    [ -n "${configured}" ] || fail "Set K8S_MATRIX_VERSIONS or K8S_VERSIONS before running. See https://hub.docker.com/r/kindest/node for available tags."

    local normalized
    normalized="$(echo "${configured}" | tr ',' ' ' | xargs)"
    local count
    count="$(echo "${normalized}" | wc -w | tr -d ' ')"
    [ "${count}" -ge 1 ] || fail "K8S_MATRIX_VERSIONS did not contain any usable versions. See https://hub.docker.com/r/kindest/node for available tags."

    echo "${normalized}"
}

# -- Configuration --------------------------------------------------------------
# k8s_versions() runs in a command substitution, so its fail() only exits that
# subshell; guard here so an empty result aborts the parent (otherwise the loop
# would run zero times and report a misleading "all passed").
read -ra MATRIX_K8S_VERSIONS <<< "$(k8s_versions)"
[ "${#MATRIX_K8S_VERSIONS[@]}" -ge 1 ] || exit 1
KIND_CLUSTER_NAME="acceptance"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHART_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
KIND_CONFIG="${SCRIPT_DIR}/kind-acceptance-config.yaml"
TCP_TEST="${SCRIPT_DIR}/tcp-target-conn-test.sh"

# Print the resolved versions and exit (used by tooling / CI to build a matrix).
if [ "${PRINT_RESOLVED_K8S_VERSIONS:-false}" = "true" ]; then
    echo "${MATRIX_K8S_VERSIONS[*]}"
    exit 0
fi

# -- Architecture detection (for arch-aware image preload) ----------------------
_ARCH="$(uname -m)"
case "${_ARCH}" in
    x86_64)         _ARCH="amd64"  ;;
    arm64|aarch64)  _ARCH="arm64"  ;;
esac

# -- Load .env (for Boundary credentials / BOUNDARY_* vars) --------------------
if [ -f "${CHART_DIR}/.env" ]; then
    set -o allexport
    # shellcheck disable=SC1091
    source "${CHART_DIR}/.env"
    set +o allexport
fi

# -- Pre-flight checks ----------------------------------------------------------
header "Pre-flight Checks"
for cmd in kubectl helm boundary curl docker kind; do
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

# -- Crash-safe cleanup --------------------------------------------------------
# CURRENT_VERSION is set just before a cluster is created and cleared once that
# version has been fully torn down, so the EXIT trap only acts when the run is
# interrupted mid-version (Ctrl-C, error, or CI cancellation).
CURRENT_VERSION=""
_matrix_cleanup() {
    if [ -n "${CURRENT_VERSION:-}" ]; then
        echo "" >&2
        warn "Interrupted — tearing down KIND cluster '${KIND_CLUSTER_NAME}'..."
        kind delete cluster --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1 || true
    fi
    [ -n "${CHART_DIR:-}" ] && rm -f "${CHART_DIR}/worker.hcl" 2>/dev/null || true
}
trap _matrix_cleanup EXIT

# -- preload_worker_image: pull image locally then load into KIND node ---------
# This avoids a cold registry pull on a fresh node, which is the main cause
# of the deployment-readiness timeout in matrix runs.
preload_worker_image() {
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
    if ! kind load docker-image "${image}" \
            --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1; then
        warn "kind load docker-image failed — pod will pull from registry (may be slow)"
        return 0
    fi
    pass "Worker image pre-loaded: ${image}"
}

# -- cleanup_cluster: delete the acceptance cluster if it exists ---------------
cleanup_cluster() {
    if kind get clusters 2>/dev/null | grep -q "^${KIND_CLUSTER_NAME}$"; then
        info "Deleting existing KIND cluster '${KIND_CLUSTER_NAME}'..."
        kind delete cluster --name "${KIND_CLUSTER_NAME}" >/dev/null 2>&1
        pass "Cluster '${KIND_CLUSTER_NAME}' deleted"
    fi
}

# -- create_kind_config_for_k8s: pin every node to kindest/node:<version> ------
# Preserves the worker's NodePort extraPortMappings from kind-acceptance-config.yaml
# while injecting the requested Kubernetes node image on each node so the matrix
# can exercise the chart across multiple Kubernetes API-server versions.
create_kind_config_for_k8s() {
    local k8s_version="$1"
    local cfg
    cfg="$(mktemp)" || fail "Failed to create temp kind config"
    cat >"${cfg}" <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: ${KIND_CLUSTER_NAME}
nodes:
- role: control-plane
  image: kindest/node:${k8s_version}
  extraPortMappings:
  - containerPort: 30000
    hostPort: 30000
    protocol: TCP
  - containerPort: 30001
    hostPort: 30001
    protocol: TCP
- role: worker
  image: kindest/node:${k8s_version}
- role: worker
  image: kindest/node:${k8s_version}
EOF
    echo "${cfg}"
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
header "Kubernetes Version Matrix Test — TCP Target Connection"
echo "  Versions  : ${MATRIX_K8S_VERSIONS[*]}" >&2
echo "  Chart dir : ${CHART_DIR}" >&2

for VERSION in "${MATRIX_K8S_VERSIONS[@]}"; do

    header "Testing with Kubernetes ${VERSION}"
    info "Using node image: kindest/node:${VERSION}"
    echo "" >&2

    # Arm the EXIT trap for this version so an interrupt mid-setup still tears
    # the cluster down.
    CURRENT_VERSION="${VERSION}"

    # --- Per-version setup (steps 1-5) -----------------------------------------
    # Run setup in a subshell so a failure (cluster create / helm install)
    # records FAIL for this version and continues to the next, instead of
    # aborting the whole matrix via fail() -> exit 1.
    set +e
    (
        set -euo pipefail

        # 1. Remove any leftover cluster from a previous run
        cleanup_cluster

        # 2. Create a fresh cluster pinned to this Kubernetes version
        local_kind_cfg="$(create_kind_config_for_k8s "${VERSION}")"
        info "Creating KIND cluster '${KIND_CLUSTER_NAME}' using kindest/node:${VERSION}..."
        CREATE_OUT=$(mktemp) || fail "Failed to create temp file for cluster creation output"
        if ! kind create cluster \
            --name "${KIND_CLUSTER_NAME}" \
            --config "${local_kind_cfg}" >"${CREATE_OUT}" 2>&1; then
            echo "" >&2
            echo "❌ kind create cluster failed. Output:" >&2
            cat "${CREATE_OUT}" >&2
            rm -f "${local_kind_cfg}" "${CREATE_OUT}"
            fail "KIND cluster creation failed for Kubernetes ${VERSION}"
        fi
        rm -f "${local_kind_cfg}" "${CREATE_OUT}"
        pass "Cluster '${KIND_CLUSTER_NAME}' created with Kubernetes ${VERSION}"
        echo "" >&2

        # 3. Pre-load the worker image into the KIND node to avoid cold registry pull
        preload_worker_image
        echo "" >&2

        # 4. Generate a new worker activation token / worker.hcl
        generate_worker_config
        echo "" >&2

        # 5. Install the Helm chart
        install_helm_chart
        echo "" >&2
    )
    SETUP_EXIT=$?
    set -e

    if [ "${SETUP_EXIT}" -ne 0 ]; then
        RESULTS["${VERSION}"]="FAIL"
        RESULT_NOTES["${VERSION}"]="setup failed (exit code ${SETUP_EXIT})"
        warn "Kubernetes ${VERSION}: setup FAILED (exit code ${SETUP_EXIT}) — skipping TCP test"
    else
        # 6. Run the TCP target connection test with an extended timeout.
        # TIMEOUT=600 gives 10 min — enough for image load + Boundary registration.
        # tcp-target-conn-test.sh honours TIMEOUT env var (falls back to 300).
        info "Running tcp-target-conn-test.sh for Kubernetes ${VERSION} (TIMEOUT=600s)..."
        echo ""
        set +e
        ( cd "${CHART_DIR}" && TIMEOUT=600 bash "${TCP_TEST}" )
        TCP_EXIT=$?
        set -e

        if [ "${TCP_EXIT}" -eq 0 ]; then
            RESULTS["${VERSION}"]="PASS"
            RESULT_NOTES["${VERSION}"]=""
            pass "Kubernetes ${VERSION}: TCP target connection test PASSED"
        else
            RESULTS["${VERSION}"]="FAIL"
            RESULT_NOTES["${VERSION}"]="tcp-target-conn-test.sh exited with code ${TCP_EXIT}"
            warn "Kubernetes ${VERSION}: TCP target connection test FAILED (exit code ${TCP_EXIT})"
        fi
    fi

    # 7. Tear down the cluster
    echo ""
    info "Tearing down cluster for Kubernetes ${VERSION}..."
    cleanup_cluster

    # 8. Run Boundary-side cleanup to remove worker registration(s)
    # Run cleanup script from chart dir so it can load .env
    if [ -x "${SCRIPT_DIR}/cleanup-worker.sh" ]; then
        info "Running Boundary worker cleanup script..."
        (cd "${CHART_DIR}" && bash "${SCRIPT_DIR}/cleanup-worker.sh") || warn "cleanup-worker.sh failed for Kubernetes ${VERSION}"
    else
        warn "cleanup-worker.sh not found or not executable at ${SCRIPT_DIR}"
    fi

    info "Removing worker.hcl..."
    rm -f "${CHART_DIR}/worker.hcl"

    # This version is fully cleaned up — disarm the EXIT trap for it.
    CURRENT_VERSION=""
    pass "Cleanup complete for Kubernetes ${VERSION}"

done

# -- Summary --------------------------------------------------------------------
header "Matrix Test Summary"
printf "  %-16s  %-8s  %s\n" "K8s Version" "Result" "Notes" >&2
printf "  %-16s  %-8s  %s\n" "----------------" "--------" "-----" >&2

OVERALL_PASS=true
for VERSION in "${MATRIX_K8S_VERSIONS[@]}"; do
    RESULT="${RESULTS[${VERSION}]:-SKIP}"
    NOTE="${RESULT_NOTES[${VERSION}]:-}"
    if [ "${RESULT}" = "PASS" ]; then
        printf "  %-16s  ✅ %-8s  %s\n" "${VERSION}" "PASS" "${NOTE}" >&2
    else
        printf "  %-16s  ❌ %-8s  %s\n" "${VERSION}" "${RESULT}" "${NOTE}" >&2
        OVERALL_PASS=false
    fi
done

echo "" >&2
if [ "${OVERALL_PASS}" = "true" ]; then
    pass "All Kubernetes versions passed the TCP target connection test!"
    exit 0
else
    fail "One or more Kubernetes versions failed — see summary above."
fi
