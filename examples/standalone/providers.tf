# Authentication comes from the environment: HCP Terraform dynamic credentials
# (OIDC) or `az login` locally. ARM_SUBSCRIPTION_ID selects the subscription.
provider "azurerm" {
  storage_use_azuread = true

  # azurerm 5.x registers nothing by default; register only what this needs.
  resource_providers_to_register = [
    "Microsoft.ContainerRegistry",
    "Microsoft.ContainerService",
    "Microsoft.Insights",
    "Microsoft.KeyVault",
    "Microsoft.KubernetesConfiguration",
    "Microsoft.ManagedIdentity",
    "Microsoft.Network",
    "Microsoft.OperationalInsights",
    "Microsoft.OperationsManagement",
    "Microsoft.PolicyInsights",
  ]

  features {
    key_vault {
      purge_soft_delete_on_destroy    = true
      recover_soft_deleted_key_vaults = true
    }

    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
