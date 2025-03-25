terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=4.1.0" // Specify the AzureRM provider version
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {} // Enable all features for the AzureRM provider

  subscription_id = "00000000-0000-0000-0000000000" // Azure subscription ID
}

# since these variables are re-used - a locals block makes this more maintainable
locals {
  // Define reusable variables for resource names and configurations
  backend_address_pool_name      = "${azurerm_virtual_network.example.name}-beap"
  frontend_port_name_5000        = "${azurerm_virtual_network.example.name}-feport5000"
  frontend_port_name_5001        = "${azurerm_virtual_network.example.name}-feport5001"
  frontend_ip_configuration_name = "${azurerm_virtual_network.example.name}-feip"
  http_setting_name              = "${azurerm_virtual_network.example.name}-be-htst"
  listener_name_5000             = "${azurerm_virtual_network.example.name}-httplstn5000"
  listener_name_5001             = "${azurerm_virtual_network.example.name}-httplstn5001"
  request_routing_rule_name_5000 = "${azurerm_virtual_network.example.name}-rqrt5000"
  request_routing_rule_name_5001 = "${azurerm_virtual_network.example.name}-rqrt5001"
  redirect_configuration_name    = "${azurerm_virtual_network.example.name}-rdrcfg"
  resource_group_name            = "cosmin-rg"
  location                       = "Poland Central"
}

data "azurerm_client_config" "current" {
  // Fetch details of the current Azure client configuration
}

data "azuread_user" "current_user" {
  // Retrieve details of the current Azure Active Directory user
  object_id = data.azurerm_client_config.current.object_id
}

resource "azurerm_resource_group" "example" {
  // Create a resource group
  name     = local.resource_group_name
  location = local.location
  tags = {
    userCreated = data.azuread_user.current_user.user_principal_name // Tag with the creator's username
  }
}

resource "azurerm_role_assignment" "example" {
  // Assign the "Owner" role to the current user for the resource group
  depends_on = [ azurerm_resource_group.example ]
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Owner"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_user_assigned_identity" "example" {
  // Create a User Assigned Identity
  depends_on = [ azurerm_resource_group.example ]
  location            = local.location
  name                = "example-identity"
  resource_group_name = local.resource_group_name
}

resource "azurerm_role_assignment" "example2" {
  // Assign the "Owner" role to the User Assigned Identity for the resource group
  depends_on = [ azurerm_user_assigned_identity.example ]
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

resource "azurerm_virtual_network" "example" {
  // Create a virtual network
  depends_on = [ azurerm_resource_group.example ]
  name                = "example-network"
  resource_group_name = local.resource_group_name
  location            = local.location
  address_space       = ["10.254.0.0/16"] // Define the address space
}

resource "azurerm_public_ip" "example" {
  // Create a public IP address
  depends_on = [ azurerm_resource_group.example ]
  name                = "example-pip"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static" // Use a static IP
}

resource "azurerm_subnet" "example" {
  // Create a subnet within the virtual network
  depends_on = [ azurerm_virtual_network.example ]
  name                 = "example-subnet"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.254.0.0/24"] // Define the subnet address range
}

resource "azurerm_application_gateway" "example" {
  // Create an Application Gateway
  depends_on = [ azurerm_public_ip.example, azurerm_subnet.example, azurerm_user_assigned_identity.example, azurerm_role_assignment.example ]
  name                = "example-appgateway"
  resource_group_name = local.resource_group_name
  location            = local.location

  sku {
    name     = "Standard_v2" // Specify the SKU
    tier     = "Standard_v2"
    capacity = 2 // Number of instances
  }

  gateway_ip_configuration {
    // Configure the gateway's IP settings
    name      = "example-gateway-ip-configuration"
    subnet_id = azurerm_subnet.example.id
  }

  frontend_port {
    // Define a frontend port for HTTP traffic on port 5000
    name = local.frontend_port_name_5000
    port = 5000
  }

  frontend_port {
    // Define a frontend port for HTTP traffic on port 5001
    name = local.frontend_port_name_5001
    port = 5001
  }

  frontend_ip_configuration {
    // Configure the frontend IP with the public IP address
    name                 = local.frontend_ip_configuration_name
    public_ip_address_id = azurerm_public_ip.example.id
  }

  backend_address_pool {
    // Define a backend address pool
    name = local.backend_address_pool_name
  }

  backend_http_settings {
    // Configure backend HTTP settings
    name                  = local.http_setting_name
    cookie_based_affinity = "Disabled"
    path                  = "/path1/"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    // Create an HTTP listener for port 5000
    name                           = local.listener_name_5000
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name_5000
    protocol                       = "Http"
  }

  http_listener {
    // Create an HTTP listener for port 5001
    name                           = local.listener_name_5001
    frontend_ip_configuration_name = local.frontend_ip_configuration_name
    frontend_port_name             = local.frontend_port_name_5001
    protocol                       = "Http"
  }

  request_routing_rule {
    // Define a routing rule for port 5000
    name                       = local.request_routing_rule_name_5000
    priority                   = 9
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name_5000
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  request_routing_rule {
    // Define a routing rule for port 5001
    name                       = local.request_routing_rule_name_5001
    priority                   = 10
    rule_type                  = "Basic"
    http_listener_name         = local.listener_name_5001
    backend_address_pool_name  = local.backend_address_pool_name
    backend_http_settings_name = local.http_setting_name
  }

  identity {
    // Attach a User Assigned Identity to the Application Gateway
    type = "UserAssigned"
    identity_ids = [ azurerm_user_assigned_identity.example.id ]
  }
}

resource "azurerm_role_assignment" "example3" {
  // Assign the "Owner" role to the User Assigned Identity for the Application Gateway
  depends_on = [ azurerm_application_gateway.example ]
  scope                = azurerm_application_gateway.example.id
  role_definition_name = "Owner"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}

resource "azurerm_role_assignment" "example4" {
  // Assign the "Network Contributor" role to the User Assigned Identity for the Virtual Network
  depends_on = [ azurerm_application_gateway.example ]
  scope                = azurerm_virtual_network.example.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.example.principal_id
}