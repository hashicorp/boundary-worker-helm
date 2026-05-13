# Copyright IBM Corp. 2026

output "cluster_name" {
  description = "AKS cluster name"
  value       = azurerm_kubernetes_cluster.aks.name
}

output "resource_group_name" {
  description = "Azure resource group containing the cluster"
  value       = azurerm_resource_group.aks.name
}

output "cluster_location" {
  description = "Azure region the cluster was created in"
  value       = var.azure_location
}

output "cluster_fqdn" {
  description = "FQDN of the AKS API server"
  value       = azurerm_kubernetes_cluster.aks.fqdn
}

output "vnet_id" {
  description = "VNet ID"
  value       = azurerm_virtual_network.aks.id
}

output "node_subnet_id" {
  description = "Subnet ID used by AKS node pool"
  value       = azurerm_subnet.aks_nodes.id
}

output "aks_identity_principal_id" {
  description = "Principal ID of the AKS system-assigned managed identity"
  value       = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}

output "storage_class_name" {
  description = "Name of the managed-CSI premium StorageClass (analogous to gp3 on EKS)"
  value       = kubernetes_storage_class_v1.managed_csi_premium.metadata[0].name
}

output "kubeconfig_command" {
  description = "Run this command to update your local kubeconfig"
  value       = "az aks get-credentials --resource-group ${azurerm_resource_group.aks.name} --name ${azurerm_kubernetes_cluster.aks.name} --overwrite-existing"
}

output "aks_context" {
  description = "kubectl/helm context name for this cluster (after running kubeconfig_command)"
  value       = azurerm_kubernetes_cluster.aks.name
}
