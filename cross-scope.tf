# Cross-region / cross-resource-group test.
# Question: can the agent (deployed in var.location) see and reason about resources in another
# resource group in ANOTHER region? Answer is decided by RBAC + the agent's managed resources,
# not by the agent's region. Two steps:
#   1. cross_scope_test = true             -> rg-…-fr in France Central with an NSG that blocks 443.
#                                            The agent has NO role there: it must say it has no access.
#   2. + cross_scope_grant = true          -> Reader on rg-…-fr and rg-…-fr added to managed resources.
#                                            It must now name the deny rule.
# Everything here is free (resource group + NSG).

variable "cross_scope_test" {
  description = "Create rg-…-fr (France Central) with an NSG that blocks HTTPS, for the cross-region / cross-RG test."
  type        = bool
  default     = false
}

variable "cross_scope_grant" {
  description = "Give the agent Reader on rg-…-fr and add it to the agent's managed resources (step 2 of the test)."
  type        = bool
  default     = false
}

variable "cross_scope_location" {
  description = "Region of the cross-scope resource group (different from var.location on purpose)."
  type        = string
  default     = "francecentral"
}

resource "azurerm_resource_group" "fr" {
  count    = var.cross_scope_test ? 1 : 0
  name     = "rg-${local.base}-fr"
  location = var.cross_scope_location
  tags     = local.tags
}

resource "azurerm_network_security_group" "fr" {
  count               = var.cross_scope_test ? 1 : 0
  name                = "nsg-${local.base}-fr"
  location            = azurerm_resource_group.fr[0].location
  resource_group_name = azurerm_resource_group.fr[0].name
  tags                = local.tags

  security_rule {
    name                       = "deny-https-in"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_role_assignment" "sre_reader_fr" {
  count                = var.deploy_sre_agent && var.cross_scope_test && var.cross_scope_grant ? 1 : 0
  scope                = azurerm_resource_group.fr[0].id
  role_definition_name = "Reader"
  principal_id         = local.sre_principal
}

locals {
  cross_scope_managed = var.cross_scope_test && var.cross_scope_grant ? [azurerm_resource_group.fr[0].id] : []
}
