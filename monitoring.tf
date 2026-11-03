resource "azurerm_log_analytics_workspace" "lab" {
  name                = "log-${local.base}"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 1
  tags                = local.tags
}

resource "azurerm_monitor_data_collection_rule" "vm" {
  name                = "dcr-${local.base}-vm"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  tags                = local.tags

  destinations {
    log_analytics {
      name                  = "law"
      workspace_resource_id = azurerm_log_analytics_workspace.lab.id
    }
  }

  data_flow {
    streams      = ["Microsoft-Perf", "Microsoft-Syslog"]
    destinations = ["law"]
  }

  data_sources {
    performance_counter {
      name                          = "perf"
      streams                       = ["Microsoft-Perf"]
      sampling_frequency_in_seconds = 60
      counter_specifiers = [
        "Processor(*)\\% Processor Time",
        "Memory(*)\\% Used Memory",
        "Logical Disk(*)\\Disk Transfers/sec",
        "Logical Disk(*)\\% Used Space",
        "Network(*)\\Total Bytes Transmitted",
      ]
    }

    syslog {
      name           = "syslog"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["user", "daemon", "syslog"]
      log_levels     = ["*"]
    }
  }
}

# --- Alerts the agent can be triggered from -----------------------------

resource "azurerm_monitor_metric_alert" "web_cpu" {
  name                = "alert-${local.base}-web-cpu"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [azurerm_linux_virtual_machine.vm["web"].id]
  description         = "Web VM CPU above 90% for 5 minutes"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Percentage CPU"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 90
  }
}

resource "azurerm_monitor_metric_alert" "web_disk_iops" {
  name                = "alert-${local.base}-web-disk-iops"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [azurerm_linux_virtual_machine.vm["web"].id]
  description         = "Web VM data disk using more than 95% of its provisioned IOPS"
  severity            = 2
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Microsoft.Compute/virtualMachines"
    metric_name      = "Data Disk IOPS Consumed Percentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 95
  }
}

# --- VNet flow logs with traffic analytics -----------------------------

resource "azurerm_storage_account" "flowlogs" {
  name                            = "st${local.flat}fl"
  location                        = azurerm_resource_group.lab.location
  resource_group_name             = azurerm_resource_group.lab.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  tags                            = local.tags
}

# Azure creates one Network Watcher per region in "NetworkWatcherRG", but not always on a new
# subscription. This makes sure it exists; both commands do nothing if it already does.
resource "terraform_data" "network_watcher" {
  provisioner "local-exec" {
    command = "az group create -n NetworkWatcherRG -l ${var.location} --subscription ${var.subscription_id} -o none && az network watcher configure -g NetworkWatcherRG -l ${var.location} --enabled true --subscription ${var.subscription_id} -o none"
  }
}

resource "azurerm_network_watcher_flow_log" "vnet" {
  name                 = "fl-${local.base}"
  network_watcher_name = "NetworkWatcher_${var.location}"
  resource_group_name  = "NetworkWatcherRG"
  target_resource_id   = azurerm_virtual_network.lab.id
  storage_account_id   = azurerm_storage_account.flowlogs.id
  enabled              = true
  version              = 2
  tags                 = local.tags

  retention_policy {
    enabled = true
    days    = 3
  }

  traffic_analytics {
    enabled               = true
    workspace_id          = azurerm_log_analytics_workspace.lab.workspace_id
    workspace_region      = azurerm_log_analytics_workspace.lab.location
    workspace_resource_id = azurerm_log_analytics_workspace.lab.id
    interval_in_minutes   = 10
  }

  depends_on = [terraform_data.network_watcher]
}
