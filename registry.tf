# Premium is the cheapest tier that supports private endpoints.
resource "azurerm_container_registry" "lab" {
  name                          = "acr${local.flat}"
  location                      = azurerm_resource_group.lab.location
  resource_group_name           = azurerm_resource_group.lab.name
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = false
  # Lets `az acr import` (a trusted service) reach the registry despite public access being off.
  network_rule_bypass_option = "AzureServices"
  tags                       = local.tags
}

resource "azurerm_private_dns_zone" "acr" {
  name                = "privatelink.azurecr.io"
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

# Fault: unlinking the zone makes the registry name resolve to its public IP inside the VNet.
resource "azurerm_private_dns_zone_virtual_network_link" "acr" {
  count               = var.fault_private_dns_unlinked ? 0 : 1
  name                = "vlnk-${local.base}"
  private_dns_zone_id = azurerm_private_dns_zone.acr.id
  virtual_network_id  = azurerm_virtual_network.lab.id
  tags                = local.tags
}

resource "azurerm_private_endpoint" "acr" {
  name                = "pep-${local.base}-acr"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  subnet_id           = azurerm_subnet.pe.id
  tags                = local.tags

  private_service_connection {
    name                           = "acr"
    private_connection_resource_id = azurerm_container_registry.lab.id
    subresource_names              = ["registry"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "acr"
    private_dns_zone_ids = [azurerm_private_dns_zone.acr.id]
  }
}

# Copy a small public sample image into the registry once.
resource "terraform_data" "sample_image" {
  triggers_replace = [azurerm_container_registry.lab.id]

  provisioner "local-exec" {
    command = "az acr import --name ${azurerm_container_registry.lab.name} --source mcr.microsoft.com/azuredocs/aci-helloworld:latest --image hello:v1 --subscription ${var.subscription_id} --force"
  }
}
