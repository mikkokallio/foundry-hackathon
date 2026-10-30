locals {
  knowledge_index = "${var.workload_name}-knowledge"
  knowledge_host  = trimprefix(var.foundation.search_endpoint, "https://")
  embedding_uri   = "https://${var.foundation.foundry_name}.openai.azure.com"
  organization_markdown = replace(
    replace(replace(replace(var.organization_name, "&", "&amp;"), "<", "&lt;"), ">", "&gt;"),
    "/([\\\\`*_\\[\\]|])/", "\\$1"
  )
  knowledge_sources = {
    published = { container = azurerm_storage_container.documents.name, prefix = "published/" }
    standards = { container = azurerm_storage_container.knowledge.name, prefix = "" }
  }
  search_rbac_retry = {
    error_message_regex  = ["(?i)Forbidden|AuthorizationPermissionMismatch|status.?code.?403"]
    interval_seconds     = 5
    max_interval_seconds = 30
  }
}

resource "terraform_data" "embedding_boundary" {
  lifecycle {
    precondition {
      condition = (
        (var.models["embedding"].name == "text-embedding-3-large" && var.embedding_dimensions <= 3072) ||
        (var.models["embedding"].name == "text-embedding-3-small" && var.embedding_dimensions <= 1536) ||
        (var.models["embedding"].name == "text-embedding-ada-002" && var.embedding_dimensions == 1536)
      )
      error_message = "Verify embedding model/dimension compatibility explicitly; no unknown-model substitution is permitted."
    }
  }
}

resource "azurerm_storage_container" "knowledge" {
  name                  = "${var.workload_name}-knowledge"
  storage_account_id    = var.foundation.storage_id
  container_access_type = "private"
  depends_on            = [terraform_data.boundary]
}

resource "azurerm_role_assignment" "search_source_reader" {
  for_each = {
    published = azurerm_storage_container.documents.name
    standards = azurerm_storage_container.knowledge.name
  }
  scope                = "${var.foundation.storage_id}/blobServices/default/containers/${each.value}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = var.foundation.search_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "operator_knowledge_content" {
  scope                = "${var.foundation.storage_id}/blobServices/default/containers/${azurerm_storage_container.knowledge.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "operator_search_author" {
  scope                = var.foundation.search_id
  role_definition_name = "Search Service Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "operator_search_reader" {
  scope                = var.foundation.search_id
  role_definition_name = "Search Index Data Reader"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_blob" "knowledge_standard" {
  for_each               = fileset("${path.module}/../data/standard", "*.md")
  name                   = each.key
  storage_account_name   = var.foundation.storage_name
  storage_container_name = azurerm_storage_container.knowledge.name
  type                   = "Block"
  content_type           = "text/markdown; charset=utf-8"
  source_content         = replace(file("${path.module}/../data/standard/${each.key}"), "{{organization_name}}", local.organization_markdown)
  depends_on             = [azurerm_role_assignment.operator_knowledge_content]
  timeouts { create = "10m" }
}

resource "azapi_data_plane_resource" "knowledge_index" {
  type      = "Microsoft.Search/searchServices/indexes@2024-07-01"
  parent_id = local.knowledge_host
  name      = local.knowledge_index
  retry     = local.search_rbac_retry
  timeouts {
    create = "10m"
    update = "10m"
  }
  body = {
    name = local.knowledge_index
    fields = [
      { name = "chunk_id", type = "Edm.String", key = true, searchable = true, filterable = true, analyzer = "keyword" },
      { name = "parent_id", type = "Edm.String", filterable = true },
      { name = "title", type = "Edm.String", searchable = true },
      { name = "content", type = "Edm.String", searchable = true },
      { name = "source_url", type = "Edm.String", retrievable = true },
      { name = "content_vector", type = "Collection(Edm.Single)", searchable = true, dimensions = var.embedding_dimensions, vectorSearchProfile = "embedding" },
    ]
    vectorSearch = {
      algorithms = [{ name = "hnsw", kind = "hnsw", hnswParameters = { metric = "cosine" } }]
      profiles   = [{ name = "embedding", algorithm = "hnsw", vectorizer = "embedding" }]
      vectorizers = [{
        name = "embedding"
        kind = "azureOpenAI"
        azureOpenAIParameters = {
          resourceUri  = local.embedding_uri
          deploymentId = azapi_resource.model["embedding"].name
          modelName    = var.models["embedding"].name
        }
      }]
    }
    semantic = {
      defaultConfiguration = "architecture"
      configurations = [{
        name = "architecture"
        prioritizedFields = {
          titleField               = { fieldName = "title" }
          prioritizedContentFields = [{ fieldName = "content" }]
        }
      }]
    }
  }
  depends_on = [azurerm_role_assignment.operator_search_author, terraform_data.embedding_boundary]
}

