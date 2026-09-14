# ---------------------------------------------------------------------------
# Bootstrap: erzeugt das Remote-Backend fuer den State.
# Henne-Ei-Problem: Dieser Code laeuft EINMALIG mit lokalem State,
# danach wird sein eigener State per "terraform init -migrate-state" umgezogen.
# ---------------------------------------------------------------------------

terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }
  }
}

provider "azurerm" {
  features {}

  # Datenebene des Storage ueber Entra ID ansprechen statt ueber Account-Keys.
  # Zwingend, weil unten shared_access_key_enabled = false gesetzt ist -
  # sonst scheitert schon das Anlegen des Containers mit HTTP 403.
  storage_use_azuread = true
}

variable "location" {
  type        = string
  default     = "germanywestcentral"
  description = "Azure-Region. Frankfurt-naeher Standort fuer DE-Workloads."
}

resource "random_string" "suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_resource_group" "tfstate" {
  name     = "rg-tfstate"
  location = var.location

  tags = {
    Purpose   = "terraform-backend"
    ManagedBy = "terraform"
  }
}

resource "azurerm_storage_account" "tfstate" {
  name                = "sttfstate${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location

  account_tier             = "Standard"
  account_replication_type = "GRS" # georedundant: State ist kritisch
  min_tls_version          = "TLS1_2"

  # Haerten: kein anonymer Zugriff, kein Shared Key
  allow_nested_items_to_be_public = false
  shared_access_key_enabled       = false # erzwingt Entra-ID-Auth
  public_network_access_enabled   = true  # Uebung; produktiv: Private Endpoint

  blob_properties {
    versioning_enabled = true # State-Historie fuer Notfaelle

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = azurerm_resource_group.tfstate.tags
}

# Der ausfuehrende Benutzer braucht Rechte auf der Datenebene,
# da shared_access_key_enabled = false gesetzt ist.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "tfstate_contributor" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# Rollenzuweisungen brauchen in Entra ID bis zu einigen Minuten, bis sie
# auf der Datenebene wirksam sind. Ohne diese Wartezeit scheitert das
# Anlegen des Containers mit HTTP 403 - ein klassischer Wettlauf.
resource "time_sleep" "rbac_propagation" {
  depends_on      = [azurerm_role_assignment.tfstate_contributor]
  create_duration = "90s"
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"

  depends_on = [time_sleep.rbac_propagation]
}

output "backend_config" {
  description = "In envs/*/backend.tf eintragen."
  value       = <<-EOT

    terraform {
      backend "azurerm" {
        resource_group_name  = "${azurerm_resource_group.tfstate.name}"
        storage_account_name = "${azurerm_storage_account.tfstate.name}"
        container_name       = "${azurerm_storage_container.tfstate.name}"
        key                  = "<env>.tfstate"
        use_azuread_auth     = true
      }
    }
  EOT
}

output "storage_account_name" {
  description = "Name des erzeugten Storage Accounts."
  value       = azurerm_storage_account.tfstate.name
}
