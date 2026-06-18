# Changelog

All notable changes to the Boundary Worker Helm Chart will be documented in this file.

## [0.1.0-beta] - 2026-06-18

Initial public beta release of the Boundary Worker Helm chart.

### Added

**Core chart**
- Helm chart for deploying a HashiCorp Boundary Worker on Kubernetes
- Single-replica worker `Deployment` with persistent storage
- Support for controller-led, worker-led, and KMS-based worker registration
- Configurable proxy (`worker.service.proxy`) and operations (`worker.service.ops`) Services
- Optional `PersistentVolumeClaim` for auth storage — KMS-based workers can use an `emptyDir` instead (`worker.persistence.authStorage.enabled: false`)
- Optional `PersistentVolumeClaim` for session recording (`worker.persistence.recording.enabled`)
- Worker HCL config embedded in `values.yaml` by default; `--set-file worker.config=<file>` also supported
- Security-hardened pod and container security contexts (non-root UID/GID, read-only root filesystem, all capabilities dropped)
- Kubernetes Secrets support via `secretRefs` for sensitive values
- Artifact Hub annotations in `Chart.yaml`

**Testing**
- Unit tests with helm-unittest (25+ test files covering deployment, configmap, services, PVCs, RBAC, security contexts, and more)
- KIND cluster acceptance tests including a live TCP target connection test
- AWS EKS and Azure AKS integration test suites with Terraform (IRSA / workload identity, managed addons, full lifecycle)

**Tooling**
- `Makefile` targets for lint, unit tests, acceptance tests, and cloud integration tests
- Trivy vulnerability scanning and Kubescape compliance scanning
- Kubernetes manifest validation with kubeconform

### Configuration Defaults

| Parameter | Default | Notes |
|---|---|---|
| Image | `hashicorp/boundary-enterprise:0.21.3-ent` | chart `appVersion` |
| Storage class | `""` | uses cluster default `StorageClass` |
| Auth storage size | `1Gi` | auto-disabled for KMS auth method |
| Recording storage size | `10Gi` | |
| Termination grace period | `7200s` (2 h) | allows active sessions to drain |
| CPU request / limit | `100m` / `200m` | |
| Memory request / limit | `512Mi` / `1Gi` | |

### Documentation
- README with installation guide and configuration reference
- Embedded-values workflow as the primary installation approach
- Common deployment patterns
- Public address and service exposure strategies
- Operations guide covering upgrades and troubleshooting
- Security model overview

### Known Limitations
- Single replica only — horizontal scaling is not supported
- No automatic `public_addr` discovery
- No multi-worker topology orchestration
