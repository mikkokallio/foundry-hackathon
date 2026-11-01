variable "subscription_id" {
  description = "Azure subscription GUID to deploy into. Use the explicitly approved target subscription, not a subscription display name."
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
  description = "Real monitored email address for the API Management publisher contact, for example operator@your-domain.tld."
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
variable "search_configuration" {
  description = "Explicit Search capacity and billing overrides. sku is basic or standard (S1); replicas are 1-12 and partitions 1, 2, 3, 4, 6 or 12, subject to service-tier limits. Omitted semantic billing follows profile; omitted knowledge_retrieval leaves agentic billing unmanaged. Billing values are free or standard."
  type = object({
    sku                 = optional(string, "basic")
    replica_count       = optional(number, 1)
    partition_count     = optional(number, 1)
    semantic_search_sku = optional(string)
    knowledge_retrieval = optional(string)
  })
  default  = {}
  nullable = false
  validation {
    condition = (
      contains(["basic", "standard"], var.search_configuration.sku) &&
      var.search_configuration.replica_count >= 1 &&
      var.search_configuration.replica_count <= 12 &&
      floor(var.search_configuration.replica_count) == var.search_configuration.replica_count &&
      contains([1, 2, 3, 4, 6, 12], var.search_configuration.partition_count)
    )
    error_message = "Use basic or standard Search, 1-12 whole replicas, and 1, 2, 3, 4, 6 or 12 partitions; verify the selected tier's regional limits."
  }
  validation {
    condition = (
      (var.search_configuration.semantic_search_sku == null ? true : contains(["free", "standard"], var.search_configuration.semantic_search_sku)) &&
      (var.search_configuration.knowledge_retrieval == null ? true : contains(["free", "standard"], var.search_configuration.knowledge_retrieval))
    )
    error_message = "Explicit semantic_search_sku and knowledge_retrieval billing must each be free or standard."
  }
}
variable "tags" {
  description = "Optional HCL map of extra Azure resource tags, for example { owner = \"workshop\", event = \"hackathon\" }. Default {}."
  type        = map(string)
  default     = {}
}
