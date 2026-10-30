resource "azurerm_cognitive_account" "content_safety" {
  name                          = "${var.workload_name}-safety-${local.runtime_suffix}"
  resource_group_name           = module.runtime_group.name
  location                      = var.foundation.location
  kind                          = "ContentSafety"
  sku_name                      = "S0"
  custom_subdomain_name         = "${var.workload_name}-safety-${local.runtime_suffix}"
  local_auth_enabled            = false
  public_network_access_enabled = true
  network_acls {
    default_action = "Allow"
  }
  tags = var.foundation.tags
}

resource "azurerm_role_assignment" "gateway_content_safety" {
  scope                = azurerm_cognitive_account.content_safety.id
  role_definition_name = "Cognitive Services User"
  principal_id         = var.foundation.gateway_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azapi_resource" "content_safety_backend" {
  type      = "Microsoft.ApiManagement/service/backends@2024-06-01-preview"
  name      = "${var.workload_name}-content-safety"
  parent_id = var.foundation.gateway_id
  # This credential is used by Microsoft's AI-Gateway content-safety sample,
  # but is still absent from the published backend schema.
  schema_validation_enabled = false
  body = {
    properties = {
      description = "Content Safety for the workload's B4 policy exercise"
      protocol    = "http"
      url         = "https://${var.workload_name}-safety-${local.runtime_suffix}.cognitiveservices.azure.com"
      credentials = { managedIdentity = { resource = "https://cognitiveservices.azure.com" } }
    }
  }
  depends_on = [azurerm_role_assignment.gateway_content_safety]
}

resource "azapi_resource" "exercise_model_backend" {
  for_each  = toset(["chat-small", "chat-medium"])
  type      = "Microsoft.ApiManagement/service/backends@2025-03-01-preview"
  name      = "${var.workload_name}-${each.key}"
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      type        = "Single"
      protocol    = "http"
      description = "B4 deployment backend; shares the workload Foundry account and region"
      url         = "https://${var.foundation.foundry_name}.openai.azure.com/openai/deployments/${azapi_resource.model[each.key].name}"
      circuitBreaker = {
        rules = [{
          name             = "throttling-or-unavailable"
          acceptRetryAfter = true
          tripDuration     = "PT30S"
          failureCondition = {
            count            = 1
            interval         = "PT30S"
            statusCodeRanges = [{ min = 429, max = 429 }, { min = 500, max = 599 }]
          }
        }]
      }
    }
  }
}

resource "azapi_resource" "exercise_model_pool" {
  type      = "Microsoft.ApiManagement/service/backends@2025-03-01-preview"
  name      = "${var.workload_name}-model-pool"
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      type        = "Pool"
      description = "B4 deployment balancing; not account-level or regional failover"
      pool = {
        services = [
          for backend in azapi_resource.exercise_model_backend :
          { id = backend.id, priority = 1, weight = 1 }
        ]
      }
    }
  }
}

output "gateway_exercises" {
  value = {
    model_backend_ids                = { for name, backend in azapi_resource.exercise_model_backend : name => backend.id }
    pool_backend_id                  = azapi_resource.exercise_model_pool.id
    content_safety_id                = azurerm_cognitive_account.content_safety.id
    content_safety_backend           = azapi_resource.content_safety_backend.name
    regional_failover                = false
    semantic_cache_enabled           = var.semantic_cache_enabled
    semantic_cache_policy_enabled    = false
    semantic_cache_embeddings_auth   = var.semantic_cache_enabled ? "system-assigned" : null
    semantic_cache_id                = var.semantic_cache_enabled ? module.semantic_cache[0].resource_id : null
    semantic_cache_connection        = var.semantic_cache_enabled ? azapi_resource.semantic_cache_connection[0].id : null
    semantic_cache_embedding_backend = var.semantic_cache_enabled ? azapi_resource.cache_embedding_backend[0].name : null
    live_accepted                    = false
  }
}
