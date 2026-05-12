# Contributing to Boundary Worker Helm Chart

Thank you for your interest in contributing to the Boundary Worker Helm Chart! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Testing](#testing)
- [Submitting Changes](#submitting-changes)
- [Code Review Process](#code-review-process)
- [Release Process](#release-process)

## Code of Conduct

This project adheres to a Code of Conduct that all contributors are expected to follow.

## Getting Started

### Prerequisites

Before contributing, ensure you have the following tools installed:

- [Helm](https://helm.sh/docs/intro/install/) 3.x
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) or another Kubernetes cluster
- [Boundary CLI](https://www.boundaryproject.io/downloads) (for acceptance tests)
- [Make](https://www.gnu.org/software/make/)

Optional but recommended:
- [Prettier](https://prettier.io/) for YAML formatting
- [yamllint](https://github.com/adrienverge/yamllint) for YAML linting
- [Trivy](https://github.com/aquasecurity/trivy) for security scanning
- [Kubescape](https://github.com/kubescape/kubescape) for Kubernetes security

### Quick Setup

```bash
# Clone the repository
git clone https://github.com/hashicorp/boundary-worker-helm.git
cd boundary-worker-helm

# Install dependencies (macOS)
make deps

# Run tests
make test

# Run linting
make lint
```

## Development Setup

### 1. Fork and Clone

1. Fork the repository on GitHub
2. Clone your fork locally:
   ```bash
   git clone https://github.com/YOUR_USERNAME/boundary-worker-helm.git
   cd boundary-worker-helm
   ```

3. Add the upstream repository:
   ```bash
   git remote add upstream https://github.com/hashicorp/boundary-worker-helm.git
   ```

### 2. Create a Branch

Create a feature branch for your changes:

```bash
git checkout -b feature/your-feature-name
```

Use descriptive branch names:
- `feature/` for new features
- `fix/` for bug fixes
- `docs/` for documentation changes
- `test/` for test improvements

## Making Changes

### Chart Development

1. **Modify templates** in the `templates/` directory
2. **Update values** in `values.yaml` if adding new configuration options
3. **Update documentation** in `README.md` for user-facing changes
4. **Add tests** for new functionality

### Commit Guidelines

Write clear, descriptive commit messages:

```
<type>: <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `test`: Test additions or modifications
- `refactor`: Code refactoring
- `chore`: Maintenance tasks

**Example:**
```
feat: add support for custom annotations on services

Add new values for proxy and ops service annotations to allow
users to configure cloud provider-specific settings.

Closes #123
```

### Code Style

- **YAML files**: Use 2-space indentation
- **HCL files**: Follow HashiCorp HCL style guide
- **Comments**: Add comments for complex logic
- **Formatting**: Run `make format` before committing

## Testing

### Unit Tests

Run Helm unit tests with helm-unittest:

```bash
make unit-test
```

Add tests for new templates in `tests/unit/`:

```yaml
suite: test new feature
templates:
  - worker-deployment.yaml
tests:
  - it: should set custom annotation
    set:
      worker.customAnnotation: "test-value"
    asserts:
      - equal:
          path: metadata.annotations.custom
          value: "test-value"
```

### Acceptance Tests

Run acceptance tests on a KIND cluster:

```bash
# Full acceptance workflow
make acceptance-full

# Or step by step:
make acceptance-setup
make worker-config  # Requires BOUNDARY_* env vars
make acceptance-helm
make acceptance-test
```

### Linting and Security

```bash
# Run all lints and scans
make lint

# Individual checks
make lint-helm-k8s    # Helm lint + kubeconform
make trivy-scan       # Security vulnerabilities
make kubescape-scan   # Kubernetes security posture
```

### Manual Testing

Test your changes manually:

```bash
# Render templates
helm template boundary-worker . -f your-values.yaml

# Dry run install
helm install boundary-worker . --dry-run --debug

# Install on test cluster
helm install boundary-worker . -n boundary --create-namespace
```

## Submitting Changes

### Before Submitting

Ensure your changes pass all checks:

```bash
# Format code
make format

# Run tests
make test

# Run linting
make lint

# Verify no secrets or placeholders
git diff | grep -i "password\|token\|secret"
```

### Pull Request Process

1. **Push your branch** to your fork:
   ```bash
   git push origin feature/your-feature-name
   ```

2. **Open a Pull Request** on GitHub with:
   - Clear title describing the change
   - Description of what changed and why
   - Reference to related issues (e.g., "Closes #123")
   - Screenshots for UI/output changes
   - Testing performed

3. **Complete the PR template** checklist

4. **Respond to feedback** from reviewers

### PR Requirements

- [ ] All tests pass
- [ ] Linting passes
- [ ] Documentation updated
- [ ] CHANGELOG.md updated (for user-facing changes)
- [ ] Commit messages follow guidelines
- [ ] No merge conflicts with main branch

## Code Review Process

### What to Expect

- **Initial review**: Within 3-5 business days
- **Feedback**: Reviewers may request changes
- **Approval**: Requires approval from at least one maintainer
- **Merge**: Maintainers will merge approved PRs

### Review Criteria

Reviewers will check for:

- **Functionality**: Does it work as intended?
- **Tests**: Are there adequate tests?
- **Documentation**: Is it well documented?
- **Security**: Are there security implications?
- **Compatibility**: Does it maintain backward compatibility?
- **Code quality**: Is the code clean and maintainable?

## Release Process

Releases are managed by maintainers following this process:

1. Update version in `Chart.yaml`
2. Update `CHANGELOG.md` with release notes
3. Create and push a git tag (e.g., `v0.1.0`)
4. Package the chart: `helm package .`
5. Create GitHub release with packaged chart
6. Publish to Helm repository (if applicable)

## Getting Help

- **Questions**: Open a [GitHub Discussion](https://github.com/hashicorp/boundary-worker-helm/discussions)
- **Bugs**: Open a [GitHub Issue](https://github.com/hashicorp/boundary-worker-helm/issues)
- **Security**: See [SECURITY.md](SECURITY.md)

## Additional Resources

- [Helm Chart Best Practices](https://helm.sh/docs/chart_best_practices/)
- [Boundary Documentation](https://www.boundaryproject.io/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [GitHub Flow](https://guides.github.com/introduction/flow/)

## Recognition

Contributors will be recognized in:
- Release notes
- GitHub contributors page
- Project documentation (for significant contributions)

Thank you for contributing to make this project better! 🎉
