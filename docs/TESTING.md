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
```

#### 2. Generate a worker HCL configuration

```bash
make worker-config
```

This authenticates with Boundary, creates a new worker resource, and writes a ready-to-use `worker.hcl` to the chart root. The activation token is embedded automatically.

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

### KIND Version Matrix Test

Runs `tcp-target-conn-test.sh` across multiple KIND versions for Kubernetes compatibility validation.

```bash
cd boundary-worker-helm
bash tests/acceptance/kind-version-matrix-test.sh
```

Or via `make`:

```bash
make kind-matrix-test
```

**What it tests:**
- Full TCP target connection test across the two most recent stable KIND releases
- Automatically resolves latest KIND releases from the GitHub Releases API
- Falls back to hardcoded versions when offline (`v0.30.0`, `v0.29.0`)

**Duration:** ~15–20 minutes (runs the full test suite twice)

**Process:**
1. Resolves two prior stable KIND versions (latest-1 and latest-2)
2. Downloads pinned KIND binaries (cached in `/tmp`)
3. Creates a fresh KIND cluster for each version using `kind-acceptance-config.yaml`
4. Generates a new `worker.hcl` via `make worker-config`
5. Installs the Helm chart via `make acceptance-helm`
6. Runs `tcp-target-conn-test.sh` with `TIMEOUT=600`
7. Tears down the cluster
8. Repeats for the next version
9. Prints a per-version pass/fail summary

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
2. Deletes the `acceptance` KIND cluster
3. Uninstalls the Helm release
4. Preserves cached KIND binaries in `/tmp` for faster subsequent test runs

To also remove cached KIND binaries (used by the matrix test):

```bash
make kind-matrix-cleanup
```

This removes all downloaded KIND version binaries from `/tmp/kind-v*`. Use this when you want a completely clean state or to free up disk space.

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

# Clean up cached KIND binaries (optional)
rm -f /tmp/kind-v*
```

---

## CI/CD Integration

The tests are integrated into GitHub Actions workflows:

- **PR validation**: `lint-helm-k8s`, unit tests, and Trivy / Kubescape scans run on every pull request
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

### Updating KIND versions

The matrix test automatically resolves the two latest stable KIND versions. To update fallback versions (used when offline), edit `tests/acceptance/kind-version-matrix-test.sh`:

```bash
_FALLBACK_KIND_VERSIONS=("v0.30.0" "v0.29.0")
```

### Updating test values

The acceptance tests install the chart using the generated `worker.hcl` and the default `values.yaml`. To override chart values during acceptance testing, edit `make acceptance-helm` in the `Makefile` and pass an additional `-f` flag.

**Important:** Keep acceptance-specific overrides minimal and focused on what the test environment requires.
