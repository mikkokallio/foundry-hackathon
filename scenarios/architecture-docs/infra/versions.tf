terraform {
  backend "local" {}
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
    azapi   = { source = "Azure/azapi", version = "~> 2.13" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.10" }
  }
}

provider "azurerm" {
  features {
    cognitive_account {
      purge_soft_delete_on_destroy = true
    }
  }
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

provider "azuread" {
  tenant_id = var.foundation.tenant_id
}
