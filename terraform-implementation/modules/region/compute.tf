# Compute resources for the region module
# Handles VMs with either Availability Sets or Availability Zones

# Availability Set for Web Tier (when not using Availability Zones)
resource "azurerm_availability_set" "web" {
count = var.use_availability_zones ? 0 : 1
name = "${var.project_name}-${var.environment}-${var.region_suffix}-web-as"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
platform_fault_domain_count = 2
platform_update_domain_count = 2
managed = true
tags = var.tags
}

# Availability Set for App Tier (when not using Availability Zones)
resource "azurerm_availability_set" "app" {
count = var.use_availability_zones ? 0 : 1
name = "${var.project_name}-${var.environment}-${var.region_suffix}-app-as"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
platform_fault_domain_count = 2
platform_update_domain_count = 2
managed = true
tags = var.tags
}

# Availability Set for Data Tier (when not using Availability Zones)
resource "azurerm_availability_set" "data" {
count = var.use_availability_zones ? 0 : 1
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-as"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
platform_fault_domain_count = 2
platform_update_domain_count = 2
managed = true
tags = var.tags
}

# Web Tier Virtual Machines
resource "azurerm_network_interface" "web" {
count = 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-web-nic-${count.index + 1}"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

ip_configuration {
name = "internal"
subnet_id = azurerm_subnet.web.id
private_ip_address_allocation = "Dynamic"
}

tags = var.tags
}

resource "azurerm_network_interface_backend_address_pool_association" "web" {
count = 2
network_interface_id = azurerm_network_interface.web[count.index].id
ip_configuration_name = "internal"
backend_address_pool_id = azurerm_lb_backend_address_pool.main.id
}

resource "azurerm_linux_virtual_machine" "web" {
count = var.is_dr_region ? 0 : 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-web-vm-${count.index + 1}"
resource_group_name = azurerm_resource_group.main.name
location = azurerm_resource_group.main.location
size = var.vm_size_web
admin_username = var.vm_admin_username
disable_password_authentication = false
admin_password = var.vm_admin_password

# Use either Availability Zone or Availability Set
zone = var.use_availability_zones ? tostring((count.index % 2) + 1) : null
availability_set_id = var.use_availability_zones ? null : azurerm_availability_set.web[0].id

network_interface_ids = [
azurerm_network_interface.web[count.index].id,
]

os_disk {
caching = "ReadWrite"
storage_account_type = "Premium_LRS"
}

source_image_reference {
publisher = "Canonical"
offer = "0001-com-ubuntu-server-focal"
sku = "20_04-lts-gen2"
version = "latest"
}

custom_data = base64encode(templatefile("${path.module}/scripts/web-setup.sh", {
tier = "web"
}))

tags = merge(var.tags, {
Tier = "Web"
})
}

# App Tier Virtual Machines
resource "azurerm_network_interface" "app" {
count = 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-app-nic-${count.index + 1}"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

ip_configuration {
name = "internal"
subnet_id = azurerm_subnet.app.id
private_ip_address_allocation = "Dynamic"
}

tags = var.tags
}

resource "azurerm_network_interface_backend_address_pool_association" "app" {
count = 2
network_interface_id = azurerm_network_interface.app[count.index].id
ip_configuration_name = "internal"
backend_address_pool_id = azurerm_lb_backend_address_pool.internal.id
}

resource "azurerm_linux_virtual_machine" "app" {
count = var.is_dr_region ? 0 : 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-app-vm-${count.index + 1}"
resource_group_name = azurerm_resource_group.main.name
location = azurerm_resource_group.main.location
size = var.vm_size_app
admin_username = var.vm_admin_username
disable_password_authentication = false
admin_password = var.vm_admin_password

# Use either Availability Zone or Availability Set
zone = var.use_availability_zones ? tostring((count.index % 2) + 1) : null
availability_set_id = var.use_availability_zones ? null : azurerm_availability_set.app[0].id

network_interface_ids = [
azurerm_network_interface.app[count.index].id,
]

os_disk {
caching = "ReadWrite"
storage_account_type = "Premium_LRS"
}

source_image_reference {
publisher = "Canonical"
offer = "0001-com-ubuntu-server-focal"
sku = "20_04-lts-gen2"
version = "latest"
}

custom_data = base64encode(templatefile("${path.module}/scripts/app-setup.sh", {
tier = "app"
}))

tags = merge(var.tags, {
Tier = "Application"
})
}

# Data Disks for Database Storage
resource "azurerm_managed_disk" "data" {
count = var.is_dr_region ? 0 : 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-vm-${count.index + 1}-data-disk"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
storage_account_type = "Premium_LRS"
create_option = "Empty"
disk_size_gb = 128

tags = merge(var.tags, {
Tier = "Data"
})
}

resource "azurerm_virtual_machine_data_disk_attachment" "data" {
count = var.is_dr_region ? 0 : 2
managed_disk_id = azurerm_managed_disk.data[count.index].id
virtual_machine_id = azurerm_linux_virtual_machine.data[count.index].id
lun = "0"
caching = "ReadWrite"
}

# Data Tier Virtual Machines
resource "azurerm_network_interface" "data" {
count = 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-nic-${count.index + 1}"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

ip_configuration {
name = "internal"
subnet_id = azurerm_subnet.data.id
private_ip_address_allocation = "Dynamic"
}

tags = var.tags
}

resource "azurerm_linux_virtual_machine" "data" {
count = var.is_dr_region ? 0 : 2
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-vm-${count.index + 1}"
resource_group_name = azurerm_resource_group.main.name
location = azurerm_resource_group.main.location
size = var.vm_size_data
admin_username = var.vm_admin_username
disable_password_authentication = false
admin_password = var.vm_admin_password

# Use either Availability Zone or Availability Set
zone = var.use_availability_zones ? tostring((count.index % 2) + 1) : null
availability_set_id = var.use_availability_zones ? null : azurerm_availability_set.data[0].id

network_interface_ids = [
azurerm_network_interface.data[count.index].id,
]

os_disk {
caching = "ReadWrite"
storage_account_type = "Premium_LRS"
}


source_image_reference {
publisher = "Canonical"
offer = "0001-com-ubuntu-server-focal"
sku = "20_04-lts-gen2"
version = "latest"
}

custom_data = base64encode(templatefile("${path.module}/scripts/data-setup-enhanced.sh", {
tier = "data"
}))

tags = merge(var.tags, {
Tier = "Data"
})
}