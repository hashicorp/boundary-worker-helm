# Boundary Worker Helm Chart - Upgrade Guide

This document provides guidance for upgrading the Boundary Worker Helm chart between versions.

## General Upgrade Process

1. **Review the CHANGELOG** - Check for breaking changes in the version you're upgrading to
2. **Backup worker state** - If using persistent volumes, ensure they're backed up
3. **Test in non-production** - Validate the upgrade in a test environment first
4. **Plan for session drainage** - Active sessions may be interrupted during upgrade

## Breaking Changes by Version

### Version x.x.x (Initial Release)

This is the initial release. No upgrade path from previous versions.

**Important Configuration Changes:**
- Worker configuration now requires explicit setting of required fields
- `observations_enable` corrected to `observations_enabled` in default config

## Standard Upgrade Procedure

### Step 1: Update Your Values File

Review your `values.yaml` file and compare it with the new chart's default values:

```bash
helm show values hashicorp/boundary-worker > new-values.yaml
diff my-values.yaml new-values.yaml
```

### Step 2: Perform the Upgrade

```bash
helm upgrade boundary-worker hashicorp/boundary-worker \
  --namespace boundary \
  -f my-values.yaml
```

The worker pod will be recreated with the new configuration. The long `terminationGracePeriodSeconds` (2 hours by default) allows active sessions to complete naturally.

### Step 3: Verify the Upgrade

Check that the worker pod is running:

```bash
kubectl get pods -n boundary -l app.kubernetes.io/name=boundary-worker
```

Check worker logs:

```bash
kubectl logs -n boundary -l app.kubernetes.io/name=boundary-worker --tail=50
```

Verify worker registration with controller:

```bash
boundary workers list
```

## Handling Active Sessions During Upgrade

The worker has a long termination grace period (default 2 hours) to allow active sessions to complete. During an upgrade:

1. Kubernetes sends SIGTERM to the old worker pod
2. The worker enters graceful shutdown mode
3. Active sessions continue until completion or timeout
4. New worker pod starts and registers with the controller
5. New sessions are routed to the new worker

**To minimize disruption:**
- Schedule upgrades during low-usage periods
- Notify users of planned maintenance
- Consider the maximum expected session duration
- Adjust `terminationGracePeriodSeconds` if needed

## Rollback Procedure

If the upgrade fails, you can rollback to the previous version:

```bash
helm rollback boundary-worker -n boundary
```

**Note:** If persistent volumes were modified, you may need to restore from backup.

## Common Upgrade Issues

### Issue: Worker fails to start after upgrade

**Symptoms:** Pod is in CrashLoopBackOff state

**Solutions:**
1. Check worker logs: `kubectl logs -n boundary <pod-name>`
2. Verify worker configuration is valid HCL
3. Ensure required fields are set (activation token or cluster ID)
4. Check persistent volume mounts

### Issue: Worker not registering with controller

**Symptoms:** Worker pod runs but doesn't appear in controller

**Solutions:**
1. Verify network connectivity to controller
2. Check activation token is valid
3. Ensure controller address is correct
4. Review worker logs for authentication errors

### Issue: Persistent volume claim pending

**Symptoms:** PVC remains in Pending state

**Solutions:**
1. Check if StorageClass exists: `kubectl get storageclass`
2. Verify cluster has available storage
3. Check PVC events: `kubectl describe pvc -n boundary`
4. Ensure storageClass is specified in values if no default exists

### Issue: Old worker pod won't terminate

**Symptoms:** Old pod stays in Terminating state

**Solutions:**
1. Check for active sessions keeping it alive
2. Wait for termination grace period to expire
3. Force delete only as last resort: `kubectl delete pod <name> --force --grace-period=0`

## Version-Specific Upgrade Notes

### Upgrading to x.x.x (Future)

*This section will be populated when version x.x.x is released*

## Upgrading Worker Configuration

If you need to update the worker configuration (HCL):

1. Update your `values.yaml` with the new configuration
2. Run `helm upgrade` as normal
3. The worker pod will be recreated with the new config
4. Active sessions will drain from the old pod

**Example:**

```yaml
worker:
  config: |
    # Updated configuration here
    worker {
      tags {
        type = ["worker", "egress", "new-tag"]
      }
    }
```

## Persistent Volume Considerations

### Auth Storage

The auth storage volume contains the worker's identity. If this is lost, the worker will need to re-register with the controller.

**Backup strategy:**
```bash
# Create a backup of the auth storage PVC
kubectl get pvc -n boundary boundary-worker-auth-storage -o yaml > auth-storage-backup.yaml
```

### Recording Storage

The recording storage volume contains session recordings. Ensure adequate backup strategy for compliance requirements.

## Getting Help

If you encounter issues during upgrade:

1. Check the [FAQ](FAQ.md) for common issues
2. Review the [CHANGELOG](../CHANGELOG.md) for known issues
3. Check worker logs for error messages
4. Consult the [Boundary documentation](https://developer.hashicorp.com/boundary/docs)

## Best Practices

1. **Test upgrades in non-production** - Validate in a test environment first
2. **Review breaking changes** - Read the CHANGELOG before upgrading
3. **Plan for session drainage** - Consider active sessions and grace period
4. **Monitor after upgrade** - Watch logs and verify worker registration
5. **Backup persistent volumes** - Especially auth storage
6. **Schedule during maintenance windows** - Minimize user impact
7. **Keep chart and Boundary versions aligned** - Use compatible versions
8. **Document your configuration** - Keep track of customizations