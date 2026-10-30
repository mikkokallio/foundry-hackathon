module "runtime_group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "0.4.0"
  name             = "rg-${var.workload_name}-${local.runtime_suffix}"
  location         = var.foundation.location
  tags             = var.foundation.tags
  enable_telemetry = false
  depends_on       = [terraform_data.boundary, terraform_data.identity_boundary]
}

locals {
  runtime_apps = {
    backend = { image = var.runtime_images.backend, port = 8000 }
    toolkit = { image = var.runtime_images.toolkit, port = 8080 }
  }
}

resource "azurerm_user_assigned_identity" "runtime" {
  for_each            = local.runtime_apps
  name                = "id-${var.workload_name}-${each.key}-${local.runtime_suffix}"
  location            = var.foundation.location
  resource_group_name = module.runtime_group.name
  tags                = var.foundation.tags
}

resource "azurerm_role_assignment" "runtime_pull" {
  for_each           = local.runtime_apps
  scope              = var.foundation.registry_id
  role_definition_id = "/subscriptions/${var.foundation.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/7f951dda-4ed3-4680-a7ca-43fe172d538d"
  principal_id       = azurerm_user_assigned_identity.runtime[each.key].principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_assignment" "backend_documents" {
  scope              = "${var.foundation.storage_id}/blobServices/default/containers/${azurerm_storage_container.documents.name}"
  role_definition_id = "/subscriptions/${var.foundation.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe"
  principal_id       = azurerm_user_assigned_identity.runtime["backend"].principal_id
  principal_type     = "ServicePrincipal"
}

module "runtime_app" {
  for_each                              = local.runtime_apps
  source                                = "Azure/avm-res-app-containerapp/azurerm"
  version                               = "0.9.0"
  name                                  = "ca-${substr(var.workload_name, 0, 12)}-${each.key}-${local.runtime_suffix}"
  resource_group_name                   = module.runtime_group.name
  location                              = var.foundation.location
  container_app_environment_resource_id = var.foundation.container_environment_id
  managed_identities                    = { user_assigned_resource_ids = [azurerm_user_assigned_identity.runtime[each.key].id] }
  registries = [{
    server   = var.foundation.registry_server
    identity = azurerm_user_assigned_identity.runtime[each.key].id
  }]
  ingress = {
    external_enabled = true
    target_port      = each.value.port
    transport        = "http"
    traffic_weight   = [{ latest_revision = true, percentage = 100 }]
  }
  template = {
    min_replicas = 1
    max_replicas = 1
    containers = [{
      name   = each.key
      image  = each.value.image
      cpu    = 0.25
      memory = "0.5Gi"
      env = [
        { name = "ORGANIZATION_NAME", value = var.organization_name },
        { name = "STORAGE_MODE", value = "blob" },
        { name = "STORAGE_ACCOUNT_URL", value = "https://${var.foundation.storage_name}.blob.core.windows.net" },
        { name = "STORAGE_CONTAINER", value = azurerm_storage_container.documents.name },
        { name = "SEED_ON_START", value = "false" },
        { name = "AZURE_CLIENT_ID", value = azurerm_user_assigned_identity.runtime[each.key].client_id },
        { name = "AUTH_MODE", value = "entra" },
        { name = "AZURE_TENANT_ID", value = var.foundation.tenant_id },
        { name = "BACKEND_AUDIENCE", value = azuread_application.gateway.client_id },
        { name = "GATEWAY_PRINCIPAL_ID", value = var.foundation.gateway_principal_id },
        { name = "REFERENCE_DATE", value = var.reference_date }
      ]
      readiness_probes = [{ transport = "HTTP", port = each.value.port, path = "/health" }]
      liveness_probes  = [{ transport = "HTTP", port = each.value.port, path = "/health", initial_delay = 10 }]
    }]
  }
  tags             = var.foundation.tags
  enable_telemetry = false
  depends_on       = [azurerm_role_assignment.runtime_pull, azurerm_role_assignment.backend_documents, azurerm_storage_blob.document_seed]
}

output "runtime" {
  description = "Application addresses and exact artifacts, not runtime acceptance."
  value = {
    resource_group_id = module.runtime_group.resource_id
    apps = {
      for name, app in module.runtime_app : name => {
        url          = app.fqdn_url
        image        = local.runtime_apps[name].image
        identity_id  = azurerm_user_assigned_identity.runtime[name].id
        principal_id = azurerm_user_assigned_identity.runtime[name].principal_id
      }
    }
  }
}
