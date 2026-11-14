# Private AKS cluster:
# - API server reachable only from the VNet (and anything peered/linked to it)
# - Entra ID sign-in with Azure RBAC; local (certificate) accounts disabled
# - Azure CNI Overlay with the Cilium data plane and network policies
# - Workload identity, Key Vault CSI driver, Azure Policy, Container Insights
# - Automatic patch upgrades and node image updates in maintenance windows
resource "azurerm_kubernetes_cluster" "this" {
  name                = local.names.cluster
  location            = var.location
  resource_group_name = var.resource_group_name
  node_resource_group = local.names.node_rg
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  # A hub-owned API server zone needs the private-cluster prefix.
  dns_prefix                 = local.custom_api_dns_zone ? null : local.names.cluster
  dns_prefix_private_cluster = local.custom_api_dns_zone ? local.names.cluster : null

  private_cluster_enabled             = true
  private_dns_zone_id                 = var.api_server_private_dns_zone_id
  private_cluster_public_fqdn_enabled = false

  local_account_disabled            = true
  role_based_access_control_enabled = true
  oidc_issuer_enabled               = true
  workload_identity_enabled         = true
  azure_policy_enabled              = true
  image_cleaner_enabled             = true
  image_cleaner_interval_hours      = 48
  run_command_enabled               = false

  automatic_upgrade_channel = var.automatic_upgrade_channel
  node_os_upgrade_channel   = var.node_os_upgrade_channel

  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cp.id]
  }

  kubelet_identity {
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
  }

  node_provisioning_profile {
    mode = "Manual"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_node_pool.vm_size
    vnet_subnet_id               = var.node_subnet_id
    zones                        = local.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_node_pool.min_count
    max_count                    = var.system_node_pool.max_count
    only_critical_addons_enabled = true
    os_sku                       = "AzureLinux"
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 100
    max_pods                     = 110
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = var.dns_service_ip
    outbound_type       = var.outbound_type
    load_balancer_sku   = "standard"
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "+02:00"
  }

  maintenance_window_node_os {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Saturday"
    start_time  = "02:00"
    utc_offset  = "+02:00"
  }

  depends_on = [
    azurerm_role_assignment.cp_network,
    azurerm_role_assignment.cp_kubelet_operator,
    azurerm_role_assignment.cp_private_dns,
  ]

  lifecycle {
    # The autoscaler owns the node count.
    ignore_changes = [default_node_pool[0].node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                  = "user"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  mode                  = "User"
  vm_size               = var.user_node_pool.vm_size
  vnet_subnet_id        = var.node_subnet_id
  zones                 = local.zones
  auto_scaling_enabled  = true
  min_count             = var.user_node_pool.min_count
  max_count             = var.user_node_pool.max_count
  os_sku                = "AzureLinux"
  os_disk_type          = "Ephemeral"
  os_disk_size_gb       = 100
  max_pods              = 110
  tags                  = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}
