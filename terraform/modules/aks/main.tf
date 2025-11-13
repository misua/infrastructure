resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.cluster_name
  
  # Cheap node pool for testing
  default_node_pool {
    name       = "default"
    node_count = var.node_count
    vm_size    = var.vm_size
    vnet_subnet_id = var.subnet_id
  }
  
  # System-assigned identity (simplest option)
  identity {
    type = "SystemAssigned"
  }
  
  # Network profile
  network_profile {
    network_plugin = "azure"
    network_policy = "azure"
  }
}
