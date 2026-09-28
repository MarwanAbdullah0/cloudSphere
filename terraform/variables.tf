variable "location" {
  description = "The Azure region to deploy resources in."
  type        = string
  default     = "eastus"

}
variable "subscription_id" {
  description = "The Azure subscription ID to deploy resources in."
  type        = string
  default     = "id"
}
variable "resource_group_name" {
  description = "The name of the resource group to create."
  type        = string
  default     = "gitlab-rg"
}

variable "backup_storage_account_name" {
  description = "Globally unique lowercase Azure Storage account name for backups (3-24 letters or digits)."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.backup_storage_account_name))
    error_message = "Use 3-24 lowercase letters or digits."
  }
}


# Compute variables

variable "admin_username" {
  description = "The admin username for the virtual machines."
  type        = string
  default     = "azureadmin"
}


variable "ssh_public_key_path" {
  description = "Path to the SSH public key used for VM access"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "gitlab_vm_size" {
  description = "Azure VM size for GitLab"
  type        = string
  default     = "Standard_D2as_v7"
}

variable "runner_vm_size" {
  description = "Azure VM size for GitLab Runner"
  type        = string
  default     = "Standard_D2as_v7"
}

variable "monitoring_vm_size" {
  description = "Azure VM size for the monitoring stack"
  type        = string
  default     = "Standard_D2ds_v7"
}

# VPN variables


variable "vpn_client_address_space" {
  description = "The address pool for the VPN client."
  type        = list(string)
  default     = ["172.16.100.0/24"]
}

variable "vpn_entra_audience" {
  description = "Client ID of the dedicated Entra app registration for VPN access. Leave null until its enterprise app requires assignment and approved users are assigned."
  type        = string
  default     = null

  validation {
    condition     = var.vpn_entra_audience == null || can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.vpn_entra_audience))
    error_message = "vpn_entra_audience must be a GUID client ID or null."
  }
}

variable "entra_tenant_id" {
  description = "Entra tenant ID for VPN authentication. Defaults to the tenant of the active Azure provider login."
  type        = string
  default     = null

  validation {
    condition     = var.entra_tenant_id == null || can(regex("^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", var.entra_tenant_id))
    error_message = "entra_tenant_id must be a GUID tenant ID or null."
  }
}
