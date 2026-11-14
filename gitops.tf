# GitOps with Flux (an AKS cluster extension). Flux pulls the manifests in
# gitops_path and applies them. Terraform passes the environment-specific values
# (identity client ID, tenant, vault name) as post-build substitutions, so the
# manifests in Git stay generic and contain no secrets.
resource "azurerm_kubernetes_cluster_extension" "flux" {
  count = local.gitops_enabled ? 1 : 0

  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.flux"
}

resource "azurerm_kubernetes_flux_configuration" "apps" {
  count = local.gitops_enabled ? 1 : 0

  name       = "apps"
  cluster_id = azurerm_kubernetes_cluster.this.id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url                      = var.gitops_repository_url
    reference_type           = "branch"
    reference_value          = var.gitops_branch
    sync_interval_in_seconds = 300
  }

  kustomizations {
    name                       = "apps"
    path                       = var.gitops_path
    sync_interval_in_seconds   = 300
    garbage_collection_enabled = true

    post_build {
      substitute = {
        WORKLOAD_CLIENT_ID = azurerm_user_assigned_identity.workload.client_id
        AZURE_TENANT_ID    = data.azurerm_client_config.current.tenant_id
        KEY_VAULT_NAME     = azurerm_key_vault.this.name
      }
    }
  }

  depends_on = [
    azurerm_kubernetes_cluster_extension.flux,
    azurerm_federated_identity_credential.workload,
  ]
}
