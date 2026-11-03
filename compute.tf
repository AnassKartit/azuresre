# Two small Linux VMs, no public IP, no inbound access.
#   web: CPU and disk IOPS scenarios (has a tiny Premium P1 data disk, 120 IOPS)
#   cli: client side: probes SMTP and the web app every 2 minutes and writes the result to syslog
locals {
  vms = {
    web = { cloud_init = "web.yaml" }
    cli = { cloud_init = "cli.yaml" }
  }
}

# Key is only needed by Azure to create the VM; nothing connects over SSH.
resource "tls_private_key" "vm" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "azurerm_network_interface" "vm" {
  for_each            = local.vms
  name                = "nic-vm-${local.base}-${each.key}-001"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.vm.id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_linux_virtual_machine" "vm" {
  for_each              = local.vms
  name                  = "vm-${local.base}-${each.key}"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.vm_size
  admin_username        = "labadmin"
  network_interface_ids = [azurerm_network_interface.vm[each.key].id]
  custom_data = base64encode(templatefile("${path.module}/cloud-init/${each.value.cloud_init}", {
    webapp_host = azurerm_linux_web_app.lab.default_hostname
  }))
  tags = local.tags

  admin_ssh_key {
    username   = "labadmin"
    public_key = tls_private_key.vm.public_key_openssh
  }

  os_disk {
    name                 = "osdisk-vm-${local.base}-${each.key}-001"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }

  boot_diagnostics {}
}

# Smallest Premium SSD (P1: 4 GiB, 120 IOPS) so the disk throttles quickly under load.
resource "azurerm_managed_disk" "web_data" {
  name                 = "disk-vm-${local.base}-web-001"
  location             = azurerm_resource_group.lab.location
  resource_group_name  = azurerm_resource_group.lab.name
  storage_account_type = "Premium_LRS"
  create_option        = "Empty"
  disk_size_gb         = 4
  tags                 = local.tags
}

resource "azurerm_virtual_machine_data_disk_attachment" "web_data" {
  managed_disk_id    = azurerm_managed_disk.web_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.vm["web"].id
  lun                = 0
  caching            = "None"
}

# Azure Monitor agent, sending CPU, memory, disk counters and syslog to Log Analytics.
resource "azurerm_virtual_machine_extension" "ama" {
  for_each                   = local.vms
  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = azurerm_linux_virtual_machine.vm[each.key].id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = local.tags
}

resource "azurerm_monitor_data_collection_rule_association" "vm" {
  for_each                = local.vms
  name                    = "dcra-${each.key}"
  target_resource_id      = azurerm_linux_virtual_machine.vm[each.key].id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.vm.id
}
