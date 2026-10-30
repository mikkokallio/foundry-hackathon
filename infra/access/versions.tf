terraform {
  backend "local" {}
  required_version = ">= 1.9, < 2.0"
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.10" }
  }
}

provider "azurerm" {
  features {}
  subscription_id                 = var.foundation.subscription_id
  tenant_id                       = var.foundation.tenant_id
  resource_provider_registrations = "none"
}
provider "azuread" {
  tenant_id = var.foundation.tenant_id
}

variable "foundation" {
  description = "Foundation output object from the APPLIED foundation state, not the terraform output -json envelope. Retain the subscription/tenant IDs, resource IDs, projects and telemetry IDs unchanged."
  type = object({
    subscription_id        = string
    tenant_id              = string
    resource_group_id      = string
    gateway_id             = string
    catalog_id             = string
    workspace_id           = string
    applicationinsights_id = string
    search_id              = string
    projects               = map(object({ id = string }))
  })
}
variable "teams" {
  description = "HCL map of foundation team keys to existing-tenant user UPNs or object GUIDs, for example { alpha = [\"person@your-domain.tld\"] }. No invitations are created. A person must belong to exactly one team."
  type        = map(set(string))
}
variable "expected_participant_count" {
  description = "Positive integer count of distinct people in teams. Must equal the resolved roster count; use real participant identities, not repeated test accounts."
  type        = number
}

module "participants" {
  source                     = "../modules/participant-access"
  subscription_id            = var.foundation.subscription_id
  teams                      = var.teams
  expected_participant_count = var.expected_participant_count
  project_ids                = { for team, project in var.foundation.projects : team => project.id }
  resource_group_id          = var.foundation.resource_group_id
  gateway_id                 = var.foundation.gateway_id
  catalog_id                 = var.foundation.catalog_id
  workspace_id               = var.foundation.workspace_id
  applicationinsights_id     = var.foundation.applicationinsights_id
  search_id                  = var.foundation.search_id
}

output "members" {
  value = module.participants.members
}

output "authoring_permissions" {
  value = module.participants.authoring_permissions
}

output "deployment_access" {
  description = "Applied roster/context for workload grants; not effective-access acceptance."
  value = {
    contract_version  = 1
    subscription_id   = var.foundation.subscription_id
    tenant_id         = var.foundation.tenant_id
    resource_group_id = var.foundation.resource_group_id
    teams             = var.teams
    members           = module.participants.members
  }
}
