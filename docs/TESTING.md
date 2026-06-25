# Testing Guide

This document describes the test suite for the Boundary Worker Helm chart.

## Overview

The chart includes several layers of test coverage:

- **Unit Tests**: Helm template rendering validation using `helm-unittest`
- **Helm Tests**: In-cluster smoke hooks run with `helm test`
- **Acceptance Tests**: Local KIND cluster tests that validate end-to-end worker functionality
- **Integration Tests**: Cloud provider tests against EKS (AWS) , GKE (GCP) and AKS (Azure)

## Prerequisites

All tests share these base requirements:

- Docker running locally
- `kubectl` CLI installed
- `helm` CLI installed
- `boundary` CLI installed
- `curl` installed
- `python3` installed (used to parse Boundary JSON output in the acceptance tests)
- KIND for local cluster testing (`brew install kind`)

Install all local dependencies at once:

```bash
make deps
```

Acceptance and integration tests additionally require a `.env` file in the chart root directory (see [Acceptance Tests](#acceptance-tests) below).

---

## Unit Tests

Unit tests validate that Helm templates render correctly for a range of value combinations. They run entirely offline — no cluster is required.

### Running unit tests

```bash
make unit-test
```

Or directly with the `helm-unittest` plugin:

```bash
helm unittest .
```

### Test files

Unit test files are in `tests/unit/`:

| File | What it covers |
|---|---|
| `helpers_test.yaml` | Template helper functions (labels, names, selectors) |
| `worker-deployment_test.yaml` | Deployment structure, security context, volume mounts |
| `worker-configmap_test.yaml` | ConfigMap rendering, HCL content injection |
| `worker-service_test.yaml` | Proxy and ops Service creation, port mappings, annotations |
| `worker-pvc_test.yaml` | PVC creation, access modes, StorageClass, disabled behaviour |

### CI setup

Install the plugin in a CI environment:

```bash
make setup-helm-unittest
```

---

## Helm Tests

The `templates/tests/` directory contains in-cluster Helm test hooks that run after installation. They validate that the deployed worker is healthy.

```bash
helm test boundary-worker -n boundary
```

These tests cover:
- Pod readiness and health endpoints
- Proxy and ops Service reachability
- ConfigMap and volume mount correctness
- Security context enforcement

---

## Acceptance Tests

Acceptance tests run against a local KIND cluster and validate the full worker deployment workflow, including registration with a live Boundary cluster.

### Setup

#### 1. Create a `.env` file

Create a `.env` file in the chart root directory with the following variables:

```bash
# Boundary cluster connection
BOUNDARY_ADDR="https://<your-boundary-cluster-addr>"
BOUNDARY_AUTH_METHOD_ID="ampw_<your-auth-method-id>"
BOUNDARY_LOGIN_NAME="<your-admin-username>"
BOUNDARY_PASSWORD="<your-admin-password>"

# Required for worker registration (HCP Boundary)
BOUNDARY_CLUSTER_ID="<your-hcp-boundary-cluster-id>"

# Required for TCP target connection test
BOUNDARY_TARGET_ID="ttcp_<your-target-id>"

# Optional: default Kubernetes version matrix (space or comma separated kindest/node tags).
# Auto-loaded and exported by the Makefile; override per-run with K8S_VERSIONS.
# K8S_MATRIX_VERSIONS="v1.36.1 v1.35.5 v1.34.8"
```

#### 2. Generate a worker HCL configuration

```bash
make worker-config
```

This authenticates with Boundary, creates a new worker resource, and writes a ready-to-use `worker.hcl` to the chart root. That workflow still embeds the activation token directly for local and CI automation. The chart also supports the controller-chart-style Secret flow, where `worker.config` references `env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN` and the token comes from `secretRefs`.

#### 3. Install dependencies

```bash
make acceptance-setup
```

This installs KIND and creates a local `acceptance` cluster using `tests/acceptance/kind-acceptance-config.yaml`.

---

### Cluster Smoke Test

Basic validation that a KIND cluster can be created and accessed.

```bash
bash tests/acceptance/cluster-smoke-test.sh
```

**What it tests:**
- KIND cluster accessibility (`kind-acceptance` context)
- Namespace creation
- Basic `kubectl` operations

**Duration:** ~30 seconds

---

### TCP Target Connection Test

End-to-end validation of a fully deployed worker: registration, session creation, and TCP proxy connection.

```bash
cd boundary-worker-helm
bash tests/acceptance/tcp-target-conn-test.sh
```

**What it tests:**
1. Worker Deployment is running in the KIND cluster
2. Worker pod is healthy (ops health endpoint at port 9203)
3. Worker auth storage is populated (node enrollment initiated)
4. Worker record exists in Boundary after activation token consumption
5. Worker is reaching the upstream Boundary cluster (log inspection)
6. Session can be authorized against a configured TCP target
7. `boundary connect` establishes a proxy and returns valid session fields:
   - Session ID, proxy address, port, protocol, expiration, connection limit

**Duration:** ~5–10 minutes

**Requirements:**
- `.env` file with all variables listed above
- An active, reachable TCP target in your Boundary environment (`BOUNDARY_TARGET_ID`)
- The worker must have connectivity to the Boundary cluster from inside the KIND cluster

---

### Kubernetes Version Matrix Test

Runs `tcp-target-conn-test.sh` across multiple Kubernetes versions to validate the chart against different Kubernetes API-server versions. Each version uses a KIND cluster pinned to the matching `kindest/node` image.

```bash
make k8s-matrix-test K8S_MATRIX_VERSIONS="v1.36.1 v1.35.5 v1.34.8"
```

Test a single version (faster iteration):

```bash
make k8s-matrix-test K8S_VERSIONS="v1.36.1"
```

**Version source:**
- `K8S_MATRIX_VERSIONS` — the configured list of `kindest/node` tags (space or comma separated).
- `K8S_VERSIONS` — a one-off override that takes precedence over `K8S_MATRIX_VERSIONS`.

The run fails fast if neither is set. Available tags: https://hub.docker.com/r/kindest/node

**What it tests:**
- The full TCP target connection test on every configured Kubernetes version
- Independent pass/fail per version (one version failing does not stop the others)

**Process (per version):**
1. Deletes any leftover `acceptance` cluster
2. Creates a fresh cluster pinned to `kindest/node:<version>`, rendered from `tests/acceptance/k8s-matrix-config.yaml.tpl`
3. Pre-loads the worker image into the node (arch-aware)
4. Generates a new `worker.hcl` via `make worker-config`
5. Installs the Helm chart
6. Runs `tcp-target-conn-test.sh` with `TIMEOUT=600`
7. Tears down the cluster and removes the worker registration from Boundary
8. Prints a per-version pass/fail summary at the end

**Requirements:**
- KIND **v0.32.0+** locally — current node images (e.g. `v1.36.1`) require it; older KIND cannot load them and the worker pod will `ImagePullBackOff`. The `kindest/node` tags must match your installed KIND version (see each KIND release's notes).
- Same `.env` and target requirements as the TCP target connection test.

**Duration:** ~5–10 minutes per version (run serially on one machine).

**Configuring the matrix in CI:**

In GitHub Actions the version list comes from a **repository variable** named `K8S_MATRIX_VERSIONS` (not a secret). The `acceptance-matrix` job hard-fails if it is unset, so you must create it before the workflow can run:

1. Go to **Settings → Secrets and variables → Actions → Variables → New repository variable**.
2. Name: `K8S_MATRIX_VERSIONS`
3. Value: a space- or comma-separated list of `kindest/node` image tags, e.g. `v1.36.1 v1.35.5 v1.34.8`.

Format and tag rules:
- Each entry is a `kindest/node` tag including the leading `v` (e.g. `v1.36.1`), **not** a bare `1.36`.
- Tags must be published for the KIND version CI installs (CI uses the latest KIND, so use the latest release's tags). Browse valid tags at https://hub.docker.com/r/kindest/node or the KIND release notes.
- For a one-off run you can override the variable with the `workflow_dispatch` **`k8s_versions`** input — it takes precedence over the repository variable for that run only.

The same `BOUNDARY_*` secrets the TCP target connection test needs must also be configured as Actions secrets, otherwise the per-version jobs fail at worker registration.

> In CI, these versions run **in parallel** — one job per version — via the `acceptance-matrix` and `acceptance-test` jobs in `.github/workflows/test.yml`, driven by the `K8S_MATRIX_VERSIONS` repository variable (or the `workflow_dispatch` `k8s_versions` input).

Preview the resolved version list without creating any clusters:

```bash
PRINT_RESOLVED_K8S_VERSIONS=true K8S_MATRIX_VERSIONS="v1.36.1 v1.35.5" \
  bash tests/acceptance/k8s-version-matrix-test.sh
```

---

### Full acceptance workflow (one command)

```bash
make acceptance-full
```

This runs the complete sequence: `acceptance-setup` → `worker-config` → `acceptance-helm` → `acceptance-test`.

---

### Cleanup

Remove the KIND cluster, Helm release, and worker registration from Boundary:

```bash
make acceptance-cleanup
```

This performs the following cleanup actions:
1. Deletes the worker registration from the Boundary cluster (prevents worker buildup)
2. Deletes the `acceptance` KIND cluster (removing the Helm release with it)
3. Removes the generated `worker.hcl` and the worker-ID file (`/tmp/boundary-worker-id.txt`)

To clean up after a matrix run:

```bash
make k8s-matrix-cleanup
```

This deletes the `acceptance` KIND cluster and removes the generated `worker.hcl` and worker-ID file (`/tmp/boundary-worker-id.txt`).

---

## Integration Tests

### AWS EKS

Integration tests deploy the worker chart to a real EKS cluster provisioned with Terraform.

#### Setup

```bash
# Provision EKS cluster (VPC + EKS + EBS CSI + Load Balancer Controller)
make eks-setup
```

#### Install chart

```bash
# Generates worker.hcl and installs the chart with gp3 StorageClass and NLB annotations
make eks-helm
```

#### Run tests

```bash
make eks-test
```

#### Full workflow

```bash
make eks-full
```

#### Cleanup

```bash
# Uninstall Helm release only
make eks-cleanup

# Uninstall Helm release and destroy cluster
DESTROY_CLUSTER=true make eks-cleanup
```

#### Terraform targets (AWS)

```bash
make tf-setup       # terraform init + apply
make tf-plan        # preview changes
make tf-output      # show outputs (cluster name, kubeconfig command)
make tf-destroy     # destroy all AWS resources
```

---

### Azure AKS

Integration tests deploy the worker chart to an AKS cluster provisioned with Terraform.

#### Full workflow

```bash
make aks-full
```

#### Cleanup

```bash
# Uninstall Helm release only
make aks-cleanup

# Uninstall Helm release and destroy cluster
DESTROY_CLUSTER=true make aks-cleanup
```

#### Terraform targets (Azure)

```bash
make tf-setup-aks    # terraform init + apply (VNet + AKS + StorageClass)
make tf-plan-aks     # preview changes
make tf-output-aks   # show outputs
make tf-destroy-aks  # destroy all Azure resources
```

---

## Test Configuration

### KIND cluster configuration

The acceptance cluster is defined in `tests/acceptance/kind-acceptance-config.yaml`:

- 1 control-plane node, 2 worker nodes
- Port 30000 and 30001 mapped from container to host for NodePort services

The Kubernetes version matrix test uses a separate template, `tests/acceptance/k8s-matrix-config.yaml.tpl`, with the same topology but a `__K8S_VERSION__` placeholder that the script substitutes with each `kindest/node` tag. Edit node roles / port mappings there to change the matrix cluster layout.

### Timeout configuration

The `tcp-target-conn-test.sh` script defaults to a 300-second deployment wait timeout. The matrix test overrides this to 600 seconds. You can override it manually:

```bash
TIMEOUT=600 bash tests/acceptance/tcp-target-conn-test.sh
```

---

## Linting and Security Scans

These checks run against the chart templates without a live cluster.

```bash
# Helm lint + template render + Kubernetes schema validation (Kubeconform)
make lint-helm-k8s

# Trivy vulnerability scan
make trivy-scan

# Kubescape NSA/MITRE security scan
make kubescape-scan

# Run everything: lint, trivy, kubescape
make lint
```

---

## Troubleshooting

### Worker pod not ready

```bash
kubectl get pods -n boundary
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker
kubectl describe pod -n boundary -l app.kubernetes.io/name=boundary-worker
```

### PVC stuck in `Pending`

KIND does not have a default dynamic StorageClass for persistent volumes. For acceptance tests the chart uses the cluster default. If PVCs remain pending, check:

```bash
kubectl get pvc -n boundary
kubectl describe pvc -n boundary
kubectl get storageclass
```

### Ops health endpoint not responding

```bash
kubectl port-forward -n boundary svc/boundary-worker-ops 9203:9203
curl http://localhost:9203/health
```

### Worker not registering with Boundary

1. Confirm `BOUNDARY_CLUSTER_ID` or `initial_upstreams` is correct in `worker.hcl`.
2. Check pod logs for upstream connection errors:
   ```bash
   kubectl logs -n boundary deployment/boundary-worker-deployment
   ```
3. Confirm the activation token in `worker.hcl` has not already been consumed (tokens are single-use).
4. Check that the KIND cluster nodes can reach the Boundary cluster address (DNS + firewall).

### Cleanup after test failures

```bash
# Delete the KIND cluster
kind delete cluster --name acceptance

# Remove generated worker artifacts (optional)
rm -f worker.hcl /tmp/boundary-worker-id.txt
```

---

## CI/CD Integration

The tests are integrated into GitHub Actions workflows:

- **PR validation**: `lint-helm-k8s`, unit tests, and Trivy / Kubescape scans run on every pull request
- **Acceptance matrix**: On non-draft PRs to `main` (and via manual dispatch), the worker is deployed and the TCP target connection test runs in parallel across every Kubernetes version in `K8S_MATRIX_VERSIONS` (`acceptance-matrix` / `acceptance-test` jobs in `test.yml`). Requires the `K8S_MATRIX_VERSIONS` repository variable and the `BOUNDARY_*` secrets.
- **Push validation**: Runs on pushes to main branches
- **Release validation**: Runs before creating releases

See `.github/workflows/` for workflow configuration.

---

## Adding New Tests

### Unit tests

1. Create a `*_test.yaml` file in `tests/unit/`.
2. Follow the [helm-unittest](https://github.com/helm-unittest/helm-unittest) assertion format.
3. Run `make unit-test` to validate.

### Acceptance tests

1. Place test scripts in `tests/acceptance/`.
2. Make scripts executable: `chmod +x tests/acceptance/your-test.sh`.
3. Follow existing patterns for cleanup traps and `.env` loading.
4. Document test purpose and requirements.
5. Update this guide with a test description.

---

## Test Maintenance

### Updating Kubernetes versions

The matrix test resolves versions from the `K8S_MATRIX_VERSIONS` repository variable (CI) or the `K8S_VERSIONS` / `K8S_MATRIX_VERSIONS` argument (local) — there are no hardcoded Kubernetes versions in the script. To change the tested set:

- **CI:** update the `K8S_MATRIX_VERSIONS` repository variable (Settings → Secrets and variables → Actions → Variables), e.g. `v1.36.1 v1.35.5 v1.34.8`.
- **Local:** pass them on the command line, e.g. `make k8s-matrix-test K8S_MATRIX_VERSIONS="v1.36.1 v1.35.5"`.

Use `kindest/node` tags that match your installed KIND version (each KIND release publishes a specific set). Available tags: https://hub.docker.com/r/kindest/node

### Updating test values

The acceptance tests install the chart using the generated `worker.hcl` and the default `values.yaml`. To override chart values during acceptance testing, edit `make acceptance-helm` in the `Makefile` and pass an additional `-f` flag.

**Important:** Keep acceptance-specific overrides minimal and focused on what the test environment requires.
