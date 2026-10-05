output "gitlab_backup_identity_client_id" {
  value = azurerm_user_assigned_identity.gitlab_backup.client_id
}

output "monitoring_backup_identity_client_id" {
  value = azurerm_user_assigned_identity.monitoring_backup.client_id
}

output "backup_storage_account_name" {
  value = azurerm_storage_account.backups.name
}
