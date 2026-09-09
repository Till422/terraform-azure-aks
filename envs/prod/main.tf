# ---------------------------------------------------------------------------
# Umgebung: PROD
# Gleiche Module wie dev - andere Dimensionierung und Haertung.
# Unterschiede zu dev bewusst explizit statt via Bedingungslogik im Modul.
# ---------------------------------------------------------------------------

locals {
  tags = {
    Environment = "prod"
    Project     = "demo-platform"
    ManagedBy   = "terraform"
    Owner       = "platform-team"
    CostCenter  = "product"
    Criticality = "high"
  }
}

resource "azurerm_resource_group" "main" {
  name     = "rg-${var.name_prefix}"
  location = var.location
  tags     = local.tags

  lifecycle {
    prevent_destroy = true # Schutzschalter fuer Produktion
  }
}

module "network" {
  source = "../../modules/network"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.20.0.0/16"] # kein Overlap mit dev - Peering moeglich

  subnets = {
    aks = {
      address_prefix    = "10.20.0.0/21" # groesser: mehr Nodes
      service_endpoints = ["Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    }
    ingress = {
      address_prefix = "10.20.8.0/24"
    }
    data = {
      address_prefix    = "10.20.9.0/24"
      service_endpoints = ["Microsoft.Sql", "Microsoft.Storage"]
    }
  }

  tags = local.tags
}

resource "azurerm_log_analytics_workspace" "main" {
  name                = "log-${var.name_prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 90 # laengere Aufbewahrung fuer Audits
  tags                = local.tags
}

resource "azurerm_container_registry" "main" {
  name                = replace("acr${var.name_prefix}", "-", "")
  resource_group_name = azurerm_resource_group.main.name
  location            = var.location
  sku                 = "Premium" # Geo-Replikation, Private Endpoints moeglich
  admin_enabled       = false
  tags                = local.tags

  retention_policy_in_days = 30
  trust_policy_enabled     = true # nur signierte Images
}

module "aks" {
  source = "../../modules/aks"

  name_prefix         = var.name_prefix
  location            = var.location
  resource_group_name = azurerm_resource_group.main.name
  subnet_id           = module.network.subnet_ids["aks"]
  kubernetes_version  = var.kubernetes_version
  sku_tier            = "Standard" # 99,95 % SLA fuer die Control Plane

  default_node_pool = {
    vm_size    = "Standard_D4s_v5" # 4 vCPU, 16 GB
    min_count  = 3                 # ueber Availability Zones verteilt
    max_count  = 5
    os_disk_gb = 128
  }

  user_node_pools = {
    apps = {
      vm_size     = "Standard_D4s_v5"
      min_count   = 3
      max_count   = 12
      node_labels = { workload = "apps" }
    }
    batch = {
      vm_size     = "Standard_D8s_v5"
      min_count   = 0 # skaliert auf null, wenn keine Jobs laufen
      max_count   = 6
      spot        = true
      node_labels = { workload = "batch" }
      node_taints = ["workload=batch:NoSchedule"]
    }
  }

  acr_id                     = azurerm_container_registry.main.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  admin_group_object_ids     = var.admin_group_object_ids
  tags                       = local.tags
}
