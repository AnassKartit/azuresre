# Least privilege for the SRE Agent, measured in the video (2026-11-03):
# - Reader can't run `az webapp config appsettings list`: it needs Microsoft.Web/sites/config/list/Action,
#   which Azure itself names "List Web App Security Sensitive Settings". Keep it that way.
# - In Autonomous mode the agent tried to restart the web app and RBAC blocked it. If you want it to fix
#   things, give it exactly the actions it needs, on the resources it needs, and keep a Review plan.

# 1. Investigate: App Service's own diagnostics, without secrets. Always on with the agent.
resource "azurerm_role_definition" "web_diagnostics_reader" {
  name        = "SRE Web Diagnostics Reader (${local.base})"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "App Service diagnostics, detectors and container logs. No app settings, no writes."

  permissions {
    actions = [
      "Microsoft.Web/sites/read",
      "Microsoft.Web/sites/config/read",
      "Microsoft.Web/sites/diagnostics/*",
      "Microsoft.Web/sites/detectors/read",
      "Microsoft.Web/sites/containerlogs/action",
    ]
    not_actions = [
      "Microsoft.Web/sites/config/list/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.lab.id]
}

resource "azurerm_role_assignment" "sre_web_diagnostics" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azurerm_resource_group.lab.id
  role_definition_id = azurerm_role_definition.web_diagnostics_reader.role_definition_resource_id
  principal_id       = local.sre_principal
}

# 2. Fix (optional): restart the web app and edit ONE network security group. Nothing else.
variable "agent_can_remediate" {
  description = "Give the agent a narrow responder role (restart/start/stop the web app, edit rules of the private-endpoint NSG). Pair with a Review response plan."
  type        = bool
  default     = false
}

resource "azurerm_role_definition" "responder" {
  name        = "SRE Responder (${local.base})"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Restart/start/stop web apps and edit NSG rules. Assigned on single resources only."

  permissions {
    actions = [
      "Microsoft.Web/sites/restart/action",
      "Microsoft.Web/sites/start/action",
      "Microsoft.Web/sites/stop/action",
      "Microsoft.Network/networkSecurityGroups/read",
      "Microsoft.Network/networkSecurityGroups/securityRules/read",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
    ]
  }

  assignable_scopes = [azurerm_resource_group.lab.id]
}

resource "azurerm_role_assignment" "sre_responder_webapp" {
  count              = var.deploy_sre_agent && var.agent_can_remediate ? 1 : 0
  scope              = azurerm_linux_web_app.lab.id
  role_definition_id = azurerm_role_definition.responder.role_definition_resource_id
  principal_id       = local.sre_principal
}

resource "azurerm_role_assignment" "sre_responder_nsg" {
  count              = var.deploy_sre_agent && var.agent_can_remediate ? 1 : 0
  scope              = azurerm_network_security_group.pe.id
  role_definition_id = azurerm_role_definition.responder.role_definition_resource_id
  principal_id       = local.sre_principal
}
