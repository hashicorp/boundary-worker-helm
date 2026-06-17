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
----

Please note: We take Boundary security and user trust seriously. If you believe you found a security issue in Boundary, please responsibly disclose it at [security@hashicorp.com](mailto:security@hashicorp.com).

----
