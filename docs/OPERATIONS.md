# Boundary Worker Helm Chart

Helm chart for running a single self-managed HashiCorp Boundary worker on Kubernetes.

This repository packages the Kubernetes resources required to run one Boundary worker with persistent identity storage and optional session recording storage. It is intended for customer-managed workers used with Boundary deployments where the data plane runs inside your network.

The chart is deliberately narrow in scope:

- Single worker replica
- Kubernetes-native deployment using Deployment, Services, ConfigMap, and PersistentVolumeClaims
- Customer-supplied Boundary worker configuration file
- Optional proxy and operations Services
- Optional recording storage

The chart does not manage controller resources, Boundary scopes, worker resources in HCP Boundary, DNS, certificates, ingress controllers, or multi-worker topology orchestration.

## Contents

- [Overview](#overview)
- [What The Chart Deploys](#what-the-chart-deploys)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Secret Creation And Usage](#secret-creation-and-usage)
- [Configuration Model](#configuration-model)
- [Required Worker Configuration](#required-worker-configuration)
- [Public Address And Service Exposure](#public-address-and-service-exposure)
- [Common Deployment Patterns](#common-deployment-patterns)
- [Configuration Reference](#configuration-reference)
- [Operations](#operations)
- [Monitoring](#monitoring)
- [Security Model](#security-model)
- [Repository Layout](#repository-layout)
- [Known Limitations](#known-limitations)
- [Contributing](#contributing)

Additional documentation:

- [docs/TESTING.md](docs/TESTING.md) — unit, acceptance, and integration test guide
- [docs/FAQ.md](docs/FAQ.md) — frequently asked questions and troubleshooting

## Overview

Boundary workers are the data-plane component of Boundary. They receive session assignments from controllers and proxy traffic between clients and target systems. Because worker identity is stored locally, and because session recordings may also be stored locally, a worker needs durable storage that survives restarts and pod rescheduling.

This chart packages that deployment model into a reusable Helm release.

## What The Chart Deploys

By default, a release renders the following resources:

- One Deployment with exactly one worker replica
- One optional PersistentVolumeClaim for Boundary auth storage (not required when using KMS auth)
- One optional PersistentVolumeClaim for session recording storage
- One ConfigMap containing the Boundary worker configuration file
- One proxy Service for session traffic
- One operations Service for the worker ops listener

The worker pod runs the official Boundary Enterprise image and starts Boundary with the mounted config file.

## Prerequisites

Before installing the chart, make sure the following are in place:

- A Kubernetes cluster with dynamic or pre-provisioned PersistentVolumes
- Helm v3 and above
- Network connectivity from the worker pod to the appropriate Boundary upstreams or controllers
- A Boundary worker configuration file in HCL format
- A registration workflow chosen in advance:
    - Controller-led registration with an activation token
    - Worker-led registration using information emitted in pod logs during initial startup, followed by explicit registration or authorization with the controller
    - KMS-backed worker authentication for self-managed Boundary deployments configured for it
    - A PVC if persistent storage is required

Additional requirements for intermediate worker capabilities:

- A routable external endpoint if the worker must be reached from outside the cluster
- Cluster support for the selected proxy Service type, such as `LoadBalancer`
- If you use controller-led registration with an activation token, create a Kubernetes Secret for the token

## Installation

Use this flow when you want to deploy a Boundary worker with this chart.

### 1. Add the worker configuration to your values file

Put the Boundary worker HCL directly in `worker.config` inside your values file.

Start from the provided template if you want a base to copy from:

```bash
cp scripts/worker-template.hcl worker.hcl
```

Then paste the contents into `worker.config: |` in your values file and edit it so it matches your Boundary deployment model.

Note: `--set-file worker.config=...` is still supported if you prefer to keep the HCL in a separate file, but this document uses the embedded-values approach as the primary workflow.

At minimum, set:

- Any of the three registration mechanisms: controller-led, worker-led, or KMS-based registration
- Your `hcp_boundary_cluster_id` or upstream endpoint using `initial_upstreams` (KMS auth is only supported for self-hosted upstreams)
- `public_addr` if the worker must be reachable from outside the cluster or by upstream workers
- Storage paths that match the chart values if you override the defaults

### 2. Review chart values

Check `values.yaml` before installing, especially:

- `image.repository`, `image.tag`, and `image.pullPolicy`
- `worker.service.proxy.type`
- `worker.service.proxy.annotations`
- `worker.service.ops.type`
- `worker.persistence.authStorage.enabled`
- `worker.persistence.authStorage.storageClass`
- `worker.persistence.recording.enabled`
- `worker.persistence.recording.storageClass`
- `worker.resources`

The defaults use the cluster's default StorageClass. Override `storageClass` if you need a specific provisioner (e.g. `gp3` on AWS).

If you want overrides, create a separate values file such as `my-values.yaml`.

Example:

```yaml
secretRefs:
	secretName: boundary-worker-secrets
	keys:
		controllerGeneratedActivationToken: worker-controller-generated-activation-token

worker:
	config: |
		disable_mlock = true

		listener "tcp" {
			address = "0.0.0.0:9202"
			purpose = "proxy"
		}

		worker {
			auth_storage_path = "/var/lib/boundary"
			recording_storage_path = "/boundary/recording"
			controller_generated_activation_token = "env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN"
		}

		hcp_boundary_cluster_id = "<hcp-boundary-cluster-id>"
	service:
		proxy:
			type: LoadBalancer
	persistence:
		authStorage:
			storageClass: gp3
		recording:
			storageClass: gp3
```

### 3. Secret creation and usage

Create the Kubernetes Secret used by `secretRefs` before installing the chart:

```bash
kubectl create secret generic boundary-worker-secrets \
	--namespace boundary \
	--from-literal=worker-controller-generated-activation-token='<activation-token>'
```

### 4. Create the namespace

```bash
kubectl create namespace boundary
```

### 5. Install the chart

Install using the default values in `values.yaml`. 
Before running this command, replace any placeholders in `worker.config`.

```bash
helm install boundary-worker . \
	--namespace boundary \
	--create-namespace \
	--wait \
	--rollback-on-failure
```

Install with an additional values file containing your worker config and overrides:

```bash
helm install boundary-worker . \
    --namespace boundary \
    --create-namespace \
	--wait \
	--rollback-on-failure \
    --values my-values.yaml
```

### 6. Verify the deployment

```bash
kubectl get pods --namespace boundary
kubectl get pvc --namespace boundary
kubectl get svc --namespace boundary
kubectl logs --namespace boundary deployment/boundary-worker-deployment
```

Confirm that:

- The pod becomes ready
- The auth storage PVCs are bound if enabled
- The proxy and ops Services match your intended exposure model
- The worker appears in Boundary and becomes eligible for session assignment

### 7. If you use a LoadBalancer, update `public_addr` if needed

If the proxy Service is exposed through `LoadBalancer`, Kubernetes may assign the external hostname or IP only after installation.

Check the Service:

```bash
kubectl get svc boundary-worker-proxy --namespace boundary
```

If your worker config needs to be updated with that final address, edit `worker.config` in your values file and upgrade the release:

```bash
helm upgrade boundary-worker . \
    --namespace boundary \
	--wait \
	--rollback-on-failure \
    --values my-values.yaml
```

## Configuration Model

The chart splits configuration into two distinct layers.

### 1. Boundary runtime configuration

The actual worker behavior is defined by `worker.config`, which is supplied as raw HCL content. The chart stores it in a ConfigMap and mounts it into the container.

Important characteristics:

- The chart does not validate Boundary runtime semantics.
- The chart does not infer Kubernetes resources from the HCL.
- The operator is responsible for keeping service ports, public addresses, and storage paths aligned with the worker config.
- The config is rendered through Helm's `tpl` function, so Helm template expressions inside `worker.config` are evaluated.
- At container startup, `${POD_NAME_LOWER}` is replaced with the pod name in lowercase before Boundary starts.
- If preferred, `worker.config` can also be provided with `--set-file worker.config=<path-to-hcl>` instead of embedding the HCL in a values file.

### 2. Kubernetes infrastructure configuration

Kubernetes-specific settings live under chart values such as:

- `image.*`
- `worker.service.*`
- `worker.resources.*`
- `worker.persistence.*`
- `podSecurityContext`
- `containerSecurityContext`
- `nodeSelector`
- `tolerations`
- `affinity`

These values control how the worker runs in Kubernetes, but they do not replace or generate the Boundary runtime configuration.

## Required Worker Configuration

This chart does not ship with a default Boundary worker configuration. You must provide valid HCL through `worker.config`.

At minimum, a usable worker config usually includes:

- Listener blocks for proxy and ops traffic
- Worker registration settings such as a controller-generated activation token, worker-led registration settings, or KMS worker-auth configuration
- Controller connection settings such as `initial_upstreams` or `hcp_boundary_cluster_id`, depending on your deployment model
- Public addresses reachable by clients or upstream workers when your topology requires them
- PVC is required if appropriate config is used and storage paths that match the chart values if you override the defaults

Example:

```hcl
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
	name                   = "k8s-worker-${POD_NAME_LOWER}"
	public_addr            = "worker.example.com:9202"
	auth_storage_path      = "/var/lib/boundary"
	recording_storage_path = "/boundary/recording"

	controller_generated_activation_token = "env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN"

	tags {
		type = ["kubernetes"]
	}
}
```

You can pass HCL directly with `--set-file` or template it from a values file. Because the chart evaluates `worker.config` with Helm `tpl`, Helm template expressions inside the HCL are supported.

For controller-led registration, the preferred pattern is to inject the activation token from an existing Kubernetes Secret using `secretRefs` and `env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN`. Inline activation tokens still work for externally generated HCL such as `make worker-config`.

## Public Address And Service Exposure

`public_addr` is a Boundary runtime setting in the worker HCL, not a Helm value. The chart does not compute or inject it automatically.

You must decide how the worker will be reached and then keep `worker.config` aligned with the Kubernetes Service you expose.

### Internal-only exposure

If the worker is only reachable inside the cluster or through private networking, use an internal service type such as `ClusterIP` or an internal load balancer.

Typical cases:

- Egress worker that does not need inbound worker-to-worker reachability
- Intermediate worker reachable only from private networks
- Platform-managed internal load balancer

Example values:

```yaml
worker:
	service:
		proxy:
			enabled: true
			type: ClusterIP
```

In this model:

- Set `public_addr` only if your topology requires other workers or clients to reach this worker
- If you do set `public_addr`, it should be a private address or DNS name that is actually routable from the relevant upstream systems

### Public internet exposure

If the worker must be reachable from outside the cluster, the usual approach is a `LoadBalancer` proxy Service.

Example values:

```yaml
worker:
	service:
		proxy:
			enabled: true
			type: LoadBalancer
```

In this model:

- Boundary still requires `public_addr` to be set in `worker.config`
- The address should match the final reachable endpoint for the worker, including the proxy port
- The chart will create the Service, but it will not update the HCL after Kubernetes assigns the external address

### DNS-first exposure

If you already know the DNS name you want to use, set `public_addr` before installation and point DNS to the service endpoint later.

Example HCL:

```hcl
worker {
	initial_upstreams = ["<upstream-host>:9201"]
	public_addr       = "boundary-worker.example.com:9202"
	auth_storage_path = "/var/lib/boundary"
}
```

This avoids a second Helm change for the HCL itself, but it shifts responsibility to the operator to ensure that:

- The DNS name is created
- The DNS name resolves to the final load balancer address
- The DNS update is completed before the worker needs to be used in session paths

### LoadBalancer-first exposure

If you do not know the final address until the load balancer is created, install first, wait for the external address, then update `public_addr` and run `helm upgrade`.

Typical flow:

1. Install with a temporary or incomplete intermediate-worker config.
2. Wait for the proxy Service external IP or hostname.
3. Update `public_addr` in the HCL file.
4. Upgrade the release with the revised config.

Example:

```bash
kubectl get svc boundary-worker-proxy --namespace boundary --watch

helm upgrade boundary-worker . \
	--namespace boundary \
	--wait \
	--rollback-on-failure \
	--reuse-values \
	--set-file worker.config=./intermediate-worker.hcl
```

### Internal load balancer or provider-managed DNS

Some platforms assign either:

- An internal-only load balancer hostname
- A provider-managed private DNS name
- A DNS name managed by an external DNS controller

In those cases, set `public_addr` to the actual hostname or address other workers will use. The important rule is simple: `public_addr` must match the endpoint reachable by the rest of your Boundary topology, regardless of whether that endpoint is public, private, or DNS-based.

## Common Deployment Patterns

### Egress worker

An egress worker usually does not need a publicly reachable `public_addr`. In that case you can keep the default proxy Service type or disable it entirely if you do not want Kubernetes to expose a proxy listener.

Example overrides:

```yaml
worker:
	service:
		proxy:
			enabled: false
		ops:
			enabled: true
```

### Intermediate worker

An intermediate worker typically needs:

- `initial_upstreams` configured in `worker.config`
- `public_addr` configured in `worker.config`
- A reachable proxy Service, often `LoadBalancer`

Typical workflow:

1. Install the chart.
2. Wait for the proxy Service external address.
3. Update `public_addr` in the HCL file.
4. Run `helm upgrade` with the updated config.

If you already control DNS ahead of time, you can set `public_addr` during the initial install and point DNS at the eventual load balancer address afterward.

If the intermediate worker is meant to stay private, the same pattern applies with an internal address or private DNS name instead of a public internet endpoint.

### Worker-led registration

For worker-led registration:

1. Install the worker without a controller-generated activation token.
2. Inspect pod logs.
3. Explicitly register or authorize the worker with the Boundary controller using the information emitted during initial startup.
4. Confirm the worker becomes active.

### Controller-led registration

For controller-led registration:

1. Create the worker in Boundary or HCP Boundary.
2. Obtain the activation token.
3. Create a Kubernetes Secret containing the activation token under the key configured by `secretRefs.keys.controllerGeneratedActivationToken`.
4. Reference `env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN` in `worker.config`.
5. Ensure auth storage PVC is enabled.
6. Install the chart.
7. Verify the worker registers and persists its credentials to auth storage.

### KMS-backed worker authentication

For KMS-based worker authentication in self-managed Boundary deployments, only when using self-hosted upstreams:

1. Configure worker authentication through Boundary with KMS worker auth enabled.
2. Add the required `kms "worker-auth"` configuration and related worker settings to the HCL file.
3. Disable the auth storage PVC, as KMS auth does not require persistent auth storage:

```yaml
worker:
  persistence:
    authStorage:
      enabled: false
```

4. Install the chart.
5. Verify the worker authenticates successfully via KMS.

## Configuration Reference

The table below documents the primary chart values shipped in `values.yaml`.

| Key | Default | Description |
| --- | --- | --- |
| `image.repository` | `hashicorp/boundary-enterprise` | Boundary worker container image repository. |
| `image.tag` | `0.21-ent` | Image tag used by the worker container. |
| `image.pullPolicy` | `IfNotPresent` | Kubernetes image pull policy. |
| `secretRefs.secretName` | `boundary-worker-secrets` | Existing Kubernetes Secret containing sensitive worker values. |
| `secretRefs.validateExisting` | `false` | When true, Helm validates the Secret exists when `worker.config` uses the chart-managed env-backed activation token. |
| `secretRefs.keys.controllerGeneratedActivationToken` | `worker-controller-generated-activation-token` | Secret key for `BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN`. |
| `imagePullSecrets` | `[]` | Optional registry credentials for private image pulls. |
| `worker.config` | Embedded HCL block | Raw HCL worker configuration passed through a ConfigMap. Set this directly in your values file. |
| `worker.terminationGracePeriodSeconds` | `7200` | Pod termination grace period in seconds (2 hours). Allows active sessions to drain before pod termination. |
| `worker.service.proxy.enabled` | `true` | Whether to create the proxy Service. |
| `worker.service.proxy.type` | `LoadBalancer` | Service type for proxy traffic. |
| `worker.service.proxy.port` | `9202` | Service port exposed for proxy traffic. |
| `worker.service.proxy.targetPort` | `9202` | Container port targeted by the proxy Service. |
| `worker.service.proxy.annotations` | AWS NLB annotations | Annotations applied to the proxy Service. AWS load balancer annotations are filtered out automatically when the proxy Service type is not `LoadBalancer`. |
| `worker.service.ops.enabled` | `true` | Whether to create the operations Service. |
| `worker.service.ops.type` | `ClusterIP` | Service type for the operations endpoint. |
| `worker.service.ops.port` | `9203` | Service port for the operations endpoint. |
| `worker.service.ops.targetPort` | `9203` | Container port targeted by the operations Service. |
| `worker.service.ops.annotations` | `{}` | Annotations applied to the operations Service. |
| `worker.resources.requests.cpu` | `100m` | CPU request for the worker container. |
| `worker.resources.requests.memory` | `512Mi` | Memory request for the worker container. |
| `worker.resources.limits.cpu` | `200m` | CPU limit for the worker container. |
| `worker.resources.limits.memory` | `1Gi` | Memory limit for the worker container. |
| `worker.persistence.authStorage.enabled` | `true` | Whether to create the auth storage PVC. Set to `false` when using KMS auth, which does not require persistent auth storage. |
| `worker.persistence.authStorage.size` | `1Gi` | Size of the auth storage PVC. |
| `worker.persistence.authStorage.accessMode` | `ReadWriteOnce` | Access mode for the auth storage PVC. |
| `worker.persistence.authStorage.storageClass` | `""` | StorageClass for the auth storage PVC. Empty uses the cluster default. |
| `worker.persistence.authStorage.path` | `/var/lib/boundary` | Mount path for auth storage. Must match `auth_storage_path` in the HCL. |
| `worker.persistence.recording.enabled` | `true` | Whether to create a recording PVC and mount it into the worker pod. |
| `worker.persistence.recording.size` | `10Gi` | Size of the recording PVC. |
| `worker.persistence.recording.accessMode` | `ReadWriteOnce` | Access mode for the recording PVC. |
| `worker.persistence.recording.storageClass` | `""` | StorageClass for the recording PVC. Empty uses the cluster default. |
| `worker.persistence.recording.path` | `/boundary/recording` | Mount path for recording storage. Must match `recording_storage_path` in the HCL when recording is enabled. |
| `podSecurityContext` | secure non-root defaults | Pod-level security context. |
| `containerSecurityContext` | secure non-root defaults | Container-level security context with dropped Linux capabilities and read-only root filesystem. |
| `podAnnotations` | `{}` | Extra pod annotations merged with checksum annotations. |
| `nodeSelector` | `{}` | Node selector constraints. |
| `tolerations` | `[]` | Tolerations for pod scheduling. |
| `affinity` | `{}` | Affinity rules for pod scheduling. |

### Example values override

```yaml
image:
	tag: "0.21-ent"

worker:
	terminationGracePeriodSeconds: 7200
	service:
		proxy:
			type: LoadBalancer
			annotations:
				service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
		ops:
			type: ClusterIP
	persistence:
		authStorage:
			size: 5Gi
			storageClass: gp3
		recording:
			enabled: true
			size: 50Gi
			storageClass: gp3
```

Install with both an override file and the worker HCL file:

```bash
helm install boundary-worker . \
    --namespace boundary \
	--wait \
	--rollback-on-failure \
    --values values.yaml \
    --set-file worker.config=./worker.hcl
```

## Operations

### Check release resources

```bash
kubectl get deployment,pods,svc,pvc --namespace boundary
```

### Inspect worker logs

```bash
kubectl logs --namespace boundary deployment/boundary-worker-deployment
```

### Upgrade configuration

```bash
helm upgrade boundary-worker . \
	--namespace boundary \
	--wait \
	--rollback-on-failure \
	--reuse-values \
	--set-file worker.config=./worker.hcl
```

This is also the command to use after Kubernetes assigns a proxy Service load balancer address and you need to update `public_addr` in the HCL file.

### Change the Boundary image version

```bash
helm upgrade boundary-worker . \
	--namespace boundary \
	--wait \
	--rollback-on-failure \
	--reuse-values \
	--set image.tag=0.21.1-ent \
	--set-file worker.config=./worker.hcl
```

### Roll back a release

```bash
helm history boundary-worker --namespace boundary
helm rollback boundary-worker <revision> --namespace boundary --wait
```

### Uninstall

```bash
helm uninstall boundary-worker --namespace boundary
```

By default, the pod receives a `SIGTERM` and has the configured grace period to shut down. Because the chart runs a single replica, upgrades and deletes can interrupt in-flight sessions.

## Monitoring

The worker exposes an ops listener at port 9203. The ops Service (`boundary-worker-ops`) defaults to `ClusterIP`, so it is not reachable outside the cluster without port-forwarding.

### Health check

```bash
kubectl port-forward --namespace boundary svc/boundary-worker-ops 9203:9203
curl http://localhost:9203/health
```

### Prometheus metrics

Metrics are available at the `/metrics` path on the ops listener:

```bash
kubectl port-forward --namespace boundary svc/boundary-worker-ops 9203:9203
curl http://localhost:9203/metrics
```

To scrape metrics with Prometheus, add a `ServiceMonitor` (if using the Prometheus Operator):

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: boundary-worker
  namespace: boundary
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: boundary-worker
      app.kubernetes.io/component: worker
  endpoints:
    - port: ops
      path: /metrics
      interval: 30s
```

### Structured event logging

The default `worker.config` emits all event types to stderr in CloudEvents JSON format:

```hcl
events {
  audit_enabled       = true
  sysevents_enabled   = true
    observations_enabled = true
  sink "stderr" {
    name        = "all-events"
    event_types = ["*"]
    format      = "cloudevents-json"
  }
}
```

Filter by event type using `jq`:

```bash
kubectl logs --namespace boundary deployment/boundary-worker-deployment \
  | jq 'select(.type | startswith("audit"))'
```

### Checking resource usage

```bash
kubectl top pod --namespace boundary -l app.kubernetes.io/name=boundary-worker
```

## Security Model

The chart runs the worker with restricted Kubernetes security settings:

- Runs as non-root
- Drops all Linux capabilities
- Disables privilege escalation
- Uses a read-only root filesystem
- Sets `SKIP_SETCAP=1` to avoid capability modification at startup
- Disables service account token automounting
- Uses `RuntimeDefault` seccomp

Operational implications:

- `disable_mlock = true` should remain set in the worker configuration when using this deployment model.
- If swap is enabled on cluster nodes, sensitive data may still be paged to disk. The chart assumes standard Kubernetes node behavior where swap is disabled.
- The ops endpoint is exposed separately and defaults to an internal `ClusterIP` Service.

## Repository Layout

```text
.
├── Chart.yaml
├── CHANGELOG.md
├── README.md
├── values.yaml
├── docs/
│   ├── FAQ.md
│   └── TESTING.md
├── scripts/
│   └── worker-template.hcl
├── templates/
│   ├── _helpers.tpl
│   ├── NOTES.txt
│   ├── worker-configmap.yaml
│   ├── worker-deployment.yaml
│   ├── worker-pvc.yaml
│   ├── worker-service.yaml
│   └── tests/
└── tests/
		├── acceptance/
		│   ├── cluster-smoke-test.sh
		│   ├── k8s-matrix-config.yaml.tpl
		│   ├── k8s-version-matrix-test.sh
		│   ├── kind-acceptance-config.yaml
		│   └── tcp-target-conn-test.sh
		├── integration/
		│   ├── aks-integration-test.sh
		│   └── eks-integration-test.sh
		└── unit/
				├── helpers_test.yaml
				├── worker-configmap_test.yaml
				├── worker-deployment_test.yaml
				├── worker-pvc_test.yaml
				└── worker-service_test.yaml
```

Key files:

- `values.yaml`: default chart values
- `scripts/worker-template.hcl`: starter HCL template for generating `worker.hcl`
- `templates/worker-deployment.yaml`: single-replica worker Deployment
- `templates/worker-service.yaml`: proxy and ops Services
- `templates/worker-pvc.yaml`: auth and recording PVCs
- `templates/worker-configmap.yaml`: mounted worker HCL configuration
- `templates/tests/`: Helm test hooks run by `helm test`
- `tests/unit/*_test.yaml`: Helm unit tests run with `helm-unittest`
- `tests/acceptance/cluster-smoke-test.sh`: validates a KIND cluster is up and accessible
- `tests/acceptance/tcp-target-conn-test.sh`: end-to-end session and TCP connection test
- `tests/acceptance/k8s-version-matrix-test.sh`: runs `tcp-target-conn-test.sh` across multiple Kubernetes versions
- `tests/acceptance/k8s-matrix-config.yaml.tpl`: KIND cluster template rendered per Kubernetes version by the matrix test
- `tests/integration/`: EKS and AKS integration tests
- `docs/TESTING.md`: full testing guide
- `docs/FAQ.md`: frequently asked questions

## Known Limitations

The current chart intentionally does not attempt to solve the following problems:

- Horizontal scaling of a single release
- Automatic drain or handoff of active sessions during upgrades
- Automatic discovery or injection of `public_addr`
- Secret management or external secret integration for bootstrap tokens
- Controller deployment or Boundary control plane provisioning
- TLS termination, DNS automation, or ingress controller configuration

If you need scale-out, deploy multiple independent releases and manage worker topology explicitly.

## Contributing

Contribution guidance is documented in `CONTRIBUTING.md`.

When submitting changes, include:

- A clear description of the behavior or documentation change
- Validation notes with the commands you ran
- Any chart value changes that affect install or upgrade workflows