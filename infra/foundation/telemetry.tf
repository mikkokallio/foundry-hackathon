locals {
  project_telemetry_metadata = {
    ApiType                             = "Azure"
    ResourceId                          = module.insights.resource_id
    ApplicationInsightsConnectionString = module.insights.connection_string
  }
}

resource "azapi_resource" "gateway_logger" {
  type      = "Microsoft.ApiManagement/service/loggers@2024-05-01"
  name      = "platform-insights"
  parent_id = module.gateway.resource_id
  body = {
    properties = {
      loggerType  = "applicationInsights"
      resourceId  = module.insights.resource_id
      description = "Entra-authenticated gateway telemetry without request bodies or authorization headers"
    }
  }
  sensitive_body = {
    properties = {
      credentials = {
        connectionString = module.insights.connection_string
        identityClientId = "SystemAssigned"
      }
    }
  }
  sensitive_body_version = {
    "properties.credentials" = nonsensitive(sha256(jsonencode({
      connectionString = module.insights.connection_string
      identityClientId = "SystemAssigned"
    })))
  }
  depends_on = [azurerm_role_assignment.gateway_telemetry]
}

resource "azapi_resource" "project_telemetry" {
  for_each  = azapi_resource.project
  type      = "Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview"
  name      = "platform-insights-${each.key}"
  parent_id = each.value.id
  # Foundry supports ProjectManagedIdentity for trace ingestion; the ARM enum lags.
  schema_validation_enabled = false
  body = {
    properties = {
      category      = "AppInsights"
      target        = module.insights.resource_id
      authType      = "ProjectManagedIdentity"
      isSharedToAll = false
    }
  }
  sensitive_body = {
    properties = { metadata = local.project_telemetry_metadata }
  }
  sensitive_body_version = {
    "properties.metadata" = nonsensitive(sha256(jsonencode(local.project_telemetry_metadata)))
  }
  depends_on = [azurerm_role_assignment.project_telemetry]
}
