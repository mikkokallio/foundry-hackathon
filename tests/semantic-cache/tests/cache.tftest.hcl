mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = { object_id = "00000000-0000-0000-0000-000000000002" }
  }
}
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.Cache/redisEnterprise/test-only"
      output = { properties = { hostName = "test-only.redis.azure.net", redisVersion = "7.4" } }
    }
  }
  mock_resource "azapi_update_resource" {
    defaults = { output = { properties = { port = 10000 } } }
  }
  mock_resource "azapi_data_plane_resource" {
    defaults = { output = { id = "https://test-only.vault.azure.net/secrets/test-only/test-version" } }
  }
  mock_data "azapi_resource_action" {
    defaults = { sensitive_output = { primaryKey = "TEST-ONLY-NOT-A-CREDENTIAL" } }
  }
  mock_data "azapi_resource_list" {
    defaults = { output = { value = [] } }
  }
}

run "disabled_creates_no_cache_or_secret_grants" {
  command = plan
  assert {
    condition = (
      length(module.semantic_cache) == 0 &&
      length(azapi_resource.semantic_cache_connection) == 0 &&
      length(azapi_data_plane_resource.cache_secret) == 0 &&
      length(azurerm_role_assignment.cache_secret_operator) == 0 &&
      length(azurerm_role_assignment.gateway_cache_secret) == 0 &&
      length(data.azapi_resource_action.semantic_cache_keys) == 0
    )
    error_message = "Disabled must not create cache resources, secrets, grants or credential reads."
  }
}

run "enabled_wires_real_resource_shapes" {
  command = plan
  variables { semantic_cache_enabled = true }
  assert {
    condition = (
      length(module.semantic_cache) == 1 &&
      azapi_resource.semantic_cache_connection[0].body.properties.connectionString == "{{test-only-semantic-cache}}" &&
      azapi_resource.semantic_cache_connection[0].body.properties.useFromLocation == "swedencentral" &&
      azapi_resource.cache_named_value[0].body.properties.secret
    )
    error_message = "Connect the actual selected Redis through a secret named-value reference."
  }
  assert {
    condition = (
      azurerm_role_assignment.cache_secret_operator[0].role_definition_name == "Key Vault Secrets Officer" &&
      azurerm_role_assignment.gateway_cache_secret[0].role_definition_name == "Key Vault Secrets User" &&
      azapi_update_resource.semantic_cache_key_auth[0].body.properties.accessKeysAuthentication == "Enabled"
    )
    error_message = "The explicit APIM key-auth exception requires predeclared secret-management and ingestion grants."
  }
  assert {
    condition = (
      azapi_resource.cache_embedding_backend[0].body.properties.url == "https://test-only.openai.azure.com/openai/deployments/test-only-embedding/embeddings"
    )
    error_message = "Semantic-cache embeddings require the selected real deployment and managed-identity audience."
  }
}

run "mocked_apply_verifies_secret_scope_and_reference" {
  command = apply
  variables { semantic_cache_enabled = true }
  assert {
    condition = (
      azurerm_role_assignment.gateway_cache_secret[0].scope == "${var.foundation.vault_id}/secrets/${azapi_data_plane_resource.cache_secret[0].name}" &&
      azapi_resource.semantic_cache_connection[0].body.properties.resourceId == "https://management.azure.com${module.semantic_cache[0].resource_id}" &&
      azapi_resource.cache_named_value[0].body.properties.keyVault.secretIdentifier == "https://test-only.vault.azure.net/secrets/test-only/test-version" &&
      azapi_data_plane_resource.cache_secret[0].parent_id == "test-only.vault.azure.net"
    )
    error_message = "The gateway gets only the actual selected Key Vault secret, not vault-wide secret access or plaintext configuration."
  }
}

run "accept_own_gateway_cache_on_repeat_plan" {
  command = plan
  variables { semantic_cache_enabled = true }
  override_data {
    target = data.azapi_resource_list.gateway_caches[0]
    values = {
      output = {
        value = [{
          id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.ApiManagement/service/test-only/caches/test-only-semantic-cache"
          properties = { useFromLocation = "swedencentral" }
        }]
      }
    }
  }
}

run "reject_other_workloads_gateway_cache" {
  command = plan
  variables { semantic_cache_enabled = true }
  override_data {
    target = data.azapi_resource_list.gateway_caches[0]
    values = {
      output = {
        value = [{
          id         = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.ApiManagement/service/test-only/caches/another-workload"
          properties = { useFromLocation = "default" }
        }]
      }
    }
  }
  expect_failures = [azapi_resource.semantic_cache_connection]
}
