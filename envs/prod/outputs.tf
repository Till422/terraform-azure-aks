output "resource_group" {
  value = azurerm_resource_group.main.name
}

output "cluster_name" {
  value = module.aks.cluster_name
}

output "acr_login_server" {
  value = azurerm_container_registry.main.login_server
}

output "oidc_issuer_url" {
  value = module.aks.oidc_issuer_url
}

output "next_step" {
  value = module.aks.get_credentials_command
}
