terraform {
  required_providers {
    azurerm = { source = "hashicorp/azurerm", version = "~> 4.81" }
    azuread = { source = "hashicorp/azuread", version = "~> 3.10" }
  }
}

variable "subscription_id" { type = string }
variable "teams" { type = map(set(string)) }
variable "expected_participant_count" { type = number }
variable "project_ids" { type = map(string) }
variable "resource_group_id" { type = string }
variable "gateway_id" { type = string }
variable "catalog_id" { type = string }
variable "workspace_id" { type = string }
variable "applicationinsights_id" { type = string }
variable "search_id" { type = string }

locals {
  members = flatten([
    for team, references in var.teams : [
      for reference in references : { team = team, reference = lower(trimspace(reference)) }
    ]
  ])
  references = toset([for member in local.members : member.reference])
  members_by_reference = {
    for member in local.members : member.reference => member...
  }
  assignments = {
    for reference, members in local.members_by_reference : reference => members[0]
  }
}

data "azuread_user" "member" {
  for_each = local.references
  object_id = can(regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", each.key
  )) ? each.key : null
  user_principal_name = can(regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", each.key
  )) ? null : each.key
}

resource "terraform_data" "roster" {
  lifecycle {
    precondition {
      condition = (
        var.expected_participant_count > 0 &&
        length(local.members) == var.expected_participant_count &&
        length(local.references) == length(local.members) &&
        alltrue([for team, members in var.teams : contains(keys(var.project_ids), team) && length(members) > 0])
      )
      error_message = "Supply the complete roster, with every member in exactly one declared team and no empty teams."
    }
    precondition {
      condition = (
        length(distinct([for user in data.azuread_user.member : user.object_id])) == length(local.members) &&
        alltrue([for user in data.azuread_user.member : user.account_enabled])
      )
      error_message = "UPN/object-ID aliases must resolve to distinct enabled tenant users."
    }
  }
}

locals {
  role_requests = merge({}, [
    for key, member in local.assignments : merge({
      "${key}/reader" = {
        member = member.reference, scope = var.resource_group_id
        role   = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
      }
      "${key}/foundry" = {
        member = member.reference, scope = var.project_ids[member.team]
        role   = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
      }
      "${key}/gateway-author" = {
        member = member.reference, scope = var.gateway_id
        role   = azurerm_role_definition.author["gateway"].role_definition_id
      }
      "${key}/catalog-author" = {
        member = member.reference, scope = var.catalog_id
        role   = azurerm_role_definition.author["catalog"].role_definition_id
      }
      "${key}/trace-reader" = {
        member = member.reference, scope = var.workspace_id
        role   = "73c42c96-874c-492b-b04d-ab87d138a893"
      }
      "${key}/telemetry-publisher" = {
        member = member.reference, scope = var.applicationinsights_id
        role   = "3913510d-42f4-4e42-8a64-420c390055eb"
      }
      }, var.search_id == null ? {} : {
      "${key}/search-author" = {
        member = member.reference, scope = var.search_id
        role   = azurerm_role_definition.author["search"].role_definition_id
      }
      "${key}/search-data-author" = {
        member = member.reference, scope = var.search_id
        role   = "8ebe5a00-799e-43f5-93ac-243d3dce84a7"
      }
    })
  ]...)
}

resource "azurerm_role_assignment" "member" {
  for_each           = local.role_requests
  scope              = each.value.scope
  role_definition_id = "/subscriptions/${var.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role}"
  principal_id       = data.azuread_user.member[each.value.member].object_id
  principal_type     = "User"
  depends_on         = [terraform_data.roster]
}

output "members" {
  value = {
    for key, member in local.assignments : data.azuread_user.member[member.reference].object_id => {
      team = member.team
      azure_assignments = [
        for role_key, request in local.role_requests : {
          id      = azurerm_role_assignment.member[role_key].id
          scope   = request.scope
          role_id = request.role
        } if request.member == member.reference
      ]
    }
  }
}
