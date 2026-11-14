output "cluster" {
  description = "Cluster name and private API server FQDN."
  value       = module.aks.cluster
}

output "registry" {
  description = "Container registry login server."
  value       = module.aks.registry
}

output "key_vault" {
  description = "Key Vault the workload reads."
  value       = module.aks.key_vault
}

output "workload_identity" {
  description = "Workload identity values (substituted into the manifests by Flux)."
  value       = module.aks.workload_identity
}
