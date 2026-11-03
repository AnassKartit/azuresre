# Azure SRE Agent, set up the way an enterprise would allow it:
#   - Low access level (Reader on the managed resource groups) and Review mode by default
#   - Azure OpenAI models ("MicrosoftFoundry"), inside the EU Data Boundary
#   - network: the agent's sandbox traffic leaves through a delegated subnet in this VNet (AzureVNet),
#     so your NSG and routes apply to it; no package registries, code repos, extra hosts or remote
#     MCP servers are allowed.
# Schema: stable API 2026-07-01, Azure/azure-rest-api-specs specification/app/resource-manager/Microsoft.App/SreAgent.
# Models available per region: GET /subscriptions/{id}/providers/Microsoft.App/locations/{region}/supportedAgentModels?api-version=2026-07-01
resource "azurerm_user_assigned_identity" "sre" {
  count               = var.deploy_sre_agent ? 1 : 0
  name                = "id-${local.base}-sre"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azapi_resource" "sre_agent" {
  count     = var.deploy_sre_agent ? 1 : 0
  type      = "Microsoft.App/agents@2026-07-01"
  name      = "sre-${local.base}"
  parent_id = azurerm_resource_group.lab.id
  location  = azurerm_resource_group.lab.location
  tags      = local.tags
  # The azapi provider may not ship this API version's schema yet; the service validates the body.
  schema_validation_enabled = false

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.sre[0].id]
  }

  body = {
    properties = {
      knowledgeGraphConfiguration = {
        identity         = azurerm_user_assigned_identity.sre[0].id
        managedResources = concat([azurerm_resource_group.lab.id, azurerm_resource_group.other.id], local.cross_scope_managed)
      }
      actionConfiguration = {
        mode        = var.agent_mode
        identity    = azurerm_user_assigned_identity.sre[0].id
        accessLevel = "Low"
      }
      defaultModel = {
        provider = var.agent_model_provider
        name     = var.agent_model
      }
      vnetConfiguration = var.agent_network_mode == "AzureVNet" ? {
        subnetResourceId = azurerm_subnet.agent.id
      } : null
      sandboxConfiguration = var.agent_network_mode == "Unrestricted" ? null : {
        egress = {
          mode                            = var.agent_network_mode
          allowedHosts                    = []
          allowedRegistries               = []
          allowedCodeRepositories         = []
          allowHttpMcpServerNetworkAccess = false
        }
      }
    }
  }

  response_export_values = ["properties"]
}

# --- What the agent's identity may read ----------------------------------

locals {
  sre_principal      = var.deploy_sre_agent ? azurerm_user_assigned_identity.sre[0].principal_id : null
  network_watcher_rg = "/subscriptions/${var.subscription_id}/resourceGroups/NetworkWatcherRG"
  sre_reader_scopes  = { lab = azurerm_resource_group.lab.id, other = azurerm_resource_group.other.id }
  sre_netdiag_scopes = { lab = azurerm_resource_group.lab.id, nw = local.network_watcher_rg }
}

resource "azurerm_role_assignment" "sre_reader" {
  for_each             = var.deploy_sre_agent ? local.sre_reader_scopes : {}
  scope                = each.value
  role_definition_name = "Reader"
  principal_id         = local.sre_principal
}

resource "azurerm_role_assignment" "sre_monitoring_reader" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Monitoring Reader"
  principal_id         = local.sre_principal
}

resource "azurerm_role_assignment" "sre_log_reader" {
  count                = var.deploy_sre_agent ? 1 : 0
  scope                = azurerm_resource_group.lab.id
  role_definition_name = "Log Analytics Reader"
  principal_id         = local.sre_principal
}

# Network Watcher checks (IP flow verify, next hop, effective NSG and routes) are "actions",
# not reads, so Reader alone doesn't allow them. This role adds only those.
resource "azurerm_role_definition" "network_diagnostics_reader" {
  name        = "Network Diagnostics Reader (${local.base})"
  scope       = "/subscriptions/${var.subscription_id}"
  description = "Read-only network diagnostics for the SRE Agent POC."

  permissions {
    actions = [
      "Microsoft.Network/networkWatchers/read",
      "Microsoft.Network/networkWatchers/ipFlowVerify/action",
      "Microsoft.Network/networkWatchers/nextHop/action",
      "Microsoft.Network/networkWatchers/securityGroupView/action",
      "Microsoft.Network/networkWatchers/queryFlowLogStatus/action",
      "Microsoft.Network/networkInterfaces/effectiveNetworkSecurityGroups/action",
      "Microsoft.Network/networkInterfaces/effectiveRouteTable/action",
    ]
  }

  assignable_scopes = [azurerm_resource_group.lab.id, local.network_watcher_rg]

  depends_on = [terraform_data.network_watcher]
}

resource "azurerm_role_assignment" "sre_network_diagnostics" {
  for_each           = var.deploy_sre_agent ? local.sre_netdiag_scopes : {}
  scope              = each.value
  role_definition_id = azurerm_role_definition.network_diagnostics_reader.role_definition_resource_id
  principal_id       = local.sre_principal
}

# You, as SRE Agent Administrator on the agent, to manage it and chat with it.
resource "azurerm_role_assignment" "me_sre_admin" {
  count              = var.deploy_sre_agent ? 1 : 0
  scope              = azapi_resource.sre_agent[0].id
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/e79298df-d852-4c6d-84f9-5d13249d1e55"
  principal_id       = data.azurerm_client_config.current.object_id
}
