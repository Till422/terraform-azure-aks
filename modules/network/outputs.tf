output "vnet_id" {
  description = "Resource-ID des VNet."
  value       = azurerm_virtual_network.main.id
}

output "vnet_name" {
  value = azurerm_virtual_network.main.name
}

output "subnet_ids" {
  description = "Map Subnetz-Name -> Resource-ID."
  value       = { for k, v in azurerm_subnet.this : k => v.id }
}
