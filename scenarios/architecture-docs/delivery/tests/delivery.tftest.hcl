# Test-scoped provider doubles only; no Azure/Foundry calls or live acceptance.
mock_provider "azurerm" {
  mock_resource "azurerm_user_assigned_identity" {
    defaults = {
      id           = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-delivery-test/providers/Microsoft.ManagedIdentity/userAssignedIdentities/test"
      principal_id = "00000000-0000-0000-0000-000000000003"
      client_id    = "00000000-0000-0000-0000-000000000004"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-delivery-test/providers/Microsoft.Storage/storageAccounts/stcistatetest"
    }
  }
}
mock_provider "azapi" {
  mock_resource "azapi_resource" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-delivery-test/providers/Microsoft.Storage/storageAccounts/stcistatetest/blobServices/default/containers/tfstate"
    }
  }
}

variables {
  foundation = {
    contract_version = 1
    subscription_id  = "00000000-0000-0000-0000-000000000001"
    tenant_id        = "00000000-0000-0000-0000-000000000002"
    location         = "francecentral"
    foundry_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test"
    workspace_id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
    projects = {
      alpha = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test/projects/alpha" }
    }
  }
  project_name              = "alpha"
  suffix                    = "test"
  github_repository         = "test-owner/test-repository"
  github_environment        = "workshop"
  state_operator_object_ids = ["00000000-0000-0000-0000-000000000005"]
}

run "protected_environment_and_state" {
  command = apply
  assert {
    condition     = azurerm_federated_identity_credential.github.subject == "repo:test-owner/test-repository:environment:workshop"
    error_message = "Trust must bind the exact repository and environment, never a branch wildcard."
  }
  assert {
    condition = (
      !azurerm_storage_account.state.shared_access_key_enabled &&
      !azurerm_storage_account.state.allow_nested_items_to_be_public &&
      azurerm_storage_account.state.blob_properties[0].versioning_enabled &&
      azurerm_storage_account.state.blob_properties[0].delete_retention_policy[0].days == 30 &&
      azurerm_storage_account.state.blob_properties[0].container_delete_retention_policy[0].days == 30 &&
      azurerm_management_lock.state.lock_level == "CanNotDelete"
    )
    error_message = "State must be Entra-only, non-public, versioned and recoverable."
  }
  assert {
    condition = (
      length(azurerm_role_assignment.ci) == 5 &&
      endswith(azurerm_role_assignment.ci["foundation_plan_reader"].role_definition_id, "/acdd72a7-3385-48ef-bd42-f606fba81ae7") &&
      azurerm_role_assignment.ci["project_evaluator"].scope == var.foundation.projects.alpha.id &&
      azurerm_role_assignment.ci["state_writer"].scope == azapi_resource.state_container.id
    )
    error_message = "CI gets read-only infrastructure access, one project and one state container; no apply or role-management grant."
  }
}

run "environment_colon_is_encoded" {
  command = plan
  variables {
    github_environment = "workshop:reviewed"
  }
  assert {
    condition     = azurerm_federated_identity_credential.github.subject == "repo:test-owner/test-repository:environment:workshop%3Areviewed"
    error_message = "GitHub percent-encodes colons inside environment metadata."
  }
}

run "reject_unknown_project" {
  command = plan
  variables {
    project_name = "other-team"
  }
  expect_failures = [var.project_name]
}

run "reject_repository_wildcard" {
  command = plan
  variables {
    github_repository = "test-owner/*"
  }
  expect_failures = [var.github_repository]
}

run "reject_no_state_operator" {
  command = plan
  variables {
    state_operator_object_ids = []
  }
  expect_failures = [var.state_operator_object_ids]
}

run "reject_forbidden_region" {
  command = plan
  variables {
    foundation = {
      contract_version = 1
      subscription_id  = "00000000-0000-0000-0000-000000000001"
      tenant_id        = "00000000-0000-0000-0000-000000000002"
      location         = "northeurope"
      foundry_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test"
      workspace_id     = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
      projects = {
        alpha = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test/projects/alpha" }
      }
    }
  }
  expect_failures = [var.foundation]
}

run "reject_cross_subscription_workspace" {
  command = plan
  variables {
    foundation = {
      contract_version = 1
      subscription_id  = "00000000-0000-0000-0000-000000000001"
      tenant_id        = "00000000-0000-0000-0000-000000000002"
      location         = "francecentral"
      foundry_id       = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test"
      workspace_id     = "/subscriptions/00000000-0000-0000-0000-000000000009/resourceGroups/test/providers/Microsoft.OperationalInsights/workspaces/test"
      projects = {
        alpha = { id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/test/providers/Microsoft.CognitiveServices/accounts/test/projects/alpha" }
      }
    }
  }
  expect_failures = [var.foundation]
}
