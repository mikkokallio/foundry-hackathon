variable "protection" {
  description = "Enter one HCL object: { monthly_cap_eur = NUMBER, reserve_eur = NUMBER, max_hourly_eur = NUMBER }. All values must be positive; reserve must be below cap. Cap covers the WHOLE subscription including existing resources; max_hourly_eur is a reviewed conservative exposure estimate, not a model quota. Cost/visibility cutoff or expiry DELETES enrolled lab groups and data. Billing is delayed: this is not a guaranteed hard spending cap."
  type = object({
    monthly_cap_eur = number
    reserve_eur     = number
    max_hourly_eur  = number
  })
  nullable = false
  validation {
    condition = try(
      var.protection.monthly_cap_eur > 0 &&
      var.protection.reserve_eur > 0 &&
      var.protection.reserve_eur < var.protection.monthly_cap_eur &&
      var.protection.max_hourly_eur > 0,
      false
    )
    error_message = "Review a positive EUR cap, reserve below the cap and conservative hourly exposure estimate."
  }
}

module "protection_group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "0.4.0"
  name             = "rg-${local.name}-protection"
  location         = var.location
  tags             = merge(local.tags, { purpose = "spending-protection" })
  enable_telemetry = false
  depends_on       = [terraform_data.boundary]
}

module "protection" {
  source                        = "Azure/avm-res-automation-automationaccount/azurerm"
  version                       = "0.3.0"
  name                          = "aa-${local.name}"
  location                      = var.location
  resource_group_name           = module.protection_group.name
  managed_identities            = { system_assigned = true }
  sku                           = "Basic"
  local_authentication_enabled  = false
  public_network_access_enabled = true
  tags                          = local.tags
  enable_telemetry              = false
}

resource "azurerm_role_assignment" "protection_cost_reader" {
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = "Cost Management Reader"
  principal_id         = module.protection.system_assigned_mi_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_definition" "protection_bindings" {
  name               = "Workshop protection scope discovery ${var.suffix}"
  role_definition_id = uuidv5("url", "${var.subscription_id}/${var.suffix}/protection-scope-reader")
  scope              = "/subscriptions/${var.subscription_id}"
  assignable_scopes  = ["/subscriptions/${var.subscription_id}"]
  description        = "Read role bindings to discover only resource groups explicitly enrolled in this protector."
  permissions { actions = ["Microsoft.Authorization/roleAssignments/read"] }
}

