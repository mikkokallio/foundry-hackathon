data "azapi_resource_list" "regional_models" {
  type                   = "Microsoft.CognitiveServices/locations/models@2025-06-01"
  parent_id              = "/subscriptions/${var.foundation.subscription_id}/providers/Microsoft.CognitiveServices/locations/${var.foundation.location}"
  response_export_values = ["value"]
}

locals {
  selected_catalog_models = {
    for alias, model in var.models : alias => [
      for candidate in data.azapi_resource_list.regional_models.output.value : candidate
      if candidate.kind == "AIServices" && candidate.skuName == "S0" &&
      candidate.model.format == "OpenAI" && candidate.model.name == model.name &&
      candidate.model.version == model.version
    ]
  }
}

resource "terraform_data" "model_lifecycle" {
  for_each = var.models
  lifecycle {
    precondition {
      condition = length(local.selected_catalog_models[each.key]) > 0 && alltrue([
        for candidate in local.selected_catalog_models[each.key] :
        try(candidate.model.lifecycleStatus == "GenerallyAvailable", false) &&
        try(timecmp(candidate.model.deprecation.inference, plantimestamp()) > 0, false)
      ])
      error_message = "Selected model ${each.key} must have fresh regional GenerallyAvailable metadata and a future inference retirement date. Legacy, deprecated, preview, retired or unknown status is rejected."
    }
    precondition {
      condition = anytrue(flatten([
        for candidate in local.selected_catalog_models[each.key] : [
          for sku in candidate.model.skus :
          sku.name == each.value.sku && try(!endswith(sku.usageName, "-finetune"), false) &&
          (try(sku.deprecationDate, null) == null ? true : try(timecmp(sku.deprecationDate, plantimestamp()) > 0, false))
        ]
      ]))
      error_message = "Selected model ${each.key} has no non-retired regional deployment SKU."
    }
  }
}

resource "azapi_resource" "model" {
  for_each  = var.models
  type      = "Microsoft.CognitiveServices/accounts/deployments@2025-06-01"
  name      = "${var.workload_name}-${each.key}"
  parent_id = var.foundation.foundry_id
  body = {
    sku = {
      name     = each.value.sku
      capacity = each.value.capacity
    }
    properties = {
      model = {
        format  = "OpenAI"
        name    = each.value.name
        version = each.value.version
      }
      versionUpgradeOption = "NoAutoUpgrade"
    }
  }
  locks = [var.foundation.foundry_id]
  retry = {
    error_message_regex = ["RequestConflict", "Another operation is in progress"]
    interval_seconds    = 10
  }
  depends_on = [terraform_data.boundary, terraform_data.model_lifecycle]
}

output "model_deployments" {
  value = { for alias, deployment in azapi_resource.model : alias => deployment.name }
}
