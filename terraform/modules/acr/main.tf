resource "azurerm_container_registry" "acr" {
  name                = var.acr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Basic"  # Cheapest tier
  admin_enabled       = true     # Needed for Azure DevOps
}
