# Troubleshooting Guide: Acceptance Tests

## Error: "KIND cluster is not accessible"

### Problem
```
Test 1: Verifying KIND cluster accessibility...
❌ FAILED: KIND cluster is not accessible
```

### Cause
The KIND (Kubernetes IN Docker) cluster named "acceptance" has not been created yet.

### Solution

Follow these steps in order:

#### Step 1: Load Environment Variables
```bash
cd boundary-worker-helm
source tests/acceptance/load-env.sh
```

**Expected Output:**
```
Loading environment variables from .env file...
✅ Environment variables loaded successfully

Loaded variables:
  BOUNDARY_ADDR: https://your-cluster.boundary.hcp.to
  BOUNDARY_LOGIN_NAME: boundarye2e
  BOUNDARY_PASSWORD: <set>
  BOUNDARY_CLUSTER_ID: your-cluster-id
```

#### Step 2: Create KIND Cluster
```bash
make acceptance-setup
```

**What this does:**
- Checks for required tools (kubectl, kind, helm, boundary CLI)
- Installs missing tools (on macOS/Linux)
- Creates a KIND cluster named "acceptance" with the configuration from [`kind-acceptance-config.yaml`](tests/acceptance/kind-acceptance-config.yaml)
- Verifies the cluster is accessible

**Expected Output:**
```
================================
Setting up Acceptance Environment
================================

Step 1: Checking dependencies...
✅ kubectl is installed
✅ kind is installed
✅ helm is installed
✅ boundary CLI is installed

Step 2: Setting up KIND cluster...
Creating KIND cluster 'acceptance'...
✅ Acceptance cluster created

Verifying cluster...
✅ Cluster is ready

================================
✅ Acceptance Environment Ready!
================================
```

#### Step 3: Generate Worker Configuration
```bash
make worker-config
```

**What this does:**
- Authenticates with your Boundary controller
- Creates a controller-led worker
- Generates `worker.hcl` with activation token

**Expected Output:**
```
================================
Authenticating with Boundary
================================
Boundary Address: https://your-cluster.boundary.hcp.to
Login Name: boundarye2e

✅ Successfully authenticated with Boundary

Creating controller-led worker...
✅ Created worker wrkr_xxxxxxxxxxxxx

Generating worker.hcl from template...
✅ Created worker.hcl
```

#### Step 4: Install Helm Chart
```bash
make acceptance-helm
```

**What this does:**
- Installs the boundary-worker Helm chart in the KIND cluster
- Uses the `worker.hcl` configuration
- Waits for deployment to be ready
- Runs Helm tests

**Expected Output:**
```
================================
Installing Helm Chart in Acceptance Cluster
================================
✅ Helm is available

Installing boundary-worker chart with test values...
✅ Helm chart installed successfully

Waiting for deployment to be ready...
✅ Deployment is ready

================================
Running Helm Tests
================================
✅ Helm tests completed successfully
```

#### Step 5: Run Comprehensive Tests
```bash
make acceptance-kind-test
```

**What this does:**
- Runs all 12 acceptance tests
- Validates worker registration with Boundary controller
- Tests session creation capability
- Verifies worker-controller communication

**Expected Output:**
```
================================
Boundary Worker KIND Cluster Acceptance Test
================================

Test 0: Validating environment variables...
✅ PASSED: All required environment variables are set

Test 1: Verifying KIND cluster accessibility...
✅ PASSED: KIND cluster is accessible

Test 2: Verifying namespace 'boundary' exists...
✅ PASSED: Namespace 'boundary' exists

Test 3: Verifying worker deployment...
✅ PASSED: Worker deployment exists
✅ PASSED: Worker deployment is ready

Test 4: Verifying worker pod status...
✅ PASSED: Worker pod found: boundary-worker-deployment-xxxxx
✅ PASSED: Worker pod is running

Test 5: Checking worker logs for successful startup...
✅ PASSED: Worker started successfully

Test 6: Authenticating with Boundary controller...
✅ PASSED: Successfully authenticated with Boundary controller

Test 7: Verifying worker registration with Boundary controller...
✅ PASSED: Successfully retrieved worker list from controller
✅ PASSED: Worker with PKI authentication found (controller-led worker)

Test 8: Verifying worker health endpoints...
✅ PASSED: Worker health endpoint is responding (HTTP 200)

Test 9: Validating session creation capability...
✅ PASSED: Session authorization successful (Session ID: s_xxxxxxxxxxxxx)

Test 10: Verifying worker-controller communication...
✅ PASSED: Worker successfully connected to controller

Test 11: Verifying persistent volumes...
✅ PASSED: Persistent volume claims found

Test 12: Verifying services...
✅ PASSED: Services found

================================
✅ Acceptance Test Suite Completed!
================================
```

