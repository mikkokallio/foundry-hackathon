# Remote Foundry evaluators invoke the judge with the participant's identity.
# This documented account-level role also permits direct model inference, not APIM-only enforcement.
resource "azurerm_role_assignment" "evaluation_model_user" {
  for_each             = var.participant_members
  scope                = var.foundation.foundry_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = each.key
  principal_type       = "User"
  depends_on           = [azapi_resource.model]
}

output "evaluation_access" {
  value = {
    scope                      = var.foundation.foundry_id
    role                       = "Cognitive Services OpenAI User"
    participant_ids            = sort(keys(var.participant_members))
    direct_model_access        = true
    universal_apim_enforcement = false
  }
}
