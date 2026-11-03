data "azurerm_client_config" "current" {}

resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

locals {
  base = "${var.name}-${random_string.suffix.result}"
  # Alphanumeric-only names (registry, storage, key vault friendly)
  flat = "${var.name}${random_string.suffix.result}"

  tags = {
    purpose = "sre-agent-poc"
    owner   = "lab"
  }
}

resource "azurerm_resource_group" "lab" {
  name     = "rg-${local.base}"
  location = var.location
  tags     = local.tags
}

# Empty resource group used by the permissions scenario (role on the wrong scope).
resource "azurerm_resource_group" "other" {
  name     = "rg-${local.base}-other"
  location = var.location
  tags     = local.tags
}