### Quick Command (All Steps at Once)

Instead of running each step individually, you can run everything at once:

```bash
# Load environment variables
source tests/acceptance/load-env.sh

# Run full workflow
make acceptance-full
```

This runs all steps automatically:
1. `acceptance-setup` - Create KIND cluster
2. `worker-config` - Generate worker configuration
3. `acceptance-helm` - Install Helm chart
4. `acceptance-test` - Run basic tests
5. `acceptance-kind-test` - Run comprehensive tests

---

## Other Common Issues

### Issue: "boundary CLI not found"

**Solution:**
```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/boundary

# Linux (Ubuntu/Debian)
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install boundary
```

### Issue: "Authentication failed"

**Symptoms:**
```
❌ Boundary authentication failed
```

**Solution:**
1. Verify your `.env` file has correct credentials:
   ```bash
   cat .env
   ```

2. Test authentication manually:
   ```bash
   boundary authenticate password \
     -addr="$BOUNDARY_ADDR" \
     -login-name="$BOUNDARY_LOGIN_NAME" \
     -password="env://BOUNDARY_PASSWORD"
   ```

3. Check network connectivity:
   ```bash
   curl -I "$BOUNDARY_ADDR"
   ```

### Issue: "Worker not registering"

**Symptoms:**
```
⚠️  WARNING: Could not confirm controller connection from logs
```

**Solution:**
1. Check worker logs:
   ```bash
   kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance
   ```

2. Verify worker.hcl was generated:
   ```bash
   cat worker.hcl
   ```

3. Check if activation token is valid:
   ```bash
   # Regenerate worker config
   make worker-config
   
   # Reinstall Helm chart
   helm uninstall boundary-worker -n boundary --kube-context kind-acceptance
   make acceptance-helm
   ```

### Issue: "Session creation failed"

**Symptoms:**
```
⚠️  WARNING: Could not authorize session
```

**Possible Causes:**
1. No targets configured in Boundary
2. Worker not available for the target
3. Network connectivity issues

**Solution:**
1. List targets in Boundary:
   ```bash
   boundary targets list -addr="$BOUNDARY_ADDR" -token="$BOUNDARY_TOKEN"
   ```

2. If no targets exist, this is expected - the test will show a warning but continue

3. To fully test session creation, configure a target in your Boundary controller

### Issue: "Port already in use"

**Symptoms:**
```
ERROR: failed to create cluster: node(s) already exist for a cluster with the name "acceptance"
```

**Solution:**
```bash
# Delete existing cluster
make acceptance-cleanup

# Recreate cluster
make acceptance-setup
```

---

## Cleanup

When you're done testing, clean up resources:

```bash
make acceptance-cleanup
```

This will:
- Delete the KIND cluster
- Remove the `worker.hcl` file

---

## Verification Commands

### Check KIND cluster status
```bash
kind get clusters
kubectl cluster-info --context kind-acceptance
```

### Check worker deployment
```bash
kubectl get all -n boundary --context kind-acceptance
```

### Check worker logs
```bash
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance -f
```

### Check worker in Boundary
```bash
boundary workers list -addr="$BOUNDARY_ADDR" -token="$BOUNDARY_TOKEN"
```

---

## Need More Help?

1. Check the [Acceptance Testing README](tests/acceptance/README.md) for detailed documentation
2. Review the [Quick Start Guide](ACCEPTANCE_TESTING.md)
3. Examine the test scripts:
   - [`kind-cluster-test.sh`](tests/acceptance/kind-cluster-test.sh) - Comprehensive tests
   - [`acceptance-test.sh`](tests/acceptance/acceptance-test.sh) - Basic tests