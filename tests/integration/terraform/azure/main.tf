# Copyright IBM Corp. 2026

locals {
  tags = {
    Project     = "boundary-worker"
    ManagedBy   = "terraform"
    ClusterName = var.cluster_name
  }
}

data "azurerm_client_config" "current" {}

# ── Resource Group ────────────────────────────────────────────────────────────
resource "azurerm_resource_group" "aks" {
  name     = var.resource_group_name
  location = var.azure_location
  tags     = local.tags
}

# ── Virtual Network ───────────────────────────────────────────────────────────
# Single VNet with two subnets:
#   aks-nodes  — worker node NICs and pod CIDRs (Azure CNI)
#   aks-pods   — reserved for pod overlay (used when network_plugin = "azure")
resource "azurerm_virtual_network" "aks" {
  name                = "${var.cluster_name}-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  tags                = local.tags
}

resource "azurerm_subnet" "aks_nodes" {
  name                 = "aks-nodes"
  resource_group_name  = azurerm_resource_group.aks.name
  virtual_network_name = azurerm_virtual_network.aks.name
  # /22 gives 1022 usable host addresses — enough for node NICs and pod IPs
  # with Azure CNI (30 pods per node × node_max_count nodes + headroom).
  address_prefixes = ["10.0.0.0/22"]
}

# ── AKS Cluster ───────────────────────────────────────────────────────────────
resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = azurerm_resource_group.aks.location
  resource_group_name = azurerm_resource_group.aks.name
  dns_prefix          = var.cluster_name
  kubernetes_version  = var.k8s_version

  # Public API endpoint is required for workstation / CI kubectl access.
  # Restrict to specific CIDRs in production via allowed_public_access_cidrs.
  api_server_access_profile {
    authorized_ip_ranges = length(var.allowed_public_access_cidrs) > 0 ? var.allowed_public_access_cidrs : null
  }

  default_node_pool {
    name                 = "default"
    vm_size              = var.node_vm_size
    os_disk_size_gb      = 50
    vnet_subnet_id       = azurerm_subnet.aks_nodes.id
    enable_auto_scaling  = var.enable_auto_scaling
    node_count           = var.enable_auto_scaling ? null : var.node_count
    min_count            = var.enable_auto_scaling ? var.node_min_count : null
    max_count            = var.enable_auto_scaling ? var.node_max_count : null

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # System-assigned managed identity — AKS uses this to manage Azure resources
  # (load balancers, NICs, disks) on behalf of the cluster. No client credentials
  # to rotate, and it works out-of-the-box without extra role assignments.
  identity {
    type = "SystemAssigned"
  }

  network_profile {
    # Azure CNI: pods receive real VNet IPs, which is required for direct
    # Boundary worker-to-controller TCP connectivity without NAT masquerading.
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    # Use a non-overlapping range for Kubernetes service ClusterIPs.
    # VNet is 10.0.0.0/16 — use 10.1.0.0/16 to avoid the ServiceCidrOverlap error.
    service_cidr   = "10.1.0.0/16"
    dns_service_ip = "10.1.0.10"
  }

  # Azure Disk CSI driver is enabled by default in AKS ≥ 1.21.
  # Explicitly enabling ensures it remains active even if the default changes.
  storage_profile {
    disk_driver_enabled = true
  }

  tags = local.tags
}

# ── Role assignment: AKS → VNet ───────────────────────────────────────────────
# Allows the AKS system identity to attach NICs and manage subnets in the VNet.
resource "azurerm_role_assignment" "aks_vnet_contributor" {
  scope                = azurerm_virtual_network.aks.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_kubernetes_cluster.aks.identity[0].principal_id
}
