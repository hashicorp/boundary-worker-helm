# Acceptance Testing Quick Start Guide

This guide helps you quickly set up and run acceptance tests for the Boundary Worker Helm chart in a KIND cluster.

## Prerequisites

Ensure you have the following tools installed:
- `kubectl`
- `kind`
- `helm`
- `boundary` CLI
- `curl`

## Setup Steps

### 1. Configure Environment Variables

Create a `.env` file with your Boundary credentials:

```bash
# Copy the template
cp .env.example .env

# Edit with your actual values
vim .env
```

Your `.env` should contain:
```bash
BOUNDARY_ADDR=https://your-cluster.boundary.hashicorp.cloud
BOUNDARY_LOGIN_NAME=admin
BOUNDARY_PASSWORD=your-actual-password
BOUNDARY_CLUSTER_ID=your-cluster-id
```

### 2. Load Environment Variables

```bash
source tests/acceptance/load-env.sh
```

### 3. Run Full Acceptance Test

```bash
make acceptance-full
```

This will:
1. ✅ Create KIND cluster
2. ✅ Install dependencies
3. ✅ Generate worker configuration
4. ✅ Deploy Helm chart
5. ✅ Run basic tests
6. ✅ Run comprehensive tests (worker registration + session validation)

## Individual Test Steps

If you prefer to run steps individually:

```bash
# Step 1: Setup KIND cluster
make acceptance-setup

# Step 2: Generate worker config
make worker-config

# Step 3: Install Helm chart
make acceptance-helm

# Step 4: Run basic tests
make acceptance-test

# Step 5: Run comprehensive tests
make acceptance-kind-test
```

## What Gets Tested

### Basic Tests (`acceptance-test`)
- KIND cluster accessibility
- Namespace creation
- Basic cluster operations

### Comprehensive Tests (`acceptance-kind-test`)
- ✅ Worker deployment in KIND cluster
- ✅ Worker pod running and healthy
- ✅ Worker registration with INT long-lived cluster
- ✅ Boundary controller authentication
- ✅ Session creation and authorization
- ✅ Worker-controller communication
- ✅ Health endpoints responding
- ✅ Persistent volumes bound
- ✅ Services configured correctly

## Cleanup

Remove the KIND cluster and generated files:

```bash
make acceptance-cleanup
```

## Troubleshooting

### Environment Variables Not Set

If you see errors about missing environment variables:
```bash
source tests/acceptance/load-env.sh
```

### Authentication Failed

Verify your credentials in `.env`:
- Check `BOUNDARY_ADDR` is correct
- Verify `BOUNDARY_LOGIN_NAME` and `BOUNDARY_PASSWORD`
- Ensure network connectivity to Boundary controller

### Worker Not Registering

Check worker logs:
```bash
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance
```

### Session Creation Failed

This may be expected if no targets are configured. To fully test:
1. Configure a target in your Boundary controller
2. Ensure the worker is available for that target
3. Re-run the tests

## Security Notes

- ✅ `.env` is gitignored - your credentials are safe
- ✅ Never commit `.env` with real credentials
- ✅ Use `.env.example` as a template
- ✅ For CI/CD, use secrets management

## More Information

For detailed documentation, see:
- [`tests/acceptance/README.md`](tests/acceptance/README.md) - Complete testing guide
- [`.env.example`](.env.example) - Environment variable template
- [`Makefile`](Makefile) - All available targets

## Quick Reference

```bash
# Full workflow
make acceptance-full

# Individual steps
make acceptance-setup      # Setup KIND cluster
make worker-config         # Generate worker config
make acceptance-helm       # Install Helm chart
make acceptance-test       # Basic tests
make acceptance-kind-test  # Comprehensive tests
make acceptance-cleanup    # Cleanup

# Load environment
source tests/acceptance/load-env.sh

# View logs
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --context kind-acceptance -f