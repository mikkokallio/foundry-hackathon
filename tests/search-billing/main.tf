terraform {
  required_providers {
    azapi = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

locals {
  search_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.Search/searchServices/test-only"
}

resource "terraform_data" "search" {
  input = {
    sku           = var.search_configuration.sku
    replica_count = var.search_configuration.replica_count
    tags          = var.tags
  }
}
