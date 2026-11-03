# Permissions scenario: an "ops" identity that should be able to create alert rules in the lab.
# With fault_rbac_wrong_scope = true it gets Contributor on another resource group instead, so writes
# such as Microsoft.Insights/scheduledQueryRules/write in the lab are denied, the classic
# "I activated Contributor but it's still refused" ticket.
resource "azurerm_user_assigned_identity" "ops" {
  name                = "id-${local.base}-ops"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "ops_contributor" {
  scope                = var.fault_rbac_wrong_scope ? azurerm_resource_group.other.id : azurerm_resource_group.lab.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.ops.principal_id
}
