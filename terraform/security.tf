
# Network security groups

resource "azurerm_network_security_group" "gitlab_nsg" {
  name                = "gitlab-nsg"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
}

resource "azurerm_network_security_group" "monitoring_nsg" {
  name                = "monitoring-nsg"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
}



# NSG Rules
resource "azurerm_network_security_rule" "gitlab_allow_vpn_https" {
  name      = "allow-vpn-https"
  priority  = 100
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "443"

  source_address_prefixes    = var.vpn_client_address_space
  destination_address_prefix = azurerm_subnet.gitlab.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name
}


# VPN clients -> GitLab SSH; authorized keys control login
resource "azurerm_network_security_rule" "gitlab_allow_vpn_ssh" {
  name      = "allow-vpn-ssh"
  priority  = 110
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "22"

  source_address_prefixes    = var.vpn_client_address_space
  destination_address_prefix = azurerm_subnet.gitlab.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name
}


# Runner -> GitLab HTTPS
resource "azurerm_network_security_rule" "gitlab_allow_runner_https" {
  name      = "allow-runner-https"
  priority  = 120
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "443"

  source_address_prefix      = azurerm_subnet.monitoring.address_prefixes[0]
  destination_address_prefix = azurerm_subnet.gitlab.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name
}


# Prometheus -> GitLab Node Exporter
resource "azurerm_network_security_rule" "gitlab_allow_monitoring_metrics" {
  name      = "allow-monitoring-metrics"
  priority  = 130
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "9100"

  source_address_prefix      = azurerm_subnet.monitoring.address_prefixes[0]
  destination_address_prefix = azurerm_subnet.gitlab.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name
}


# Block other VNet -> GitLab traffic
resource "azurerm_network_security_rule" "gitlab_deny_vnet" {
  name      = "deny-vnet-inbound"
  priority  = 4000
  direction = "Inbound"
  access    = "Deny"
  protocol  = "*"

  source_port_range      = "*"
  destination_port_range = "*"

  source_address_prefix      = "VirtualNetwork"
  destination_address_prefix = azurerm_subnet.gitlab.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.gitlab_nsg.name
}


# Monitoring and Runner subnet rules

# VPN clients -> VM SSH; authorized keys control login
resource "azurerm_network_security_rule" "monitoring_allow_vpn_ssh" {
  name      = "allow-vpn-ssh"
  priority  = 100
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "22"

  source_address_prefixes    = var.vpn_client_address_space
  destination_address_prefix = azurerm_subnet.monitoring.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.monitoring_nsg.name
}


# VPN users -> Grafana
resource "azurerm_network_security_rule" "monitoring_allow_vpn_grafana" {
  name      = "allow-vpn-grafana"
  priority  = 110
  direction = "Inbound"
  access    = "Allow"
  protocol  = "Tcp"

  source_port_range      = "*"
  destination_port_range = "3000"

  source_address_prefixes    = var.vpn_client_address_space
  destination_address_prefix = azurerm_subnet.monitoring.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.monitoring_nsg.name
}


# Block other VNet -> Runner/Monitoring VM traffic
resource "azurerm_network_security_rule" "monitoring_deny_vnet" {
  name      = "deny-vnet-inbound"
  priority  = 4000
  direction = "Inbound"
  access    = "Deny"
  protocol  = "*"

  source_port_range      = "*"
  destination_port_range = "*"

  source_address_prefix      = "VirtualNetwork"
  destination_address_prefix = azurerm_subnet.monitoring.address_prefixes[0]

  resource_group_name         = azurerm_resource_group.gitlab_rg.name
  network_security_group_name = azurerm_network_security_group.monitoring_nsg.name
}
