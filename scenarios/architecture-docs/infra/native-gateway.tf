locals {
  gateway_model_deployments = {
    for alias in ["chat-small", "chat-medium", "judge"] : alias => azapi_resource.model[alias].name
  }
  native_gateway_connection_body = {
    properties = {
      category      = "ApiManagement"
      target        = "${var.foundation.gateway_url}/${var.workload_name}/models"
      authType      = "ProjectManagedIdentity"
      audience      = azuread_application_identifier_uri.gateway.identifier_uri
      isSharedToAll = false
      metadata = {
        deploymentInPath    = "false"
        inferenceAPIVersion = "2024-10-21"
        models = jsonencode([
          for alias in sort(keys(local.gateway_model_deployments)) : {
            name = alias
            properties = {
              model = {
                name    = var.models[alias].name
                version = var.models[alias].version
                format  = "OpenAI"
              }
            }
          }
        ])
      }
    }
  }
}

resource "azapi_resource" "native_gateway_connection" {
  for_each = local.team_roles
  # AzAPI 2.13's embedded enum omits documented ProjectManagedIdentity.
  # https://github.com/microsoft-foundry/foundry-samples/blob/main/infrastructure/infrastructure-setup-bicep/01-connections/apim/modules/apim-connection-common.bicep
  # Disable only local schema checking; ARM errors still fail normal CRUD.
  type                      = "Microsoft.CognitiveServices/accounts/projects/connections@2026-03-01"
  schema_validation_enabled = false
  name                      = "${var.workload_name}-${each.key}-models"
  parent_id                 = var.foundation.projects[each.key].id
  body                      = local.native_gateway_connection_body
  depends_on = [
    azuread_app_role_assignment.project,
    azurerm_api_management_api_policy.models,
    azurerm_api_management_api_operation.chat,
  ]
}

output "native_gateway_models" {
  description = "Explicit PromptAgentDefinition.model values. This does not enforce universal routing or prove live acceptance."
  value = {
    projects = {
      for team, connection in azapi_resource.native_gateway_connection : team => {
        connection_name = connection.name
        connection_id   = connection.id
        agent_model_ids = {
          for alias in keys(local.gateway_model_deployments) : alias => "${connection.name}/${alias}"
        }
      }
    }
    project_connection_ids = { for team, connection in azapi_resource.native_gateway_connection : team => connection.id }
    live_accepted          = false
    universal_enforcement  = false
  }
}
