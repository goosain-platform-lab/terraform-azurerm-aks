#------------------------------------------------------------------------------
# Naming and placement
#------------------------------------------------------------------------------
variable "workload" {
  description = "Workload token used in resource names: <type>-<workload>-<environment>-<region>."
  type        = string
  default     = "apps"

  validation {
    condition     = can(regex("^[a-z0-9]{2,8}$", var.workload))
    error_message = "workload must be 2-8 lowercase letters or digits (it is also used in the registry name)."
  }
}

variable "environment" {
  description = "Environment token used in resource names."
  type        = string
  default     = "lab"
}

variable "location" {
  description = "Azure region for the cluster."
  type        = string
}

variable "unique_suffix" {
  description = "Optional 0-4 character suffix for globally unique names (registry, Key Vault)."
  type        = string
  default     = ""

  validation {
    condition     = can(regex("^[a-z0-9]{0,4}$", var.unique_suffix))
    error_message = "unique_suffix must be 0-4 lowercase letters or digits."
  }
}

variable "resource_group_name" {
  description = "Existing resource group for the cluster and its supporting resources."
  type        = string
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}

#------------------------------------------------------------------------------
# Network wiring
#------------------------------------------------------------------------------
variable "node_subnet_id" {
  description = "Subnet for the nodes. With Azure CNI Overlay, pods get IPs from pod_cidr, so a /27 holds up to about 25 nodes."
  type        = string
}

variable "private_endpoint_subnet_id" {
  description = "Subnet for the registry and Key Vault private endpoints."
  type        = string
}

variable "private_dns_zone_ids" {
  description = "Private DNS zone IDs. Required keys: acr (privatelink.azurecr.io), vault (privatelink.vaultcore.azure.net). Extra keys are ignored."
  type        = map(string)

  validation {
    condition     = alltrue([for k in ["acr", "vault"] : contains(keys(var.private_dns_zone_ids), k)])
    error_message = "private_dns_zone_ids must contain the keys acr and vault."
  }
}

variable "api_server_private_dns_zone_id" {
  description = "Private DNS zone for the private API server: \"System\" (AKS manages it) or the ID of a hub-owned privatelink.<region>.azmk8s.io zone."
  type        = string
  default     = "System"

  validation {
    condition     = var.api_server_private_dns_zone_id == "System" || can(regex("/privateDnsZones/", var.api_server_private_dns_zone_id))
    error_message = "Use \"System\" or a private DNS zone resource ID."
  }
}

variable "outbound_type" {
  description = "Egress path: loadBalancer (lab default) or userDefinedRouting (through a hub firewall via a route table on the node subnet)."
  type        = string
  default     = "loadBalancer"

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway"], var.outbound_type)
    error_message = "outbound_type must be loadBalancer, userDefinedRouting, managedNATGateway or userAssignedNATGateway."
  }
}

variable "pod_cidr" {
  description = "Overlay address range for pods (not routed outside the cluster)."
  type        = string
  default     = "192.168.0.0/16"
}

variable "service_cidr" {
  description = "Address range for Kubernetes services. Must not overlap the VNet or anything it is peered with."
  type        = string
  default     = "172.16.0.0/16"
}

variable "dns_service_ip" {
  description = "Cluster DNS service IP, inside service_cidr."
  type        = string
  default     = "172.16.0.10"
}

variable "log_analytics_workspace_id" {
  description = "Log Analytics workspace for Container Insights and control-plane logs."
  type        = string
}

#------------------------------------------------------------------------------
# Cluster (defaults are production-grade)
#------------------------------------------------------------------------------
variable "kubernetes_version" {
  description = "Kubernetes minor version, for example \"1.33\". Null takes the AKS default at creation; the patch channel keeps it current."
  type        = string
  default     = null
}

variable "sku_tier" {
  description = "Free, Standard (financially backed uptime SLA) or Premium (long-term support)."
  type        = string
  default     = "Standard"
}

variable "automatic_upgrade_channel" {
  description = "Cluster auto-upgrade channel: patch, stable, rapid or node-image."
  type        = string
  default     = "patch"
}

variable "node_os_upgrade_channel" {
  description = "Node OS upgrade channel: NodeImage, SecurityPatch, Unmanaged or None."
  type        = string
  default     = "NodeImage"
}

variable "availability_zones" {
  description = "Zones to spread node pools across. Empty for regions without zones."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_node_pool" {
  description = "System pool: runs only critical add-ons (tainted CriticalAddonsOnly). The VM size needs a local temp disk for the ephemeral OS disk (a \"d\" size)."
  type = object({
    vm_size   = optional(string, "Standard_D4ds_v5")
    min_count = optional(number, 3)
    max_count = optional(number, 5)
  })
  default = {}
}

variable "user_node_pool" {
  description = "User pool for application workloads."
  type = object({
    vm_size   = optional(string, "Standard_D4ds_v5")
    min_count = optional(number, 2)
    max_count = optional(number, 10)
  })
  default = {}
}

variable "admin_group_object_ids" {
  description = "Entra groups granted cluster admin (Azure RBAC for Kubernetes). Local accounts are disabled, so this is the way in."
  type        = list(string)
  default     = []
}

#------------------------------------------------------------------------------
# Supporting services
#------------------------------------------------------------------------------
variable "acr_retention_days" {
  description = "Days to keep untagged manifests in the registry."
  type        = number
  default     = 7
}

variable "key_vault_purge_protection_enabled" {
  description = "Key Vault purge protection (off for the lab so redeploys can reuse the name)."
  type        = bool
  default     = false
}

variable "workload_identity" {
  description = "Kubernetes service account that gets an Azure identity through workload identity federation."
  type = object({
    namespace       = optional(string, "demo")
    service_account = optional(string, "demo-app")
  })
  default = {}
}

#------------------------------------------------------------------------------
# GitOps (Flux)
#------------------------------------------------------------------------------
variable "gitops_repository_url" {
  description = "Public Git repository Flux reconciles from. Null skips the Flux extension and configuration."
  type        = string
  default     = null
}

variable "gitops_branch" {
  description = "Branch Flux tracks."
  type        = string
  default     = "main"
}

variable "gitops_path" {
  description = "Path to the kustomization Flux applies."
  type        = string
  default     = "./k8s/overlays/lab"
}
