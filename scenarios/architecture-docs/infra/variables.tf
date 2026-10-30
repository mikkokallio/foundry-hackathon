variable "foundation" {
  description = "Unmodified foundation output object from the APPLIED foundation state, not the terraform output -json envelope. Contract version 1 and AI Search are required; IDs, team projects and endpoints must belong to the same deployment."
  type = object({
    contract_version          = number
    subscription_id           = string
    tenant_id                 = string
    location                  = string
    resource_group_id         = string
    resource_group_name       = string
    foundry_id                = string
    foundry_name              = string
    foundry_endpoint          = string
    storage_id                = string
    storage_name              = string
    vault_id                  = string
    search_id                 = string
    search_endpoint           = string
    search_principal_id       = string
    registry_id               = string
    registry_server           = string
    container_environment_id  = string
    gateway_principal_id      = string
    gateway_id                = string
    gateway_name              = string
    gateway_url               = string
    gateway_logger_id         = string
    catalog_id                = string
    protection_principal_id   = string
    protection_cutoff_role_id = string
    projects = map(object({
      id           = string
      principal_id = string
    }))
    tags = map(string)
  })
  validation {
    condition     = var.foundation.contract_version == 1 && var.foundation.search_id != null
    error_message = "Architecture-docs requires foundation contract version 1 with AI Search enabled."
  }
}

variable "semantic_cache_enabled" {
  description = "Explicit boolean choice: true provisions the B4 Redis/Key Vault/APIM cache prerequisites; false omits B4. Choose true if participants will run B4; review added cost, Microsoft.Cache registration and the Redis access-key exception first. No Terraform default silently excludes this exercise."
  type        = bool
  nullable    = false
}

variable "gateway_tokens_per_minute" {
  description = "Positive integer tokens/minute per team on the normal model gateway route; default 50000. Size for complete multi-step agent turns and shared deployment capacity. The separate models-tight exercise stays at 256. This throttle is not an absolute spending limit; the subscription spending protector is unchanged."
  type        = number
  default     = 50000
  nullable    = false
  validation {
    condition     = var.gateway_tokens_per_minute > 0 && floor(var.gateway_tokens_per_minute) == var.gateway_tokens_per_minute
    error_message = "Use a positive whole-number token/minute limit for the normal model gateway."
  }
}

variable "runtime_images" {
  description = "HCL object { backend = \"REGISTRY.azurecr.io/REPOSITORY@sha256:DIGEST\", toolkit = \"REGISTRY.azurecr.io/REPOSITORY@sha256:DIGEST\" }. Use both genuinely built, reviewed image digests. Tags, dummy hashes and omitted apps are rejected."
  type = object({
    backend = string
    toolkit = string
  })
  validation {
    condition = alltrue([
      for image in [var.runtime_images.backend, var.runtime_images.toolkit] :
      can(regex("^[a-z0-9]+\\.azurecr\\.io/[a-z0-9][a-z0-9._/-]*@sha256:[0-9a-f]{64}$", image)) &&
      !can(regex("@sha256:0{64}$", image))
    ])
    error_message = "Both images must be real Azure Container Registry repository@sha256 digests, never mutable tags or placeholders."
  }

}

variable "reference_date" {
  description = "Synthetic corpus reference date in YYYY-MM-DD format. The supplied corpus and evaluation ground truths use 2026-11-01; changing it requires reviewing their date-dependent expectations."
  type        = string
  validation {
    condition     = can(formatdate("YYYY-MM-DD", "${var.reference_date}T00:00:00Z"))
    error_message = "Supply the scenario's explicit YYYY-MM-DD synthetic-corpus reference date."
  }
}

variable "participant_members" {
  description = "HCL map from applied access-stage members: { \"USER-OBJECT-GUID\" = { team = \"alpha\" } }. Use actual resolved tenant user IDs and foundation team keys, not emails or guessed IDs; facilitator is excluded."
  type        = map(object({ team = string }))
  validation {
    condition = length(var.participant_members) > 0 && alltrue([
      for id, member in var.participant_members :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id)) &&
      member.team != "facilitator"
    ])
    error_message = "Supply the nonempty, resolved participant roster from the applied access stage."
  }
}

variable "librarians" {
  description = "HCL list of explicitly selected real human publishers, for example [\"librarian@your-domain.tld\"]. Accepts tenant user object GUIDs or work-account UPNs; at least one is required. The deploying operator is NOT added implicitly."
  type        = set(string)
  validation {
    condition = length(var.librarians) > 0 && alltrue([
      for reference in var.librarians :
      length(trimspace(reference)) > 0 &&
      !strcontains(reference, "REPLACE_") &&
      !endswith(lower(reference), ".example")
    ])
    error_message = "Select at least one real human librarian explicitly."
  }
}
variable "workload_name" {
  description = "Workload instance identifier: 4-30 lowercase letters/digits/hyphens, beginning with a letter and ending with a letter/digit, for example architecture-docs. Used in model aliases, routes and workload resource names."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,28}[a-z0-9]$", var.workload_name))
    error_message = "Use a neutral 4-30 character lowercase workload identifier."
  }
}
variable "organization_name" {
  description = "Your chosen real or fictional organization display name, 1-120 characters without surrounding whitespace or control characters. No organization name is imposed; this does not change synthetic business facts."
  type        = string
  nullable    = false
  validation {
    condition = (
      length(var.organization_name) >= 1 && length(var.organization_name) <= 120 &&
      var.organization_name == trimspace(var.organization_name) &&
      length(regexall("[[:cntrl:]]", var.organization_name)) == 0
    )
    error_message = "Choose a nonempty organization name of at most 120 characters, without surrounding whitespace or control characters."
  }
}
variable "embedding_dimensions" {
  description = "Integer vector dimensions supported by your embedding model, 1-3072. Default 3072 for text-embedding-3-large; passed consistently to the Search index, embedding skill and vectorizer."
  type        = number
  default     = 3072
  validation {
    condition = (
      floor(var.embedding_dimensions) == var.embedding_dimensions &&
      var.embedding_dimensions >= 1 && var.embedding_dimensions <= 3072
    )
    error_message = "Choose an integer embedding size supported by the selected model (1-3072)."
  }
}
variable "models" {
  description = "HCL map keyed chat-small, chat-medium, judge and embedding, each with { name = \"MODEL\", version = \"VERSION\", sku = \"GlobalStandard\", capacity = INTEGER }. Use reviewed scenario.json selections and actual free regional quota. Chat deployments are SHARED across teams: size for aggregate demand, not one team's gateway cap. Read actual deployed TPM/RPM; allocation units are model/SKU-specific, not reserved throughput or a spending cap. Native plan rejects unavailable, non-GA or retired models/SKUs."
  type = map(object({
    name     = string
    version  = string
    sku      = string
    capacity = number
  }))
  validation {
    condition = alltrue([
      for alias in ["chat-small", "chat-medium", "judge", "embedding"] : contains(keys(var.models), alias)
      ]) && alltrue([
      for model in values(var.models) : model.capacity > 0 && floor(model.capacity) == model.capacity
    ])
    error_message = "This scenario requires positive-capacity chat-small, chat-medium, judge and embedding deployments."
  }
}
