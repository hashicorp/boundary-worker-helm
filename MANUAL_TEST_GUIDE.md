# Manual Test Execution Guide
## Boundary Worker KIND Cluster Testing - Step-by-Step Instructions

This guide provides detailed, copy-paste ready commands to manually execute the Boundary Worker KIND cluster tests from start to finish.

---

## Table of Contents
1. [Prerequisites](#prerequisites)
2. [Environment Setup](#environment-setup)
3. [Step 1: Install Required Tools](#step-1-install-required-tools)
4. [Step 2: Configure Environment Variables](#step-2-configure-environment-variables)
5. [Step 3: Create KIND Cluster](#step-3-create-kind-cluster)
6. [Step 4: Authenticate with Boundary](#step-4-authenticate-with-boundary)
7. [Step 5: Create Worker Configuration](#step-5-create-worker-configuration)
8. [Step 6: Install Helm Chart](#step-6-install-helm-chart)
9. [Step 7: Run Helm Tests](#step-7-run-helm-tests)
10. [Step 8: Run Acceptance Tests](#step-8-run-acceptance-tests)
11. [Step 9: Verify Worker Status](#step-9-verify-worker-status)
12. [Step 10: Troubleshooting](#step-10-troubleshooting)
13. [Step 11: Cleanup](#step-11-cleanup)

---

## Prerequisites

### System Requirements
- **Operating System:** macOS, Linux, or Windows with WSL2
- **RAM:** Minimum 8GB (16GB recommended)
- **Disk Space:** At least 10GB free
- **Internet Connection:** Required for downloading tools and connecting to HCP Boundary

### Access Requirements
- Access to HCP Boundary cluster
- Admin credentials for Boundary
- Terminal/command line access

---

## Environment Setup

### Project Directory
All commands assume you're in the project root directory:

```bash
cd /Users/abhishekmanjegowda/Downloads/Helm_Projects/version/boundary-worker-helm
```

---

## Step 1: Install Required Tools

### 1.1 Install kubectl (Kubernetes CLI)

**macOS:**
```bash
brew install kubectl
```

**Linux:**
```bash
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

**Verify:**
```bash
kubectl version --client
```

### 1.2 Install KIND (Kubernetes in Docker)

**macOS:**
```bash
brew install kind
```

**Linux:**
```bash
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind
```

**Verify:**
```bash
kind version
```

### 1.3 Install Helm

**macOS:**
```bash
brew install helm
```

**Linux:**
```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

**Verify:**
```bash
helm version
```

### 1.4 Install Boundary CLI

**macOS:**
```bash
brew tap hashicorp/tap
brew install hashicorp/tap/boundary
```

**Linux (Ubuntu/Debian):**
```bash
wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install boundary
```

**Verify:**
```bash
boundary version
```

### 1.5 Install Docker (if not already installed)

**macOS:**
```bash
brew install --cask docker
# Start Docker Desktop application
```

**Linux:**
```bash
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER
# Log out and back in for group changes to take effect
```

**Verify:**
```bash
docker --version
docker ps
```

---

## Step 2: Configure Environment Variables

### 2.1 Review the .env File

Check if `.env` file exists and contains your credentials:

```bash
cat .env
```

**Expected content:**
```bash
BOUNDARY_ADDR=https://83200186-7716-4020-ad77-da7266fd6340.boundary.hcp.to
BOUNDARY_LOGIN_NAME=boundarye2e
BOUNDARY_PASSWORD=yzh-juq!fxu9XKF5ubn
BOUNDARY_CLUSTER_ID=83200186-7716-4020-ad77-da7266fd6340
```

### 2.2 Load Environment Variables

**Option A: Using the load-env.sh script (Recommended)**
```bash
source tests/acceptance/load-env.sh
```

**Option B: Manual export**
```bash
export BOUNDARY_ADDR="https://83200186-7716-4020-ad77-da7266fd6340.boundary.hcp.to"
export BOUNDARY_LOGIN_NAME="boundarye2e"
export BOUNDARY_PASSWORD="yzh-juq!fxu9XKF5ubn"
export BOUNDARY_CLUSTER_ID="83200186-7716-4020-ad77-da7266fd6340"
```

### 2.3 Verify Environment Variables

```bash
echo "BOUNDARY_ADDR: $BOUNDARY_ADDR"
echo "BOUNDARY_LOGIN_NAME: $BOUNDARY_LOGIN_NAME"
echo "BOUNDARY_PASSWORD: ${BOUNDARY_PASSWORD:+<set>}"
echo "BOUNDARY_CLUSTER_ID: $BOUNDARY_CLUSTER_ID"
```

**Expected output:**
```
BOUNDARY_ADDR: https://83200186-7716-4020-ad77-da7266fd6340.boundary.hcp.to
BOUNDARY_LOGIN_NAME: boundarye2e
BOUNDARY_PASSWORD: <set>
BOUNDARY_CLUSTER_ID: 83200186-7716-4020-ad77-da7266fd6340
```

---

## Step 3: Create KIND Cluster

### 3.1 Check for Existing Clusters

```bash
kind get clusters
```

If you see `acceptance` in the list, you can either:
- **Delete it:** `kind delete cluster --name acceptance`
- **Use it:** Skip to Step 3.3

### 3.2 Create the Cluster

```bash
kind create cluster --config tests/acceptance/kind-acceptance-config.yaml
```

**Expected output:**
```
Creating cluster "acceptance" ...
 ✓ Ensuring node image (kindest/node:v1.35.0) 🖼
 ✓ Preparing nodes 📦 📦 📦
 ✓ Writing configuration 📜
 ✓ Starting control-plane 🕹️
 ✓ Installing CNI 🔌
 ✓ Installing StorageClass 💾
 ✓ Joining worker nodes 🚜
Set kubectl context to "kind-acceptance"
```

**Duration:** 2-3 minutes

### 3.3 Verify Cluster

```bash
kubectl cluster-info --context kind-acceptance
```

**Expected output:**
```
Kubernetes control plane is running at https://127.0.0.1:XXXXX
CoreDNS is running at https://127.0.0.1:XXXXX/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

### 3.4 Check Nodes

```bash
kubectl get nodes --context kind-acceptance
```

**Expected output:**
```
NAME                       STATUS   ROLES           AGE   VERSION
acceptance-control-plane   Ready    control-plane   1m    v1.35.0
acceptance-worker          Ready    <none>          1m    v1.35.0
acceptance-worker2         Ready    <none>          1m    v1.35.0
```

---

## Step 4: Authenticate with Boundary

### 4.1 Test Boundary Connection

```bash
curl -I $BOUNDARY_ADDR
```

**Expected:** HTTP response (200 or redirect)

### 4.2 Authenticate with Boundary

```bash
boundary authenticate password \
  -addr="$BOUNDARY_ADDR" \
  -login-name="$BOUNDARY_LOGIN_NAME" \
  -password="env://BOUNDARY_PASSWORD" \
  -keyring-type=none \
  -format=json
```

**Expected output:** JSON with authentication token

### 4.3 Extract and Export Token

```bash
AUTH_OUTPUT=$(boundary authenticate password \
  -addr="$BOUNDARY_ADDR" \
  -login-name="$BOUNDARY_LOGIN_NAME" \
  -password="env://BOUNDARY_PASSWORD" \
  -keyring-type=none \
  -format=json 2>&1)

AUTH_TOKEN=$(echo "$AUTH_OUTPUT" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
export BOUNDARY_TOKEN="$AUTH_TOKEN"

echo "Token set: ${BOUNDARY_TOKEN:+Yes}"
```

### 4.4 Verify Authentication

```bash
boundary workers list \
  -addr="$BOUNDARY_ADDR" \
  -token="env://BOUNDARY_TOKEN" \
  -format=json | head -20
```

**Expected:** JSON list of workers

---

## Step 5: Create Worker Configuration

### 5.1 Create Controller-Led Worker

```bash
WORKER_OUTPUT=$(boundary workers create controller-led \
  -addr="$BOUNDARY_ADDR" \
  -token="env://BOUNDARY_TOKEN" 2>&1)

echo "$WORKER_OUTPUT"
```

**Expected output:**
```
Worker information:
  Created Time:        [timestamp]
  ID:                  w_XXXXXXXXXX
  Type:                pki
  ...
  Controller-Generated Activation Token:  neslat_XXXXXXXXXX...
```

### 5.2 Extract Activation Token

```bash
ACTIVATION_TOKEN=$(echo "$WORKER_OUTPUT" | awk -F': *' '/Controller-Generated Activation Token:/ { if ($2 != "") { print $2; exit } if (getline > 0) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0); print $0; exit } }')

echo "Activation Token: ${ACTIVATION_TOKEN:0:20}..."
```

### 5.3 Extract Worker ID (Optional)

```bash
WORKER_ID=$(echo "$WORKER_OUTPUT" | awk -F': *' '/^  ID:/ { print $2; exit }')
echo "Worker ID: $WORKER_ID"
```

### 5.4 Generate worker.hcl

```bash
cat > worker.hcl << EOF
disable_mlock = true

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

listener "tcp" {
  address     = "0.0.0.0:9203"
  purpose     = "ops"
  tls_disable = true
}

worker {
  auth_storage_path = "/var/lib/boundary"
  recording_storage_path = "/boundary/recording"
  tags {
    type = ["worker", "egress", "test"]
  }
  
  controller_generated_activation_token = "$ACTIVATION_TOKEN"
}

hcp_boundary_cluster_id = "$BOUNDARY_CLUSTER_ID"

events {
  audit_enabled       = true
  sysevents_enabled   = true
  observations_enable = true
  sink "stderr" {
    name = "all-events"
    description = "All events sent to stderr"
    event_types = ["*"]
    format = "cloudevents-json"
  }
}
EOF
```

### 5.5 Verify worker.hcl

```bash
cat worker.hcl
```

**Check that:**
- Activation token is present (starts with `neslat_`)
- Cluster ID matches your environment
- No placeholder values remain

---

## Step 6: Install Helm Chart

### 6.1 Create Namespace

```bash
kubectl create namespace boundary --context kind-acceptance
```

**Note:** If namespace exists, you'll see an error - that's okay.

### 6.2 Install Helm Chart

```bash
helm upgrade --install boundary-worker . \
  --namespace boundary \
  --create-namespace \
  --kube-context kind-acceptance \
  --set worker.service.proxy.type=NodePort \
  --set worker.persistence.recording.storageClass=standard \
  --set worker.persistence.authStorage.storageClass=standard \
  --set-file worker.config=worker.hcl \
  --timeout 5m \
  --wait
```

**Expected output:**
```
Release "boundary-worker" does not exist. Installing it now.
NAME: boundary-worker
LAST DEPLOYED: [timestamp]
NAMESPACE: boundary
STATUS: deployed
REVISION: 1
```

**Duration:** 1-2 minutes

### 6.3 Verify Installation

```bash
helm list -n boundary --kube-context kind-acceptance
```

**Expected output:**
```
NAME              NAMESPACE  REVISION  STATUS    CHART                    APP VERSION
boundary-worker   boundary   1         deployed  boundary-worker-0.1.0    0.18.1
```

### 6.4 Check Deployed Resources

```bash
kubectl get all -n boundary --context kind-acceptance
```

**Expected output:**
```
NAME                                              READY   STATUS    RESTARTS   AGE
pod/boundary-worker-deployment-XXXXXXXXXX-XXXXX   1/1     Running   0          1m

NAME                            TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
service/boundary-worker-ops     ClusterIP   10.96.X.X       <none>        9203/TCP
service/boundary-worker-proxy   NodePort    10.96.X.X       <none>        9202:XXXXX/TCP

NAME                                         READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/boundary-worker-deployment   1/1     1            1           1m
```

### 6.5 Wait for Deployment to be Ready

```bash
kubectl wait --for=condition=available --timeout=5m \
  deployment/boundary-worker-deployment \
  -n boundary \
  --context kind-acceptance
```

**Expected output:**
```
deployment.apps/boundary-worker-deployment condition met
```

---

## Step 7: Run Helm Tests

### 7.1 Execute Helm Tests

```bash
helm test boundary-worker \
  --namespace boundary \
  --kube-context kind-acceptance \
  --timeout 10m
```

**Expected output:**
```
NAME: boundary-worker
...
TEST SUITE:     boundary-worker-test-configmap
Last Started:   [timestamp]
Last Completed: [timestamp]
Phase:          Succeeded
...
```

**Duration:** 5-10 minutes

### 7.2 View Test Results Summary

```bash
kubectl get pods -n boundary --context kind-acceptance | grep test
```

### 7.3 Check Failed Tests (if any)

```bash
# List all test pods
kubectl get pods -n boundary --context kind-acceptance -l app.kubernetes.io/component=test

# View logs of failed test (example)
kubectl logs -n boundary boundary-worker-test-controller-connection --context kind-acceptance
```

---

## Step 8: Run Acceptance Tests

### 8.1 Run Basic Acceptance Test

```bash
bash tests/acceptance/acceptance-test.sh
```

**Expected output:**
```
================================
Acceptance Test Suite
================================

Test 1: Verifying cluster accessibility...
✅ PASSED: Cluster is accessible
...
```

### 8.2 Run KIND Cluster Test

```bash
bash tests/acceptance/kind-cluster-test.sh
```

**Expected output:**
```
================================
Boundary Worker KIND Cluster Acceptance Test
================================

Test 0: Validating environment variables...
✅ PASSED: All required environment variables are set

Test 1: Verifying KIND cluster accessibility...
✅ PASSED: KIND cluster is accessible
...
```

**Duration:** 3-5 minutes

### 8.3 Monitor Test Progress

If tests seem to hang, open a new terminal and monitor:

```bash
# Watch pod status
watch kubectl get pods -n boundary --context kind-acceptance

# Follow worker logs
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance -f
```

---

## Step 9: Verify Worker Status

### 9.1 Check Worker Pod

```bash
# Get pod name
POD_NAME=$(kubectl get pods -n boundary --context kind-acceptance -l app.kubernetes.io/name=boundary-worker -o jsonpath='{.items[0].metadata.name}')

echo "Worker Pod: $POD_NAME"

# Check pod status
kubectl get pod $POD_NAME -n boundary --context kind-acceptance
```

### 9.2 View Worker Logs

```bash
# Last 50 lines
kubectl logs $POD_NAME -n boundary --context kind-acceptance --tail=50

# Follow logs in real-time
kubectl logs $POD_NAME -n boundary --context kind-acceptance -f
```

### 9.3 Check Worker Health Endpoint

```bash
# Port-forward to access health endpoint
kubectl port-forward -n boundary --context kind-acceptance pod/$POD_NAME 9203:9203 &
PF_PID=$!

# Wait for port-forward to establish
sleep 3

# Check health
curl -s http://localhost:9203/health

# Stop port-forward
kill $PF_PID
```

**Expected output:** `OK` or similar health status

### 9.4 Verify Worker in Boundary Controller

```bash
boundary workers list \
  -addr="$BOUNDARY_ADDR" \
  -token="env://BOUNDARY_TOKEN" \
  -format=json | grep -A 10 "$WORKER_ID"
```

### 9.5 Check Worker Services

```bash
kubectl get svc -n boundary --context kind-acceptance
```

### 9.6 Check Persistent Volumes

```bash
kubectl get pvc -n boundary --context kind-acceptance
```

---

## Step 10: Troubleshooting

### 10.1 Worker Not Starting

**Check pod events:**
```bash
kubectl describe pod $POD_NAME -n boundary --context kind-acceptance
```

**Check deployment events:**
```bash
kubectl describe deployment boundary-worker-deployment -n boundary --context kind-acceptance
```

### 10.2 TLS Connection Errors

**Check worker logs for TLS errors:**
```bash
kubectl logs $POD_NAME -n boundary --context kind-acceptance | grep -i "tls\|error"
```

**Test connectivity from pod:**
```bash
kubectl exec -n boundary $POD_NAME --context kind-acceptance -- \
  curl -v https://83200186-7716-4020-ad77-da7266fd6340.boundary.hcp.to
```

**Check DNS resolution:**
```bash
kubectl exec -n boundary $POD_NAME --context kind-acceptance -- \
  nslookup 83200186-7716-4020-ad77-da7266fd6340.boundary.hcp.to
```

### 10.3 Authentication Issues

**Re-authenticate:**
```bash
boundary authenticate password \
  -addr="$BOUNDARY_ADDR" \
  -login-name="$BOUNDARY_LOGIN_NAME" \
  -password="env://BOUNDARY_PASSWORD" \
  -keyring-type=none
```

**Check token validity:**
```bash
boundary workers list -addr="$BOUNDARY_ADDR" -token="env://BOUNDARY_TOKEN"
```

### 10.4 Worker Not Registered

**Regenerate worker configuration:**
```bash
# Delete old worker.hcl
rm worker.hcl

# Create new worker and generate config
# Repeat Step 5
```

**Reinstall Helm chart:**
```bash
helm uninstall boundary-worker -n boundary --kube-context kind-acceptance
# Wait 30 seconds
# Repeat Step 6
```

### 10.5 Check Cluster Resources

**Node status:**
```bash
kubectl get nodes --context kind-acceptance
```

**Cluster info:**
```bash
kubectl cluster-info --context kind-acceptance
```

**All resources in namespace:**
```bash
kubectl get all,pvc,configmap,secret -n boundary --context kind-acceptance
```

### 10.6 View All Logs

**Worker logs:**
```bash
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance --tail=100
```

**All pod logs in namespace:**
```bash
for pod in $(kubectl get pods -n boundary --context kind-acceptance -o name); do
  echo "=== $pod ==="
  kubectl logs -n boundary $pod --context kind-acceptance --tail=20
  echo ""
done
```

### 10.7 Common Issues and Solutions

#### Issue: "no application protocol" TLS error

**Possible causes:**
- Network connectivity issue
- Activation token expired
- ALPN configuration mismatch

**Solutions:**
1. Regenerate worker with fresh token
2. Check network connectivity
3. Verify HCP Boundary cluster configuration

#### Issue: Pod stuck in Pending state

**Check:**
```bash
kubectl describe pod $POD_NAME -n boundary --context kind-acceptance
```

**Common causes:**
- PVC not binding (check storage class)
- Resource constraints
- Image pull issues

#### Issue: Helm test timeout

**Increase timeout:**
```bash
helm test boundary-worker \
  --namespace boundary \
  --kube-context kind-acceptance \
  --timeout 20m
```

---

## Step 11: Cleanup

### 11.1 Delete Helm Release

```bash
helm uninstall boundary-worker -n boundary --kube-context kind-acceptance
```

### 11.2 Delete Namespace

```bash
kubectl delete namespace boundary --context kind-acceptance
```

### 11.3 Delete KIND Cluster

```bash
kind delete cluster --name acceptance
```

**Verify deletion:**
```bash
kind get clusters
```

### 11.4 Remove Generated Files

```bash
rm worker.hcl
```

### 11.5 Clean Docker Resources (Optional)

```bash
# Remove unused images
docker image prune -a

# Remove unused volumes
docker volume prune
```

---

## Quick Reference Commands

### Essential Commands

```bash
# Load environment
source tests/acceptance/load-env.sh

# Create cluster
kind create cluster --config tests/acceptance/kind-acceptance-config.yaml

# Authenticate
boundary authenticate password -addr="$BOUNDARY_ADDR" -login-name="$BOUNDARY_LOGIN_NAME" -password="env://BOUNDARY_PASSWORD" -keyring-type=none

# Install chart
helm upgrade --install boundary-worker . --namespace boundary --create-namespace --kube-context kind-acceptance --set-file worker.config=worker.hcl --wait

# Run tests
bash tests/acceptance/kind-cluster-test.sh

# View logs
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance -f

# Cleanup
kind delete cluster --name acceptance
```

### Useful Aliases

Add to your `~/.bashrc` or `~/.zshrc`:

```bash
alias k='kubectl --context kind-acceptance'
alias kn='kubectl --context kind-acceptance -n boundary'
alias kl='kubectl logs --context kind-acceptance -n boundary'
alias kd='kubectl describe --context kind-acceptance -n boundary'
```

---

## Troubleshooting Checklist

Before asking for help, verify:

- [ ] All tools installed and versions checked
- [ ] Environment variables loaded correctly
- [ ] KIND cluster created and accessible
- [ ] Boundary authentication successful
- [ ] worker.hcl file generated with valid token
- [ ] Helm chart installed without errors
- [ ] Worker pod is running (not CrashLoopBackOff)
- [ ] Worker logs reviewed for errors
- [ ] Network connectivity tested from pod
- [ ] Activation token is valid (not expired)

---

## Additional Resources

### Documentation
- **Boundary Documentation:** https://developer.hashicorp.com/boundary
- **KIND Documentation:** https://kind.sigs.k8s.io/
- **Helm Documentation:** https://helm.sh/docs/
- **Kubernetes Documentation:** https://kubernetes.io/docs/

### Project Files
- **Test Script:** `tests/acceptance/kind-cluster-test.sh`
- **Environment Loader:** `tests/acceptance/load-env.sh`
- **KIND Config:** `tests/acceptance/kind-acceptance-config.yaml`
- **Makefile:** `Makefile` (for automated workflows)
- **Troubleshooting Guide:** `TROUBLESHOOTING.md`

### Getting Help
1. Check worker logs for specific errors
2. Review `TROUBLESHOOTING.md` for common issues
3. Consult Boundary documentation
4. Check GitHub issues for similar problems

---

## Success Criteria

Your test is successful when:

✅ KIND cluster is running  
✅ Worker pod is in Running state  
✅ Worker registered with Boundary controller  
✅ Health endpoint returns HTTP 200  
✅ No continuous TLS errors in logs  
✅ Helm tests pass (at least 18/21)  
✅ Acceptance tests complete successfully  

---

**Last Updated:** April 20, 2026  
**Version:** 1.0  
**Tested On:** macOS (ARM64), KIND v0.31.0, Kubernetes v1.35.0