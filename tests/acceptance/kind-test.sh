#!/usr/bin/env bash

set -euo pipefail

############################################
# CONFIG (override via env vars if needed)
############################################

KIND_CLUSTER_NAME="${KIND_CLUSTER_NAME:-boundary-acceptance}"
NAMESPACE="${NAMESPACE:-boundary}"

BOUNDARY_ADDR="${BOUNDARY_ADDR:?Set BOUNDARY_ADDR}"
BOUNDARY_TOKEN="${BOUNDARY_TOKEN:?Set BOUNDARY_TOKEN}"
TARGET_ID="${TARGET_ID:?Set TARGET_ID}"

WORKER_TOKEN="${WORKER_TOKEN:?Set WORKER_TOKEN}"

WAIT_TIME="${WAIT_TIME:-60}"

############################################
# HELPERS
############################################

log() {
  echo -e "\n==== $1 ====\n"
}

retry() {
  local retries=$1
  shift
  local count=0
  until "$@"; do
    exit_code=$?
    count=$((count + 1))
    if [ $count -ge $retries ]; then
      echo "❌ Command failed after $count attempts: $*"
      return $exit_code
    fi
    echo "Retry $count/$retries..."
    sleep 5
  done
}

############################################
# STEP 1: CREATE KIND CLUSTER
############################################

log "Creating kind cluster"

if ! kind get clusters | grep -q "$KIND_CLUSTER_NAME"; then
  kind create cluster --name "$KIND_CLUSTER_NAME"
else
  echo "Cluster already exists"
fi

kubectl cluster-info --context "kind-$KIND_CLUSTER_NAME"

############################################
# STEP 2: DEPLOY WORKER
############################################

log "Deploying Boundary worker"

kubectl create namespace "$NAMESPACE" || true

cat <<EOF | kubectl apply -n "$NAMESPACE" -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: boundary-auth-storage
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: worker-config
data:
  worker.hcl: |
    disable_mlock = true

    listener "tcp" {
      address = "0.0.0.0:9202"
      purpose = "proxy"
    }

    listener "tcp" {
      address = "0.0.0.0:9203"
      purpose = "ops"
      tls_disable = true
    }

    worker {
      public_addr = "boundary-worker.boundary.svc.cluster.local"
      controller_generated_activation_token = "$WORKER_TOKEN"
      auth_storage_path = "/var/lib/boundary"
      tags {
        type = ["egress"]
      }
    }

    hcp_boundary_cluster_id = "83200186-7716-4020-ad77-da7266fd6340"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: boundary-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: boundary-worker
  template:
    metadata:
      labels:
        app: boundary-worker
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      securityContext:
        runAsNonRoot: true
        runAsUser: 100
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: "OnRootMismatch"
      containers:
      - name: worker
        image: hashicorp/boundary:latest
        args: ["server", "-config=/config/worker.hcl"]
        securityContext:
          runAsNonRoot: true
          runAsUser: 100
          runAsGroup: 1000
          allowPrivilegeEscalation: false
          capabilities:
            drop:
              - ALL
        env:
        - name: SKIP_SETCAP
          value: "1"
        volumeMounts:
        - name: config
          mountPath: /config
          readOnly: true
        - name: auth-storage
          mountPath: /var/lib/boundary
        - name: tmp
          mountPath: /tmp
        ports:
        - containerPort: 9202
          name: proxy
        - containerPort: 9203
          name: ops
      volumes:
      - name: config
        configMap:
          name: worker-config
      - name: auth-storage
        persistentVolumeClaim:
          claimName: boundary-auth-storage
      - name: tmp
        emptyDir: {}
EOF

############################################
# STEP 3: WAIT FOR POD READY
############################################

log "Waiting for worker pod"

# Wait for pod to be created
echo "Waiting for pod to be created..."
for i in {1..30}; do
  if kubectl get pods -n "$NAMESPACE" -l app=boundary-worker 2>/dev/null | grep -q boundary-worker; then
    echo "Pod found, waiting for it to be ready..."
    break
  fi
  echo "Attempt $i/30: Pod not yet created, waiting..."
  sleep 2
