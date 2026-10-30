locals {
  name     = "ai-lab-${var.suffix}"
  projects = setunion(var.team_names, toset(["facilitator"]))
  # ARM returns associations in project-creation order, not configuration order.
  existing_project_order = flatten([
    for account in data.azapi_resource_list.foundry_accounts.output.value :
    account.properties.associatedProjects if account.name == "aif-${local.name}"
  ])
  project_associations = concat(
    [for project in local.existing_project_order : project if contains(local.projects, project)],
    sort(tolist(setsubtract(local.projects, toset(local.existing_project_order))))
  )
  tags = merge(var.tags, {
    workload     = "ai-lab"
    environment  = "sandbox"
    deployment   = var.suffix
    layer        = "foundation"
    profile      = var.profile
    "expires-on" = var.expires_at
  })
}

data "azurerm_client_config" "current" {}

resource "terraform_data" "boundary" {
  lifecycle {
    precondition {
      condition = (
        data.azurerm_client_config.current.subscription_id == var.subscription_id &&
        data.azurerm_client_config.current.tenant_id == var.tenant_id
      )
      error_message = "The authenticated subscription and tenant must match the explicit target."
    }
    precondition {
      condition     = timecmp(var.expires_at, plantimestamp()) > 0
      error_message = "Spending authorization has expired."
    }
  }
}

module "group" {
  source           = "Azure/avm-res-resources-resourcegroup/azurerm"
  version          = "0.4.0"
  name             = "rg-${local.name}"
  location         = var.location
  tags             = local.tags
  enable_telemetry = false
  depends_on       = [terraform_data.boundary]
}

module "logs" {
  source                                               = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version                                              = "0.5.1"
  name                                                 = "log-${local.name}"
  resource_group_name                                  = module.group.name
  location                                             = var.location
  log_analytics_workspace_retention_in_days            = 30
  log_analytics_workspace_sku                          = "PerGB2018"
  log_analytics_workspace_daily_quota_gb               = 0.1
  log_analytics_workspace_local_authentication_enabled = false
  log_analytics_workspace_internet_ingestion_enabled   = "true"
  log_analytics_workspace_internet_query_enabled       = "true"
  tags                                                 = local.tags
  enable_telemetry                                     = false
}

module "insights" {
  source                        = "Azure/avm-res-insights-component/azurerm"
  version                       = "0.5.0"
  name                          = "appi-${local.name}"
  parent_id                     = module.group.resource_id
  location                      = var.location
  workspace_id                  = module.logs.resource_id
  local_authentication_disabled = true
  tags                          = local.tags
  enable_telemetry              = false
}

data "azapi_resource_list" "foundry_accounts" {
  type                   = "Microsoft.CognitiveServices/accounts@2025-06-01"
  parent_id              = module.group.resource_id
  response_export_values = ["value"]
}

module "foundry" {
  source                        = "Azure/avm-res-cognitiveservices-account/azurerm"
  version                       = "0.11.1"
  name                          = "aif-${local.name}"
  parent_id                     = module.group.resource_id
  location                      = var.location
  kind                          = "AIServices"
  sku_name                      = "S0"
  custom_subdomain_name         = "aif-${local.name}"
  allow_project_management      = true
  associated_projects           = local.project_associations
  managed_identities            = { system_assigned = true }
  local_auth_enabled            = false
  public_network_access_enabled = true
  network_acls                  = { default_action = "Allow" }
  cognitive_deployments         = {}
  tags                          = local.tags
  enable_telemetry              = false
}

resource "azapi_resource" "project" {
  for_each  = local.projects
  type      = "Microsoft.CognitiveServices/accounts/projects@2025-06-01"
  name      = each.key
  parent_id = module.foundry.resource_id
  location  = var.location
  identity { type = "SystemAssigned" }
  body = {
    properties = { displayName = each.key, description = "AI sandbox project" }
  }
  response_export_values = ["properties.endpoints", "identity.principalId"]
  locks                  = [module.foundry.resource_id]
  retry = {
    error_message_regex = ["RequestConflict", "Another operation is in progress"]
    interval_seconds    = 10
  }
  tags = local.tags
}

