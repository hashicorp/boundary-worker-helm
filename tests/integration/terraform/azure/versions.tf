# Copyright IBM Corp. 2026

terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }

  # ── Remote State (recommended for CI/CD) ─────────────────────────────────
  # Uncomment and fill in to store state in Azure Blob Storage:
  #
  # backend "azurerm" {
  #   resource_group_name  = "your-tfstate-rg"
  #   storage_account_name = "yourtfstateaccount"
  #   container_name       = "tfstate"
  #   key                  = "boundary-worker/aks/terraform.tfstate"
  # }
}

provider "azurerm" {
  features {}

  # Skip automatic resource-provider registration. The providers needed for AKS
  # (Microsoft.ContainerService, Microsoft.Network, Microsoft.Compute,
  # Microsoft.Storage) must already be registered in the subscription, which is
  # the default state for any active subscription.
  # In azurerm ~> 3.x the equivalent of resource_provider_registrations="none".
  skip_provider_registration = true

  # Explicitly target the subscription set in AZURE_SUBSCRIPTION_ID so that
  # Terraform never accidentally runs against the wrong account. Falls back to
  # the subscription that is active in the current 'az' CLI context when the
  # variable is not set.
  subscription_id = var.azure_subscription_id != "" ? var.azure_subscription_id : null
}

# The kubernetes and helm providers are configured directly from the AKS cluster
# credentials output. Terraform resolves the implicit dependency on
# azurerm_kubernetes_cluster.aks before initialising these providers.
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

provider "helm" {
  kubernetes {
    host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
    client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
    client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
    cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
  }
}
