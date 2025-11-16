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
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = "10.1.0.0/16"      # Non-overlapping with VNet (10.0.0.0/16)
    dns_service_ip    = "10.1.0.10"        # Must be within service_cidr
    load_balancer_sku = "standard"
  }
}
