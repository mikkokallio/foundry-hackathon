resource "azapi_resource" "catalog_api" {
  type      = "Microsoft.ApiCenter/services/workspaces/apis@2024-03-01"
  name      = var.workload_name
  parent_id = "${var.foundation.catalog_id}/workspaces/default"
  body = {
    properties = {
      title       = "${var.organization_name} architecture documentation"
      kind        = "rest"
      description = "Synthetic inventory, draft validation and human-approved proposals. Publication is human librarian-only."
      externalDocumentation = [
        { title = "Governed REST endpoint", url = "${var.foundation.gateway_url}/${local.gateway_paths.docs}" },
        { title = "Documentation MCP", url = local.remote_tools.docs },
        { title = "Independent drafting toolkit MCP", url = local.remote_tools.toolkit },
      ]
    }
  }
}

resource "azapi_resource" "catalog_version" {
  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions@2024-03-01"
  name      = "version-1"
  parent_id = azapi_resource.catalog_api.id
  body      = { properties = { title = "1.0", lifecycleStage = "development" } }
}

resource "azapi_resource" "catalog_definition" {
  type      = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-03-01"
  name      = "openapi"
  parent_id = azapi_resource.catalog_version.id
  body      = { properties = { title = "OpenAPI definition" } }
}

resource "azapi_resource_action" "catalog_specification" {
  type        = "Microsoft.ApiCenter/services/workspaces/apis/versions/definitions@2024-03-01"
  resource_id = azapi_resource.catalog_definition.id
  action      = "importSpecification"
  method      = "POST"
  body = {
    format        = "inline"
    value         = jsonencode(local.docs_spec)
    specification = { name = "openapi", version = local.docs_spec.openapi }
  }
}
