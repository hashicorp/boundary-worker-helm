# Boundary Worker Helm Chart — FAQ

## Installation

### Why does `helm install` fail immediately?

The most common causes are:

1. **No worker configuration provided** — The chart requires a valid Boundary HCL block in `worker.config`. The default in `values.yaml` is a template with placeholder values. Running `helm install` without customising `worker.config` will create a broken deployment. Set `worker.config` in your values file or supply the HCL with `--set-file worker.config=./worker.hcl`.

2. **Missing activation-token Secret for controller-led registration** — If `worker.config` uses `controller_generated_activation_token = "env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN"`, create the Secret named by `secretRefs.secretName` first, and ensure it contains the key configured by `secretRefs.keys.controllerGeneratedActivationToken`.

3. **Missing PersistentVolume** — If the cluster has no default StorageClass or no pre-provisioned PersistentVolume, the PVCs will remain in `Pending` and the worker pod will not start. Override `storageClass` in your values file:
   ```yaml
   worker:
     persistence:
       authStorage:
         storageClass: gp3
       recording:
         storageClass: gp3
   ```

4. **`helm lint` validation errors** — Run `helm lint .` before installing to catch rendering errors in your values.

---

### Can I run `helm template` without a live cluster?

Yes. The chart performs no cluster API calls during rendering. All validation is template-only:

```bash
helm template boundary-worker . \
  --namespace boundary \
  -f my-values.yaml
```

---

### Do I need to create the namespace manually?

No — pass `--create-namespace` to `helm install`:

```bash
helm install boundary-worker . \
  --namespace boundary \
  --create-namespace \
  -f my-values.yaml
```

---

### How do I supply the worker HCL configuration?

Two equivalent methods:

**Embedded in a values file** (recommended for GitOps):
```yaml
worker:
  config: |
    disable_mlock = true
    listener "tcp" {
      address = "0.0.0.0:9202"
      purpose = "proxy"
    }
    # ... rest of HCL
```

**As a separate HCL file** (useful for local dev):
```bash
helm install boundary-worker . \
  --namespace boundary \
  --set-file worker.config=./worker.hcl
```

Both approaches result in identical ConfigMap output.

---

## Configuration

### What is the minimum required `worker.config`?

At minimum a usable config usually requires:

- At least one `listener "tcp"` block with `purpose = "proxy"` (port 9202)
- An `ops` listener block with `purpose = "ops"` (port 9203) for health checks and metrics
- A `worker` block with a registration mechanism (activation token, worker-led, or KMS)
- An upstream destination (`hcp_boundary_cluster_id` or `initial_upstreams`)
- `auth_storage_path` if `worker.persistence.authStorage.enabled = true`

