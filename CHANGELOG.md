# Changelog

All notable changes to the Boundary Worker Helm Chart will be documented in this file.

## [Unreleased]

## [x.x.x] - YYYY-MM-DD

### Added
- Initial Helm chart for HashiCorp Boundary Worker
- Single-replica worker deployment with persistent storage
- Support for controller-led, worker-led, and KMS-based worker registration
- Configurable proxy and operations Services
- Optional PersistentVolumeClaims for auth storage and session recording
- Auth storage PVC is optional — KMS-based workers can use an `emptyDir` instead (`worker.persistence.authStorage.enabled: false`)
- Worker HCL config embedded in `values.yaml` by default; `--set-file worker.config=<file>` supported
- Comprehensive unit tests with helm-unittest (25+ test pods)
- KIND cluster acceptance tests including TCP target connection test
- AWS EKS integration test suite with Terraform (IRSA support, addons, full lifecycle)
- Azure AKS integration test suite with Terraform (workload identity, addons, full lifecycle)
- Security-hardened pod and container contexts (non-root, read-only filesystem, dropped capabilities)
- Makefile with lint, unit-test, acceptance, and integration workflow targets
- Trivy and Kubescape security scanning
- Kubernetes manifest validation with kubeconform
- Artifact Hub annotations in `Chart.yaml` (`artifacthub.io/*`)

### Configuration Defaults
- Default image: `hashicorp/boundary-enterprise:0.21-ent` (chart `appVersion`)
- Default storage class: `""` — uses the cluster default StorageClass
- Default auth storage: `1Gi` (disabled automatically for KMS auth)
- Default recording storage: `10Gi`
- Default termination grace period: `7200s` (2 hours) — allows active sessions to drain
- Default resources: `100m` CPU / `512Mi` memory (requests), `200m` CPU / `1Gi` memory (limits)

### Documentation
- Comprehensive README with installation and configuration guide
- Embedded-values workflow as the primary installation approach
- Common deployment patterns (egress, intermediate workers)
- Public address and service exposure strategies
- Operations guide for upgrades and troubleshooting
- Security model documentation

### Known Limitations
- Single replica only (no horizontal scaling)
- No automatic session drain during upgrades
- No automatic `public_addr` discovery
- No built-in secret management integration
- No multi-worker topology orchestration
