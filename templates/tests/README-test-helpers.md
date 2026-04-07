# Helper Templates Unit Test

## Overview
The `test-helpers.yaml` file provides comprehensive unit testing for all helper templates defined in `_helpers.tpl`.

## Test Coverage

This test validates all 14 helper templates in the chart:

### 1. **boundary.name**
- Validates non-empty output
- Ensures truncation to 63 characters (DNS compliance)
- Verifies no trailing hyphens

### 2. **boundary.fullname**
- Validates non-empty output
- Ensures truncation to 63 characters
- Verifies no trailing hyphens
- Confirms it uses Release.Name or fullnameOverride

### 3. **boundary.chart**
- Validates non-empty output
- Ensures truncation to 63 characters
- Verifies format: `name-version`
- Confirms `+` characters are replaced with `_`
- Verifies no trailing hyphens
- Validates chart name is included

### 4. **boundary.labels**
- Validates presence of `helm.sh/chart`
- Validates presence of `app.kubernetes.io/name`
- Validates presence of `app.kubernetes.io/instance`
- Validates presence of `app.kubernetes.io/managed-by`
- Validates presence of `app.kubernetes.io/version` (if AppVersion is set)

### 5. **boundary.selectorLabels**
- Validates presence of `app.kubernetes.io/name`
- Validates presence of `app.kubernetes.io/instance`
- Confirms release name is included

### 6. **boundary.worker.selectorLabels**
- Validates presence of `app.kubernetes.io/name`
- Validates presence of `app.kubernetes.io/instance`
- Validates presence of `app.kubernetes.io/component: worker`

### 7. **boundary.worker.proxy.serviceName**
- Validates non-empty output
- Confirms suffix `-proxy`
- Validates includes fullname

### 8. **boundary.worker.ops.serviceName**
- Validates non-empty output
- Confirms suffix `-ops`
- Validates includes fullname

### 9. **boundary.worker.configmapName**
- Validates non-empty output
- Confirms suffix `-config`
- Validates includes fullname

### 10. **boundary.worker.deploymentName**
- Validates non-empty output
- Confirms suffix `-deployment`
- Validates includes fullname

### 11. **boundary.worker.recordingPvcName**
- Validates non-empty output
- Confirms suffix `-recording-storage`
- Validates includes fullname

### 12. **boundary.worker.authStoragePvcName**
- Validates non-empty output
- Confirms suffix `-auth-storage`
- Validates includes fullname

### 13. **boundary.test.podSecurityContext**
- Validates `runAsNonRoot: true`
- Validates `runAsUser: 65534`
- Validates `runAsGroup: 65534`
- Validates `fsGroup: 65534`
- Validates `seccompProfile.type: RuntimeDefault`

### 14. **boundary.test.containerSecurityContext**
- Validates `allowPrivilegeEscalation: false`
- Validates `runAsNonRoot: true`
- Validates `runAsUser: 65534`
- Validates `runAsGroup: 65534`
- Validates `readOnlyRootFilesystem: true`
- Validates capabilities drop ALL

### 15. **boundary.test.resources**
- Validates CPU request: `100m`
- Validates memory request: `128Mi`
- Validates CPU limit: `200m`
- Validates memory limit: `256Mi`

## Additional Validations

### Resource Name Uniqueness
- Verifies all generated resource names are unique

### DNS Compliance
- Validates all resource names follow DNS naming conventions:
  - Lowercase alphanumeric characters
  - Hyphens allowed (but not at start/end)
  - Maximum 63 characters

## Test Execution

The test runs as a Kubernetes test hook with:
- **Hook Weight**: 5 (runs early in test sequence)
- **Hook Policy**: `before-hook-creation,hook-succeeded`
- **Service Account**: Uses test service account
- **Security Context**: Runs with restricted security settings
- **Image**: `bitnami/kubectl:latest`

## Test Output

The test provides detailed output including:
- Individual test results (✅ PASS / ❌ FAIL)
- Expected vs actual values for failures
- Summary statistics (passed/failed/total)
- Exit code 0 for success, 1 for failure

## Running the Test

```bash
# Install the chart with tests
helm install my-release ./boundary-worker-helm

# Run all tests
helm test my-release

# Run only the helpers test
helm test my-release --filter name=test-helpers
```

## Test Structure

The test uses helper functions for validation:
- `validate_test()` - Compares expected vs actual values
- `validate_not_empty()` - Ensures value is not empty
- `validate_contains()` - Checks if string contains substring
- `validate_max_length()` - Validates maximum length constraint

## Dependencies

This test requires:
- Kubernetes cluster with test service account
- kubectl available in test container
- Worker deployment and related resources created