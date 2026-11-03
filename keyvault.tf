# Certificate scenario: a self-signed certificate that expires within a month.
# Tests what the agent can and can't see about Key Vault certificates.
resource "azurerm_key_vault" "lab" {
  name                       = "kv-${local.flat}"
  location                   = azurerm_resource_group.lab.location
  resource_group_name        = azurerm_resource_group.lab.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
  tags                       = local.tags
}

resource "azurerm_role_assignment" "me_kv_certs" {
  scope                = azurerm_key_vault.lab.id
  role_definition_name = "Key Vault Certificates Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_key_vault_certificate" "expiring" {
  name         = "app-${var.name}-test"
  key_vault_id = azurerm_key_vault.lab.id

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }
    key_properties {
      exportable = true
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = false
    }
    secret_properties {
      content_type = "application/x-pkcs12"
    }
    x509_certificate_properties {
      subject            = "CN=app.${var.name}.test"
      validity_in_months = 1
      key_usage          = ["digitalSignature", "keyEncipherment"]
    }
  }

  depends_on = [azurerm_role_assignment.me_kv_certs]
}
