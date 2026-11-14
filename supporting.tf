#------------------------------------------------------------------------------
# Container registry: Premium for private endpoints. No admin user, no
# anonymous pull, no public access; nodes pull with the kubelet identity.
#------------------------------------------------------------------------------
resource "azurerm_container_registry" "this" {
  name                          = local.names.registry
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = "Premium"
  admin_enabled                 = false
  anonymous_pull_enabled        = false
  public_network_access_enabled = false
  export_policy_enabled         = false
  network_rule_bypass_option    = "AzureServices"
  data_endpoint_enabled         = true
  zone_redundancy_enabled       = length(var.availability_zones) > 0
  retention_policy_in_days      = var.acr_retention_days
  tags                          = var.tags
}

#------------------------------------------------------------------------------
# Key Vault for application secrets, read by pods through the CSI driver.
#------------------------------------------------------------------------------
resource "azurerm_key_vault" "this" {
  name                          = local.names.key_vault
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = var.key_vault_purge_protection_enabled
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
}

#------------------------------------------------------------------------------
# Private endpoints
#------------------------------------------------------------------------------
locals {
  private_endpoints = {
    acr = {
      resource_id = azurerm_container_registry.this.id
      subresource = "registry"
      dns_zone    = "acr"
    }
    kv = {
      resource_id = azurerm_key_vault.this.id
      subresource = "vault"
      dns_zone    = "vault"
    }
  }
}

resource "azurerm_private_endpoint" "this" {
  for_each = local.private_endpoints

  name                          = "pe-${each.key}-${local.base}"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  subnet_id                     = var.private_endpoint_subnet_id
  custom_network_interface_name = "nic-pe-${each.key}-${local.base}"
  tags                          = var.tags

  private_service_connection {
    name                           = "psc-${each.key}-${local.base}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [var.private_dns_zone_ids[each.value.dns_zone]]
  }
}

#------------------------------------------------------------------------------
# Control-plane audit and diagnostics to Log Analytics
#------------------------------------------------------------------------------
resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = {
    cluster   = azurerm_kubernetes_cluster.this.id
    registry  = azurerm_container_registry.this.id
    key_vault = azurerm_key_vault.this.id
  }

  name                       = "diag-to-law"
  target_resource_id         = each.value
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
