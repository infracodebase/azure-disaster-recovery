# Outputs for the region module

output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.main.id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.main.name
}

output "vnet_id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.main.id
}

output "public_ip_id" {
  description = "The ID of the public IP"
  value       = azurerm_public_ip.main.id
}

output "public_ip_address" {
  description = "The public IP address"
  value       = azurerm_public_ip.main.ip_address
}

output "load_balancer_fqdn" {
  description = "The FQDN of the load balancer"
  value       = azurerm_public_ip.main.fqdn
}

output "load_balancer_id" {
  description = "The ID of the load balancer"
  value       = azurerm_lb.main.id
}

output "internal_load_balancer_ip" {
  description = "The IP address of the internal load balancer"
  value       = azurerm_lb.internal.frontend_ip_configuration[0].private_ip_address
}

# Subnet outputs
output "web_subnet_id" {
  description = "The ID of the web subnet"
  value       = azurerm_subnet.web.id
}

output "app_subnet_id" {
  description = "The ID of the app subnet"
  value       = azurerm_subnet.app.id
}

output "data_subnet_id" {
  description = "The ID of the data subnet"
  value       = azurerm_subnet.data.id
}

# Virtual Machine outputs
output "web_vm_ids" {
  description = "The IDs of the web tier VMs"
  value       = azurerm_linux_virtual_machine.web[*].id
}

output "web_vm_names" {
  description = "The names of the web tier VMs"
  value       = azurerm_linux_virtual_machine.web[*].name
}

output "web_vm_private_ips" {
  description = "Private IP addresses of web tier VMs"
  value       = azurerm_network_interface.web[*].private_ip_address
}

output "app_vm_ids" {
  description = "The IDs of the app tier VMs"
  value       = azurerm_linux_virtual_machine.app[*].id
}

output "app_vm_names" {
  description = "The names of the app tier VMs"
  value       = azurerm_linux_virtual_machine.app[*].name
}

output "app_vm_private_ips" {
  description = "Private IP addresses of app tier VMs"
  value       = azurerm_network_interface.app[*].private_ip_address
}

output "data_vm_ids" {
  description = "The IDs of the data tier VMs"
  value       = azurerm_linux_virtual_machine.data[*].id
}

output "data_vm_names" {
  description = "The names of the data tier VMs"
  value       = azurerm_linux_virtual_machine.data[*].name
}

output "data_vm_private_ips" {
  description = "Private IP addresses of data tier VMs"
  value       = azurerm_network_interface.data[*].private_ip_address
}

# VM Disk IDs for Site Recovery
output "web_vm_os_disk_ids" {
  description = "OS disk IDs of web tier VMs"
  value       = var.is_dr_region ? [] : azurerm_linux_virtual_machine.web[*].os_disk[0].managed_disk_id
}

output "app_vm_os_disk_ids" {
  description = "OS disk IDs of app tier VMs"
  value       = var.is_dr_region ? [] : azurerm_linux_virtual_machine.app[*].os_disk[0].managed_disk_id
}

output "data_vm_os_disk_ids" {
  description = "OS disk IDs of data tier VMs"
  value       = var.is_dr_region ? [] : azurerm_linux_virtual_machine.data[*].os_disk[0].managed_disk_id
}

output "data_vm_data_disk_ids" {
  description = "Data disk IDs of data tier VMs"
  value       = var.is_dr_region ? [] : azurerm_managed_disk.data[*].id
}

# VM Network Interface IDs for Site Recovery
output "web_vm_nic_ids" {
  description = "Network interface IDs of web tier VMs"
  value       = azurerm_network_interface.web[*].id
}

output "app_vm_nic_ids" {
  description = "Network interface IDs of app tier VMs"
  value       = azurerm_network_interface.app[*].id
}

output "data_vm_nic_ids" {
  description = "Network interface IDs of data tier VMs"
  value       = azurerm_network_interface.data[*].id
}

# Availability Set IDs for Site Recovery
output "web_availability_set_id" {
  description = "Web tier availability set ID"
  value       = var.use_availability_zones ? null : (length(azurerm_availability_set.web) > 0 ? azurerm_availability_set.web[0].id : null)
}

output "app_availability_set_id" {
  description = "App tier availability set ID"
  value       = var.use_availability_zones ? null : (length(azurerm_availability_set.app) > 0 ? azurerm_availability_set.app[0].id : null)
}

output "data_availability_set_id" {
  description = "Data tier availability set ID"
  value       = var.use_availability_zones ? null : (length(azurerm_availability_set.data) > 0 ? azurerm_availability_set.data[0].id : null)
}

# Network security group outputs
output "web_nsg_id" {
  description = "The ID of the web tier NSG"
  value       = azurerm_network_security_group.web.id
}

output "app_nsg_id" {
  description = "The ID of the app tier NSG"
  value       = azurerm_network_security_group.app.id
}

output "data_nsg_id" {
  description = "The ID of the data tier NSG"
  value       = azurerm_network_security_group.data.id
}

# Availability configuration outputs
output "availability_sets" {
  description = "Availability sets information"
  value = var.use_availability_zones ? {} : {
    web  = var.use_availability_zones ? null : azurerm_availability_set.web[0].id
    app  = var.use_availability_zones ? null : azurerm_availability_set.app[0].id
    data = var.use_availability_zones ? null : azurerm_availability_set.data[0].id
  }
}

output "region_summary" {
  description = "Summary of the region deployment"
  value = {
    location               = var.location
    region_suffix          = var.region_suffix
    is_dr_region           = var.is_dr_region
    use_availability_zones = var.use_availability_zones
    web_vm_count           = length(azurerm_linux_virtual_machine.web)
    app_vm_count           = length(azurerm_linux_virtual_machine.app)
    data_vm_count          = length(azurerm_linux_virtual_machine.data)
    total_vm_count         = length(azurerm_linux_virtual_machine.web) + length(azurerm_linux_virtual_machine.app) + length(azurerm_linux_virtual_machine.data)
  }
}