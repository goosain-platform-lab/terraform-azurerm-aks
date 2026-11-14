variable "location" {
  description = "Azure region for the deployment."
  type        = string
  default     = "southafricanorth"
}

variable "environment" {
  description = "Environment token used in names."
  type        = string
  default     = "lab"
}

variable "unique_suffix" {
  description = "Optional 0-4 character suffix for globally unique names."
  type        = string
  default     = ""
}

variable "address_space" {
  description = "VNet address space (/22: a /24 for nodes and a /27 for private endpoints)."
  type        = string
  default     = "10.40.0.0/22"
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap in GB (-1 for no cap)."
  type        = number
  default     = 2
}

variable "admin_group_object_ids" {
  description = "Entra groups granted cluster admin."
  type        = list(string)
  default     = []
}

variable "gitops_repository_url" {
  description = "Repository Flux reconciles from. Null turns GitOps off."
  type        = string
  default     = "https://github.com/goosain-platform-lab/terraform-azurerm-aks"
}

variable "tags" {
  description = "Extra tags merged onto the defaults."
  type        = map(string)
  default     = {}
}
