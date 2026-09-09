terraform {
  required_version = "~> 1.9"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  # Werte aus dem bootstrap-Output eintragen.
  # storage_account_name ist zufaellig - deshalb Platzhalter.
  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "REPLACE_ME"
    container_name       = "tfstate"
    key                  = "prod.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {
    resource_group {
      # Schutz vor versehentlichem Loeschen nicht-leerer Gruppen.
      prevent_deletion_if_contains_resources = true
    }
  }
}
