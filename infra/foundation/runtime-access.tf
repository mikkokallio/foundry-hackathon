resource "azurerm_role_assignment" "project_model_invocation" {
  for_each             = azapi_resource.project
  scope                = module.foundry.resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.value.output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "gateway_model_invocation" {
  scope                = module.foundry.resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.gateway.resource.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "gateway_telemetry" {
  scope                = module.insights.resource_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = module.gateway.resource.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "project_telemetry" {
  for_each             = azapi_resource.project
  scope                = module.insights.resource_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = each.value.output.identity.principalId
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search_embedding_invocation" {
  count                = var.enable_search ? 1 : 0
  scope                = module.foundry.resource_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.search[0].resource.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "project_search_query" {
  for_each             = var.enable_search ? azapi_resource.project : {}
  scope                = module.search[0].resource_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = each.value.output.identity.principalId
  principal_type       = "ServicePrincipal"
}
