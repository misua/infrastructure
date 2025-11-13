terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
  
  # State stored in Azure Storage (you'll need to create this manually first)
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "tfstatemirrorapi"  # Must be globally unique
    container_name       = "tfstate"
    key                  = "devops-test.tfstate"
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = true
    }
  }
}

# Resource group for everything
resource "azurerm_resource_group" "main" {
  name     = var.resource_group_name
  location = var.location
}

# Networking
module "networking" {
  source = "./modules/networking"
  
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# Container Registry
module "acr" {
  source = "./modules/acr"
  
  acr_name            = var.acr_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# AKS Cluster
module "aks" {
  source = "./modules/aks"
  
  cluster_name        = var.cluster_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  node_count          = var.node_count
  vm_size             = var.vm_size
  subnet_id           = module.networking.aks_subnet_id
}

# Key Vault
module "keyvault" {
  source = "./modules/keyvault"
  
  keyvault_name       = var.keyvault_name
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
}

# Give AKS permission to pull from ACR
resource "azurerm_role_assignment" "aks_acr_pull" {
  principal_id                     = module.aks.kubelet_identity_object_id
  role_definition_name             = "AcrPull"
  scope                            = module.acr.acr_id
  skip_service_principal_aad_check = true
}
