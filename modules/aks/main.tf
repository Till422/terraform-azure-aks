# ---------------------------------------------------------------------------
# AKS-Cluster mit:
#   - Workload Identity (OIDC) statt Secrets in Pods
#   - Azure CNI Overlay (spart IP-Adressen gegenueber klassischem CNI)
#   - Autoscaling auf System- und User-Pools
#   - Entra-ID-RBAC, lokale Admin-Konten deaktiviert
#   - Key Vault CSI Driver fuer Secret-Injection
# ---------------------------------------------------------------------------

terraform {
  required_version = "~> 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

resource "azurerm_user_assigned_identity" "aks" {
  name                = "id-aks-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "aks-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = var.name_prefix
  kubernetes_version  = var.kubernetes_version
  sku_tier            = var.sku_tier
  tags                = var.tags

  # Nur Patch-Versionen automatisch, keine Minor-Spruenge.
  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Workload Identity: Pods holen Azure-Token per OIDC,
  # keine Client Secrets im Cluster.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Secrets aus dem Key Vault als Volume in den Pod.
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.default_node_pool.vm_size
    vnet_subnet_id               = var.subnet_id
    os_disk_size_gb              = var.default_node_pool.os_disk_gb
    auto_scaling_enabled         = true
    min_count                    = var.default_node_pool.min_count
    max_count                    = var.default_node_pool.max_count
    max_pods                     = 50
    only_critical_addons_enabled = true # System-Pool bleibt Workloads vorbehalten

    upgrade_settings {
      max_surge = "33%"
    }
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay" # Pod-IPs ausserhalb des VNet-Adressraums
    network_policy      = "cilium"
    network_data_plane  = "cilium"
    load_balancer_sku   = "standard"
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
    outbound_type       = "loadBalancer"
  }

  # Entra-ID-RBAC; lokale kubeconfig-Konten aus.
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }
  local_account_disabled = length(var.admin_group_object_ids) > 0

  # Monitoring nur, wenn ein Workspace uebergeben wurde.
  dynamic "oms_agent" {
    for_each = var.log_analytics_workspace_id != null ? [1] : []

    content {
      log_analytics_workspace_id      = var.log_analytics_workspace_id
      msi_auth_for_monitoring_enabled = true
    }
  }

  lifecycle {
    ignore_changes = [
      # Der Autoscaler aendert node_count zur Laufzeit -
      # Terraform soll das nicht zurueckdrehen.
      default_node_pool[0].node_count,
    ]
  }
}

# Ein Block, beliebig viele Pools - dank for_each.
resource "azurerm_kubernetes_cluster_node_pool" "user" {
  for_each = var.user_node_pools

  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  vnet_subnet_id        = var.subnet_id
  auto_scaling_enabled  = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints
  tags                  = var.tags

  # Spot-Instanzen: bis zu 90 % guenstiger, koennen entzogen werden.
  priority        = each.value.spot ? "Spot" : "Regular"
  eviction_policy = each.value.spot ? "Delete" : null
  spot_max_price  = each.value.spot ? -1 : null # -1 = bis zum On-Demand-Preis

  lifecycle {
    ignore_changes = [node_count]
  }
}

# Der Cluster darf Images aus der eigenen Registry ziehen -
# ohne imagePullSecrets im Cluster.
resource "azurerm_role_assignment" "acr_pull" {
  count = var.attach_acr ? 1 : 0

  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}
