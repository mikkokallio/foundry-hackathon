resource "azurerm_storage_container" "documents" {
  name                  = var.workload_name
  storage_account_id    = var.foundation.storage_id
  container_access_type = "private"
  depends_on            = [terraform_data.boundary]
}

resource "azurerm_role_assignment" "operator_document_seed" {
  scope                = "${var.foundation.storage_id}/blobServices/default/containers/${azurerm_storage_container.documents.name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_storage_blob" "document_seed" {
  for_each               = fileset("${path.module}/../data/docs", "*.md")
  name                   = "published/${each.key}"
  storage_account_name   = var.foundation.storage_name
  storage_container_name = azurerm_storage_container.documents.name
  type                   = "Block"
  content_type           = "text/markdown; charset=utf-8"
  source_content         = file("${path.module}/../data/docs/${each.key}")
  depends_on             = [azurerm_role_assignment.operator_document_seed]
  timeouts { create = "10m" }
  lifecycle {
    # Published workshop edits belong to the librarian, not subsequent applies.
    ignore_changes = [source_content, content_md5]
  }
}

output "document_container" {
  value = azurerm_storage_container.documents.name
}
