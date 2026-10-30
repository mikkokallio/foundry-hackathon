locals {
  cache_name       = "${var.workload_name}-semantic-cache"
  cache_vault_host = "${basename(var.foundation.vault_id)}.vault.azure.net"
}

module "semantic_cache" {
  count                 = var.semantic_cache_enabled ? 1 : 0
  source                = "Azure/avm-res-cache-redisenterprise/azurerm"
  version               = "0.2.0"
  name                  = "${var.workload_name}-cache-${local.runtime_suffix}"
  parent_id             = module.runtime_group.resource_id
  location              = var.foundation.location
  sku_name              = "Balanced_B0"
  high_availability     = "Disabled"
  clustering_policy     = "EnterpriseCluster"
  eviction_policy       = "NoEviction"
  minimum_tls_version   = "1.2"
  enable_non_ssl_port   = false
  public_network_access = "Enabled"
  redis_modules         = [{ name = "RediSearch", args = "" }]
  tags                  = merge(var.foundation.tags, { layer = "workload" })
  enable_telemetry      = false
}

# APIM requires Redis access keys; AVM 0.2.0 does not expose this database flag.
resource "azapi_update_resource" "semantic_cache_key_auth" {
  count       = var.semantic_cache_enabled ? 1 : 0
  type        = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id = module.semantic_cache[0].database_id
  body = {
    properties = { accessKeysAuthentication = "Enabled" }
  }
  response_export_values = ["properties.port"]
}

data "azapi_resource_action" "semantic_cache_keys" {
  count                            = var.semantic_cache_enabled ? 1 : 0
  type                             = "Microsoft.Cache/redisEnterprise/databases@2025-07-01"
  resource_id                      = module.semantic_cache[0].database_id
  action                           = "listKeys"
  sensitive_response_export_values = ["primaryKey"]
  depends_on                       = [azapi_update_resource.semantic_cache_key_auth]
}

resource "random_id" "cache_secret" {
  count       = var.semantic_cache_enabled ? 1 : 0
  byte_length = 4
}

resource "azurerm_role_assignment" "cache_secret_operator" {
  count                = var.semantic_cache_enabled ? 1 : 0
  scope                = var.foundation.vault_id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azapi_data_plane_resource" "cache_secret" {
  count     = var.semantic_cache_enabled ? 1 : 0
  type      = "Microsoft.KeyVault/vaults/secrets@7.4"
  name      = "${var.workload_name}-cache-${random_id.cache_secret[0].hex}"
  parent_id = local.cache_vault_host
  body = {
    contentType = "text/plain"
    attributes  = { enabled = true }
  }
  sensitive_body = {
    value = format("%s:%d,password=%s,ssl=True,abortConnect=False",
      module.semantic_cache[0].hostname,
      azapi_update_resource.semantic_cache_key_auth[0].output.properties.port,
    data.azapi_resource_action.semantic_cache_keys[0].sensitive_output.primaryKey)
  }
  sensitive_body_version = {
    value = nonsensitive(sha256(format("%s:%d:%s",
      module.semantic_cache[0].hostname,
      azapi_update_resource.semantic_cache_key_auth[0].output.properties.port,
    data.azapi_resource_action.semantic_cache_keys[0].sensitive_output.primaryKey)))
  }
  response_export_values = ["id"]
  retry = {
    error_message_regex  = ["Forbidden", "status.*403"]
    interval_seconds     = 5
    max_interval_seconds = 30
  }
  timeouts {
    create = "10m"
    update = "10m"
  }
  depends_on = [azurerm_role_assignment.cache_secret_operator]
}

resource "azurerm_role_assignment" "gateway_cache_secret" {
  count                = var.semantic_cache_enabled ? 1 : 0
  scope                = "${var.foundation.vault_id}/secrets/${azapi_data_plane_resource.cache_secret[0].name}"
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.foundation.gateway_principal_id
  principal_type       = "ServicePrincipal"
  depends_on           = [azapi_data_plane_resource.cache_secret]
}

resource "azapi_resource" "cache_named_value" {
  count     = var.semantic_cache_enabled ? 1 : 0
  type      = "Microsoft.ApiManagement/service/namedValues@2024-05-01"
  name      = local.cache_name
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      displayName = local.cache_name
      secret      = true
      keyVault = {
        secretIdentifier = azapi_data_plane_resource.cache_secret[0].output.id
      }
    }
  }
  retry = {
    error_message_regex  = ["Forbidden", "Access denied", "does not have.*permission", "status.*403"]
    interval_seconds     = 5
    max_interval_seconds = 30
  }
  timeouts {
    create = "10m"
    update = "10m"
  }
  depends_on = [azurerm_role_assignment.gateway_cache_secret]
}

data "azapi_resource_list" "gateway_caches" {
  count                  = var.semantic_cache_enabled ? 1 : 0
  type                   = "Microsoft.ApiManagement/service/caches@2024-05-01"
  parent_id              = var.foundation.gateway_id
  response_export_values = ["value"]
}

resource "azapi_resource" "semantic_cache_connection" {
  count     = var.semantic_cache_enabled ? 1 : 0
  type      = "Microsoft.ApiManagement/service/caches@2024-05-01"
  name      = local.cache_name
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      connectionString = "{{${azapi_resource.cache_named_value[0].name}}}"
      useFromLocation  = var.foundation.location
      resourceId       = "https://management.azure.com${module.semantic_cache[0].resource_id}"
      description      = "B4 shared gateway cache; policies must namespace and vary cached answers appropriately"
    }
  }
  lifecycle {
    precondition {
      condition = alltrue([
        for cache in data.azapi_resource_list.gateway_caches[0].output.value :
        !contains(["default", lower(var.foundation.location)], lower(cache.properties.useFromLocation)) ||
        lower(cache.id) == lower("${var.foundation.gateway_id}/caches/${local.cache_name}")
      ])
      error_message = "Another workload owns this gateway location's external cache. Review shared-cache ownership instead of replacing it."
    }
  }
}

resource "azapi_resource" "cache_embedding_backend" {
  count     = var.semantic_cache_enabled ? 1 : 0
  type      = "Microsoft.ApiManagement/service/backends@2024-05-01"
  name      = "${var.workload_name}-cache-embeddings"
  parent_id = var.foundation.gateway_id
  body = {
    properties = {
      protocol = "http"
      url      = "https://${var.foundation.foundry_name}.openai.azure.com/openai/deployments/${azapi_resource.model["embedding"].name}/embeddings"
    }
  }
  depends_on = [module.semantic_cache]
}
