resource "random_string" "azppf-storage-suffix" {
  length  = 8
  special = false
  upper   = false
}

resource "azurerm_storage_account" "azppf-sa" {
  name                     = "azppfstorage${random_string.azppf-storage-suffix.result}"
  resource_group_name      = azurerm_resource_group.azppf-rg.name
  location                 = azurerm_resource_group.azppf-rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

  shared_access_key_enabled = false

  tags = {
    environment = "dev"
  }
}

resource "azurerm_storage_container" "azppf-fn-releases" {
  name                  = "function-releases"
  storage_account_id    = azurerm_storage_account.azppf-sa.id
  container_access_type = "private"
}

# Zip the echo function source from the ./functions directory
data "archive_file" "azppf-fn-zip" {
  type        = "zip"
  source_dir  = "${path.module}/functions"
  output_path = "${path.module}/.terraform/echo-function.zip"
}

# Grant the Terraform runner identity permission to upload blobs.
# Required because shared_access_key_enabled = false forces Azure AD auth for all
# storage data-plane operations, including the blob upload during terraform apply.
resource "azurerm_role_assignment" "azppf-tf-runner-blob-contributor" {
  scope                = azurerm_storage_account.azppf-sa.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Azure RBAC propagates asynchronously. The role assignment exists in ARM within
# seconds but the storage data-plane auth cache can lag by up to ~2 minutes.
# This sleep ensures the blob upload doesn't race ahead of propagation.
resource "time_sleep" "azppf-rbac-propagation" {
  create_duration = "90s"
  depends_on      = [azurerm_role_assignment.azppf-tf-runner-blob-contributor]
}

resource "azurerm_storage_blob" "azppf-fn-blob" {
  name                   = "echo-function-${data.archive_file.azppf-fn-zip.output_md5}.zip"
  storage_account_name   = azurerm_storage_account.azppf-sa.name
  storage_container_name = azurerm_storage_container.azppf-fn-releases.name
  type                   = "Block"
  source                 = data.archive_file.azppf-fn-zip.output_path

  depends_on = [time_sleep.azppf-rbac-propagation]
}

# Grant the function app's managed identity the roles required by the Functions runtime
# and for WEBSITE_RUN_FROM_PACKAGE blob access.
resource "azurerm_role_assignment" "azppf-fn-blob-owner" {
  scope                = azurerm_storage_account.azppf-sa.id
  role_definition_name = "Storage Blob Data Owner"
  principal_id         = azurerm_linux_function_app.azppf-fn.identity[0].principal_id
}

resource "azurerm_role_assignment" "azppf-fn-queue-contributor" {
  scope                = azurerm_storage_account.azppf-sa.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_linux_function_app.azppf-fn.identity[0].principal_id
}

resource "azurerm_role_assignment" "azppf-fn-table-contributor" {
  scope                = azurerm_storage_account.azppf-sa.id
  role_definition_name = "Storage Table Data Contributor"
  principal_id         = azurerm_linux_function_app.azppf-fn.identity[0].principal_id
}

resource "azurerm_service_plan" "azppf-sp" {
  name                = var.service_plan_name
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = azurerm_resource_group.azppf-rg.location
  os_type             = "Linux"
  sku_name            = "EP1" # Elastic Premium required for VNet integration on consumption

  tags = {
    environment = "dev"
  }
}

resource "azurerm_linux_function_app" "azppf-fn" {
  name                = "azppf-echo-fn-${random_string.azppf-storage-suffix.result}"
  resource_group_name = azurerm_resource_group.azppf-rg.name
  location            = azurerm_resource_group.azppf-rg.location
  service_plan_id     = azurerm_service_plan.azppf-sp.id

  storage_account_name          = azurerm_storage_account.azppf-sa.name
  storage_uses_managed_identity = true

  identity {
    type = "SystemAssigned"
  }

  virtual_network_subnet_id = azurerm_subnet.azppf-fn-subnet.id

  site_config {
    application_stack {
      python_version = "3.12"
    }
  }

  app_settings = {
    FUNCTIONS_WORKER_RUNTIME = "python"
    # No SAS token — the system-assigned managed identity is granted Storage Blob Data Owner
    # on the storage account, so the runtime can read the package blob directly.
    WEBSITE_RUN_FROM_PACKAGE = "https://${azurerm_storage_account.azppf-sa.name}.blob.core.windows.net/${azurerm_storage_container.azppf-fn-releases.name}/${azurerm_storage_blob.azppf-fn-blob.name}"

    # Auto-registered by the portal when selecting Flex Consumption + system-assigned managed identity.
    APPLICATIONINSIGHTS_CONNECTION_STRING = azurerm_application_insights.azppf-ai.connection_string
    AzureWebJobsStorage__blobServiceUri   = "https://${azurerm_storage_account.azppf-sa.name}.blob.core.windows.net"
    AzureWebJobsStorage__queueServiceUri  = "https://${azurerm_storage_account.azppf-sa.name}.queue.core.windows.net"
    AzureWebJobsStorage__tableServiceUri  = "https://${azurerm_storage_account.azppf-sa.name}.table.core.windows.net"
    AzureWebJobsStorage__credential       = "managedidentity"
  }

  tags = {
    environment = "dev"
  }
}
