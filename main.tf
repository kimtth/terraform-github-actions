terraform {
  required_providers {
    # Official documentation for the AzureRM provider can be found here:
    # https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=4.1.0"
    }
    # Used to zip the Azure Functions source code for deployment
    archive = {
      source  = "hashicorp/archive"
      version = ">=2.7.1"
    }
    # Used to generate a unique suffix for globally-unique resource names
    random = {
      source  = "hashicorp/random"
      version = ">=3.6.0"
    }
    # Used to delay blob upload until Azure RBAC propagation completes
    time = {
      source  = "hashicorp/time"
      version = ">=0.12.0"
    }
  }

  # Update this block with the location of your terraform state file
  # this block is required for when you want to use Azure Storage as the state backend for Terraform.
  # backend "azurerm" {
  #   resource_group_name  = "rg-terraform-github-actions-state"
  #   storage_account_name = "terraformgithubactions"
  #   container_name       = "tfstate"
  #   key                  = "terraform.tfstate"
  #   use_oidc             = true
  # }
}

# Authentication to Azure is handled via the Azure CLI.
provider "azurerm" {
  features {}

  tenant_id              = var.tenant_id
  subscription_id        = var.subscription_id
  storage_use_azuread    = true
}

# Exposes the object_id of whichever identity is running terraform apply
# (Azure CLI user locally, or service principal in GitHub Actions).
data "azurerm_client_config" "current" {}

