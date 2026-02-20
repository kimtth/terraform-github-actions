# ─── Secondary VNet ───────────────────────────────────────────────────────────
# Required for US geography (eastus + westus pair).
# Set enable_secondary_vnet = true before running setup-powerplatform-vnet.ps1.
# https://learn.microsoft.com/en-us/power-platform/admin/vnet-support-overview#supported-regions

variable "enable_secondary_vnet" {
  type        = bool
  description = "Deploy secondary VNet. Required for US geography Power Platform VNet integration."
  default     = false
}

variable "vnet_secondary_name" {
  type    = string
  default = "azppf-vnet-secondary"
}

variable "vnet_secondary_address_space" {
  type    = string
  default = "10.124.0.0/16"
}

variable "ppf_secondary_subnet_name" {
  type        = string
  description = "Must have the same number of available IPs as ppf_subnet_prefix"
  default     = "azppf-ppf-subnet"
}

variable "ppf_secondary_subnet_prefix" {
  type    = string
  default = "10.124.1.0/24"
}

variable "nsg_secondary_name" {
  type    = string
  default = "azppf-nsg-secondary"
}

# ─── Resources ────────────────────────────────────────────────────────────────

resource "azurerm_virtual_network" "azppf-vn-secondary" {
  count               = var.enable_secondary_vnet ? 1 : 0
  name                = var.vnet_secondary_name
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = var.secondary_location
  address_space       = [var.vnet_secondary_address_space]

  tags = {
    environment = "dev"
  }
}

resource "azurerm_subnet" "azppf-ppf-subnet-secondary" {
  count                = var.enable_secondary_vnet ? 1 : 0
  name                 = var.ppf_secondary_subnet_name
  resource_group_name  = azurerm_resource_group.azppf-rg.name
  virtual_network_name = azurerm_virtual_network.azppf-vn-secondary[0].name
  address_prefixes     = [var.ppf_secondary_subnet_prefix]

  delegation {
    name = "ppf-delegation"
    service_delegation {
      name    = "Microsoft.PowerPlatform/enterprisePolicies"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# NSGs are region-scoped — a separate NSG in secondary_location is required.
# Reuses the same inbound rule as the primary NSG.
resource "azurerm_network_security_group" "azppf-sg-secondary" {
  count               = var.enable_secondary_vnet ? 1 : 0
  name                = var.nsg_secondary_name
  location            = var.secondary_location
  resource_group_name = azurerm_resource_group.azppf-rg.name

  tags = {
    environment = "dev"
  }
}

resource "azurerm_network_security_rule" "azppf-dev-rule-secondary" {
  count                       = var.enable_secondary_vnet ? 1 : 0
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
  network_security_group_name = azurerm_network_security_group.azppf-sg-secondary[0].name
}

resource "azurerm_subnet_network_security_group_association" "azppf-ppf-sga-secondary" {
  count                     = var.enable_secondary_vnet ? 1 : 0
  subnet_id                 = azurerm_subnet.azppf-ppf-subnet-secondary[0].id
  network_security_group_id = azurerm_network_security_group.azppf-sg-secondary[0].id
}

# ─── VNet Peering ─────────────────────────────────────────────────────────────
# Power Platform workers injected into the secondary VNet (japanwest) must be
# able to reach the ACI at 10.123.2.4 which lives in the primary VNet (japaneast).
# Without peering, secondary workers have no route to the ACI and all flows
# routed there return 502. Peering is bidirectional and requires one resource on
# each side.

resource "azurerm_virtual_network_peering" "azppf-primary-to-secondary" {
  count                        = var.enable_secondary_vnet ? 1 : 0
  name                         = "azppf-primary-to-secondary"
  resource_group_name          = azurerm_resource_group.azppf-rg.name
  virtual_network_name         = azurerm_virtual_network.azppf-vn.name
  remote_virtual_network_id    = azurerm_virtual_network.azppf-vn-secondary[0].id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}

resource "azurerm_virtual_network_peering" "azppf-secondary-to-primary" {
  count                        = var.enable_secondary_vnet ? 1 : 0
  name                         = "azppf-secondary-to-primary"
  resource_group_name          = azurerm_resource_group.azppf-rg.name
  virtual_network_name         = azurerm_virtual_network.azppf-vn-secondary[0].name
  remote_virtual_network_id    = azurerm_virtual_network.azppf-vn.id
  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
}