resource "azapi_data_plane_resource" "knowledge_source" {
  for_each  = local.knowledge_sources
  type      = "Microsoft.Search/searchServices/datasources@2024-07-01"
  parent_id = local.knowledge_host
  name      = "${var.workload_name}-${each.key}"
  retry     = local.search_rbac_retry
  timeouts {
    create = "10m"
    update = "10m"
  }
  body = {
    name        = "${var.workload_name}-${each.key}"
    type        = "azureblob"
    credentials = { connectionString = "ResourceId=${var.foundation.storage_id};" }
    container   = { name = each.value.container, query = each.value.prefix }
  }
  depends_on = [azurerm_role_assignment.operator_search_author, azurerm_role_assignment.search_source_reader]
}

resource "azapi_data_plane_resource" "knowledge_skillset" {
  type      = "Microsoft.Search/searchServices/skillsets@2024-07-01"
  parent_id = local.knowledge_host
  name      = "${var.workload_name}-embedding"
  retry     = local.search_rbac_retry
  timeouts {
    create = "10m"
    update = "10m"
  }
  body = {
    name = "${var.workload_name}-embedding"
    skills = [
      {
        "@odata.type"     = "#Microsoft.Skills.Text.SplitSkill"
        name              = "split"
        context           = "/document"
        textSplitMode     = "pages"
        maximumPageLength = 2000
        pageOverlapLength = 300
        inputs            = [{ name = "text", source = "/document/content" }]
        outputs           = [{ name = "textItems", targetName = "pages" }]
      },
      {
        "@odata.type" = "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill"
        name          = "embedding"
        context       = "/document/pages/*"
        resourceUri   = local.embedding_uri
        deploymentId  = azapi_resource.model["embedding"].name
        modelName     = var.models["embedding"].name
        dimensions    = var.embedding_dimensions
        inputs        = [{ name = "text", source = "/document/pages/*" }]
        outputs       = [{ name = "embedding", targetName = "vector" }]
      },
    ]
    indexProjections = {
      selectors = [{
        targetIndexName    = azapi_data_plane_resource.knowledge_index.name
        parentKeyFieldName = "parent_id"
        sourceContext      = "/document/pages/*"
        mappings = [
          { name = "content", source = "/document/pages/*" },
          { name = "content_vector", source = "/document/pages/*/vector" },
          { name = "title", source = "/document/metadata_storage_name" },
          { name = "source_url", source = "/document/metadata_storage_path" },
        ]
      }]
      parameters = { projectionMode = "skipIndexingParentDocuments" }
    }
  }
  depends_on = [azurerm_role_assignment.operator_search_author, terraform_data.embedding_boundary]
}

resource "azapi_data_plane_resource" "knowledge_indexer" {
  for_each  = local.knowledge_sources
  type      = "Microsoft.Search/searchServices/indexers@2024-07-01"
  parent_id = local.knowledge_host
  name      = "${var.workload_name}-${each.key}"
  retry     = local.search_rbac_retry
  timeouts {
    create = "10m"
    update = "10m"
  }
  body = {
    name            = "${var.workload_name}-${each.key}"
    dataSourceName  = azapi_data_plane_resource.knowledge_source[each.key].name
    targetIndexName = azapi_data_plane_resource.knowledge_index.name
    skillsetName    = azapi_data_plane_resource.knowledge_skillset.name
    schedule        = { interval = "PT15M" }
    parameters = {
      maxFailedItems         = 0
      maxFailedItemsPerBatch = 0
      configuration          = { dataToExtract = "contentAndMetadata", parsingMode = "text", indexedFileNameExtensions = ".md" }
    }
  }
  depends_on = [azurerm_storage_blob.knowledge_standard, azurerm_storage_blob.document_seed]
}

