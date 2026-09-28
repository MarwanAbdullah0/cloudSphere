# NICs

resource "azurerm_network_interface" "gitlab_nic" {
  name                = "gitlab-nic"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.gitlab.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.1.10"
  }
}

resource "azurerm_network_interface" "monitoring_nic" {
  name                = "monitoring-nic"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.monitoring.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.3.10"
  }
}


# GitLab VM

resource "azurerm_linux_virtual_machine" "gitlab" {
  name                = "gitlab-vm"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name

  size           = var.gitlab_vm_size
  admin_username = var.admin_username

  disable_password_authentication = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.gitlab_backup.id]
  }

  network_interface_ids = [
    azurerm_network_interface.gitlab_nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    name                 = "gitlab-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 64
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    environment = "Bootcamp"
    role        = "GitLab"
  }
}


# Runner + Monitoring VM

resource "azurerm_linux_virtual_machine" "monitoring" {
  name                = "monitoring-vm"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name

  size           = var.monitoring_vm_size
  admin_username = var.admin_username

  disable_password_authentication = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.monitoring_backup.id]
  }

  network_interface_ids = [
    azurerm_network_interface.monitoring_nic.id
  ]

  admin_ssh_key {
    username   = var.admin_username
    public_key = file(pathexpand(var.ssh_public_key_path))
  }

  os_disk {
    name                 = "monitoring-os-disk"
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
    disk_size_gb         = 32
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  tags = {
    environment = "Bootcamp"
    role        = "Runner-Monitoring"
  }
}