resource "azurerm_role_assignment" "protection_bindings" {
  scope              = "/subscriptions/${var.subscription_id}"
  role_definition_id = azurerm_role_definition.protection_bindings.role_definition_resource_id
  principal_id       = module.protection.system_assigned_mi_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "protection_cutoff" {
  name               = "Workshop spending cutoff ${var.suffix}"
  role_definition_id = uuidv5("url", "${var.subscription_id}/${var.suffix}/protection-cutoff")
  scope              = "/subscriptions/${var.subscription_id}"
  assignable_scopes  = ["/subscriptions/${var.subscription_id}"]
  description        = "Delete explicitly enrolled disposable lab groups; clear Foundry project associations before deletion."
  permissions {
    actions = [
      "Microsoft.Resources/subscriptions/resourceGroups/read",
      "Microsoft.Resources/subscriptions/resourceGroups/delete",
      "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
      "Microsoft.CognitiveServices/accounts/read",
      "Microsoft.CognitiveServices/accounts/write",
      "Microsoft.CognitiveServices/accounts/projects/read",
      "Microsoft.CognitiveServices/accounts/projects/delete",
      "Microsoft.CognitiveServices/accounts/deployments/read",
      "Microsoft.CognitiveServices/accounts/deployments/delete",
    ]
  }
}

resource "azurerm_role_assignment" "protection_foundation" {
  scope              = module.group.resource_id
  role_definition_id = azurerm_role_definition.protection_cutoff.role_definition_resource_id
  principal_id       = module.protection.system_assigned_mi_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_automation_variable_string" "protection" {
  name                    = "SpendingProtection"
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  encrypted               = false
  value = jsonencode({
    subscription_id  = var.subscription_id
    tenant_id        = var.tenant_id
    deployment       = var.suffix
    principal_id     = module.protection.system_assigned_mi_principal_id
    cutoff_role_id   = azurerm_role_definition.protection_cutoff.role_definition_resource_id
    protection_group = module.protection_group.resource_id
    expires_at       = var.expires_at
    limits           = var.protection
  })
}

resource "azurerm_automation_runbook" "protection" {
  name                    = "Protect-Spending"
  location                = var.location
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  runbook_type            = "PowerShell"
  log_verbose             = false
  log_progress            = true
  content                 = file("${path.module}/../scripts/Protect-Spending.ps1")
}

resource "azurerm_automation_schedule" "protection" {
  name                    = "hourly-spending-protection"
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  frequency               = "Hour"
  interval                = 1
  timezone                = "Etc/UTC"
  expiry_time             = timeadd(var.expires_at, "168h")
}

resource "azurerm_automation_job_schedule" "protection" {
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  schedule_name           = azurerm_automation_schedule.protection.name
  runbook_name            = azurerm_automation_runbook.protection.name
  depends_on = [
    azurerm_automation_variable_string.protection,
    azurerm_role_assignment.protection_cost_reader,
    azurerm_role_assignment.protection_bindings,
    azurerm_role_assignment.protection_foundation,
  ]
}

resource "azurerm_automation_schedule" "expiry" {
  name                    = "authorization-expiry"
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  frequency               = "OneTime"
  timezone                = "Etc/UTC"
  start_time              = var.expires_at
}

resource "azurerm_automation_job_schedule" "expiry" {
  resource_group_name     = module.protection_group.name
  automation_account_name = module.protection.automation_account_name
  schedule_name           = azurerm_automation_schedule.expiry.name
  runbook_name            = azurerm_automation_runbook.protection.name
  depends_on = [
    azurerm_automation_variable_string.protection,
    azurerm_role_assignment.protection_cost_reader,
    azurerm_role_assignment.protection_bindings,
    azurerm_role_assignment.protection_foundation,
  ]
}
resource "azurerm_monitor_action_group" "protection" {
  name                = "ag-spending-${var.suffix}"
  resource_group_name = module.protection_group.name
  short_name          = "LabSpending"
  email_receiver {
    name                    = "operator"
    email_address           = var.publisher_email
    use_common_alert_schema = true
  }
  tags = local.tags
}

resource "azurerm_monitor_metric_alert" "protection" {
  for_each = {
    failure = {
      statuses = ["Failed", "Stopped", "Suspended"]
      operator = "GreaterThan", threshold = 0, window = "PT1H"
    }
    heartbeat = {
      statuses = ["Completed"]
      operator = "LessThan", threshold = 1, window = "PT6H"
    }
  }
  name                = "spending-${each.key}-${var.suffix}"
  resource_group_name = module.protection_group.name
  scopes              = [module.protection.resource_id]
  description         = "Independent spending protection ${each.key}; investigate immediately. Azure billing is not hard-capped."
  severity            = 1
  frequency           = "PT15M"
  window_size         = each.value.window
  criteria {
    metric_namespace = "Microsoft.Automation/automationAccounts"
    metric_name      = "TotalJob"
    aggregation      = "Total"
    operator         = each.value.operator
    threshold        = each.value.threshold
    dimension {
      name     = "Runbook"
      operator = "Include"
      values   = [azurerm_automation_runbook.protection.name]
    }
    dimension {
      name     = "Status"
      operator = "Include"
      values   = each.value.statuses
    }
  }
  action { action_group_id = azurerm_monitor_action_group.protection.id }
  tags = local.tags
}
