# Boundary Worker Acceptance Tests

This directory contains acceptance tests for the Boundary Worker Helm chart deployment in a KIND (Kubernetes IN Docker) cluster.

## Test Files

### 1. `acceptance-test.sh`
Basic acceptance tests that verify:
- KIND cluster accessibility
- Namespace creation and verification
- Basic cluster operations

### 2. `kind-cluster-test.sh` (NEW)
Comprehensive acceptance tests that validate:
- Worker deployment in KIND cluster
- Worker registration with INT long-lived Boundary cluster
- Session creation capability
- Worker-controller communication
- Health endpoints
- Persistent volumes
- Services configuration

### 3. `kind-acceptance-config.yaml`
KIND cluster configuration with:
- 1 control-plane node
- 2 worker nodes
- Port mappings for worker services (30000, 30001)

## Prerequisites

Before running the acceptance tests, ensure you have:

1. **Required Tools:**
   - `kubectl` - Kubernetes CLI
   - `kind` - Kubernetes IN Docker
   - `helm` - Helm package manager
   - `boundary` - Boundary CLI
   - `curl` - For health checks

2. **Environment Variables:**
   
   **Option A: Using .env file (Recommended)**
   ```bash
   # Copy the example file
   cp .env.example .env
   
   # Edit .env with your actual credentials
   # Then load the variables
   source tests/acceptance/load-env.sh
   ```
   
   **Option B: Manual export**
   ```bash
   export BOUNDARY_ADDR="https://your-cluster.boundary.hashicorp.cloud"
   export BOUNDARY_LOGIN_NAME="admin"
   export BOUNDARY_PASSWORD="your-password"
   export BOUNDARY_CLUSTER_ID="your-cluster-id"
   ```

3. **Boundary Controller:**
   - Access to an INT long-lived Boundary cluster
   - Valid admin credentials
   - Network connectivity to the controller

## Running Tests

### Quick Start - Full Workflow

1. **Set up environment variables:**
   ```bash
   # Copy and edit the .env file
   cp .env.example .env
   # Edit .env with your Boundary credentials
   
   # Load the environment variables
   source tests/acceptance/load-env.sh
   ```

2. **Run the complete acceptance test workflow:**
   ```bash
   make acceptance-full
   ```

This will:
1. Set up the KIND cluster
2. Generate worker configuration
3. Install the Helm chart
4. Run basic acceptance tests
5. Run comprehensive KIND cluster tests

### Step-by-Step Execution

#### 1. Setup KIND Cluster

```bash
make acceptance-setup
```

This installs dependencies and creates a KIND cluster named "acceptance".

#### 2. Generate Worker Configuration

```bash
make worker-config
```

This authenticates with Boundary and generates `worker.hcl` with activation token.

#### 3. Install Helm Chart

```bash
make acceptance-helm
```

This installs the boundary-worker chart and runs Helm tests.

#### 4. Run Basic Tests

```bash
make acceptance-test
```

Runs basic cluster verification tests.

#### 5. Run Comprehensive KIND Tests

```bash
make acceptance-kind-test
```

Runs the comprehensive test suite including:
- Worker registration validation
- Session creation tests
- Health endpoint checks
- Worker-controller communication verification

### Cleanup

Remove the KIND cluster and generated files:

```bash
make acceptance-cleanup
```

## Test Coverage

### `kind-cluster-test.sh` Test Cases

| Test # | Description | Validates |
|--------|-------------|-----------|
| 0 | Environment Variables | Required env vars are set |
| 1 | KIND Cluster Access | Cluster is accessible |
| 2 | Namespace Verification | Boundary namespace exists |
| 3 | Worker Deployment | Deployment exists and is ready |
| 4 | Worker Pod Status | Pod is running |
| 5 | Worker Startup Logs | Worker started successfully |
| 6 | Boundary Authentication | Can authenticate with controller |
| 7 | Worker Registration | Worker registered with controller |
| 8 | Health Endpoints | Worker health endpoint responds |
| 9 | Session Creation | Can authorize and create sessions |
| 10 | Worker-Controller Comm | Worker connected to controller |
| 11 | Persistent Volumes | PVCs are bound |
| 12 | Services | Services are configured |

## Environment Variable Management

### Using .env File (Recommended)

The repository includes a `.env.example` template for storing environment variables:

1. **Create your .env file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit .env with your credentials:**
   ```bash
   # Open in your editor
   vim .env  # or nano, code, etc.
   ```

3. **Load variables before running tests:**
   ```bash
   source tests/acceptance/load-env.sh
   ```

### Security Notes

- ✅ `.env` is in `.gitignore` - your credentials won't be committed
- ✅ `.env.example` is tracked - provides a template for others
- ✅ `load-env.sh` validates and loads variables safely
- ⚠️ Never commit `.env` with real credentials
- ⚠️ Use CI/CD secrets for automated testing

### CI/CD Integration

For CI/CD pipelines, use secrets management:

```yaml
# GitHub Actions example
env:
  BOUNDARY_ADDR: ${{ secrets.BOUNDARY_ADDR }}
  BOUNDARY_LOGIN_NAME: ${{ secrets.BOUNDARY_LOGIN_NAME }}
  BOUNDARY_PASSWORD: ${{ secrets.BOUNDARY_PASSWORD }}
  BOUNDARY_CLUSTER_ID: ${{ secrets.BOUNDARY_CLUSTER_ID }}
```

## Troubleshooting

### Test Failures

1. **Authentication Failed:**
   - Verify `BOUNDARY_ADDR`, `BOUNDARY_LOGIN_NAME`, and `BOUNDARY_PASSWORD`
   - Check network connectivity to Boundary controller
   - Ensure credentials are valid

2. **Worker Not Registered:**
   - Check worker logs: `kubectl logs -n boundary <pod-name>`
   - Verify activation token in `worker.hcl`
   - Ensure controller address is correct

3. **Session Creation Failed:**
   - Verify targets are configured in Boundary
   - Check worker is available for target
   - Review worker logs for errors

4. **Health Endpoint Not Responding:**
   - Verify pod is running
   - Check service configuration
   - Review port-forward logs

### Viewing Logs

```bash
# Worker pod logs
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance

# Follow logs in real-time
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance -f

# Helm test logs
kubectl logs -n boundary -l app.kubernetes.io/component=test --context kind-acceptance
```

### Manual Verification

```bash
# Check deployment status
kubectl get deployment -n boundary --context kind-acceptance

# Check pod status
kubectl get pods -n boundary --context kind-acceptance

# Check services
kubectl get svc -n boundary --context kind-acceptance

# Check PVCs
kubectl get pvc -n boundary --context kind-acceptance

# Describe worker pod
kubectl describe pod -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance
```

## CI/CD Integration

The acceptance tests can be integrated into CI/CD pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Acceptance Tests
  env:
    BOUNDARY_ADDR: ${{ secrets.BOUNDARY_ADDR }}
    BOUNDARY_LOGIN_NAME: ${{ secrets.BOUNDARY_LOGIN_NAME }}
    BOUNDARY_PASSWORD: ${{ secrets.BOUNDARY_PASSWORD }}
    BOUNDARY_CLUSTER_ID: ${{ secrets.BOUNDARY_CLUSTER_ID }}
  run: |
    make acceptance-full
```

## Notes

- Tests use the `kind-acceptance` context for all kubectl operations
- Worker is deployed in the `boundary` namespace
- Tests automatically clean up test sessions after validation
- Port-forwarding is used temporarily for health checks
- All tests must pass for the suite to succeed

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review worker and test logs
3. Verify all prerequisites are met
4. Ensure environment variables are correctly set