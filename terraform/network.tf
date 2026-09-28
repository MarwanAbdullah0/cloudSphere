# Vnet and Subnets


resource "azurerm_virtual_network" "gitlab_vnet" {
  name                = "gitlab-vnet"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
  address_space       = ["10.0.0.0/16"]

  tags = {
    environment = "Bootcamp"
  }
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.gitlab_rg.name
  virtual_network_name = azurerm_virtual_network.gitlab_vnet.name
  address_prefixes     = ["10.0.0.0/27"]
}

resource "azurerm_subnet" "gitlab" {
  name                 = "gitlab-subnet"
  resource_group_name  = azurerm_resource_group.gitlab_rg.name
  virtual_network_name = azurerm_virtual_network.gitlab_vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "monitoring" {
  name                 = "monitoring-subnet"
  resource_group_name  = azurerm_resource_group.gitlab_rg.name
  virtual_network_name = azurerm_virtual_network.gitlab_vnet.name
  address_prefixes     = ["10.0.3.0/24"]
}


# NSG Associations

resource "azurerm_subnet_network_security_group_association" "gitlab" {
  subnet_id                 = azurerm_subnet.gitlab.id
  network_security_group_id = azurerm_network_security_group.gitlab_nsg.id
}

resource "azurerm_subnet_network_security_group_association" "monitoring" {
  subnet_id                 = azurerm_subnet.monitoring.id
  network_security_group_id = azurerm_network_security_group.monitoring_nsg.id
}