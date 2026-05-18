# Copyright IBM Corp. 2026

# Values are supplied via environment variables using the TF_VAR_* convention,
# or via the Makefile -var= flags (which read from the .env file at the repo root).
# Variables not set here fall back to the defaults defined in variables.tf.
#
# Required environment variables (set in .env or export before running make):
#
#   AZURE_SUBSCRIPTION_ID        → azure_subscription_id (default: active az CLI subscription)
#   AZURE_LOCATION               → azure_location       (default: eastus)
#   AZURE_RESOURCE_GROUP         → resource_group_name  (default: boundary-worker-rg)
#   AKS_CLUSTER_NAME             → cluster_name         (default: boundary-aks-cluster)
#   K8S_VERSION                  → k8s_version          (default: 1.31)
#   TF_NODE_VM_SIZE              → node_vm_size         (default: Standard_D2s_v3)
#   TF_NODE_COUNT                → node_count           (default: 2)
#   TF_NODE_MIN                  → node_min_count       (default: 1)
#   TF_NODE_MAX                  → node_max_count       (default: 3)
#   TF_ENABLE_AUTO_SCALING       → enable_auto_scaling  (default: false)
#   TF_ALLOWED_PUBLIC_ACCESS_CIDRS → allowed_public_access_cidrs (default: [])
#   TF_STORAGE_CLASS_NAME        → storage_class_name   (default: managed-csi-premium)
#
# To override on the command line without changing .env:
#   terraform apply -var="cluster_name=my-aks" -var="azure_location=westeurope"
