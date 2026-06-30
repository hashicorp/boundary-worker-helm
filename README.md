# Boundary Worker Helm Chart

Boundary workers are the data-plane component of Boundary. They proxy session traffic between users and targets and register with Boundary controllers.

This chart packages the Kubernetes resources required to run one self-managed Boundary worker in Kubernetes.

## What The Chart Deploys

By default, this chart deploys:

- One Deployment with one worker replica
- Two Services:
  - Proxy Service (`boundary-worker-proxy`) on port 9202
  - Ops Service (`boundary-worker-ops`) on port 9203
- One ConfigMap for `worker.config`
- Two optional PVCs:
  - Auth storage PVC
  - Recording storage PVC

## Prerequisites

### Version Requirements

| Component | Version |
| --- | --- |
| Kubernetes | 1.34 and above |
| Helm | v3 and above |

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
  --version 0.1.0 \
  --namespace boundary \
  --values my-values.yaml \
  --wait
```

## Helm Upgrade Commands

Standard upgrade:

```bash
helm upgrade boundary-worker hashicorp/boundary-worker \
  --version 0.1.0 \
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
