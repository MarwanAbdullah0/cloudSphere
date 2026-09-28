# VPN Gateway Public IP

resource "azurerm_public_ip" "vpn_gateway" {
  name                = "vpn-gateway-pip"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags = {
    environment = "Bootcamp"
  }
}

# Add Entra ID alongside certificate authentication after a dedicated app has been
# configured with required assignment. Existing OpenVPN certificate users remain
# supported during the transition.
data "azurerm_client_config" "current" {}

locals {
  vpn_entra_enabled   = var.vpn_entra_audience != null
  vpn_entra_tenant_id = var.entra_tenant_id != null ? var.entra_tenant_id : data.azurerm_client_config.current.tenant_id
}

# VPN

resource "azurerm_virtual_network_gateway" "vpn" {
  name                = "gitlab-vpn-gateway"
  location            = azurerm_resource_group.gitlab_rg.location
  resource_group_name = azurerm_resource_group.gitlab_rg.name

  type     = "Vpn"
  vpn_type = "RouteBased"

  active_active = false

  sku        = "VpnGw1AZ"
  generation = "Generation1"

  ip_configuration {
    name                          = "vpn-gateway-ipconfig"
    public_ip_address_id          = azurerm_public_ip.vpn_gateway.id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = azurerm_subnet.gateway.id
  }

  vpn_client_configuration {
    address_space = var.vpn_client_address_space

    # AzureRM 5.5.0 requires OpenVPN-only when Entra settings are present.
    vpn_client_protocols = local.vpn_entra_enabled ? ["OpenVPN"] : ["IkeV2", "OpenVPN"]

    vpn_auth_types = local.vpn_entra_enabled ? ["AAD", "Certificate"] : ["Certificate"]

    aad_tenant   = local.vpn_entra_enabled ? "https://login.microsoftonline.com/${local.vpn_entra_tenant_id}" : null
    aad_audience = var.vpn_entra_audience
    aad_issuer   = local.vpn_entra_enabled ? "https://sts.windows.net/${local.vpn_entra_tenant_id}/" : null

    root_certificate {
      name = "bootcamp-vpn-root"

      public_cert_data = replace(
        replace(
          replace(
            replace(
              file("${path.module}/${var.vpn_root_certificate_path}"),
              "-----BEGIN CERTIFICATE-----",
              ""
            ),
            "-----END CERTIFICATE-----",
            ""
          ),
          "\n",
          ""
        ),
        "\r",
        ""
      )
    }
  }

  tags = {
    environment = "Bootcamp"
  }
}
