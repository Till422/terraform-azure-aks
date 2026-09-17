# ---------------------------------------------------------------------------
# Umgebung: DEV
# Kostenoptimiert - kleiner Node, Free-SKU, ein einzelner Spot-Pool.
# ---------------------------------------------------------------------------

locals {
  tags = {
    Environment = "dev"
    Project     = "demo-platform"
    ManagedBy   = "terraform"
    Owner       = "platform-team"
    CostCenter  = "internal"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = local.tags
}

module "network" {
  source = "../../modules/network"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.10.0.0/16"]

  subnets = {
    aks = {
      address_prefix    = "10.10.0.0/22" # 1.022 nutzbare IPs fuer Nodes
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    }
    ingress = {
      address_prefix = "10.10.4.0/24"
    }
  }

  tags = local.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30 # dev: Minimum, spart Kosten
  tags                = local.tags
}

resource "azurerm_container_registry" "main" {
  name                = replace("acr${var.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Basic"
  admin_enabled       = false # kein Admin-Passwort, nur RBAC
  tags                = local.tags
}

module "aks" {
  source = "../../modules/aks"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.subnet_ids["aks"]
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Free" # dev braucht kein SLA

  default_node_pool = {
    vm_size    = "Standard_D2as_v6" # 2 vCPU, 8 GB - Familie mit Kontingent
    min_count  = 1
    max_count  = 2
    os_disk_gb = 32
  }

  user_node_pools = {
    apps = {
      vm_size   = "Standard_D2als_v6" # 2 vCPU, 4 GB
      min_count = 1
      max_count = 3
      # Spot vorerst aus: das Low-Priority-Kontingent des Abos ist knapp
      # (3 vCPUs). Wieder einschalten, sobald der Cluster einmal steht.
      spot        = false
      node_labels = { workload = "apps" }
    }
  }

  acr_id                     = azurerm_container_registry.main.id
  attach_acr                 = true
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  admin_group_object_ids     = var.admin_group_object_ids
  tags                       = local.tags
}

# ---------------------------------------------------------------------------
# Zugriff auf die Datenebene des Clusters.
#
# Mit azure_rbac_enabled = true prueft AKS jede kubectl-Anfrage gegen Entra ID.
# Besitzerrechte auf dem Abonnement genuegen dafuer NICHT - die Datenebene
# verlangt eine eigene Rollenzuweisung. Ohne sie antwortet der Cluster auf
# jedes kubectl mit "Forbidden ... User does not have access to the resource".
#
# Bewusst hier und nicht von Hand gesetzt: Was per Klick entsteht, ist beim
# naechsten Aufbau wieder weg.
# ---------------------------------------------------------------------------
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "aks_cluster_admin" {
  scope                = module.aks.cluster_id
  role_definition_name = "Azure Kubernetes Service RBAC Cluster Admin"
  principal_id         = data.azurerm_client_config.current.object_id
}
