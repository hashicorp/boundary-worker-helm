# Boundary Worker Helm Chart

Boundary workers are the data-plane component of Boundary. They proxy session traffic between users and targets and register with Boundary controllers.

This chart packages the Kubernetes resources required to run one self-managed Boundary worker in Kubernetes.

For detailed installation and configuration guidance, see the [Boundary Helm chart documentation](https://developer.hashicorp.com/boundary/docs/deploy/helm-chart).

## What The Chart Deploys

By default, this chart deploys:

- One Deployment with one worker replica
- Two Services:
  - Proxy Service (`boundary-worker-proxy`) on port 9202
  - Ops Service (`boundary-worker-ops`) on port 9203
- One ConfigMap for `worker.config`
- Two optional PVCs (both disabled by default):
  - Auth storage PVC (`worker.persistence.authStorage.enabled`)
  - Recording storage PVC (`worker.persistence.recording.enabled`)

  When a PVC is enabled, it is annotated with `helm.sh/resource-policy: keep` by default (`retainOnUninstall: true`), so it survives `helm uninstall`. Set `retainOnUninstall: false` to allow Helm to delete the PVC on uninstall.

## Prerequisites

### Version Requirements

| Component | Version |
| --- | --- |
| Kubernetes | 1.34 and above |
| Helm | v3 and above |

### Container Images

- Kubernetes deployments use the [Boundary Enterprise image on Docker Hub](https://hub.docker.com/r/hashicorp/boundary-enterprise) by default.
- OpenShift deployments use the [Red Hat certified Boundary Enterprise image](https://catalog.redhat.com/en/software/containers/hashicorp/boundary-enterprise/6a71b25353c2732d648bbc19) from `registry.connect.redhat.com` by default.

Pulling the image from `registry.connect.redhat.com` requires Red Hat registry credentials. Configure those credentials in the OpenShift cluster pull secret or create a registry pull Secret and reference it with `imagePullSecrets`. An explicit `image.repository` override takes precedence over the platform default.

### Required Resources

- Reachable Boundary controller upstreams
- Valid Boundary worker HCL in `worker.config`
- Persistent storage support if PVCs are enabled
- Optional cloud identity setup (for example IRSA) when using cloud KMS

## Helm Install Commands

Add the HashiCorp Helm repository (one-time):

```bash
helm repo add hashicorp https://helm.releases.hashicorp.com
helm repo update
```

Install with custom values:

```bash
helm install boundary-worker hashicorp/boundary-worker \
  --namespace boundary \
  --values my-values.yaml \
  --wait
```

## Helm Upgrade Commands

Standard upgrade:

```bash
helm upgrade boundary-worker hashicorp/boundary-worker \
  --namespace boundary \
  --values my-values.yaml \
  --rollback-on-failure \
  --wait
```

## Kubernetes Secrets and env:// References

When `secretRefs.secretName` is set, the chart injects the secret value as an environment variable and validates that `worker.config` references it using the correct `env://` variable name. Using a different variable name — or hardcoding the token directly in `worker.config` — causes the chart to fail during rendering before installation completes.

The required `env://` reference for each secret-backed field is:

| Field | Required env:// reference |
| --- | --- |
| `controller_generated_activation_token` | `env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN` |

**Example `worker.config` snippet:**

```hcl
worker {
  controller_generated_activation_token = "env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN"
  ...
}
```

If you use a different variable name, the chart fails during rendering with an error that identifies the field and the expected variable name.

----

Please note: We take Boundary security and user trust seriously. If you believe you found a security issue in Boundary, please responsibly disclose it at [security@hashicorp.com](mailto:security@hashicorp.com).

----
