variable "name_prefix" {
  type        = string
  description = "Praefix fuer Ressourcennamen."
}

variable "location" {
  type = string
}

variable "resource_group_name" {
  type = string
}

variable "subnet_id" {
  type        = string
  description = "Subnetz fuer die Node Pools."
}

variable "kubernetes_version" {
  type        = string
  description = "AKS-Version, z. B. '1.32'."

  validation {
    condition     = can(regex("^1[.](3[0-9])$", var.kubernetes_version))
    error_message = "Nur Kubernetes 1.30 oder neuer (Format '1.32')."
  }
}

variable "sku_tier" {
  type        = string
  default     = "Free"
  description = "Free (kein SLA, dev) oder Standard (99,95 % SLA, prod)."

  validation {
    condition     = contains(["Free", "Standard"], var.sku_tier)
    error_message = "sku_tier muss 'Free' oder 'Standard' sein."
  }
}

variable "default_node_pool" {
  description = "System-Node-Pool. Traegt die Cluster-Komponenten."
  type = object({
    vm_size    = string
    min_count  = number
    max_count  = number
    os_disk_gb = optional(number, 64)
  })

  validation {
    condition     = var.default_node_pool.min_count >= 1
    error_message = "Der System-Pool braucht mindestens einen Node."
  }

  validation {
    condition     = var.default_node_pool.max_count >= var.default_node_pool.min_count
    error_message = "max_count darf nicht kleiner als min_count sein."
  }
}

variable "user_node_pools" {
  description = "Zusaetzliche Node Pools fuer Workloads. Key = Pool-Name."
  type = map(object({
    vm_size     = string
    min_count   = number
    max_count   = number
    node_labels = optional(map(string), {})
    node_taints = optional(list(string), [])
    spot        = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.user_node_pools) : can(regex("^[a-z][a-z0-9]{0,11}$", k))])
    error_message = "Node-Pool-Namen: Kleinbuchstaben/Ziffern, max. 12 Zeichen, Start mit Buchstabe."
  }
}

variable "admin_group_object_ids" {
  type        = list(string)
  description = "Entra-ID-Gruppen mit Cluster-Admin-Rechten. Leer = nur lokale Konten."
  default     = []
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Workspace fuer Container Insights. null = Monitoring aus."
  default     = null
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "acr_id" {
  type        = string
  description = "Resource-ID der Container Registry. null = keine Anbindung."
  default     = null
}

variable "attach_acr" {
  type        = bool
  default     = false
  description = <<-EOT
    Ob dem Cluster die Rolle AcrPull auf var.acr_id gegeben wird.

    Bewusst eine eigene Variable statt "acr_id != null": count und for_each
    muessen zur Planzeit aufloesbar sein. Eine ID, die erst beim Apply
    entsteht, ist es nicht - Terraform bricht sonst mit
    "Invalid count argument" ab.
  EOT
}
