terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=3.0.0"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
    subscription_id = ""
    tenant_id = ""
    client_id = ""
    client_secret = ""
  features {}
}

# Create a resource group
resource "azurerm_resource_group" "rg-demo" {
  name     = "rg-demo"
  location = "East US"
}
# Create a virtual network within the resource group
resource "azurerm_virtual_network" "vnet-demo" {
  name                = "vnet-demo"
  resource_group_name = azurerm_resource_group.rg-demo.name
  location            = azurerm_resource_group.rg-demo.location
  address_space       = ["10.0.0.0/24"]
  depends_on = [ azurerm_resource_group.rg-demo ]
}

# Create subnet in the virtual network within the resource group
resource "azurerm_subnet" "subnet-demo" {
  name                 = "subnet-demo"
  resource_group_name  = azurerm_resource_group.rg-demo.name
  virtual_network_name = azurerm_virtual_network.vnet-demo.name
  address_prefixes     = ["10.0.0.0/28"]
  depends_on = [ azurerm_virtual_network.vnet-demo ]
}

# create storage account
resource "azurerm_storage_account" "jinstoragesample" {
  name                     = "jinstoragesample"
  resource_group_name      = azurerm_resource_group.rg-demo.name
  location                 = azurerm_resource_group.rg-demo.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  depends_on = [ azurerm_resource_group.rg-demo ]

  tags = {
    environment = "staging"
  }
}
# container
resource "azurerm_storage_container" "democontainer" {
  name                  = "democontainer"
  storage_account_name  = azurerm_storage_account.jinstoragesample.name
  container_access_type = "blob"
  depends_on = [ azurerm_storage_account.jinstoragesample ]
}
resource "azurerm_storage_blob" "test1" {
  name                   = "test1.txt"
  storage_account_name   = azurerm_storage_account.jinstoragesample.name
  storage_container_name = azurerm_storage_container.democontainer.name
  type                   = "Block"
  source                 = "test1.txt"
}

## create a VM

# first, make a Static Public IP
resource "azurerm_public_ip" "vmiis-pip" {
  name                = "vmiis-pip"
  location            = azurerm_resource_group.rg-demo.location
  resource_group_name = azurerm_resource_group.rg-demo.name
  allocation_method   = "Static"
  depends_on = [ azurerm_resource_group.rg-demo ]  
}

# NIC first
resource "azurerm_network_interface" "vm-nic-demo" {
  name                = "vm-nic-demo"
  location            = azurerm_resource_group.rg-demo.location
  resource_group_name = azurerm_resource_group.rg-demo.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet-demo.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vmiis-pip.id
  }
  depends_on = [ azurerm_virtual_network.vnet-demo, azurerm_public_ip.vmiis-pip ]
}

resource "azurerm_windows_virtual_machine" "vm-demo" {
  name                = "vm-demo"
  resource_group_name = azurerm_resource_group.rg-demo.name
  location            = azurerm_resource_group.rg-demo.location
  size                = "Standard_F2"
  admin_username      = "adminuser"
  admin_password      = "P@$$w0rd1234!"
  network_interface_ids = [
    azurerm_network_interface.vm-nic-demo.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }
  
  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }
  depends_on = [ azurerm_network_interface.vm-nic-demo ]
}
# VM extension - IIS
resource "azurerm_virtual_machine_extension" "vmiis" {
  name                 = "vmiis"
  virtual_machine_id   = azurerm_windows_virtual_machine.vm-demo.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"

  settings = <<SETTINGS
 {
  "commandToExecute": "powershell Install-WindowsFeature -name Web-Server -IncludeManagementTools;"
 }
SETTINGS


  tags = {
    environment = "test"
  }
  depends_on = [ azurerm_windows_virtual_machine.vm-demo ]
}