resource "azurerm_resource_group" "azppf-rg" {
  name     = var.resource_group_name
  location = var.primary_location

  tags = {
    environment = "dev"
  }
}
