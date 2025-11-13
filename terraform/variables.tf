variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
  default     = "devops-test-rg"
}

variable "location" {
  description = "Azure region"
  type        = string
  default     = "eastus"
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "mirror-api-aks"
}

variable "acr_name" {
  description = "Azure Container Registry name (must be globally unique)"
  type        = string
  default     = "mirrorapiregistry"  # Change this to something unique
}

variable "keyvault_name" {
  description = "Azure Key Vault name (must be globally unique)"
  type        = string
  default     = "mirrorapikv"  # Change this to something unique
}

variable "node_count" {
  description = "Number of AKS nodes (keep low for cost)"
  type        = number
  default     = 2
}

variable "vm_size" {
  description = "VM size for AKS nodes (B2s is cheapest)"
  type        = string
  default     = "Standard_B2s"
}
