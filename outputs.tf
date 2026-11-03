output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "other_resource_group" {
  value = azurerm_resource_group.other.name
}

output "web_vm" {
  value = azurerm_linux_virtual_machine.vm["web"].name
}

output "cli_vm" {
  value = azurerm_linux_virtual_machine.vm["cli"].name
}

output "web_app_url" {
  value = "https://${azurerm_linux_web_app.lab.default_hostname}"
}

output "registry" {
  value = azurerm_container_registry.lab.login_server
}

output "ops_identity" {
  value = azurerm_user_assigned_identity.ops.name
}

output "log_analytics_workspace" {
  value = azurerm_log_analytics_workspace.lab.name
}

output "sre_agent" {
  value = var.deploy_sre_agent ? azapi_resource.sre_agent[0].name : "not deployed"
}

output "sre_agent_portal" {
  value = "https://sre.azure.com"
}
