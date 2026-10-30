locals {
  docs_source_spec = jsondecode(file("${path.module}/../openapi.json"))
  docs_spec = merge(local.docs_source_spec, {
    info = merge(local.docs_source_spec.info, {
      title = "${var.organization_name} Architecture Docs API"
    })
  })
  gateway_paths = {
    docs    = "${var.workload_name}/docs-api"
    mcp     = "${var.workload_name}/docs-mcp"
    toolkit = "${var.workload_name}/toolkit"
  }
  docs_tools = {
    for operation in flatten([
      for path, methods in local.docs_spec.paths : [
        for method, operation in methods : operation
        if contains(["get", "post"], method) && !contains(["health", "publishProposal"], operation.operationId)
      ]
    ]) : operation.operationId => operation
  }
  gateway_auth = templatefile("${path.module}/policies/identity.xml", {
    tenant_id  = var.foundation.tenant_id
    client_id  = azuread_application.gateway.client_id
    team_roles = join(", ", [for team in sort(keys(local.team_roles)) : "&quot;Team.${team}&quot;"])
  })
}

resource "azurerm_api_management_api" "docs" {
  name                  = "${var.workload_name}-docs-api"
  resource_group_name   = var.foundation.resource_group_name
  api_management_name   = var.foundation.gateway_name
  revision              = "1"
  display_name          = "${var.organization_name} architecture documentation"
  path                  = local.gateway_paths.docs
  protocols             = ["https"]
  service_url           = module.runtime_app["backend"].fqdn_url
  subscription_required = false
  import {
    content_format = "openapi+json"
    content_value  = jsonencode(local.docs_spec)
  }
}

resource "azurerm_api_management_api_policy" "docs" {
  api_name            = azurerm_api_management_api.docs.name
  api_management_name = var.foundation.gateway_name
  resource_group_name = var.foundation.resource_group_name
  xml_content = templatefile("${path.module}/policies/backend.xml", {
    auth     = local.gateway_auth
    audience = azuread_application_identifier_uri.gateway.identifier_uri
  })
  depends_on = [azuread_app_role_assignment.gateway_backend]
}

resource "azapi_resource" "docs_mcp" {
  type      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name      = "${var.workload_name}-docs-mcp"
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      type                 = "mcp"
      displayName          = "${var.organization_name} documentation MCP"
      path                 = local.gateway_paths.mcp
      protocols            = ["https"]
      subscriptionRequired = false
      mcpProperties        = { transportType = "streamable" }
    }
  }
}

resource "azapi_resource" "docs_tool" {
  for_each  = local.docs_tools
  type      = "Microsoft.ApiManagement/service/apis/tools@2025-09-01-preview"
  name      = each.key
  parent_id = azapi_resource.docs_mcp.id
  body = {
    properties = {
      displayName = each.key
      description = substr(each.value.description, 0, 1000)
      operationId = "${replace(azurerm_api_management_api.docs.id, ";rev=1", "")}/operations/${each.key}"
    }
  }
  depends_on = [azurerm_api_management_api_policy.docs]
}

resource "azurerm_api_management_api_policy" "docs_mcp" {
  api_name            = azapi_resource.docs_mcp.name
  api_management_name = var.foundation.gateway_name
  resource_group_name = var.foundation.resource_group_name
  xml_content = templatefile("${path.module}/policies/docs-mcp.xml", {
    auth           = local.gateway_auth
    query_encoding = file("${path.module}/policies/mcp-query-encoding.xml")
    json_body = templatefile("${path.module}/policies/mcp-json-body.xml", {
      docs_path = local.gateway_paths.docs
    })
  })
}

resource "azapi_resource" "toolkit_backend" {
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "${var.workload_name}-toolkit-mcp"
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      type     = "Single"
      protocol = "http"
      url      = "${module.runtime_app["toolkit"].fqdn_url}/mcp"
      tls = {
        validateCertificateChain = true
        validateCertificateName  = true
      }
    }
  }
}

