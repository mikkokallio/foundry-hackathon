mock_provider "azapi" {
  mock_data "azapi_resource" {
    defaults = {
      output = {
        sku        = { name = "standard" }
        properties = { replicaCount = 3, partitionCount = 1, semanticSearch = "standard" }
      }
    }
  }
}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000001"
  tenant_id       = "00000000-0000-0000-0000-000000000002"
  suffix          = "testonly"
  publisher_email = "operator@unit.invalid"
  team_names      = ["alpha"]
  profile         = "lite"
}

run "legacy_leaves_agentic_billing_unmanaged" {
  command = plan
  assert {
    condition     = length(azapi_update_resource.search_agentic_billing) == 0 && length(data.azapi_resource.search_configuration) == 0
    error_message = "Existing deployments must not silently opt into paid agentic retrieval."
  }
}

run "selected_billing" {
  command = apply
  variables {
    search_configuration = {
      sku                 = "standard", replica_count = 3, partition_count = 1
      semantic_search_sku = "standard", knowledge_retrieval = "standard"
    }
  }
  assert {
    condition = (
      azapi_update_resource.search_agentic_billing[0].body == { properties = { knowledgeRetrieval = "standard" } } &&
      !azapi_update_resource.search_agentic_billing[0].ignore_missing_property &&
      azapi_update_resource.search_agentic_billing[0].resource_id == local.search_id &&
      azapi_update_resource.search_agentic_billing[0].replace_triggers_external_values.service_configuration.properties.replicaCount == 3
    )
    error_message = "Manage only explicit agentic billing, after the selected service, without hiding missing readback properties."
  }
}

run "repeat_selected_billing" {
  command = plan
  variables {
    search_configuration = {
      sku                 = "standard", replica_count = 3, partition_count = 1
      semantic_search_sku = "standard", knowledge_retrieval = "standard"
    }
  }
}

run "changing_service_defers_billing_read" {
  command = plan
  variables {
    tags = { changed = "test-only" }
    search_configuration = {
      sku                 = "standard", replica_count = 3, partition_count = 1
      semantic_search_sku = "standard", knowledge_retrieval = "standard"
    }
  }
}

run "explicit_free_billing" {
  command = plan
  variables { search_configuration = { knowledge_retrieval = "free" } }
  assert {
    condition     = azapi_update_resource.search_agentic_billing[0].body.properties.knowledgeRetrieval == "free"
    error_message = "Explicit free billing must be an update, not forgetting a previously paid setting."
  }
}

run "disabled_search_has_no_billing_operations" {
  command = plan
  variables {
    enable_search        = false
    search_configuration = { knowledge_retrieval = "standard" }
  }
  assert {
    condition     = length(azapi_update_resource.search_agentic_billing) == 0 && length(data.azapi_resource.search_configuration) == 0
    error_message = "Disabled Search must not read or write billing configuration."
  }
}
