data "azurerm_client_config" "current" {}

locals {
  region_codes = {
    southafricanorth   = "zan"
    southafricawest    = "zaw"
    westeurope         = "weu"
    northeurope        = "neu"
    swedencentral      = "sdc"
    uksouth            = "uks"
    francecentral      = "frc"
    germanywestcentral = "gwc"
    switzerlandnorth   = "szn"
    eastus             = "eus"
    eastus2            = "eus2"
  }

  region = lookup(local.region_codes, var.location, var.location)

  # <type>-<workload>-<environment>-<region>[suffix]
  base = "${var.workload}-${var.environment}-${local.region}${var.unique_suffix}"

  names = {
    cluster           = "aks-${local.base}"
    node_rg           = "rg-${var.workload}-nodes-${var.environment}-${local.region}${var.unique_suffix}"
    identity_cp       = "id-${var.workload}-cp-${var.environment}-${local.region}${var.unique_suffix}"
    identity_kubelet  = "id-${var.workload}-kubelet-${var.environment}-${local.region}${var.unique_suffix}"
    identity_workload = "id-${var.workload}-workload-${var.environment}-${local.region}${var.unique_suffix}"
    # Registry names: letters and digits only, 5-50 characters.
    registry  = "cr${var.workload}${var.environment}${local.region}${var.unique_suffix}"
    key_vault = "kv-${local.base}"
  }

  custom_api_dns_zone = var.api_server_private_dns_zone_id != "System"
  gitops_enabled      = var.gitops_repository_url != null
  zones               = length(var.availability_zones) > 0 ? var.availability_zones : null
}
