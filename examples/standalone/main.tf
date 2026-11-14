# Standalone private AKS deployment: a small spoke network, private DNS,
# Log Analytics, then the AKS module with GitOps pointed at this repo's
# k8s/overlays/lab folder.
locals {
  region = lookup({
    southafricanorth = "zan"
    southafricawest  = "zaw"
    westeurope       = "weu"
    northeurope      = "neu"
    swedencentral    = "sdc"
    uksouth          = "uks"
  }, var.location, var.location)

  suffix = "${var.environment}-${local.region}${var.unique_suffix}"

  tags = merge({
    workload    = "aks"
    environment = var.environment
    managed_by  = "terraform"
    repo        = "terraform-azurerm-aks"
  }, var.tags)

  subnets = {
    nodes = cidrsubnet(var.address_space, 2, 0) # /24 nodes (pods use the overlay range)
    pe    = cidrsubnet(var.address_space, 5, 8) # /27 private endpoints
  }

  private_dns_zones = {
    acr   = "privatelink.azurecr.io"
    vault = "privatelink.vaultcore.azure.net"
  }
}

resource "azurerm_resource_group" "network" {
  name     = "rg-aks-network-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_resource_group" "workload" {
  name     = "rg-aks-${local.suffix}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_log_analytics_workspace" "this" {
  name                         = "log-aks-${local.suffix}"
  location                     = var.location
  resource_group_name          = azurerm_resource_group.workload.name
  sku                          = "PerGB2018"
  retention_in_days            = var.log_retention_days
  daily_quota_gb               = var.log_daily_quota_gb
  local_authentication_enabled = false
  tags                         = local.tags
}

resource "azurerm_virtual_network" "this" {
  name                = "vnet-aks-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-aks-nodes-${local.suffix}"
  resource_group_name  = azurerm_resource_group.network.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.subnets.nodes]
}

resource "azurerm_subnet" "pe" {
  name                            = "snet-aks-pe-${local.suffix}"
  resource_group_name             = azurerm_resource_group.network.name
  virtual_network_name            = azurerm_virtual_network.this.name
  address_prefixes                = [local.subnets.pe]
  default_outbound_access_enabled = false
}

resource "azurerm_network_security_group" "this" {
  for_each = local.subnets

  name                = "nsg-aks-${each.key}-${local.suffix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.this["nodes"].id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.this["pe"].id
}

resource "azurerm_private_dns_zone" "this" {
  for_each = local.private_dns_zones

  name                = each.value
  resource_group_name = azurerm_resource_group.network.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each = local.private_dns_zones

  name                 = "link-${each.key}-${local.suffix}"
  private_dns_zone_id  = azurerm_private_dns_zone.this[each.key].id
  virtual_network_id   = azurerm_virtual_network.this.id
  registration_enabled = false
  tags                 = local.tags
}

module "aks" {
  source = "../../"

  environment         = var.environment
  location            = var.location
  unique_suffix       = var.unique_suffix
  resource_group_name = azurerm_resource_group.workload.name
  tags                = local.tags

  node_subnet_id             = azurerm_subnet.nodes.id
  private_endpoint_subnet_id = azurerm_subnet.pe.id
  private_dns_zone_ids       = { for k, z in azurerm_private_dns_zone.this : k => z.id }
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  admin_group_object_ids = var.admin_group_object_ids
  gitops_repository_url  = var.gitops_repository_url

  depends_on = [
    azurerm_private_dns_zone_virtual_network_link.this,
    azurerm_subnet_network_security_group_association.nodes,
    azurerm_subnet_network_security_group_association.pe,
  ]
}
