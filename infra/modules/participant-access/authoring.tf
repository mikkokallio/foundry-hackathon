# Shared workshop authoring is intentional: participants can change other teams'
# child resources and synthetic Search data. This is not a team-isolation boundary.
locals {
  authoring = merge({
    gateway = {
      action = "Microsoft.ApiManagement/service/*"
      not_actions = [
        "Microsoft.ApiManagement/service/write",
        "Microsoft.ApiManagement/service/delete",
      ]
    }
    catalog = {
      action = "Microsoft.ApiCenter/services/*"
      not_actions = [
        "Microsoft.ApiCenter/services/write",
        "Microsoft.ApiCenter/services/delete",
        "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions/updateAnalysisState/action",
      ]
    }
    }, var.search_id == null ? {} : {
    search = {
      action = "Microsoft.Search/searchServices/*"
      not_actions = [
        "Microsoft.Search/searchServices/write",
        "Microsoft.Search/searchServices/delete",
        "Microsoft.Search/searchServices/listAdminKeys/action",
        "Microsoft.Search/searchServices/listQueryKeys/action",
        "Microsoft.Search/searchServices/regenerateAdminKey/action",
      ]
    }
  })
}

resource "azurerm_role_definition" "author" {
  for_each           = local.authoring
  role_definition_id = uuidv5("url", "${var.resource_group_id}/workshop-author/${each.key}")
  name               = "AI workshop ${each.key} author ${substr(sha256(var.resource_group_id), 0, 8)}"
  scope              = "/subscriptions/${var.subscription_id}"
  description        = "Shared lab authoring: teams can edit each other's child resources. Excludes foundation service deletion/resizing."
  assignable_scopes  = [var.resource_group_id]
  permissions {
    actions     = [each.value.action]
    not_actions = each.value.not_actions
  }
  depends_on = [terraform_data.roster]
}

output "authoring_permissions" {
  value = {
    for service, definition in azurerm_role_definition.author : service => {
      role_id              = definition.role_definition_id
      assignable_scopes    = definition.assignable_scopes
      permissions          = definition.permissions
      cross_team_authoring = true
    }
  }
}
