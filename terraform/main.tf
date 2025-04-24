terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }

  required_version = ">= 1.4.0"
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "rg_choco_dev" {
  name     = "rg-choco-dev"
  location = "West Europe"
}

# Virtual Network
resource "azurerm_virtual_network" "vnet_choco" {
  name                = "vnet-choco"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg_choco_dev.location
  resource_group_name = azurerm_resource_group.rg_choco_dev.name
}

# Subnet
resource "azurerm_subnet" "subnet_choco_01" {
  name                 = "subnet-choco-01"
  resource_group_name  = azurerm_resource_group.rg_choco_dev.name
  virtual_network_name = azurerm_virtual_network.vnet_choco.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Public IP
resource "azurerm_public_ip" "pip_choco" {
  name                = "pip-choco"
  location            = azurerm_resource_group.rg_choco_dev.location
  resource_group_name = azurerm_resource_group.rg_choco_dev.name
  allocation_method   = "Static"
  sku                 = "Basic"

  tags = {
    environment = "dev"
  }
}

# Network Interface
resource "azurerm_network_interface" "nic_choco" {
  name                = "nic-choco"
  location            = azurerm_resource_group.rg_choco_dev.location
  resource_group_name = azurerm_resource_group.rg_choco_dev.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet_choco_01.id
    private_ip_address_allocation = "Static"
    private_ip_address            = "10.0.2.10"
    public_ip_address_id          = azurerm_public_ip.pip_choco.id
  
  }
}

# Linux VM
resource "azurerm_linux_virtual_machine" "vm_linux_01" {
  name                = "vm-linux-01"
  resource_group_name = azurerm_resource_group.rg_choco_dev.name
  location            = azurerm_resource_group.rg_choco_dev.location
  size                = "Standard_B1s"
  admin_username      = "chocoadmin"

  network_interface_ids = [
    azurerm_network_interface.nic_choco.id,
  ]

  admin_ssh_key {
    username   = "chocoadmin"
    public_key = file("/terraform/.ssh/dusan.pub")
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  disable_password_authentication = true

}

# Output the public IP
output "vm_public_ip" {
  description = "Public IP of the VM"
  value       = azurerm_public_ip.pip_choco.ip_address
}

# NSG

resource "azurerm_network_security_group" "nsg_choco" {
  name                = "nsg-choco"
  location            = azurerm_resource_group.rg_choco_dev.location
  resource_group_name = azurerm_resource_group.rg_choco_dev.name

  security_rule {
    name                       = "AllowSSH"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowHTTP"
    priority                   = 1002
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "AllowKeycloak"
    priority                   = 1003
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8080"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "nsg_assoc_choco" {
  network_interface_id      = azurerm_network_interface.nic_choco.id
  network_security_group_id = azurerm_network_security_group.nsg_choco.id
}
