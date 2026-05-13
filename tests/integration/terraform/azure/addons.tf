# Copyright IBM Corp. 2026

# ── managed-csi-premium StorageClass ─────────────────────────────────────────
# Azure Disk CSI driver is enabled by default in AKS ≥ 1.21 (no separate addon
# installation required — analogous to the aws-ebs-csi-driver addon on EKS).
#
# This StorageClass provisions Premium SSD (P-series) managed disks via the
# built-in disk.csi.azure.com provisioner — the Azure equivalent of the gp3
# StorageClass on EKS. WaitForFirstConsumer prevents volumes from being bound
# before the pod is scheduled, avoiding availability-zone placement mismatches.
resource "kubernetes_storage_class_v1" "managed_csi_premium" {
  metadata {
    name = var.storage_class_name
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "disk.csi.azure.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    # Premium_LRS: Premium SSD with locally-redundant storage — best
    # price/performance for a single-region test/staging cluster.
    # Use Premium_ZRS for zone-redundant storage in production.
    skuName = "Premium_LRS"
  }

  depends_on = [azurerm_kubernetes_cluster.aks]
}
