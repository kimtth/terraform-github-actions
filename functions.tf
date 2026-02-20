# Echo container running inside fn-subnet — no App Service plan required.
# Uses Azure Container Instances (ACI) which draw from a separate quota pool,
# avoiding the vCPU quota constraint on the App Service / dedicated plan family.
# mendhak/http-https-echo reflects the full request (headers, body, method) as JSON.
resource "azurerm_container_group" "azppf-echo-cg" {
  name                = "azppf-echo-cg"
  location            = azurerm_resource_group.azppf-rg.location
  resource_group_name = azurerm_resource_group.azppf-rg.name
  ip_address_type     = "Private"
  subnet_ids          = [azurerm_subnet.azppf-fn-subnet.id]
  os_type             = "Linux"

  container {
    name   = "echo"
    image  = "mendhak/http-https-echo:latest"
    cpu    = "0.5"
    memory = "0.5"

    ports {
      port     = 8080
      protocol = "TCP"
    }

    environment_variables = {
      HTTP_PORT = "8080"
    }
  }

  tags = {
    environment = "dev"
  }
}

output "echo_private_ip" {
  description = "Private IP of the ACI echo container. Reachable from Power Platform via VNet injection."
  value       = azurerm_container_group.azppf-echo-cg.ip_address
}
