resource "azurerm_virtual_network" "azppf-vn" {
  name                = var.vnet_name
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = azurerm_resource_group.azppf-rg.location
  address_space       = [var.vnet_address_space]

  tags = {
    environment = "dev"
  }
}

# Dedicated subnet for Power Platform VNet integration (enterprise policy delegation)
# Docs: https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview
# Size at least /24 to accommodate plugin containers (25-30 IPs per prod environment)
resource "azurerm_subnet" "azppf-ppf-subnet" {
  name                 = var.ppf_subnet_name
  resource_group_name  = azurerm_resource_group.azppf-rg.name
  virtual_network_name = azurerm_virtual_network.azppf-vn.name
  address_prefixes     = [var.ppf_subnet_prefix]

  delegation {
    name = "ppf-delegation"
    service_delegation {
      name    = "Microsoft.PowerPlatform/enterprisePolicies"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# Dedicated subnet for ACI VNet injection
resource "azurerm_subnet" "azppf-fn-subnet" {
  name                 = var.functions_subnet_name
  resource_group_name  = azurerm_resource_group.azppf-rg.name
  virtual_network_name = azurerm_virtual_network.azppf-vn.name
  address_prefixes     = [var.functions_subnet_prefix]

  delegation {
    name = "fn-delegation"
    service_delegation {
      name    = "Microsoft.ContainerInstance/containerGroups"
      actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
    }
  }
}

resource "azurerm_network_security_group" "azppf-sg" {
  name                = var.nsg_name
  location            = azurerm_resource_group.azppf-rg.location
  resource_group_name = azurerm_resource_group.azppf-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "azppf-dev-rule" {
  name                        = var.nsg_rule_name
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = var.dev_source_address_prefix
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.azppf-rg.name
  network_security_group_name = azurerm_network_security_group.azppf-sg.name
}

resource "azurerm_subnet_network_security_group_association" "azppf-sga" {
  subnet_id                 = azurerm_subnet.azppf-ppf-subnet.id
  network_security_group_id = azurerm_network_security_group.azppf-sg.id
}

resource "azurerm_subnet_network_security_group_association" "azppf-fn-sga" {
  subnet_id                 = azurerm_subnet.azppf-fn-subnet.id
  network_security_group_id = azurerm_network_security_group.azppf-sg.id
}