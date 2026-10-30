variable "foundation" {
  description = "Unmodified foundation output from the applied state. The delivery integration uses its subscription, tenant, approved region, Foundry projects and workspace; never supply a plan's unknown outputs."
  type = object({
    contract_version = number
    subscription_id  = string
    tenant_id        = string
    location         = string
    foundry_id       = string
    workspace_id     = string
    projects         = map(object({ id = string }))
  })
  validation {
    condition = (
      var.foundation.contract_version == 1 &&
      contains(["francecentral", "swedencentral", "westeurope"], var.foundation.location) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.foundation.subscription_id)) &&
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.foundation.tenant_id)) &&
      can(regex("(?i)^/subscriptions/${var.foundation.subscription_id}/resourceGroups/[^/]+/providers/Microsoft.CognitiveServices/accounts/[^/]+$", var.foundation.foundry_id)) &&
      can(regex("(?i)^/subscriptions/${var.foundation.subscription_id}/resourceGroups/[^/]+/providers/Microsoft.OperationalInsights/workspaces/[^/]+$", var.foundation.workspace_id))
    )
    error_message = "Use an applied version-1 foundation in an authorized region, with matching subscription resource IDs."
  }
}

variable "project_name" {
  description = "Existing non-facilitator foundation team project whose real agent CI will evaluate, for example alpha. This grants no access to other projects."
  type        = string
  validation {
    condition = var.project_name != "facilitator" && try(
      lower(var.foundation.projects[var.project_name].id) == lower("${var.foundation.foundry_id}/projects/${var.project_name}"),
      false
    )
    error_message = "Select an existing team project belonging to this foundation's Foundry account."
  }
}

variable "suffix" {
  description = "Unique delivery identifier: 4-10 lowercase letters/digits, for example ci2026. Its state resources survive normal foundation/workload teardown."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{4,10}$", var.suffix))
    error_message = "Use 4-10 lowercase letters/digits."
  }
}

variable "github_repository" {
  description = "Actual GitHub OWNER/REPOSITORY, with exact spelling/case used by GitHub OIDC. No wildcard, URL, fork inference or repository creation."
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9.-]*/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "Supply the actual OWNER/REPOSITORY, not a URL or wildcard."
  }
}

variable "github_environment" {
  description = "Actual protected GitHub environment name, 1-255 characters without surrounding whitespace/control characters. Configure required reviewers and allowed deployment branches in that repository before enabling CI; Terraform does not change GitHub settings."
  type        = string
  validation {
    condition = (
      length(var.github_environment) > 0 && length(var.github_environment) <= 255 &&
      var.github_environment == trimspace(var.github_environment) &&
      length(regexall("[[:cntrl:]]", var.github_environment)) == 0
    )
    error_message = "Supply a nonempty actual GitHub environment name without surrounding whitespace or control characters."
  }
}

variable "state_operator_object_ids" {
  description = "Explicit nonempty set of real tenant principal GUIDs allowed to migrate/recover state in the dedicated state account. No operator is added implicitly; no Entra application secrets or Graph grants are created."
  type        = set(string)
  validation {
    condition = length(var.state_operator_object_ids) > 0 && alltrue([
      for id in var.state_operator_object_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Select at least one actual tenant state operator by object GUID."
  }
}

variable "tags" {
  description = "Optional resource tags. Do not copy lab-enrollment/deletion tags onto this separately retained state group."
  type        = map(string)
  default     = {}
}
