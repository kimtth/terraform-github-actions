resource "azurerm_log_analytics_workspace" "azppf-law" {
  name                = var.log_analytics_workspace_name
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = azurerm_resource_group.azppf-rg.location
  sku                 = "PerGB2018"
  retention_in_days   = 30

  tags = {
    environment = "dev"
  }
}

resource "azurerm_application_insights" "azppf-ai" {
  name                = var.application_insights_name
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = azurerm_resource_group.azppf-rg.location
  workspace_id        = azurerm_log_analytics_workspace.azppf-law.id
  application_type    = "web"

  tags = {
    environment = "dev"
  }
}