locals {
  knowledge_contract = {
    contract_version        = 1
    workload_name           = var.workload_name
    subscription_id         = var.foundation.subscription_id
    tenant_id               = var.foundation.tenant_id
    search_endpoint         = var.foundation.search_endpoint
    index_name              = azapi_data_plane_resource.knowledge_index.name
    knowledge_source_name   = "${var.workload_name}-published-architecture"
    knowledge_base_name     = "${var.workload_name}-architecture"
    indexer_names           = [for indexer in azapi_data_plane_resource.knowledge_indexer : indexer.name]
    api_version             = "2026-04-01"
    project_ids             = { for name, project in var.foundation.projects : name => project.id }
    initialization_required = false
    live_accepted           = false
  }
}

# AzAPI 2.13 does not expose Search knowledge source/base data-plane types.
# Native apply runs the existing bounded initializer instead of inventing types.
resource "terraform_data" "knowledge_initialize" {
  input = local.knowledge_contract
  triggers_replace = [
    sha256(jsonencode(local.knowledge_contract)),
    sha256(jsonencode(azapi_data_plane_resource.knowledge_index.body)),
    sha256(jsonencode(azapi_data_plane_resource.knowledge_skillset.body)),
    sha256(jsonencode({ for name, source in azapi_data_plane_resource.knowledge_source : name => source.body })),
    sha256(jsonencode({ for name, indexer in azapi_data_plane_resource.knowledge_indexer : name => indexer.body })),
    sha256(jsonencode({ for name, blob in azurerm_storage_blob.knowledge_standard : name => blob.source_content })),
    sha256(jsonencode(var.models["embedding"])),
    filesha256("${path.module}/../../../infra/scripts/Initialize-Knowledge.ps1"),
  ]
  provisioner "local-exec" {
    interpreter = ["pwsh", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:KNOWLEDGE_INITIALIZER -Knowledge ($env:KNOWLEDGE_CONTRACT | ConvertFrom-Json -AsHashtable -Depth 50) -OutputDirectory $env:KNOWLEDGE_EVIDENCE -Confirm:$false"
    environment = {
      KNOWLEDGE_INITIALIZER = abspath("${path.module}/../../../infra/scripts/Initialize-Knowledge.ps1")
      KNOWLEDGE_CONTRACT    = jsonencode(local.knowledge_contract)
      KNOWLEDGE_EVIDENCE    = abspath("${path.root}/out/knowledge")
    }
  }
  provisioner "local-exec" {
    when        = destroy
    interpreter = ["pwsh", "-NoProfile", "-NonInteractive", "-Command"]
    command     = "& $env:KNOWLEDGE_CLEANUP -Knowledge ($env:KNOWLEDGE_CONTRACT | ConvertFrom-Json -AsHashtable -Depth 50 -DateKind String) -OutputDirectory $env:KNOWLEDGE_EVIDENCE -Confirm:$false"
    environment = {
      KNOWLEDGE_CLEANUP  = abspath("${path.module}/../../../infra/scripts/Remove-Knowledge.ps1")
      KNOWLEDGE_CONTRACT = jsonencode(self.input)
      KNOWLEDGE_EVIDENCE = abspath("${path.root}/out/knowledge-cleanup")
    }
  }
  depends_on = [
    azapi_data_plane_resource.knowledge_indexer,
    azurerm_storage_blob.document_seed,
    azurerm_storage_blob.knowledge_standard,
  ]
}

output "knowledge" {
  description = "Apply initializes both source indexers, the knowledge base and project connections; real Foundry evaluation is still required."
  value       = local.knowledge_contract
  depends_on  = [terraform_data.knowledge_initialize]
}
