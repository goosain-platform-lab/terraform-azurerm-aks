# Three user-assigned identities, each with one job:
#   cp       - the cluster control plane (manages networking and the kubelet identity)
#   kubelet  - the nodes (pulls images from the registry)
#   workload - an application pod, through workload identity federation
resource "azurerm_user_assigned_identity" "cp" {
  name                = local.names.identity_cp
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "kubelet" {
  name                = local.names.identity_kubelet
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_user_assigned_identity" "workload" {
  name                = local.names.identity_workload
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Control plane: join the node subnet and assign the kubelet identity to nodes.
resource "azurerm_role_assignment" "cp_network" {
  scope                = var.node_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cp.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cp_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.cp.principal_id
  principal_type       = "ServicePrincipal"
}

# Only when the API server's private DNS zone is hub-owned rather than managed by AKS.
resource "azurerm_role_assignment" "cp_private_dns" {
  count = local.custom_api_dns_zone ? 1 : 0

  scope                = var.api_server_private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.cp.principal_id
  principal_type       = "ServicePrincipal"
}

# Nodes pull images with their own identity: no registry admin user or pull secret.
resource "azurerm_role_assignment" "kubelet_acr_pull" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type       = "ServicePrincipal"
}

# Workload identity: pods using the federated service account read Key Vault
# secrets as this identity. No client secret exists anywhere.
resource "azurerm_federated_identity_credential" "workload" {
  name                      = "fic-${var.workload_identity.namespace}-${var.workload_identity.service_account}"
  user_assigned_identity_id = azurerm_user_assigned_identity.workload.id
  audience                  = ["api://AzureADTokenExchange"]
  issuer                    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject                   = "system:serviceaccount:${var.workload_identity.namespace}:${var.workload_identity.service_account}"
}

resource "azurerm_role_assignment" "workload_kv" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.workload.principal_id
  principal_type       = "ServicePrincipal"
}

# Cluster access for the admin groups (Azure RBAC for Kubernetes).
locals {
  admin_assignments = {
    for pair in setproduct(var.admin_group_object_ids, [
      "Azure Kubernetes Service RBAC Cluster Admin",
      "Azure Kubernetes Service Cluster User Role",
    ]) : "${pair[0]}|${pair[1]}" => { principal = pair[0], role = pair[1] }
  }
}

resource "azurerm_role_assignment" "admins" {
  for_each = local.admin_assignments

  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = each.value.role
  principal_id         = each.value.principal
  principal_type       = "Group"
}
