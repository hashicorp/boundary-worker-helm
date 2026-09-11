# Changelog

All notable changes to the Boundary Worker Helm Chart will be documented in this file.

## [0.2.0-beta] - 2026-09-15

### Added

- OpenShift support via `openshift.enabled` , proxy and operations Routes configurable through `openshift.route.proxy` and `openshift.route.ops`.
- Operations listener TLS configuration through `tls.ops.disabled`, `tls.secretName`, and `tls.mountPath`, including automatic HTTPS health probes and certificate Secret mounts.
- Operations Route support for `edge` and `reencrypt` termination, `insecureEdgeTerminationPolicy`, and an optional `destinationCACertificate`.
- Validation that the operations listener TLS settings and certificate paths in `worker.config` agree with the chart TLS values.

### Changed

- Updated the chart version to `0.2.0-beta` and the default Boundary Enterprise version to `1.0.2-ent`.
- OpenShift deployments now use OpenShift-specific pod and container security contexts.
- Image defaults are selected by platform: `hashicorp/boundary-enterprise` on Kubernetes and `registry.connect.redhat.com/hashicorp/boundary-enterprise` with the `-ubi` tag suffix on OpenShift. Explicit `image.repository` and `image.tag` values still take precedence.
- Proxy and operations Services are always rendered, with their types controlled by `worker.service.proxy.type` and `worker.service.ops.type`.

### Removed

- Chart-managed ServiceAccount creation. Set `serviceAccount.name` to use an existing ServiceAccount; otherwise the pod uses the namespace's default ServiceAccount.

## [0.1.1] - 2026-07-30

### Changed

- Default worker image updated to `hashicorp/boundary-enterprise:1.0.1-ent`.

### Removed

- Removed Slack status notification step from the release workflow (`hashicorp/actions-slack-status`).

## [0.1.0] - 2026-06-30

First stable release of the Boundary Worker Helm chart, promoting `0.1.0-beta` with the following additions.

### Added

- **PVC default StorageClass** — PVCs now omit the `storageClassName` field when `worker.persistence.*.storageClass` is empty (`""`), causing Kubernetes to automatically provision storage using the cluster's default `StorageClass`. Previously an explicit class was required.
- **PVC retention policies** — New `worker.persistence.authStorage.retainOnUninstall` and `worker.persistence.recording.retainOnUninstall` boolean values (default `true`). When `true` (the default), the chart adds the `helm.sh/resource-policy: keep` annotation to the PVC, preserving it across `helm uninstall`. Set to `false` to have Helm delete the PVC on uninstall. JSON Schema validation and unit tests added for both flags.
- **Env reference validation for activation tokens** — `helm template` / `helm install` now fail with a clear error message if `secretRefs.secretName` is set and `worker.config` either hardcodes the activation token or uses an unexpected `env://` variable name. The only accepted reference is `env://BOUNDARY_WORKER_CONTROLLER_GENERATED_ACTIVATION_TOKEN`.

### Changed

- Default worker image updated to `hashicorp/boundary-enterprise:1.0.0-ent`.

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
