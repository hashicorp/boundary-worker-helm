# Copyright IBM Corp. 2026

variable "azure_subscription_id" {
  description = "Azure subscription ID to deploy into. Reads from AZURE_SUBSCRIPTION_ID env var via the Makefile. Leave empty to use the active 'az' CLI context subscription."
  type        = string
  default     = ""
}

variable "azure_location" {
  description = "Azure region for all resources (e.g. eastus, westeurope)"
  type        = string
  default     = "eastus"
}

variable "resource_group_name" {
  description = "Name of the Azure resource group that will hold all cluster resources"
  type        = string
  default     = "boundary-worker-rg"
}

variable "cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "boundary-aks-cluster"
}

variable "k8s_version" {
  description = "Kubernetes version for the AKS cluster (e.g. 1.31)"
  type        = string
  default     = "1.31"
}

variable "node_vm_size" {
  description = "Azure VM size for worker nodes (equivalent of EC2 instance type)"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "node_count" {
  description = "Fixed number of worker nodes (used when enable_auto_scaling = false)"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum number of worker nodes when auto-scaling is enabled"
  type        = number
  default     = 1
}

variable "node_max_count" {
  description = "Maximum number of worker nodes when auto-scaling is enabled"
  type        = number
  default     = 3
}

variable "enable_auto_scaling" {
  description = "Enable the AKS cluster autoscaler (uses node_min_count / node_max_count)"
  type        = bool
  default     = false
}

variable "allowed_public_access_cidrs" {
  description = <<-EOT
    CIDRs allowed to reach the AKS public API server.
    Defaults to [] (unrestricted) so any workstation or CI runner can call
    kubectl without extra configuration. For production, restrict this to your
    office egress IP, VPN CIDR, or GitHub Actions IP ranges.
    Example: ["203.0.113.0/24", "198.51.100.42/32"]
  EOT
  type        = list(string)
  default     = []
}

variable "storage_class_name" {
  description = "Name for the managed-CSI premium StorageClass created by Terraform (analogous to 'gp3' on EKS)"
  type        = string
  default     = "managed-csi-premium"
}