done

kubectl wait --for=condition=ready pod \
  -l app=boundary-worker \
  -n "$NAMESPACE" \
  --timeout=180s

WORKER_POD=$(kubectl get pods -n "$NAMESPACE" -l app=boundary-worker -o jsonpath='{.items[0].metadata.name}')

echo "Worker pod: $WORKER_POD"

############################################
# STEP 4: VALIDATE WORKER REGISTRATION
############################################

log "Validating worker registration"

export BOUNDARY_ADDR
export BOUNDARY_TOKEN

# Wait for worker to register (may take a few moments)
echo "Waiting for worker to register..."
sleep 15

retry 10 boundary workers list -scope-id global -addr="$BOUNDARY_ADDR" -token=env://BOUNDARY_TOKEN -format=json | jq -e '.items | length > 0'

echo "✅ Worker registered with controller"

# Wait additional time for worker tags to be processed
echo "Waiting for worker tags to be processed..."
sleep 10

# Verify our worker has the egress tag
WORKERS_WITH_TAG=$(boundary workers list -scope-id global -addr="$BOUNDARY_ADDR" -token=env://BOUNDARY_TOKEN -format=json | jq '[.items[] | select(.canonical_tags.type != null and (.canonical_tags.type | contains(["egress"])))] | length')

echo "Workers with 'egress' tag: $WORKERS_WITH_TAG"

if [ "$WORKERS_WITH_TAG" -eq 0 ]; then
  echo "⚠️  Warning: No workers found with 'egress' tag yet. Session authorization may fail."
  echo "This could mean the worker hasn't fully registered its tags yet."
fi

############################################
# STEP 5: VALIDATE TARGET CONNECTIVITY (FROM POD)
############################################

log "Checking worker egress to target"

kubectl exec -n "$NAMESPACE" "$WORKER_POD" -- sh -c "which nc || (apk add --no-cache netcat-openbsd || true)"

# NOTE: replace with your target host/port if needed
# This assumes target is reachable from Boundary config
echo "⚠️ Skipping explicit nc check (depends on target details)"

############################################
# STEP 6: VALIDATE SESSION CREATION
############################################

log "Validating session creation capability"

# Authorize a session using targets authorize-session
set +e
SESSION_OUTPUT=$(boundary targets authorize-session \
  -id "$TARGET_ID" \
  -addr "$BOUNDARY_ADDR" \
  -token env://BOUNDARY_TOKEN \
  -format json \
  2>&1)
EXIT_CODE=$?
set -e

if [ $EXIT_CODE -ne 0 ]; then
  echo "Session authorization output:"
  echo "$SESSION_OUTPUT"
  echo "❌ Session authorization failed"
  exit 1
fi

SESSION_ID=$(echo "$SESSION_OUTPUT" | jq -r '.item.session_id // empty')
if [ -z "$SESSION_ID" ]; then
  echo "❌ Failed to extract session ID"
  exit 1
fi

echo "✅ Session successfully authorized (ID: $SESSION_ID)"

############################################
# STEP 7: VALIDATE SESSION STATE
############################################

log "Validating session state"

# Verify the session exists and is in pending/active state
SESSION_INFO=$(boundary sessions read -id "$SESSION_ID" -addr "$BOUNDARY_ADDR" -token env://BOUNDARY_TOKEN -format json)
SESSION_STATUS=$(echo "$SESSION_INFO" | jq -r '.item.status')

if [ "$SESSION_STATUS" = "pending" ] || [ "$SESSION_STATUS" = "active" ]; then
  echo "✅ Session confirmed (Status: $SESSION_STATUS)"
else
  echo "❌ Unexpected session status: $SESSION_STATUS"
  exit 1
fi

############################################
# STEP 8: CLEANUP (OPTIONAL)
############################################

log "Test completed successfully"

# Uncomment if you want cleanup
# kind delete cluster --name "$KIND_CLUSTER_NAME"