module "storage" {
  source                          = "Azure/avm-res-storage-storageaccount/azurerm"
  version                         = "0.10.0"
  name                            = "stailab${var.suffix}"
  parent_id                       = module.group.resource_id
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  shared_access_key_enabled       = false
  public_network_access_enabled   = true
  allow_nested_items_to_be_public = false
  network_rules                   = { default_action = "Allow" }
  containers                      = {}
  tags                            = local.tags
  enable_telemetry                = false
}

module "vault" {
  source                         = "Azure/avm-res-keyvault-vault/azurerm"
  version                        = "0.12.0"
  name                           = "kv-ailab-${var.suffix}"
  resource_group_name            = module.group.name
  location                       = var.location
  tenant_id                      = var.tenant_id
  sku_name                       = "standard"
  legacy_access_policies_enabled = false
  purge_protection_enabled       = false
  soft_delete_retention_days     = 7
  public_network_access_enabled  = true
  network_acls                   = { default_action = "Allow", bypass = "AzureServices" }
  tags                           = local.tags
  enable_telemetry               = false
}

module "search" {
  count                         = var.enable_search ? 1 : 0
  source                        = "Azure/avm-res-search-searchservice/azurerm"
  version                       = "0.3.0"
  name                          = "srch-${local.name}"
  resource_group_name           = module.group.name
  location                      = var.search_location
  sku                           = "basic"
  replica_count                 = 1
  partition_count               = 1
  semantic_search_sku           = var.profile == "lite" ? "free" : "standard"
  local_authentication_enabled  = false
  public_network_access_enabled = true
  managed_identities            = { system_assigned = true }
  tags                          = local.tags
  enable_telemetry              = false
}

module "registry" {
  source                        = "Azure/avm-res-containerregistry-registry/azurerm"
  version                       = "0.8.0"
  name                          = "acrailab${var.suffix}"
  resource_group_name           = module.group.name
  location                      = var.location
  sku                           = "Basic"
  admin_enabled                 = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = false
  tags                          = local.tags
  enable_telemetry              = false
}

module "containers" {
  source                 = "Azure/avm-res-app-managedenvironment/azurerm"
  version                = "0.6.0"
  name                   = "cae-${local.name}"
  resource_group_name    = module.group.name
  location               = var.location
  app_logs_configuration = { destination = "azure-monitor" }
  zone_redundant         = false
  tags                   = local.tags
  enable_telemetry       = false
}

module "gateway" {
  source                        = "Azure/avm-res-apimanagement-service/azurerm"
  version                       = "0.9.0"
  name                          = "apim-${local.name}"
  resource_group_name           = module.group.name
  location                      = var.location
  sku_name                      = var.profile == "lite" ? "BasicV2_1" : "StandardV2_1"
  publisher_name                = "AI sandbox"
  publisher_email               = var.publisher_email
  managed_identities            = { system_assigned = true }
  public_network_access_enabled = true
  virtual_network_type          = "None"
  tags                          = local.tags
  enable_telemetry              = false
}

resource "azapi_resource" "catalog" {
  # Live RP updates require sku, which the published ARM schema still omits.
  schema_validation_enabled = false
  type                      = "Microsoft.ApiCenter/services@2024-03-01"
  name                      = "apic-${local.name}"
  parent_id                 = module.group.resource_id
  location                  = var.location
  body = {
    sku        = { name = "Free" }
    properties = {}
  }
  # API Center coerces RFC3339 tag values to locale-dependent datetime strings.
  tags = merge(local.tags, { "expires-on" = formatdate("YYYY-MM-DD", var.expires_at) })
}

resource "azurerm_monitor_diagnostic_setting" "containers" {
  name                       = "workspace-logs"
  target_resource_id         = module.containers.resource_id
  log_analytics_workspace_id = module.logs.resource_id
  enabled_log { category = "ContainerAppConsoleLogs" }
  enabled_log { category = "ContainerAppSystemLogs" }
}
