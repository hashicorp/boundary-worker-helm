# Pre-Release Checklist for Boundary Worker Helm Chart

This document contains a comprehensive checklist of items to verify before making this repository public and releasing version 0.1.0.

## 📋 Documentation

- [ ] **README.md** - Comprehensive and complete ✅
- [ ] **CONTRIBUTING.md** - Present but minimal - consider expanding with:
  - Code of conduct reference
  - Issue/PR templates guidance
  - Development setup instructions
  - Testing requirements and expectations
  - Release process documentation
- [ ] **LICENSE** - **MISSING** - add appropriate open source license (Apache 2.0, MIT, etc.)
- [ ] **CHANGELOG.md** - **MISSING** - create initial changelog for v0.1.0
- [ ] **SECURITY.md** - **MISSING** - add security policy and vulnerability reporting process
- [ ] **Remove placeholder values** from `values.yaml`:
  - Line 34: `<activation-token>` placeholder
  - Line 37: `hcp_boundary_cluster_id` contains test cluster ID `84bac8e2-5385-4b91-a056-1f45913dce6b`
- [ ] **Remove placeholders** from `scripts/worker-template.hcl`:
  - Line 23: `<activation-token>` placeholder
  - Line 26: `<cluster-id>` placeholder

## 🔒 Security & Secrets

- [ ] **Audit all files** for sensitive data (API keys, tokens, credentials, cluster IDs)
- [ ] **Review `.gitignore`** - appears complete ✅
- [ ] **Verify no secrets** in git history (run `git log -p | grep -i "password\|token\|secret\|key"`)
- [ ] **Review security contexts** in templates - appear secure ✅
- [ ] **Validate `kubescape-exceptions.json`** - ensure all exceptions are documented with justifications
- [ ] **Scan for hardcoded credentials** in all HCL and YAML files
- [ ] **Review test files** for any embedded secrets or tokens

## 🏗️ Repository Structure

- [ ] **Add CODE_OF_CONDUCT.md** - standard for open source projects
- [ ] **Create `.github/` directory** with:
  - `ISSUE_TEMPLATE/` - bug report, feature request templates
  - `PULL_REQUEST_TEMPLATE.md` - PR template with checklist
  - `workflows/` - GitHub Actions for CI/CD (optional but recommended)
  - `CODEOWNERS` - define code ownership
  - `dependabot.yml` - automated dependency updates (optional)
- [ ] **Add badges to README** (build status, license, version, Helm chart version, etc.)
- [ ] **Create `docs/` directory** (optional) for extended documentation

## 📦 Chart Metadata

- [ ] **Update `Chart.yaml`**:
  - Verify `version: 0.1.0` is appropriate for initial release
  - Update `appVersion` to match target Boundary version (currently "0.20.0", but image uses "0.21-ent")
  - Update `maintainers` information - currently generic "HashiCorp", needs contact info
  - Update `sources` URL when repository is made public (currently points to hashicorp/boundary-worker-helm)
  - Verify `keywords` are comprehensive for discoverability ✅
  - Add `home` URL verification
  - Consider adding `icon` URL that will remain stable
- [ ] **Verify chart follows Helm best practices** (`helm lint .`)
- [ ] **Consider adding `artifacthub.io` annotations** for better discoverability
- [ ] **Add chart description** to repository settings on GitHub

## 🧪 Testing & Quality

- [ ] **All unit tests passing** - run `make unit-test` and verify
- [ ] **Acceptance tests functional** - run `make acceptance-full` ✅
- [ ] **Linting passes** - run `make lint` and verify all checks pass
- [ ] **Security scans clean** - verify Trivy and Kubescape results
- [ ] **Test with multiple Kubernetes versions** (1.25, 1.26, 1.27, 1.28, 1.29)
- [ ] **Test with different storage classes** beyond `gp2` (gp3, standard, etc.)
- [ ] **Validate all documented examples** in README work as written
- [ ] **Test upgrade scenarios** (0.1.0 to future versions)
- [ ] **Test rollback scenarios** (`helm rollback`)
- [ ] **Verify graceful shutdown** with active sessions

## 🔧 Configuration

- [ ] **Review default resource limits**:
  - CPU: 200m limit, 100m request - appropriate for production?
  - Memory: 1Gi limit, 512Mi request - appropriate for production?
- [ ] **Verify default storage sizes**:
  - Auth storage: 1Gi - sufficient?
  - Recording storage: 10Gi - sufficient for expected usage?
- [ ] **Document all required vs optional configuration** clearly
- [ ] **Ensure all template variables have sensible defaults**
- [ ] **Review `terminationGracePeriodSeconds: 7200`** - 2 hours is very long, document rationale
- [ ] **Validate AWS-specific annotations** work or are properly filtered for non-AWS environments

## 📝 Legal & Compliance

- [ ] **Add copyright headers** to all source files - partially done, verify:
  - All `.yaml` files in `templates/`
  - All test files
  - All scripts
  - Makefile
