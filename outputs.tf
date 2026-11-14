output "cluster" {
  description = "Cluster name, ID and private API server FQDN."
  value = {
    id           = azurerm_kubernetes_cluster.this.id
    name         = azurerm_kubernetes_cluster.this.name
    private_fqdn = azurerm_kubernetes_cluster.this.private_fqdn
    oidc_issuer  = azurerm_kubernetes_cluster.this.oidc_issuer_url
    node_rg_name = azurerm_kubernetes_cluster.this.node_resource_group
  }
}

output "registry" {
  description = "Container registry (private; push from a VNet-connected runner)."
  value = {
    id           = azurerm_container_registry.this.id
    name         = azurerm_container_registry.this.name
    login_server = azurerm_container_registry.this.login_server
  }
}

output "key_vault" {
  description = "Key Vault the workload reads through the CSI driver."
  value = {
    id   = azurerm_key_vault.this.id
    name = azurerm_key_vault.this.name
  }
}

output "workload_identity" {
  description = "Values the Kubernetes manifests need (Flux substitutes them automatically when GitOps is on)."
  value = {
    client_id       = azurerm_user_assigned_identity.workload.client_id
    tenant_id       = data.azurerm_client_config.current.tenant_id
    namespace       = var.workload_identity.namespace
    service_account = var.workload_identity.service_account
  }
}
