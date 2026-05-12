# Changelog

All notable changes to the Boundary Worker Helm Chart will be documented in this file.

## [Unreleased]

## [0.1.0] - 2026-05-12

### Added
- Initial Helm chart for HashiCorp Boundary Worker
- Single-replica worker deployment with persistent storage
- Support for controller-led worker registration
- Support for worker-led registration
- Support for KMS-backed worker authentication
- Configurable proxy and operations Services
- PersistentVolumeClaim support for auth and recording storage
- Comprehensive unit tests with helm-unittest
- Acceptance tests for KIND clusters
- Integration with HCP Boundary and self-managed Boundary
- Security-hardened pod and container contexts
- Makefile with lint, test, and acceptance workflows
- Trivy and Kubescape security scanning
- Kubernetes manifest validation with kubeconform
- SECURITY.md with GitHub private advisory reporting process
- Expanded CONTRIBUTING.md with development setup and release process

### Features
- **Deployment**: Single worker replica with configurable resources
- **Storage**: Optional PVCs for auth storage and session recording
- **Services**: Configurable proxy (LoadBalancer/NodePort/ClusterIP) and ops (ClusterIP) services
- **Security**: Non-root execution, read-only filesystem, dropped capabilities
- **Configuration**: HCL-based worker config with Helm templating support
- **Testing**: 25+ Helm test pods covering deployment, networking, and functionality

### Configuration
- Default image: `hashicorp/boundary-enterprise:0.21-ent`
- Default storage class: cluster default (configurable)
- Default auth storage: 1Gi
- Default recording storage: 10Gi
- Default termination grace period: 7200s (2 hours)
- Default resources: 100m CPU / 512Mi memory (requests), 200m CPU / 1Gi memory (limits)

### Documentation
- Comprehensive README with installation and configuration guide
- Common deployment patterns (egress, intermediate workers)
- Public address and service exposure strategies
- Operations guide for upgrades and troubleshooting
- Security model documentation
- Contributing guidelines

### Known Limitations
- Single replica only (no horizontal scaling)
- No automatic session drain during upgrades
- No automatic public_addr discovery
- No built-in secret management integration
- No multi-worker topology orchestration

[Unreleased]: https://github.com/hashicorp/boundary-worker-helm/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/hashicorp/boundary-worker-helm/releases/tag/v0.1.0