- [ ] **Choose and add LICENSE file** - critical for open source
- [ ] **Verify third-party dependencies** and their licenses
- [ ] **Add NOTICE file** if required by dependencies
- [ ] **Verify IBM Corp. copyright (2026)** is appropriate or update to correct entity
- [ ] **Review Chart.yaml copyright** - currently shows "Copyright IBM Corp. 2026"
- [ ] **Ensure compliance** with HashiCorp trademark usage if applicable

## 🚀 Release Process

- [ ] **Create release notes** for v0.1.0 with:
  - Features included
  - Known limitations
  - Breaking changes (if any)
  - Upgrade instructions
- [ ] **Tag release in git** (`git tag -a v0.1.0 -m "Initial release"`)
- [ ] **Package Helm chart** (`helm package .`)
- [ ] **Test installation from packaged chart** on clean cluster
- [ ] **Publish to Helm repository** (if applicable - ChartMuseum, Harbor, etc.)
- [ ] **Update documentation** with installation from repository
- [ ] **Create GitHub Release** with packaged chart attached
- [ ] **Announce release** in appropriate channels

## 🌐 Community & Support

- [ ] **Define support channels** (GitHub Issues, forums, Slack, etc.)
- [ ] **Set up GitHub Discussions** (optional but recommended)
- [ ] **Create initial set of GitHub labels** for issues:
  - bug, enhancement, documentation, question, help-wanted, good-first-issue
- [ ] **Document expected response times** and support SLAs
- [ ] **Add link to HashiCorp Boundary documentation** in README
- [ ] **Create FAQ section** in README or separate doc
- [ ] **Set up issue triage process**

## ✅ Final Checks

- [ ] **All CI/CD pipelines** configured and passing (if using GitHub Actions)
- [ ] **Repository description** and topics set on GitHub
- [ ] **README renders correctly** on GitHub (check formatting, links, images)
- [ ] **All links in documentation work** (no 404s)
- [ ] **Chart installs successfully** on fresh cluster with default values
- [ ] **Uninstall/cleanup works properly** (`helm uninstall` + PVC cleanup)
- [ ] **No TODO or FIXME comments** in production code
- [ ] **Version numbers consistent** across:
  - Chart.yaml
  - README.md
  - Any documentation
- [ ] **Test on different platforms** (EKS, GKE, AKS, kind, minikube)
- [ ] **Verify image pull** works from public registry

## 🎯 Priority Items (Must Fix Before Release)

### Critical (Blocking Release)

1. **Add LICENSE file** - Cannot release open source without license
2. **Remove placeholder secrets** from:
   - `values.yaml` lines 34, 37
   - `scripts/worker-template.hcl` lines 23, 26
3. **Add SECURITY.md** - Standard security policy for public repos
4. **Verify no secrets in git history** - Security requirement

### High Priority (Should Fix Before Release)

5. **Expand CONTRIBUTING.md** - Help contributors understand process
6. **Create CHANGELOG.md** - Document release history and changes
7. **Verify copyright headers** - Legal compliance across all files
8. **Add GitHub templates** - Improve contribution quality
9. **Update Chart.yaml maintainers** - Provide accurate contact information
10. **Fix appVersion mismatch** - Chart.yaml shows 0.20.0, image uses 0.21-ent

### Medium Priority (Nice to Have)

11. **Add CODE_OF_CONDUCT.md** - Community standards
12. **Create comprehensive examples** - Help users get started
13. **Add badges to README** - Show project health
14. **Set up GitHub Actions** - Automated testing and validation
15. **Test on multiple K8s versions** - Ensure compatibility

## 📊 Verification Commands

Run these commands to verify readiness:

```bash
# Lint and validate
make lint

# Run unit tests
make unit-test

# Package chart
helm package .

# Install from package
helm install test-release ./boundary-worker-0.1.0.tgz --dry-run --debug

# Check for secrets in git history
git log -p | grep -iE "password|token|secret|key|activation" | grep -v "placeholder"

# Verify all files have copyright headers
find . -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.hcl" \) -exec grep -L "Copyright" {} \;

# Check for TODO/FIXME
grep -r "TODO\|FIXME" --exclude-dir=.git --exclude="*.md"
```

## 📅 Release Timeline

1. **Week 1**: Address all critical priority items
2. **Week 2**: Address high priority items and testing
3. **Week 3**: Address medium priority items and documentation
4. **Week 4**: Final review, testing, and release

## 📞 Questions to Answer Before Release

- [ ] Who will maintain this repository after release?
- [ ] What is the support model (community, commercial, hybrid)?
- [ ] Will this be published to a public Helm repository?
- [ ] What is the versioning strategy (semver)?
- [ ] What is the release cadence?
- [ ] Are there any trademark or branding guidelines to follow?
- [ ] What is the relationship with HashiCorp (if any)?
- [ ] Should this be under IBM Corp. or HashiCorp organization?

---

**Last Updated**: 2026-05-11  
**Target Release Date**: TBD  
**Release Version**: 0.1.0