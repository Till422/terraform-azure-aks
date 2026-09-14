variable "location" {
  type    = string
  default = "germanywestcentral"
}

variable "name_prefix" {
  type    = string
  default = "demo-dev"
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}

variable "admin_group_object_ids" {
  type        = list(string)
  description = "Entra-ID-Gruppen-Objekt-IDs mit Cluster-Admin-Rechten."
  default     = []
}
