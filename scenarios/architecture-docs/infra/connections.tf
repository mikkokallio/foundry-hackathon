locals {
  remote_tools = {
    docs    = "${var.foundation.gateway_url}/${local.gateway_paths.mcp}/mcp"
    toolkit = "${var.foundation.gateway_url}/${local.gateway_paths.toolkit}/mcp"
  }
  project_tools = {
    for pair in setproduct(keys(local.team_roles), keys(local.remote_tools)) :
    "${pair[0]}/${pair[1]}" => { team = pair[0], tool = pair[1] }
  }
}

resource "azapi_resource" "tool_connection" {
  for_each                  = local.project_tools
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name                      = "${var.workload_name}-${each.value.team}-${each.value.tool}"
  parent_id                 = var.foundation.projects[each.value.team].id
  schema_validation_enabled = false
  body = {
    properties = {
      authType      = "ProjectManagedIdentity"
      category      = "RemoteTool"
      target        = local.remote_tools[each.value.tool]
      audience      = azuread_application.gateway.client_id
      isSharedToAll = false
    }
  }
  depends_on = [
    azuread_app_role_assignment.project,
    azurerm_api_management_api_policy.docs_mcp,
    azapi_resource.docs_tool,
    azurerm_api_management_api_policy.toolkit,
  ]
}
