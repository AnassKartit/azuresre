# Address plan: one /16 from var.address_space, split with cidrsubnet() so nothing is hard-coded.
locals {
  snet_vm    = cidrsubnet(var.address_space, 8, 1)   # /24
  snet_pe    = cidrsubnet(var.address_space, 8, 2)   # /24
  snet_app   = cidrsubnet(var.address_space, 8, 3)   # /24
  snet_agent = cidrsubnet(var.address_space, 11, 32) # /27, delegated to the SRE Agent
  # Next hop for the black-hole route fault: an address inside the VNet where no appliance exists.
  missing_appliance_ip = cidrhost(cidrsubnet(var.address_space, 8, 250), 4)
}

resource "azurerm_virtual_network" "lab" {
  name                = "vnet-${local.base}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  address_space       = [var.address_space]
  tags                = local.tags
}

# VMs. Default outbound access kept on so the VMs can reach the internet without a NAT gateway.
resource "azurerm_subnet" "vm" {
  name                            = "snet-vm"
  resource_group_name             = azurerm_resource_group.lab.name
  virtual_network_name            = azurerm_virtual_network.lab.name
  address_prefixes                = [local.snet_vm]
  default_outbound_access_enabled = true
}

# Private endpoints. Network policies on, so NSG rules apply to the endpoint.
resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = azurerm_resource_group.lab.name
  virtual_network_name              = azurerm_virtual_network.lab.name
  address_prefixes                  = [local.snet_pe]
  private_endpoint_network_policies = "Enabled"
}

# Web app VNet integration.
resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [local.snet_app]

  delegation {
    name = "webapp"
    service_delegation {
      name    = "Microsoft.Web/serverFarms"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

# SRE Agent sandbox (VNet integration). Same /27 + Microsoft.App/environments delegation as
# Microsoft's zava-aks-postgres lab. Its NSG controls what the agent's own traffic can reach.
resource "azurerm_subnet" "agent" {
  name                 = "snet-agent"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.lab.name
  address_prefixes     = [local.snet_agent]

  delegation {
    name = "sre-agent"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_network_security_group" "agent" {
  name                = "nsg-${local.base}-agent"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "agent" {
  subnet_id                 = azurerm_subnet.agent.id
  network_security_group_id = azurerm_network_security_group.agent.id
}

# --- NSGs -------------------------------------------------------------------

resource "azurerm_network_security_group" "vm" {
  name                = "nsg-${local.base}-vm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "vm" {
  subnet_id                 = azurerm_subnet.vm.id
  network_security_group_id = azurerm_network_security_group.vm.id
}

resource "azurerm_network_security_group" "pe" {
  name                = "nsg-${local.base}-pe"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

# Fault: web app subnet can't reach the registry's private endpoint.
resource "azurerm_network_security_rule" "deny_app_to_acr" {
  count                       = var.fault_nsg_blocks_acr ? 1 : 0
  name                        = "deny-app-to-registry-https"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = local.snet_app
  destination_address_prefix  = local.snet_pe
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.pe.name
}

# Fault: SMTP submission blocked from the VMs.
resource "azurerm_network_security_rule" "deny_smtp" {
  count                       = var.fault_smtp_blocked ? 1 : 0
  name                        = "deny-smtp-submission-out"
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Deny"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "587"
  source_address_prefix       = local.snet_vm
  destination_address_prefix  = "Internet"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.vm.name
}

# --- Route table (fault: black-hole default route) -------------------------

resource "azurerm_route_table" "vm" {
  name                = "rt-${local.base}-vm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  route {
    name                   = "default-to-missing-appliance"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.missing_appliance_ip
  }
}

resource "azurerm_subnet_route_table_association" "vm" {
  count          = var.fault_route_blackhole ? 1 : 0
  subnet_id      = azurerm_subnet.vm.id
  route_table_id = azurerm_route_table.vm.id
}
