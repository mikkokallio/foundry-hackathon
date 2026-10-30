data "azurerm_client_config" "current" {}

resource "terraform_data" "boundary" {
  lifecycle {
    precondition {
      condition = (
        data.azurerm_client_config.current.subscription_id == var.foundation.subscription_id &&
        data.azurerm_client_config.current.tenant_id == var.foundation.tenant_id &&
        startswith(var.foundation.foundry_id, "/subscriptions/${var.foundation.subscription_id}/")
      )
      error_message = "The workload must use the authenticated, explicitly selected foundation boundary."
    }
    precondition {
      condition     = timecmp(var.foundation.tags["expires-on"], plantimestamp()) > 0
      error_message = "The foundation's spending authorization has expired."
    }
  }
}
