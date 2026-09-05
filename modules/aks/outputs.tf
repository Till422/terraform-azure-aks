output "cluster_id" {
  value = azurerm_kubernetes_cluster.main.id
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.main.name
}

output "oidc_issuer_url" {
  description = "Fuer Federated Credentials der Workload Identity."
  value       = azurerm_kubernetes_cluster.main.oidc_issuer_url
}

output "kubelet_identity_object_id" {
  value = azurerm_kubernetes_cluster.main.kubelet_identity[0].object_id
}

output "node_resource_group" {
  description = "Von AKS verwaltete RG mit VMSS, Disks, LB."
  value       = azurerm_kubernetes_cluster.main.node_resource_group
}

output "kube_config_raw" {
  description = "kubeconfig. Sensibel - landet im State!"
  value       = azurerm_kubernetes_cluster.main.kube_config_raw
  sensitive   = true
}

output "get_credentials_command" {
  description = "Bevorzugt: kubeconfig ueber die CLI holen statt aus dem State."
  value       = "az aks get-credentials --resource-group ${var.resource_group_name} --name ${azurerm_kubernetes_cluster.main.name}"
}
