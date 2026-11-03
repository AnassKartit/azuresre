resource "azurerm_service_plan" "lab" {
  name                = "asp-${local.base}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  os_type             = "Linux"
  sku_name            = "B1"
  tags                = local.tags
}

# Container web app that pulls its image from the private registry, over the VNet, with its managed identity.
resource "azurerm_linux_web_app" "lab" {
  name                      = "app-${local.base}"
  location                  = azurerm_resource_group.lab.location
  resource_group_name       = azurerm_resource_group.lab.name
  service_plan_id           = azurerm_service_plan.lab.id
  virtual_network_subnet_id = azurerm_subnet.app.id
  vnet_image_pull_enabled   = true
  https_only                = true
  tags                      = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    vnet_route_all_enabled                  = true
    container_registry_use_managed_identity = true

    application_stack {
      docker_image_name   = "hello:v1"
      docker_registry_url = "https://${azurerm_container_registry.lab.login_server}"
    }
  }

  app_settings = {
    WEBSITES_PORT = "80"
  }

  logs {
    http_logs {
      file_system {
        retention_in_days = 3
        retention_in_mb   = 35
      }
    }
  }

  depends_on = [terraform_data.sample_image]
}

# Fault: removing this role makes the image pull unauthorized.
resource "azurerm_role_assignment" "webapp_acr_pull" {
  count                = var.fault_acr_pull_role_missing ? 0 : 1
  scope                = azurerm_container_registry.lab.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_linux_web_app.lab.identity[0].principal_id
}

resource "azurerm_monitor_diagnostic_setting" "webapp" {
  name                       = "to-law"
  target_resource_id         = azurerm_linux_web_app.lab.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab.id

  enabled_log {
    category = "AppServicePlatformLogs"
  }
  enabled_log {
    category = "AppServiceConsoleLogs"
  }
  enabled_log {
    category = "AppServiceHTTPLogs"
  }
}
