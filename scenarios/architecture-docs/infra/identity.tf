locals {
  workload_key   = "${var.foundation.resource_group_id}/workloads/${var.workload_name}"
  runtime_suffix = substr(sha256(local.workload_key), 0, 8)
  team_roles = {
    for team in distinct([for member in var.participant_members : member.team]) :
    team => uuidv5("url", "${local.workload_key}/roles/team/${team}")
  }
  access_scope_id   = uuidv5("url", "${local.workload_key}/scopes/access")
  backend_role_id   = uuidv5("url", "${local.workload_key}/roles/gateway-backend")
  librarian_role_id = uuidv5("url", "${local.workload_key}/roles/librarian")
}

resource "terraform_data" "identity_boundary" {
  lifecycle {
    precondition {
      condition = alltrue([
        for team in keys(local.team_roles) : contains(keys(var.foundation.projects), team)
      ])
      error_message = "Every resolved participant team must have its actual foundation project."
    }
    precondition {
      condition = (
        alltrue([for user in data.azuread_user.librarian : user.account_enabled]) &&
        length(distinct([for user in data.azuread_user.librarian : user.object_id])) == length(data.azuread_user.librarian)
      )
      error_message = "All explicitly selected librarians must resolve to distinct enabled tenant users."
    }
    precondition {
      condition = alltrue([
        for image in [var.runtime_images.backend, var.runtime_images.toolkit] :
        startswith(image, "${var.foundation.registry_server}/")
      ])
      error_message = "Runtime images must come from the selected foundation registry."
    }
  }
}

resource "azuread_application" "gateway" {
  display_name     = "workshop-${var.workload_name}-${local.runtime_suffix}"
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azurerm_client_config.current.object_id]
  api {
    requested_access_token_version = 2
    oauth2_permission_scope {
      admin_consent_description  = "Use this workload's authenticated workshop gateway."
      admin_consent_display_name = "Use workshop gateway"
      user_consent_description   = "Use this workload's authenticated workshop gateway."
      user_consent_display_name  = "Use workshop gateway"
      enabled                    = true
      id                         = local.access_scope_id
      type                       = "User"
      value                      = "Lab.Access"
    }
  }
  dynamic "app_role" {
    for_each = local.team_roles
    content {
      allowed_member_types = ["Application", "User"]
      description          = "Use this workload's gateway as ${app_role.key}"
      display_name         = "Workshop ${app_role.key}"
      enabled              = true
      id                   = app_role.value
      value                = "Team.${app_role.key}"
    }
  }
  app_role {
    allowed_member_types = ["Application"]
    description          = "Authenticate the gateway to this workload's backend"
    display_name         = "Gateway backend"
    enabled              = true
    id                   = local.backend_role_id
    value                = "Gateway.Backend"
  }
  app_role {
    allowed_member_types = ["User"]
    description          = "Review and publish this workload's proposals as a human"
    display_name         = "Human librarian"
    enabled              = true
    id                   = local.librarian_role_id
    value                = "Librarian"
  }
  lifecycle {
    ignore_changes = [identifier_uris]
  }
  depends_on = [terraform_data.boundary, terraform_data.identity_boundary]
}

resource "azuread_application_identifier_uri" "gateway" {
  application_id = azuread_application.gateway.id
  identifier_uri = "api://${azuread_application.gateway.client_id}"
}

resource "azuread_application_pre_authorized" "cli" {
  application_id       = azuread_application.gateway.id
  authorized_client_id = "04b07795-8ddb-461a-bbee-02f9e1bf7b46"
  permission_ids       = [local.access_scope_id]
}

resource "azuread_service_principal" "gateway" {
  client_id                    = azuread_application.gateway.client_id
  app_role_assignment_required = true
  owners                       = [data.azurerm_client_config.current.object_id]
}

resource "azuread_app_role_assignment" "participant" {
  for_each            = var.participant_members
  app_role_id         = local.team_roles[each.value.team]
  principal_object_id = each.key
  resource_object_id  = azuread_service_principal.gateway.object_id
}

resource "azuread_app_role_assignment" "project" {
  for_each            = local.team_roles
  app_role_id         = each.value
  principal_object_id = var.foundation.projects[each.key].principal_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}

data "azuread_user" "librarian" {
  for_each = toset([for reference in var.librarians : lower(trimspace(reference))])
  object_id = can(regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", each.key
  )) ? each.key : null
  user_principal_name = can(regex(
    "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", each.key
  )) ? null : each.key
}

resource "azuread_app_role_assignment" "librarian" {
  for_each            = data.azuread_user.librarian
  app_role_id         = local.librarian_role_id
  principal_object_id = each.value.object_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}

resource "azuread_app_role_assignment" "gateway_backend" {
  app_role_id         = local.backend_role_id
  principal_object_id = var.foundation.gateway_principal_id
  resource_object_id  = azuread_service_principal.gateway.object_id
}

output "gateway_identity" {
  value = {
    client_id = azuread_application.gateway.client_id
    audience  = azuread_application_identifier_uri.gateway.identifier_uri
    scope     = "${azuread_application_identifier_uri.gateway.identifier_uri}/Lab.Access"
    roles     = merge(local.team_roles, { Librarian = local.librarian_role_id })
  }
}
