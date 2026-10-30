output "foundation" {
  description = "Non-secret, versioned workload input; this is not a readiness receipt."
  depends_on = [
    azurerm_role_assignment.project_model_invocation,
    azurerm_role_assignment.gateway_model_invocation,
    azurerm_role_assignment.search_embedding_invocation,
    azurerm_role_assignment.project_search_query,
    azapi_resource.gateway_logger,
    azapi_resource.project_telemetry,
    azurerm_automation_job_schedule.protection,
    azurerm_automation_job_schedule.expiry,
  ]
  value = {
    contract_version    = 1
    subscription_id     = var.subscription_id
    tenant_id           = var.tenant_id
    location            = var.location
    resource_group_id   = module.group.resource_id
    resource_group_name = module.group.name
    foundry_id          = module.foundry.resource_id
    foundry_name        = "aif-${local.name}"
    foundry_endpoint    = "https://aif-${local.name}.services.ai.azure.com"
    projects = {
      for name, project in azapi_resource.project : name => {
        id           = project.id
        principal_id = project.output.identity.principalId
        endpoint     = "https://aif-${local.name}.services.ai.azure.com/api/projects/${name}"
      }
    }
    gateway_id                = module.gateway.resource_id
    gateway_name              = "apim-${local.name}"
    gateway_url               = module.gateway.apim_gateway_url
    gateway_principal_id      = nonsensitive(module.gateway.resource.identity[0].principal_id)
    gateway_logger_id         = azapi_resource.gateway_logger.id
    catalog_id                = azapi_resource.catalog.id
    storage_id                = module.storage.resource_id
    storage_name              = "stailab${var.suffix}"
    registry_id               = module.registry.resource_id
    registry_server           = module.registry.login_server
    container_environment_id  = module.containers.resource_id
    vault_id                  = module.vault.resource_id
    search_id                 = var.enable_search ? module.search[0].resource_id : null
    search_endpoint           = var.enable_search ? "https://srch-${local.name}.search.windows.net" : null
    search_principal_id       = var.enable_search ? module.search[0].resource.identity[0].principal_id : null
    workspace_id              = module.logs.resource_id
    applicationinsights_id    = module.insights.resource_id
    protection_principal_id   = module.protection.system_assigned_mi_principal_id
    protection_cutoff_role_id = azurerm_role_definition.protection_cutoff.role_definition_resource_id
    protection_account_id     = module.protection.resource_id
    protection_group_id       = module.protection_group.resource_id
    tags                      = local.tags
  }
}
