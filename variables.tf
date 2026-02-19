variable "resource_group_name" {
  type    = string
  default = "azppf-rg"
}

variable "primary_location" {
  type        = string
  description = "Azure region for the resource group and all primary resources (e.g. \"eastus\")."
}

variable "secondary_location" {
  type        = string
  description = "Azure region for secondary resources (e.g. \"westus\"). Required for US geography Power Platform VNet integration."
}

variable "subscription_id" {
  type      = string
  sensitive = true
}

variable "tenant_id" {
  type      = string
  sensitive = true
}

# ─── Networking ───────────────────────────────────────────────────────────────

variable "vnet_name" {
  type    = string
  default = "azppf-vnet"
}

variable "vnet_address_space" {
  type    = string
  default = "10.123.0.0/16"
}

# Power Platform subnet — dedicated to Microsoft.PowerPlatform/enterprisePolicies delegation
variable "ppf_subnet_name" {
  type    = string
  default = "azppf-ppf-subnet"
}

variable "ppf_subnet_prefix" {
  type        = string
  description = "Needs enough IPs: ~30 per prod env + 5 reserved. /24 covers a single env comfortably."
  default     = "10.123.1.0/24"
}

variable "functions_subnet_name" {
  type    = string
  default = "azppf-fn-subnet"
}

variable "functions_subnet_prefix" {
  type    = string
  default = "10.123.2.0/24"
}

variable "nsg_name" {
  type    = string
  default = "azppf-nsg"
}

variable "nsg_rule_name" {
  type    = string
  default = "azppf-dev-rule"
}

variable "dev_source_address_prefix" {
  type        = string
  description = "Source IP/CIDR allowed for inbound dev access"
  default     = "*"
}

# ─── Azure Functions ──────────────────────────────────────────────────────────

variable "service_plan_name" {
  type    = string
  default = "azppf-service-plan"
}

# ─── Monitoring ───────────────────────────────────────────────────────────────

variable "log_analytics_workspace_name" {
  type    = string
  default = "azppf-law"
}

variable "application_insights_name" {
  type    = string
  default = "azppf-ai"
}