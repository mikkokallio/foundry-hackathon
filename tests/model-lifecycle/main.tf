terraform {
  required_providers {
    azapi = { source = "Azure/azapi", version = "~> 2.13" }
  }
}

variable "foundation" {
  type = object({
    subscription_id = string
    location        = string
    foundry_id      = string
  })
}

variable "models" {
  type = map(object({
    name = string, version = string, sku = string, capacity = number
  }))
}

variable "workload_name" {
  type    = string
  default = "test-only"
}

resource "terraform_data" "boundary" {}
