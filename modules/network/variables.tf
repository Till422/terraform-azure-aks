variable "name_prefix" {
  type        = string
  description = "Praefix fuer alle Ressourcennamen, z. B. 'demo-dev'."

  validation {
    condition     = can(regex("^[a-z0-9-]{3,20}$", var.name_prefix))
    error_message = "Nur Kleinbuchstaben, Ziffern und Bindestriche, 3-20 Zeichen."
  }
}

variable "location" {
  type        = string
  description = "Azure-Region."
}

variable "resource_group_name" {
  type        = string
  description = "Name der Resource Group, in die deployt wird."
}

variable "address_space" {
  type        = list(string)
  description = "CIDR-Bloecke des VNet."
  default     = ["10.10.0.0/16"]
}

variable "subnets" {
  description = "Subnetze als Map. Key = Name, Wert = Konfiguration."
  type = map(object({
    address_prefix    = string
    service_endpoints = optional(list(string), [])
    delegation        = optional(string, null)
  }))

  validation {
    condition     = alltrue([for s in var.subnets : can(cidrnetmask(s.address_prefix))])
    error_message = "Jedes address_prefix muss ein gueltiger CIDR-Block sein."
  }
}

variable "tags" {
  type        = map(string)
  description = "Tags fuer alle Ressourcen."
  default     = {}
}
