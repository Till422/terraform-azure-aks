# ---------------------------------------------------------------------------
# Netzwerk-Fundament: VNet, Subnetze, NSG.
# Bewusst eigener State-Bereich: aendert sich selten, grosser Blast Radius.
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

resource "azurerm_virtual_network" "main" {
  name                = "vnet-${var.name_prefix}"
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  tags                = var.tags
}

# for_each statt count: Loeschen eines Subnetzes zerstoert nur dieses,
# nicht alle nachfolgenden (Index-Shift-Problem).
resource "azurerm_subnet" "this" {
  for_each = var.subnets

  name                 = "snet-${each.key}"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = each.value.service_endpoints

  dynamic "delegation" {
    for_each = each.value.delegation != null ? [each.value.delegation] : []

    content {
      name = "delegation"
      service_delegation {
        name = delegation.value
      }
    }
  }
}

resource "azurerm_network_security_group" "this" {
  for_each = var.subnets

  name                = "nsg-${var.name_prefix}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  # Default-Deny fuer eingehenden Internetverkehr.
  # Azure erlaubt implizit VNet-intern und LoadBalancer-Probes.
  security_rule {
    name                       = "DenyAllInboundFromInternet"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each = var.subnets

  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = azurerm_network_security_group.this[each.key].id
}
