locals {
  subscription_scope = "/subscriptions/${var.foundation.subscription_id}"
  oidc_subject       = "repo:${var.github_repository}:environment:${replace(var.github_environment, ":", "%3A")}"
  tags               = merge(var.tags, { purpose = "workshop-ci-state", state_preservation = "retain-separately" })
}

resource "azurerm_resource_group" "delivery" {
  name     = "rg-delivery-${var.suffix}"
  location = var.foundation.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_account" "state" {
  name                            = "stcistate${var.suffix}"
  resource_group_name             = azurerm_resource_group.delivery.name
  location                        = azurerm_resource_group.delivery.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 30
    }
    container_delete_retention_policy {
      days = 30
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azapi_resource" "state_container" {
  type      = "Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01"
  name      = "tfstate"
  parent_id = "${azurerm_storage_account.state.id}/blobServices/default"
  body      = { properties = { publicAccess = "None" } }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_management_lock" "state" {
  name       = "preserve-ci-state"
  scope      = azurerm_storage_account.state.id
  lock_level = "CanNotDelete"
  notes      = "Remove only after reviewed state migration or explicit state retirement."
}

resource "azurerm_user_assigned_identity" "ci" {
  name                = "id-workshop-ci-${var.suffix}"
  resource_group_name = azurerm_resource_group.delivery.name
  location            = azurerm_resource_group.delivery.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "github" {
  name                      = "github-${var.suffix}"
  user_assigned_identity_id = azurerm_user_assigned_identity.ci.id
  issuer                    = "https://token.actions.githubusercontent.com"
  audience                  = ["api://AzureADTokenExchange"]
  subject                   = local.oidc_subject
}

locals {
  ci_roles = {
    foundation_plan_reader = {
      scope = local.subscription_scope
      role  = "acdd72a7-3385-48ef-bd42-f606fba81ae7"
    }
    project_evaluator = {
      scope = var.foundation.projects[var.project_name].id
      role  = "53ca6127-db72-4b80-b1b0-d745d6d5456d"
    }
    judge_inference = {
      scope = var.foundation.foundry_id
      role  = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd"
    }
    trace_reader = {
      scope = var.foundation.workspace_id
      role  = "73c42c96-874c-492b-b04d-ab87d138a893"
    }
    state_writer = {
      scope = azapi_resource.state_container.id
      role  = "ba92f5b4-2d11-453d-a403-e96b0029c9fe"
    }
  }
}

resource "azurerm_role_assignment" "ci" {
  for_each                         = local.ci_roles
  scope                            = each.value.scope
  role_definition_id               = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/${each.value.role}"
  principal_id                     = azurerm_user_assigned_identity.ci.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

resource "azurerm_role_assignment" "state_operator" {
  for_each                         = var.state_operator_object_ids
  scope                            = azapi_resource.state_container.id
  role_definition_id               = "${local.subscription_scope}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  principal_id                     = each.key
  skip_service_principal_aad_check = true
}

output "delivery" {
  description = "Real identity/backend bindings after apply, not CI acceptance. No secrets or state contents."
  value = {
    subscription_id    = var.foundation.subscription_id
    tenant_id          = var.foundation.tenant_id
    client_id          = azurerm_user_assigned_identity.ci.client_id
    principal_id       = azurerm_user_assigned_identity.ci.principal_id
    github_repository  = var.github_repository
    github_environment = var.github_environment
    oidc_subject       = local.oidc_subject
    project_id         = var.foundation.projects[var.project_name].id
    backend = {
      resource_group_name  = azurerm_resource_group.delivery.name
      storage_account_name = azurerm_storage_account.state.name
      container_name       = azapi_resource.state_container.name
      use_azuread_auth     = true
    }
    ci_infrastructure_access = "read-only subscription; no apply, role-management or Graph permission"
    judge_access             = "direct inference on all models in the selected Foundry account"
    retention                = "separate protected state group; 30-day blob/container soft delete and versioning"
  }
}
