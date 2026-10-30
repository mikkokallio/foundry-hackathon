terraform {
  backend "local" {}
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.foundation.subscription_id
  tenant_id                       = var.foundation.tenant_id
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

provider "azapi" {
  subscription_id            = var.foundation.subscription_id
  tenant_id                  = var.foundation.tenant_id
  skip_provider_registration = true
}
