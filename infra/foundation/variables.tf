variable "subscription_id" {
  description = "Azure subscription GUID to deploy and monitor for spending. Use the explicitly approved target subscription, not a subscription display name."
  type        = string
}
variable "tenant_id" {
  description = "Microsoft Entra tenant GUID owning the target subscription. Your Azure CLI login must belong to this tenant."
  type        = string
}
variable "location" {
  description = "Core-services region: francecentral (default/preferred), swedencentral or westeurope. No other region is authorized. Confirm regional service and model capacity before applying."
  type        = string
  default     = "francecentral"
  validation {
    condition     = contains(["francecentral", "swedencentral", "westeurope"], var.location)
    error_message = "Use francecentral (preferred), swedencentral or westeurope. Other regions, including North Europe, are not authorized."
  }
}
variable "search_location" {
  description = "AI Search region: francecentral (default/preferred), swedencentral or westeurope. May differ from the core region, but must remain in this authorized allowlist."
  type        = string
  default     = "francecentral"
  validation {
    condition     = contains(["francecentral", "swedencentral", "westeurope"], var.search_location)
    error_message = "Use francecentral (preferred), swedencentral or westeurope for Search. Other regions, including North Europe, are not authorized."
  }
}
variable "suffix" {
  description = "Unique deployment suffix: 4-10 lowercase letters/digits, for example lab2026. Used in globally unique service names; not the organization display name."
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9]{4,10}$", var.suffix))
    error_message = "Use a neutral 4-10 character lowercase alphanumeric suffix."
  }
}
variable "profile" {
  description = "Choose lite (Basic v2 gateway) or full (Standard v2 gateway). Both retain the scenario's required capabilities."
  type        = string
  validation {
    condition     = contains(["lite", "full"], var.profile)
    error_message = "Profile must be lite or full."
  }
}
variable "publisher_email" {
  description = "Real monitored email address for API Management publisher contact and spending-protection alerts, for example operator@your-domain.tld."
  type        = string
}
variable "team_names" {
  description = "HCL list of unique team keys, for example [\"alpha\",\"beta\"]. Each key starts with a lowercase letter and contains at most 31 lowercase letters/digits/hyphens. Do not include facilitator; it is created separately."
  type        = set(string)
  validation {
    condition = length(var.team_names) > 0 && alltrue([
      for name in var.team_names : can(regex("^[a-z][a-z0-9-]{0,30}$", name)) && name != "facilitator"
    ])
    error_message = "Provide at least one neutral team key; facilitator is reserved."
  }
}
variable "enable_search" {
  description = "Whether to provision AI Search. Default true; Search-dependent scenarios and exercises require true."
  type        = bool
  default     = true
}
variable "expires_at" {
  description = "Explicit UTC authorization expiry in RFC3339 format, for example 2026-11-03T16:42:33Z. The spending protector DELETES enrolled lab groups and their data at expiry."
  type        = string
  validation {
    condition     = can(formatdate("YYYY-MM-DD", var.expires_at))
    error_message = "An explicit RFC3339 spending authorization expiry is required."
  }
}
variable "tags" {
  description = "Optional HCL map of extra Azure resource tags, for example { owner = \"workshop\", event = \"hackathon\" }. Default {}."
  type        = map(string)
  default     = {}
}
