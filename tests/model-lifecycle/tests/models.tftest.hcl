mock_provider "azapi" {
  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        value = [{
          kind = "AIServices", skuName = "S0"
          model = {
            format          = "OpenAI", name = "unit-test-model", version = "1"
            lifecycleStatus = "GenerallyAvailable"
            deprecation     = { inference = "2099-01-01T00:00:00Z" }
            skus = [{
              name            = "GlobalStandard", usageName = "unit-test-model"
              deprecationDate = "2099-01-01T00:00:00Z"
            }]
          }
        }]
      }
    }
  }
}

variables {
  foundation = {
    subscription_id = "00000000-0000-0000-0000-000000000001"
    location        = "swedencentral"
    foundry_id      = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test-only/providers/Microsoft.CognitiveServices/accounts/test-only"
  }
  models = {
    chat-small = { name = "unit-test-model", version = "1", sku = "GlobalStandard", capacity = 10 }
  }
}

run "ga_is_accepted" {
  command = plan
}

run "legacy_is_rejected" {
  command = plan
  override_data {
    target = data.azapi_resource_list.regional_models
    values = {
      output = { value = [{
        kind = "AIServices", skuName = "S0"
        model = {
          format          = "OpenAI", name = "unit-test-model", version = "1"
          lifecycleStatus = "Legacy"
          deprecation     = { inference = "2099-01-01T00:00:00Z" }
          skus            = [{ name = "GlobalStandard", usageName = "unit-test-model" }]
        }
      }] }
    }
  }
  expect_failures = [terraform_data.model_lifecycle["chat-small"]]
}

run "unknown_lifecycle_is_rejected" {
  command = plan
  override_data {
    target = data.azapi_resource_list.regional_models
    values = {
      output = { value = [{
        kind = "AIServices", skuName = "S0"
        model = {
          format          = "OpenAI", name = "unit-test-model", version = "1"
          lifecycleStatus = "Unknown"
          deprecation     = { inference = "2099-01-01T00:00:00Z" }
          skus            = [{ name = "GlobalStandard", usageName = "unit-test-model" }]
        }
      }] }
    }
  }
  expect_failures = [terraform_data.model_lifecycle["chat-small"]]
}

run "retired_inference_is_rejected" {
  command = plan
  override_data {
    target = data.azapi_resource_list.regional_models
    values = {
      output = { value = [{
        kind = "AIServices", skuName = "S0"
        model = {
          format          = "OpenAI", name = "unit-test-model", version = "1"
          lifecycleStatus = "GenerallyAvailable"
          deprecation     = { inference = "2020-01-01T00:00:00Z" }
          skus            = [{ name = "GlobalStandard", usageName = "unit-test-model" }]
        }
      }] }
    }
  }
  expect_failures = [terraform_data.model_lifecycle["chat-small"]]
}

run "retired_sku_is_rejected" {
  command = plan
  override_data {
    target = data.azapi_resource_list.regional_models
    values = {
      output = { value = [{
        kind = "AIServices", skuName = "S0"
        model = {
          format          = "OpenAI", name = "unit-test-model", version = "1"
          lifecycleStatus = "GenerallyAvailable"
          deprecation     = { inference = "2099-01-01T00:00:00Z" }
          skus = [{
            name            = "GlobalStandard", usageName = "unit-test-model"
            deprecationDate = "2020-01-01T00:00:00Z"
          }]
        }
      }] }
    }
  }
  expect_failures = [terraform_data.model_lifecycle["chat-small"]]
}
