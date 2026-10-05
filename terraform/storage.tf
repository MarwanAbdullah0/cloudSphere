resource "azurerm_managed_disk" "gitlab_data" {
  name                 = "gitlab-data-disk"
  location             = azurerm_resource_group.gitlab_rg.location
  resource_group_name  = azurerm_resource_group.gitlab_rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 128
}

resource "azurerm_virtual_machine_data_disk_attachment" "gitlab_data" {
  managed_disk_id    = azurerm_managed_disk.gitlab_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.gitlab.id
  lun                = 0
  caching            = "None"
}

resource "azurerm_managed_disk" "monitoring_data" {
  name                 = "monitoring-data-disk"
  location             = azurerm_resource_group.gitlab_rg.location
  resource_group_name  = azurerm_resource_group.gitlab_rg.name
  storage_account_type = "StandardSSD_LRS"
  create_option        = "Empty"
  disk_size_gb         = 64
}

resource "azurerm_virtual_machine_data_disk_attachment" "monitoring_data" {
  managed_disk_id    = azurerm_managed_disk.monitoring_data.id
  virtual_machine_id = azurerm_linux_virtual_machine.monitoring.id
  lun                = 0
  caching            = "None"
}

resource "azurerm_storage_account" "backups" {
  name                            = var.backup_storage_account_name
  resource_group_name             = azurerm_resource_group.gitlab_rg.name
  location                        = azurerm_resource_group.gitlab_rg.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  https_traffic_only_enabled      = true
  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }
}

resource "azurerm_storage_container" "backups" {
  name                  = "platform-backups"
  storage_account_id    = azurerm_storage_account.backups.id
  container_access_type = "private"
}

resource "azurerm_storage_management_policy" "backups" {
  storage_account_id = azurerm_storage_account.backups.id

  rule {
    name    = "expire-after-30-days"
    enabled = true
    filters {
      blob_types = ["blockBlob"]
    }
    actions {
      base_blob {
        delete_after_days_since_modification_greater_than = 30
      }
    }
  }
}

resource "azurerm_user_assigned_identity" "gitlab_backup" {
  name                = "gitlab-backup-uai"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
}

resource "azurerm_user_assigned_identity" "monitoring_backup" {
  name                = "monitoring-backup-uai"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
}

resource "azurerm_role_assignment" "gitlab_backup_upload" {
  scope                            = azurerm_storage_container.backups.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.gitlab_backup.principal_id
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "monitoring_backup_upload" {
  scope                            = azurerm_storage_container.backups.id
  role_definition_name             = "Storage Blob Data Contributor"
  principal_id                     = azurerm_user_assigned_identity.monitoring_backup.principal_id
  skip_service_principal_aad_check = true
}