resource "azapi_resource" "toolkit_mcp" {
  type      = "Microsoft.ApiManagement/service/apis@2025-09-01-preview"
  name      = "${var.workload_name}-toolkit"
  parent_id = var.foundation.gateway_id
  # External MCP proxy backendId is supported by the live API but absent from its published schema.
  schema_validation_enabled = false
  body = {
    properties = {
      type                 = "mcp"
      displayName          = "${var.organization_name} drafting toolkit"
      path                 = "${local.gateway_paths.toolkit}/mcp"
      protocols            = ["https"]
      subscriptionRequired = false
      backendId            = azapi_resource.toolkit_backend.name
      mcpProperties        = { transportType = "streamable" }
    }
  }
}

resource "azurerm_api_management_api_policy" "toolkit" {
  api_name            = azapi_resource.toolkit_mcp.name
  api_management_name = var.foundation.gateway_name
  resource_group_name = var.foundation.resource_group_name
  xml_content = templatefile("${path.module}/policies/backend.xml", {
    auth     = local.gateway_auth
    audience = azuread_application_identifier_uri.gateway.identifier_uri
  })
  depends_on = [azuread_app_role_assignment.gateway_backend]
}

resource "azurerm_api_management_api" "models" {
  for_each              = toset(["models", "models-tight"])
  name                  = "${var.workload_name}-${each.key}"
  resource_group_name   = var.foundation.resource_group_name
  api_management_name   = var.foundation.gateway_name
  revision              = "1"
  display_name          = "${var.workload_name} ${each.key}"
  path                  = "${var.workload_name}/${each.key}"
  protocols             = ["https"]
  subscription_required = false
  service_url           = "https://${var.foundation.foundry_name}.openai.azure.com"
}

resource "azurerm_api_management_api_operation" "chat" {
  for_each            = azurerm_api_management_api.models
  operation_id        = "chat-completions"
  api_name            = each.value.name
  api_management_name = var.foundation.gateway_name
  resource_group_name = var.foundation.resource_group_name
  display_name        = "Chat completions through the AI gateway"
  method              = "POST"
  url_template        = "/chat/completions"
}

resource "azurerm_api_management_api_policy" "models" {
  for_each            = azurerm_api_management_api.models
  api_name            = each.value.name
  api_management_name = var.foundation.gateway_name
  resource_group_name = var.foundation.resource_group_name
  xml_content = templatefile("${path.module}/policies/models.xml", {
    auth          = local.gateway_auth
    deployments   = local.gateway_model_deployments
    request_limit = each.key == "models-tight" ? 2 : 30
    token_limit   = each.key == "models-tight" ? 256 : var.gateway_tokens_per_minute
  })
  depends_on = [azapi_resource.gateway_diagnostic]
}

locals {
  observed_apis = merge(
    { for key, api in azurerm_api_management_api.models : key => api.id },
    {
      docs    = azurerm_api_management_api.docs.id
      mcp     = azapi_resource.docs_mcp.id
      toolkit = azapi_resource.toolkit_mcp.id
    }
  )
}

resource "azapi_resource" "gateway_diagnostic" {
  for_each  = local.observed_apis
  type      = "Microsoft.ApiManagement/service/apis/diagnostics@2024-05-01"
  name      = "applicationinsights"
  parent_id = each.value
  body = {
    properties = {
      loggerId                = var.foundation.gateway_logger_id
      alwaysLog               = "allErrors"
      httpCorrelationProtocol = "W3C"
      logClientIp             = false
      metrics                 = true
      sampling                = { samplingType = "fixed", percentage = 100 }
      frontend = {
        request  = { body = { bytes = 0 }, headers = [] }
        response = { body = { bytes = 0 }, headers = ["Retry-After"] }
      }
      backend = {
        request  = { body = { bytes = 0 }, headers = ["X-Team-Id"] }
        response = { body = { bytes = 0 }, headers = [] }
      }
    }
  }
}

output "gateway" {
  description = "Workload-specific governed endpoints; not a runtime acceptance receipt."
  value = {
    docs_url    = "${var.foundation.gateway_url}/${local.gateway_paths.docs}"
    docs_mcp    = "${var.foundation.gateway_url}/${local.gateway_paths.mcp}/mcp"
    toolkit_mcp = "${var.foundation.gateway_url}/${local.gateway_paths.toolkit}/mcp"
    models = {
      for name, api in azurerm_api_management_api.models :
      name => "${var.foundation.gateway_url}/${api.path}/chat/completions?api-version=2024-10-21"
    }
    tool_names = sort(keys(local.docs_tools))
  }
}
