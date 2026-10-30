module "exercise_group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "0.4.0"
  name             = "rg-${var.workload_name}-extensions-${local.runtime_suffix}"
  location         = var.foundation.location
  tags             = merge(var.foundation.tags, { purpose = "participant-extension-apps" })
  enable_telemetry = false
  depends_on       = [terraform_data.boundary]
}

locals {
  exercise_permissions = {
    apps = {
      scope = module.exercise_group.resource_id
      actions = [
        "Microsoft.Resources/subscriptions/resourceGroups/read",
        "Microsoft.Resources/deployments/*",
        "Microsoft.App/containerApps/*",
        "Microsoft.ManagedIdentity/userAssignedIdentities/read",
        "Microsoft.ManagedIdentity/userAssignedIdentities/write",
        "Microsoft.ManagedIdentity/userAssignedIdentities/delete",
        "Microsoft.ManagedIdentity/userAssignedIdentities/assign/action",
      ]
    }
    environment = {
      scope = var.foundation.container_environment_id
      actions = [
        "Microsoft.App/managedEnvironments/read",
        "Microsoft.App/managedEnvironments/join/action",
      ]
    }
    builds = {
      scope = var.foundation.registry_id
      actions = [
        "Microsoft.ContainerRegistry/registries/read",
        "Microsoft.ContainerRegistry/registries/listBuildSourceUploadUrl/action",
        "Microsoft.ContainerRegistry/registries/scheduleRun/action",
        "Microsoft.ContainerRegistry/registries/runs/read",
        "Microsoft.ContainerRegistry/registries/runs/listLogSasUrl/action",
      ]
    }
  }
  exercise_assignments = {
    for pair in setproduct(keys(var.participant_members), keys(local.exercise_permissions)) :
    "${pair[0]}/${pair[1]}" => { principal = pair[0], permission = pair[1] }
  }
}

# Shared B2 apps are intentional; the trusted backend/toolkit group and identities
# remain outside these grants. No participant gets role-assignment write access.
resource "azurerm_role_definition" "exercise" {
  for_each           = local.exercise_permissions
  role_definition_id = uuidv5("url", "${local.workload_key}/extension-author/${each.key}")
  name               = "Workshop ${var.workload_name} ${each.key} author ${local.runtime_suffix}"
  scope              = "/subscriptions/${var.foundation.subscription_id}"
  description        = "Shared workshop extension authoring; teams can change each other's extension apps, not the trusted backend."
  assignable_scopes  = [each.key == "apps" ? module.exercise_group.resource_id : var.foundation.resource_group_id]
  permissions { actions = each.value.actions }
}

resource "azurerm_role_assignment" "exercise" {
  for_each           = local.exercise_assignments
  scope              = local.exercise_permissions[each.value.permission].scope
  role_definition_id = azurerm_role_definition.exercise[each.value.permission].role_definition_resource_id
  principal_id       = each.value.principal
  principal_type     = "User"
}

resource "azurerm_role_assignment" "exercise_push" {
  for_each             = var.participant_members
  scope                = var.foundation.registry_id
  role_definition_name = "AcrPush"
  principal_id         = each.key
  principal_type       = "User"
}

resource "azurerm_user_assigned_identity" "exercise_pull" {
  name                = "id-${var.workload_name}-extensions-${local.runtime_suffix}"
  location            = var.foundation.location
  resource_group_name = module.exercise_group.name
  tags                = var.foundation.tags
}

resource "azurerm_role_assignment" "exercise_pull" {
  scope                = var.foundation.registry_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.exercise_pull.principal_id
  principal_type       = "ServicePrincipal"
}

output "extension_authoring" {
  value = {
    resource_group_id              = module.exercise_group.resource_id
    environment_id                 = var.foundation.container_environment_id
    registry_id                    = var.foundation.registry_id
    image_pull_identity_id         = azurerm_user_assigned_identity.exercise_pull.id
    image_pull_identity_client_id  = azurerm_user_assigned_identity.exercise_pull.client_id
    cross_team_authoring           = true
    trusted_runtime_group_excluded = module.runtime_group.resource_id
    role_ids                       = { for name, role in azurerm_role_definition.exercise : name => role.role_definition_resource_id }
  }

}

resource "azurerm_role_assignment" "spending_protection" {
  for_each = {
    runtime    = module.runtime_group.resource_id
    extensions = module.exercise_group.resource_id
  }
  scope              = each.value
  role_definition_id = var.foundation.protection_cutoff_role_id
  principal_id       = var.foundation.protection_principal_id
  principal_type     = "ServicePrincipal"
}
