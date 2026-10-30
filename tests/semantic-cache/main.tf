terraform {
  required_providers {
    azapi   = { source = "Azure/azapi", version = "= 2.13.0" }
    azurerm = { source = "hashicorp/azurerm", version = "= 4.81.0" }
    random  = { source = "hashicorp/random", version = "= 3.9.1" }
  }
}

variable "semantic_cache_enabled" {
  type    = bool
  default = false
}
variable "workload_name" {
  default = "test-only"
}
variable "foundation" {
  default = {
    location             = "swedencentral"
    vault_id             = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.KeyVault/vaults/test-only"
    gateway_id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.ApiManagement/service/test-only"
    gateway_principal_id = "00000000-0000-0000-0000-000000000003"
    foundry_name         = "test-only"
    tags                 = { environment = "test-only" }
  }
}
locals {
  runtime_suffix = "test01"
}
module "runtime_group" {
  source = "./group"
}
data "azurerm_client_config" "current" {}

resource "azapi_resource" "model" {
  for_each                  = toset(["embedding"])
  type                      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  parent_id                 = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.CognitiveServices/accounts/test-only"
  name                      = "test-only-embedding"
  schema_validation_enabled = false
  body                      = {}
}
