# Boundary Worker Helm Chart

This repository contains a Helm chart for deploying a HashiCorp Boundary worker
on Kubernetes. The chart creates the worker deployment, a configuration
ConfigMap, optional proxy and ops services, and optional persistent volumes for
session recordings and worker auth storage.

For general Boundary documentation, see the
[Boundary documentation](https://developer.hashicorp.com/boundary/docs).

## Prerequisites

To use this chart, Helm must already be configured for your Kubernetes cluster.
Cluster provisioning, ingress, load balancer integration, DNS, and storage class
configuration are outside the scope of this repository.

Recommended prerequisites:

- Helm 3.6+
- A Kubernetes cluster with a working default or explicitly configured storage
  class if persistence is enabled
- Network connectivity from the worker to your Boundary control plane
- A valid Boundary worker configuration provided through `worker.config`

## What This Chart Deploys

The chart renders the following resources:

- A single `Deployment` for the Boundary worker
- A `ConfigMap` containing `boundary-worker.hcl`
- A proxy `Service` on port `9202` when `worker.service.proxy.enabled=true`
- An ops `Service` on port `9203` when `worker.service.ops.enabled=true`
- A PVC for session recording storage when
  `worker.persistence.recording.enabled=true`
- A PVC for auth storage when `worker.persistence.authStorage.enabled=true`

The worker pod starts by rendering the supplied HCL config and replacing
`${POD_NAME_LOWER}` with the current pod name in lowercase before launching
Boundary.

## Required Configuration

This chart does not ship with a default worker configuration. You must provide a
valid Boundary worker HCL configuration using `worker.config`.

At minimum, your config generally needs to define:

- A worker name or tag strategy
- Listener configuration for proxy and ops traffic
- Public addresses reachable by clients and controllers
- Upstream controller connection details
- Authentication storage and recording paths that match the chart values if you
  override them

Example:

```hcl
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
  name = "k8s-worker-${POD_NAME_LOWER}"
  public_addr = "worker.example.com:9202"
  auth_storage_path = "/var/lib/boundary"
  recording_storage_path = "/boundary/recording"

  controller_generated_activation_token = "<activation-token>"

  tags {
    type = ["kubernetes"]
  }
}
```

You can place that configuration in a values file or supply it directly with
`--set-file`.

## Usage

To install the chart from this repository:

```console
$ helm install boundary-worker . \
    --namespace boundary \
    --create-namespace \
    --set-file worker.config=./worker.hcl
```

To install with a custom values file:

```console
$ helm install boundary-worker . \
    --namespace boundary \
    --create-namespace \
    -f values.yaml \
    --set-file worker.config=./worker.hcl
```

After installation, if the proxy service is a `LoadBalancer`, wait for the
external address to be assigned:

```console
$ kubectl get svc boundary-worker-proxy -n boundary
```

If your worker `public_addr` depends on that assigned address, update the worker
configuration and run an upgrade:

```console
$ helm upgrade boundary-worker . \
    --namespace boundary \
    --reuse-values \
    --set-file worker.config=./worker.hcl
```

## Important Values

The most important chart values are:

- `image.repository`: Worker container image repository
- `image.tag`: Worker image tag. Defaults in this repository to `0.21-ent`
- `worker.config`: Raw Boundary worker HCL injected into the ConfigMap
- `worker.terminationGracePeriodSeconds`: Grace period before pod shutdown
- `worker.service.proxy.*`: Proxy service enablement, type, ports, and
  annotations
- `worker.service.ops.*`: Ops service enablement, type, ports, and annotations
- `worker.resources`: Container CPU and memory requests and limits
- `worker.persistence.recording.*`: Recording PVC configuration
- `worker.persistence.authStorage.*`: Auth storage PVC configuration
- `podSecurityContext`: Pod-level security context applied to the worker pod

The default values are defined in `values.yaml` and should be reviewed before
deployment, especially the image, load balancer annotations, storage classes,
and persistence settings.

## Persistence

Two persistence areas are supported:

- Recording storage mounted at `/boundary/recording`
- Auth storage mounted at `/var/lib/boundary`

If auth storage persistence is disabled, the chart falls back to `emptyDir` for
that path. If recording persistence is disabled, no recording volume is mounted.

Review storage class names before installing. The defaults in this repository
use `gp2`, which may not exist in every cluster.

## Services

By default, the chart enables:

- A proxy service exposed as `LoadBalancer` on port `9202`
- An ops service exposed internally as `ClusterIP` on port `9203`

The proxy service includes AWS NLB annotations by default. If you are not
deploying on AWS, you should override or remove those annotations.

## Notes

- The chart deploys a single worker replica.
- The worker container expects a valid `worker.config` to be provided.
- The chart uses an init container to create and set ownership on persistence
  paths before the worker starts.

## Security

If you believe you have found a vulnerability, do not open a public issue.
Follow the reporting process in [SECURITY.md](SECURITY.md).

## Contributing

Contribution expectations are documented in [CONTRIBUTING.md](CONTRIBUTING.md).
The repository also includes markdown and YAML linting in CI, so keep README and
workflow changes consistent with those checks.