See [Required Worker Configuration](../README.md#required-worker-configuration) in the README for a full example.

### How do I source the controller-generated activation token from a Kubernetes Secret?

Use the same pattern as the controller chart: inject the Secret as an environment variable and reference it from HCL using `env://`.

Example values:

```yaml
secretRefs:
  secretName: boundary-worker-secrets
  keys:
    controllerGeneratedActivationToken: worker-controller-generated-activation-token

worker:
  config: |
    worker {
      auth_storage_path = "/var/lib/boundary"
      controller_generated_activation_token = "env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN"
    }

    hcp_boundary_cluster_id = "<your-cluster-id>"
```

Create the Secret before install:

```bash
kubectl create secret generic boundary-worker-secrets \
  --namespace boundary \
  --from-literal=worker-controller-generated-activation-token='<activation-token>'
```

If you set `secretRefs.validateExisting=true`, Helm will fail early when that Secret is missing.

---

### Can I use Helm template functions inside `worker.config`?

Yes. The chart renders `worker.config` through Helm's `tpl` function, so any valid Helm template expression is evaluated before the config is written to the ConfigMap.

Example:
```hcl
worker {
  name = "{{ .Release.Name }}-{{ .Release.Namespace }}"
  auth_storage_path = "{{ .Values.worker.persistence.authStorage.path }}"
}
```

Be careful with special characters — HCL strings use `"` and Helm template delimiters also use `"`, so escaping is required when embedding template expressions inline in a YAML block scalar.

---

### What is `${POD_NAME_LOWER}` and how does it work?

The chart injects the pod name as the `POD_NAME` environment variable. At container startup, the entrypoint runs `sed` to replace `${POD_NAME_LOWER}` in the HCL with the actual pod name converted to lowercase before Boundary starts. This allows you to use the pod name in worker names:

```hcl
worker {
  name = "k8s-worker-${POD_NAME_LOWER}"
}
```

This is evaluated at runtime, not at Helm render time.

---

### How do I disable session recording storage?

Set `worker.persistence.recording.enabled=false`:

```yaml
worker:
  persistence:
    recording:
      enabled: false
```

When disabled, the recording storage PVC is not created and the volume is not mounted. Remove `recording_storage_path` from your `worker.config` or leave it referencing a path that does not need to persist.

---

### How do I disable auth storage for KMS-based authentication?

KMS worker authentication does not require persistent auth storage. Set `worker.persistence.authStorage.enabled=false`:

```yaml
worker:
  persistence:
    authStorage:
      enabled: false
```

When disabled, an `emptyDir` is mounted at the auth storage path instead of a PVC. The worker state will be lost when the pod restarts, but with KMS auth the worker re-authenticates automatically on startup.

---

### The chart sets `disable_mlock = true`. Is that safe?

Yes, for Kubernetes deployments. The worker containers run as a non-root user with all Linux capabilities dropped, so `mlock(2)` cannot be called. Setting `disable_mlock = true` in `worker.config` tells Boundary not to attempt it. This is the standard setting for containerised deployments.

---

### How do I add custom environment variables to the worker container?

The chart does not expose a generic `extraEnv` field. For non-sensitive values, use Helm `tpl` expressions directly inside `worker.config`. For values that need to be in the environment (such as KMS credentials via Workload Identity), use your cloud provider's workload identity mechanism — no long-lived secrets need to be injected.

If you require additional environment variables beyond `POD_NAME` and `SKIP_SETCAP`, extend the chart by modifying `templates/worker-deployment.yaml` to add an `env` entry, or use a Helm post-renderer.

---

### How do I configure a KMS worker-auth stanza?

Add a `kms "worker-auth"` block to `worker.config` matching your Boundary server's configuration:

```hcl
kms "awskms" {
  purpose    = "worker-auth"
  region     = "us-east-1"
  kms_key_id = "alias/boundary-worker-auth"
}
```

Supported KMS providers and their purposes follow the same options as the Boundary controller (`awskms`, `gcpckms`, `azurekeyvault`, `transit`). See the [Boundary KMS documentation](https://developer.hashicorp.com/boundary/docs/configuration/kms) for all parameters.

---

### How do I supply cloud KMS credentials to the worker pod?

Use your cloud provider's workload identity mechanism so no long-lived credentials are required:

- **AWS**: Annotate the pod's ServiceAccount with an IAM role ARN via IRSA (`eks.amazonaws.com/role-arn`). The chart hardcodes `automountServiceAccountToken: false` in `templates/worker-deployment.yaml` — to use IRSA you must modify that template to remove the hardcoded value and configure an appropriate ServiceAccount with the IAM role annotation.
- **GCP**: Annotate the ServiceAccount with a GCP service account email (`iam.gke.io/gcp-service-account`) for Workload Identity.
- **Azure**: Use Azure Workload Identity annotations.
- **Vault**: Inject a token via the Vault Agent Injector as an environment variable or file and reference it in the `transit` KMS stanza.

---

## Networking & Services

### Why are there two separate Services?

| Service | Port | Default type | Purpose |
|---|---|---|---|
| `<release>-proxy` | 9202 | `LoadBalancer` | Session proxy traffic — clients connect here when the worker is an egress or intermediate worker |
| `<release>-ops` | 9203 | `ClusterIP` | Health checks and Prometheus metrics — internal only |

Keeping them separate allows you to expose the proxy externally while keeping ops internal, and to apply different annotations (e.g. cloud provider load balancer annotations) precisely to the proxy Service only.

---

### How do I expose the proxy Service with an internal load balancer?

Apply cloud provider annotations to `worker.service.proxy.annotations`. The chart automatically strips AWS load balancer annotations when `worker.service.proxy.type` is not `LoadBalancer`.

**AWS (NLB internal):**
```yaml
worker:
  service:
    proxy:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/aws-load-balancer-type: "external"
        service.beta.kubernetes.io/aws-load-balancer-nlb-target-type: "ip"
        service.beta.kubernetes.io/aws-load-balancer-scheme: "internal"
```

**GCP (internal passthrough NLB):**
```yaml
worker:
  service:
    proxy:
      type: LoadBalancer
      annotations:
        networking.gke.io/load-balancer-type: "Internal"
```

**Azure (internal):**
```yaml
worker:
  service:
    proxy:
      type: LoadBalancer
      annotations:
        service.beta.kubernetes.io/azure-load-balancer-internal: "true"
```

---

### Can I change the default listener ports?

Yes, but you must update both `worker.config` and the corresponding chart values together — the chart does not synchronise them automatically.

Example: change the proxy port from 9202 to 9222:

```yaml
worker:
  service:
    proxy:
      port: 9222
      targetPort: 9222
  config: |
    listener "tcp" {
      address = "0.0.0.0:9222"
      purpose = "proxy"
    }
    listener "tcp" {
      address     = "0.0.0.0:9203"
      purpose     = "ops"
      tls_disable = true
    }
    worker {
      # ...
    }
```

The liveness and readiness probes use a `tcpSocket` probe on the named port `proxy`. If you rename the port, update the probe references in `templates/worker-deployment.yaml`.

---

### How do I disable the proxy Service?

Set `worker.service.proxy.enabled=false`:

```yaml
worker:
  service:
    proxy:
      enabled: false
```

This is typical for egress-only workers that initiate all upstream connections and do not receive inbound session traffic.

---

### What is `public_addr` and do I have to set it?

`public_addr` is a Boundary runtime setting in the worker HCL, not a Helm value. It tells Boundary the address that other workers or clients should use to reach this worker for session proxy traffic.

You **only need to set it** if other Boundary components must dial into this worker — for example, when deploying an intermediate worker that other (downstream) workers connect through, or when this worker is exposed via a `LoadBalancer` Service and its external address must be advertised.

For a simple egress worker that only dials out, `public_addr` can be omitted.

---

## Registration

### What are the three registration methods and which should I use?

| Method | When to use |
|---|---|
| **Controller-led (activation token)** | Easiest. Generate a worker resource in Boundary/HCP Boundary, get the activation token, embed it in `worker.config`. The worker registers itself on first startup. |
| **Worker-led** | When you want the worker to generate its credentials. Start without a token, inspect pod logs, then explicitly register or authorize the worker via the Boundary API or CLI. |
| **KMS worker-auth** | For self-managed Boundary deployments where a shared KMS key authenticates the worker. Requires matching KMS configuration on both worker and controller. Disable the auth storage PVC when using this method. |

---

### The worker started but I don't see it in Boundary. What should I check?

1. **Activation token already consumed** — Each controller-generated token can only be used once. If the pod restarted after the first startup, the token was consumed but the credential was stored in auth storage. If auth storage was lost (no PVC or `emptyDir` restarted), the token is invalid. Generate a new one and redeploy.

2. **Worker has no upstream connectivity** — Check pod logs for connection errors to the Boundary cluster address. Confirm that `hcp_boundary_cluster_id` or `initial_upstreams` resolves and is reachable from inside the pod.

3. **Auth storage is empty after restart** — If `worker.persistence.authStorage.enabled=false`, auth state is not persisted. The worker must re-register on every restart. Enable the PVC for production deployments.

4. **Worker record exists but shows unhealthy** — Check `public_addr` is set correctly if this is an intermediate worker. Also confirm the ops health endpoint returns 200:
   ```bash
   kubectl port-forward -n boundary svc/<release>-ops 9203:9203
   curl http://localhost:9203/health
   ```

---

### Can I use a worker-led registration workflow with this chart?

Yes. Install the chart without a `controller_generated_activation_token` in `worker.config`. On first startup the worker logs output that includes the worker-led registration information. Retrieve it:

```bash
kubectl logs -n boundary deployment/boundary-worker-deployment | grep -i "worker generated"
```

Then use the Boundary CLI or API to register the worker using the emitted token.

---

## Upgrades

### How do I upgrade the Boundary image version?

```bash
helm upgrade boundary-worker . \
  --namespace boundary \
  --reuse-values \
  --set image.tag=0.21.1-ent \
  --set-file worker.config=./worker.hcl
```

The chart uses a `RollingUpdate` strategy. Because the worker runs as a single replica, the upgrade replaces the pod. Any in-flight sessions on the old pod are lost when it terminates. The 2-hour `terminationGracePeriodSeconds` default gives active sessions time to complete naturally before the old pod is killed.

---

### How do I update `public_addr` after the load balancer is assigned?

1. Wait for the external address:
   ```bash
   kubectl get svc <release>-proxy -n boundary -w
   ```
2. Update `public_addr` in your HCL file.
3. Upgrade the release:
   ```bash
   helm upgrade boundary-worker . \
     --namespace boundary \
     --reuse-values \
     --set-file worker.config=./worker.hcl
   ```

---

### What is the difference between `terminationGracePeriodSeconds` and session drain?

`terminationGracePeriodSeconds` (chart value, default `7200`) is the Kubernetes pod termination grace period. When the pod receives `SIGTERM` (during a Helm upgrade, restart, or delete), Kubernetes waits up to this duration before sending `SIGKILL`.

Boundary workers do not have a built-in graceful session drain mechanism — they proxy TCP traffic, and when the process exits, existing TCP connections are dropped. The long grace period gives active sessions time to complete naturally before the pod is killed, but it does not actively drain them. If immediate pod replacement is required, sessions must be allowed to expire or be explicitly cancelled through the Boundary API.

---

### How do I roll back a release?

```bash
helm history boundary-worker -n boundary
helm rollback boundary-worker <revision> -n boundary
```

Rolling back replaces the Deployment spec, ConfigMap, Services, and PVCs with the previous revision's definitions. PVC data is not altered by a Helm rollback. The auth storage contents from the current revision remain on disk.

---

### What happens to auth storage during an upgrade?

The auth storage PVC is not managed as a Helm lifecycle hook — it persists independently of chart upgrades and rollbacks. The worker credentials written into `/var/lib/boundary` survive pod restarts and Helm upgrades as long as the PVC exists and the pod is rescheduled to a node that can mount it. Do not delete the auth storage PVC unless you intend the worker to re-register from scratch.

---

## Operations

### How do I check the worker health endpoint?

The ops Service (`<release>-ops`) is `ClusterIP` by default. Use `kubectl port-forward` to reach it locally:

```bash
kubectl port-forward -n boundary svc/boundary-worker-ops 9203:9203
curl http://localhost:9203/health
```

---

### How do I inspect worker logs?

```bash
kubectl logs -n boundary deployment/boundary-worker-deployment
kubectl logs -n boundary deployment/boundary-worker-deployment --previous
```

Filter for upstream connection events:

```bash
kubectl logs -n boundary deployment/boundary-worker-deployment \
  | grep -i "upstream\|upstream connection\|address"
```

Filter by event type using `jq` (when CloudEvents JSON format is enabled):

```bash
kubectl logs -n boundary deployment/boundary-worker-deployment \
  | jq 'select(.type | startswith("audit"))'
```

---

### Worker pod is stuck in `Pending`. What should I check?

1. **PVC not bound** — Check whether PVCs are binding:
   ```bash
   kubectl get pvc -n boundary
   kubectl describe pvc -n boundary
   ```
   A pending PVC usually means no matching PersistentVolume or StorageClass. Override `storageClass` in your values.

2. **Resource pressure** — Check node capacity: `kubectl describe node`.

3. **Node selector / tolerations** — If `nodeSelector` or `tolerations` are set, verify matching nodes exist.

4. **ImagePullBackOff** — Check `imagePullSecrets` and registry access:
   ```bash
   kubectl describe pod -n boundary -l app.kubernetes.io/name=boundary-worker
   ```

---

### Worker pod is in `CrashLoopBackOff`. How do I debug?

Check previous pod logs first:

```bash
kubectl logs -n boundary deployment/boundary-worker-deployment --previous
```

Common causes:

| Symptom in logs | Likely cause | Fix |
|---|---|---|
| `error reading config` | Invalid HCL syntax in `worker.config` | Validate the HCL with `boundary server -config=./worker.hcl -dry-run` locally |
| `setcap: operation not permitted` | `SKIP_SETCAP=1` not set | Ensure `containerSecurityContext` has not been overridden to drop the env var |
| `unable to create directory` | Read-only filesystem or wrong path | Confirm `auth_storage_path` and `recording_storage_path` match the PVC mount paths |
| `failed to initialize KMS` | KMS permissions missing | Verify IAM/Workload Identity bindings |
| `address already in use` | Port conflict | Should not occur in this chart; check for leftover processes |

For event-based diagnostics:

```bash
kubectl describe pod -n boundary -l app.kubernetes.io/name=boundary-worker
```

---

### How do I check which Helm revision is deployed?

```bash
helm history boundary-worker -n boundary
```

---

### How do I check current resource usage?

```bash
kubectl top pod -n boundary -l app.kubernetes.io/name=boundary-worker
```

The default resource limits (`200m` CPU, `1Gi` memory) are conservative. Adjust upward if you observe CPU throttling or OOMKill events:

```bash
kubectl describe pod -n boundary -l app.kubernetes.io/name=boundary-worker | grep -A5 "Limits\|Requests"
```

---

## Security

### Why does the chart set `SKIP_SETCAP=1`?

The Boundary container entrypoint normally calls `setcap` to grant the binary `IPC_LOCK` capability for memory locking. The container security context in this chart drops all capabilities and disallows privilege escalation, so `setcap` would fail. `SKIP_SETCAP=1` bypasses that call. Memory locking is disabled via `disable_mlock = true` in the worker config.

---

### Why is `automountServiceAccountToken: false`?

The worker pod does not need to call the Kubernetes API, so the service account token is not mounted. This reduces the blast radius if the worker container is compromised — it cannot use the token to access cluster resources.

If you need to integrate with a cloud provider's Workload Identity mechanism (e.g. AWS IRSA), modify `templates/worker-deployment.yaml` to remove the hardcoded `automountServiceAccountToken: false`. This is not configurable via Helm values. You must also add `serviceAccountName` to the pod spec and create the ServiceAccount with the appropriate cloud provider annotations outside the chart.

---

### Why does the chart use a read-only root filesystem?

`readOnlyRootFilesystem: true` prevents any process inside the container from writing to the container filesystem. All write paths used by Boundary (auth storage, recording storage, and the processed HCL temp file) are mounted as either PVCs or `emptyDir` volumes. This limits the impact of a container compromise.

---

### How do I rotate the worker's auth credentials?

1. Delete the auth storage PVC contents (or the PVC itself).
2. Generate a new activation token in Boundary.
3. Update the Kubernetes Secret or `worker.config`, depending on whether you use the secret-backed or inline-token workflow.
4. Upgrade the Helm release.
5. On first startup, the worker will re-register with the new token.

For KMS-backed authentication, coordinate key rotation with your KMS provider. The worker re-authenticates automatically when the pod restarts, so no credential rotation is needed at the application level.

---

### Can I run the worker with a custom ServiceAccount?

Yes. The chart does not currently create a ServiceAccount resource. To use a custom ServiceAccount, create it outside the chart and configure the pod's ServiceAccount in `templates/worker-deployment.yaml`, or extend the chart to add `serviceAccountName` to the pod spec. This is needed for cloud Workload Identity scenarios (IRSA on AWS, Workload Identity on GCP, Azure Workload Identity).

---

## Advanced Scenarios

### Does this chart support HCP Boundary?

Yes. HCP Boundary manages the control plane. You deploy self-managed workers using this chart that connect to your HCP Boundary cluster.

In your `worker.config`, set `hcp_boundary_cluster_id` instead of `initial_upstreams`:

```hcl
worker {
  auth_storage_path = "/var/lib/boundary"
  controller_generated_activation_token = "<token>"
}

hcp_boundary_cluster_id = "<your-cluster-id>"
```

---

### Can I run multiple worker releases in the same namespace?

Yes. Use a different Helm release name for each installation. Resource names are derived from the release name, so they will not conflict as long as the release names differ:

```bash
helm install boundary-worker-a . \
  --namespace boundary \
  -f values-a.yaml

helm install boundary-worker-b . \
  --namespace boundary \
  -f values-b.yaml
```

Each release creates its own Deployment, Services, PVCs, and ConfigMap. Each worker must have a unique `auth_storage_path` — they must not share PVCs.

---

### How do I integrate with the Vault Secrets Operator?

The worker chart can now read the controller-generated activation token from an existing Kubernetes Secret. You can use the [Vault Secrets Operator (VSO)](https://developer.hashicorp.com/vault/docs/platform/k8s/vso) to sync a Vault KV secret into the Secret named by `secretRefs.secretName`, with a key matching `secretRefs.keys.controllerGeneratedActivationToken`.

If you prefer not to manage a Secret, `make worker-config` still generates a standalone `worker.hcl` with an inline activation token for local and test automation workflows.

---

### How do I configure session recording?

Session recording storage is configured on the worker. This chart provides a PVC for local recording storage. For production deployments, Boundary Enterprise supports writing recordings directly to S3-compatible object storage — configure this in `worker.config` using the `recording_storage_minimum_available_capacity` and BSR (Boundary Session Recording) storage configuration:

```hcl
worker {
  auth_storage_path      = "/var/lib/boundary"
  recording_storage_path = "/boundary/recording"
}
```

Ensure the recording PVC is sized appropriately for your expected recording volume (`worker.persistence.recording.size`). For object storage, you may be able to disable the recording PVC entirely and configure the worker to write directly to S3.

---

### Does this chart manage session recording object storage?

No. Session recording storage backends (S3, MinIO, etc.) are configured in `worker.config` at the Boundary level, not through chart values. The chart only manages the local PVC mount path. Configure the storage backend in the `worker` block in your HCL.

---

## Monitoring

### Where is the Prometheus metrics endpoint?

Metrics are exposed on the ops listener at `/metrics` (port 9203). Because the ops Service is `ClusterIP`, scrape it via `kubectl port-forward` or configure a `ServiceMonitor`. See the [Monitoring section](../README.md#monitoring) in the README for a `ServiceMonitor` example.

---

### How do I configure structured audit logging?

Add an `events` block to `worker.config`. The default config already includes a stderr sink for all event types. To add a file sink:

```hcl
events {
  audit_enabled        = true
  sysevents_enabled    = true
  observations_enabled = true

  sink "stderr" {
    name        = "all-events"
    event_types = ["*"]
    format      = "cloudevents-json"
  }

  sink "file" {
    name        = "audit-sink"
    event_types = ["audit"]
    format      = "cloudevents-json"
    file {
      path      = "/boundary/audit"
      file_name = "audit.log"
    }
  }
}
```

The file sink path must be writable inside the container. Mount a PVC or `emptyDir` at that path and add a corresponding `volumeMount` by modifying `templates/worker-deployment.yaml`, or use a Helm post-renderer.
