# Boundary Worker Helm Chart

This repository contains a Helm chart for deploying a HashiCorp Boundary worker
on Kubernetes. The chart renders a single worker `Deployment`, a worker
configuration `ConfigMap`, optional proxy and ops `Service` resources, and
persistent volumes for Boundary auth storage and optional session recordings.

For product documentation, see the
[Boundary documentation](https://developer.hashicorp.com/boundary/docs).

## Prerequisites

To use this chart, Helm must already be configured for your Kubernetes cluster.
Cluster provisioning, ingress, DNS, load balancer integration, and storage
class management are outside the scope of this repository.

Recommended prerequisites:

- Helm 3.6+
- A reachable Boundary control plane
- A Kubernetes cluster with a valid storage class for auth storage, and for
  recording storage if recording persistence is enabled
- A valid Boundary worker configuration supplied through `worker.config`

## What the Chart Deploys

The chart renders the following resources:

- One `Deployment` for the worker
- One `ConfigMap` that stores `boundary-worker.hcl`
- One proxy `Service` when `worker.service.proxy.enabled=true`
- One ops `Service` when `worker.service.ops.enabled=true`
- One recording PVC when `worker.persistence.recording.enabled=true`
- One auth storage PVC on every install

At runtime, the container reads the rendered HCL file from the `ConfigMap`,
replaces `${POD_NAME_LOWER}` with the current pod name in lowercase, and then
starts `boundary server` with the processed configuration.

## Required Worker Configuration

This chart does not ship with a default worker configuration. You must provide a
valid Boundary worker HCL configuration with `worker.config`.

At minimum, your configuration typically needs:

- Listener blocks for proxy and ops traffic
- Worker registration or tag settings
- Controller connection settings
- Public addresses reachable by clients and controllers, when required
- Storage paths that match the chart values if you override them

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

  controller_generated_activation_token = "<activation-token>"

  tags {
    type = ["kubernetes"]
  }
}
```

You can provide that HCL directly with `--set-file` or template it inside a
values file. The chart evaluates `worker.config` with Helm `tpl`, so Helm
template expressions inside the HCL are supported.

## Installation

Install from this repository:

```console
$ helm install boundary-worker . \
    --namespace boundary \
    --create-namespace \
    --set-file worker.config=./worker.hcl
```

Install with an additional values file:

```console
$ helm install boundary-worker . \
    --namespace boundary \
    --create-namespace \
    -f values.yaml \
    --set-file worker.config=./worker.hcl
```

If your proxy service is a `LoadBalancer`, wait for the external address and
then update the worker `public_addr` if needed:

```console
$ kubectl get svc boundary-worker-proxy -n boundary

$ helm upgrade boundary-worker . \
    --namespace boundary \
    --reuse-values \
    --set-file worker.config=./worker.hcl
```

## Key Values

The default values live in `values.yaml`. Review them before deploying,
especially the image settings, service annotations, storage classes, and
security context settings.

Important values include:

- `image.repository`, `image.tag`, `image.pullPolicy`
- `imagePullSecrets`
- `worker.config`
- `worker.terminationGracePeriodSeconds`
- `worker.service.proxy.enabled`, `worker.service.proxy.type`,
  `worker.service.proxy.port`, `worker.service.proxy.targetPort`,
  `worker.service.proxy.annotations`
- `worker.service.ops.enabled`, `worker.service.ops.type`,
  `worker.service.ops.port`, `worker.service.ops.targetPort`,
  `worker.service.ops.annotations`
- `worker.resources`
- `worker.persistence.recording.enabled`, `worker.persistence.recording.size`,
  `worker.persistence.recording.accessMode`,
  `worker.persistence.recording.storageClass`,
  `worker.persistence.recording.path`
- `worker.persistence.authStorage.size`,
  `worker.persistence.authStorage.accessMode`,
  `worker.persistence.authStorage.storageClass`,
  `worker.persistence.authStorage.path`
- `podSecurityContext`
- `containerSecurityContext`
- `podAnnotations`
- `nodeSelector`, `tolerations`, `affinity`
- `fullnameOverride`

## Persistence

The chart uses two storage locations:

- Auth storage mounted at `/var/lib/boundary`
- Recording storage mounted at `/boundary/recording`

Auth storage is always backed by a PVC rendered from
`worker.persistence.authStorage.*`. Recording storage is optional and is only
mounted when `worker.persistence.recording.enabled=true`.

Review storage class names before installing. The defaults in this repository
use `gp2`, which is not available in every environment.

## Services

By default, the chart enables:

- A proxy service exposed as `LoadBalancer` on port `9202`
- An ops service exposed as `ClusterIP` on port `9203`

The default proxy annotations target AWS NLB. When the proxy service type is not
`LoadBalancer`, the chart strips the AWS load balancer annotations and keeps any
non-AWS custom annotations you set.

## Operational Notes

- The chart deploys one worker replica.
- The pod sets `automountServiceAccountToken: false`.
- The worker container exposes ports `9202` and `9203` and uses TCP readiness
  and liveness probes on the proxy port.
- The deployment includes checksum annotations so config or worker value changes
  trigger a rollout.
- Resource names are derived from the release name, for example
  `<release>-deployment`, `<release>-config`, `<release>-proxy`, and
  `<release>-auth-storage`.

## Local Validation

The repository includes local targets for formatting, linting, unit tests, and
acceptance testing:

```console
$ make format
$ make unit-test
$ make lint
```

`make lint` installs required local tools on macOS if needed and then runs Helm
linting, template rendering, Kubernetes schema validation, Trivy, and
Kubescape.

## Acceptance Workflow

The repository also includes an acceptance workflow built around KIND:

```console
$ make acceptance-setup
$ make worker-config
$ make acceptance-helm
$ make acceptance-test
```

`make worker-config` authenticates to Boundary and generates `worker.hcl` from
`scripts/worker-template.hcl`. It expects these environment variables:

- `BOUNDARY_ADDR`
- `BOUNDARY_LOGIN_NAME`
- `BOUNDARY_PASSWORD`
- `BOUNDARY_CLUSTER_ID`

To run the entire flow in one command:

```console
$ make acceptance-full
```

To clean up the KIND cluster and generated worker configuration:

```console
$ make acceptance-cleanup
```

## Contributing

Contribution expectations are documented in [CONTRIBUTING.md](CONTRIBUTING.md).
The repository includes Markdown and YAML linting in CI, so keep README and
workflow changes consistent with those checks.