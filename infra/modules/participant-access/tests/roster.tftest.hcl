mock_provider "azuread" {}
mock_provider "azurerm" {}

variables {
  subscription_id            = "11111111-1111-1111-1111-111111111111"
  expected_participant_count = 2
  teams = {
    alpha = ["22222222-2222-2222-2222-222222222222"]
    beta  = ["member@tenant.example"]
  }
  project_ids = {
    alpha = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/foundry/projects/alpha"
    beta  = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.CognitiveServices/accounts/foundry/projects/beta"
  }
  resource_group_id      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test"
  gateway_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.ApiManagement/service/apim-test"
  catalog_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.ApiCenter/services/apic-test"
  workspace_id           = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.OperationalInsights/workspaces/log-test"
  applicationinsights_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.Insights/components/appi-test"
  search_id              = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-test/providers/Microsoft.Search/searchServices/srch-test"
}

override_data {
  target = data.azuread_user.member["22222222-2222-2222-2222-222222222222"]
  values = { object_id = "22222222-2222-2222-2222-222222222222", account_enabled = true }
}
override_data {
  target = data.azuread_user.member["member@tenant.example"]
  values = { object_id = "33333333-3333-3333-3333-333333333333", account_enabled = true }
}

run "upn_and_object_id_receive_real_exercise_scopes" {
  command = apply
  assert {
    condition     = length(azurerm_role_assignment.member) == 16 && length(output.members) == 2
    error_message = "Each resolved member needs eight declared authoring/read/publish roles, including Search."
  }
  assert {
    condition = (
      azurerm_role_assignment.member["member@tenant.example/foundry"].scope == var.project_ids.beta &&
      azurerm_role_assignment.member["member@tenant.example/catalog-author"].scope == var.catalog_id &&
      azurerm_role_assignment.member["member@tenant.example/gateway-author"].scope == var.gateway_id &&
      azurerm_role_assignment.member["member@tenant.example/search-data-author"].scope == var.search_id &&
      azurerm_role_assignment.member["member@tenant.example/telemetry-publisher"].scope == var.applicationinsights_id
    )
    error_message = "Keep grants at the actual project and service scopes, never blanket resource-group Contributor."
  }
  assert {
    condition = (
      endswith(azurerm_role_assignment.member["member@tenant.example/catalog-author"].role_definition_id, "/${azurerm_role_definition.author["catalog"].role_definition_id}") &&
      endswith(azurerm_role_assignment.member["member@tenant.example/telemetry-publisher"].role_definition_id, "/3913510d-42f4-4e42-8a64-420c390055eb")
    )
    error_message = "Use the restricted catalog author role and real telemetry-publishing role."
  }
  assert {
    condition = (
      length(azurerm_role_definition.author) == 3 &&
      contains(one(azurerm_role_definition.author["gateway"].permissions).not_actions, "Microsoft.ApiManagement/service/write") &&
      contains(one(azurerm_role_definition.author["gateway"].permissions).not_actions, "Microsoft.ApiManagement/service/delete") &&
      contains(one(azurerm_role_definition.author["search"].permissions).not_actions, "Microsoft.Search/searchServices/write") &&
      contains(one(azurerm_role_definition.author["search"].permissions).not_actions, "Microsoft.Search/searchServices/delete") &&
      length(azurerm_role_definition.author["catalog"].assignable_scopes) == 1 &&
      one(azurerm_role_definition.author["catalog"].assignable_scopes) == var.resource_group_id
    )
    error_message = "Workshop authors may change shared exercises, not resize/delete the foundation or use roles outside this lab."
  }
}

run "search_is_optional_for_other_compositions" {
  command = apply
  variables { search_id = null }
  assert {
    condition     = length(azurerm_role_assignment.member) == 12
    error_message = "Do not grant Search roles when the selected foundation has no Search service."
  }
}

run "reject_incomplete_roster" {
  command = plan
  variables { expected_participant_count = 13 }
  expect_failures = [terraform_data.roster]
}

run "reject_disabled_user" {
  command = plan
  override_data {
    target = data.azuread_user.member["member@tenant.example"]
    values = { object_id = "33333333-3333-3333-3333-333333333333", account_enabled = false }
  }
  expect_failures = [terraform_data.roster]
}
