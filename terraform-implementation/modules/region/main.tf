# Region Module - Deploys multi-tier infrastructure in a single Azure region
# This module can be used for both primary and secondary (DR) regions

terraform {
required_providers {
azurerm = {
source = "hashicorp/azurerm"
version = "~> 3.0"
}
}
}

# Resource Group
resource "azurerm_resource_group" "main" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-rg"
location = var.location
tags = var.tags
}

# Virtual Network
resource "azurerm_virtual_network" "main" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-vnet"
address_space = var.address_space
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
tags = var.tags
}

# Web Tier Subnet
resource "azurerm_subnet" "web" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-web-subnet"
resource_group_name = azurerm_resource_group.main.name
virtual_network_name = azurerm_virtual_network.main.name
address_prefixes = [var.web_subnet_prefix]
}

# Application Tier Subnet
resource "azurerm_subnet" "app" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-app-subnet"
resource_group_name = azurerm_resource_group.main.name
virtual_network_name = azurerm_virtual_network.main.name
address_prefixes = [var.app_subnet_prefix]
}

# Data Tier Subnet
resource "azurerm_subnet" "data" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-subnet"
resource_group_name = azurerm_resource_group.main.name
virtual_network_name = azurerm_virtual_network.main.name
address_prefixes = [var.data_subnet_prefix]
}

# Public IP for Load Balancer
resource "azurerm_public_ip" "main" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-pip"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
allocation_method = "Static"
sku = "Standard"
domain_name_label = "${var.project_name}-${var.environment}-${var.region_suffix}"
tags = var.tags
}

# Network Security Group for Web Tier
resource "azurerm_network_security_group" "web" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-web-nsg"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

security_rule {
name = "HTTP"
priority = 1001
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "80"
source_address_prefix = "*"
destination_address_prefix = "*"
}

security_rule {
name = "HTTPS"
priority = 1002
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "443"
source_address_prefix = "*"
destination_address_prefix = "*"
}

security_rule {
name = "SSH"
priority = 1003
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "22"
source_address_prefix = "10.0.0.0/8"
destination_address_prefix = "*"
}

tags = var.tags
}

# Network Security Group for App Tier
resource "azurerm_network_security_group" "app" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-app-nsg"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

security_rule {
name = "AppPort"
priority = 1001
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "8080"
source_address_prefix = var.web_subnet_prefix
destination_address_prefix = "*"
}

security_rule {
name = "SSH"
priority = 1002
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "22"
source_address_prefix = "10.0.0.0/8"
destination_address_prefix = "*"
}

tags = var.tags
}

# Network Security Group for Data Tier
resource "azurerm_network_security_group" "data" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-data-nsg"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name

security_rule {
name = "MySQL-App"
priority = 1001
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "3306"
source_address_prefix = var.app_subnet_prefix
destination_address_prefix = "*"
description = "Allow MySQL access from application tier"
}

security_rule {
name = "MySQL-Replication-Local"
priority = 1002
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "3306"
source_address_prefix = var.data_subnet_prefix
destination_address_prefix = "*"
description = "Allow MySQL replication within local data tier"
}

security_rule {
name = "MySQL-Replication-CrossRegion"
priority = 1003
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "3306"
source_address_prefix = "10.0.0.0/8"
destination_address_prefix = "*"
description = "Allow MySQL replication from other regions"
}

security_rule {
name = "SSH"
priority = 1004
direction = "Inbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "22"
source_address_prefix = "10.0.0.0/8"
destination_address_prefix = "*"
description = "Allow SSH access from internal networks"
}

# Outbound rule for MySQL replication
security_rule {
name = "MySQL-Outbound"
priority = 1001
direction = "Outbound"
access = "Allow"
protocol = "Tcp"
source_port_range = "*"
destination_port_range = "3306"
source_address_prefix = "*"
destination_address_prefix = "10.0.0.0/8"
description = "Allow MySQL replication to other regions"
}

tags = var.tags
}

# Associate NSGs with subnets
resource "azurerm_subnet_network_security_group_association" "web" {
subnet_id = azurerm_subnet.web.id
network_security_group_id = azurerm_network_security_group.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
subnet_id = azurerm_subnet.app.id
network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
subnet_id = azurerm_subnet.data.id
network_security_group_id = azurerm_network_security_group.data.id
}

# Load Balancer
resource "azurerm_lb" "main" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-lb"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
sku = "Standard"

frontend_ip_configuration {
name = "PublicIPAddress"
public_ip_address_id = azurerm_public_ip.main.id
}

tags = var.tags
}

# Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "main" {
loadbalancer_id = azurerm_lb.main.id
name = "BackEndAddressPool"
}

# Load Balancer Health Probe
resource "azurerm_lb_probe" "main" {
loadbalancer_id = azurerm_lb.main.id
name = "http-probe"
port = 80
protocol = "Http"
request_path = "/health"
}

# Load Balancer Rule
resource "azurerm_lb_rule" "main" {
loadbalancer_id = azurerm_lb.main.id
name = "LBRule"
protocol = "Tcp"
frontend_port = 80
backend_port = 80
frontend_ip_configuration_name = "PublicIPAddress"
backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
probe_id = azurerm_lb_probe.main.id
disable_outbound_snat = false
enable_floating_ip = false
idle_timeout_in_minutes = 4
}

# HTTPS Load Balancer Rule
resource "azurerm_lb_rule" "https" {
loadbalancer_id = azurerm_lb.main.id
name = "HTTPSRule"
protocol = "Tcp"
frontend_port = 443
backend_port = 443
frontend_ip_configuration_name = "PublicIPAddress"
backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
probe_id = azurerm_lb_probe.main.id
disable_outbound_snat = false
enable_floating_ip = false
idle_timeout_in_minutes = 4
}

# Internal Load Balancer for App Tier
resource "azurerm_lb" "internal" {
name = "${var.project_name}-${var.environment}-${var.region_suffix}-internal-lb"
location = azurerm_resource_group.main.location
resource_group_name = azurerm_resource_group.main.name
sku = "Standard"

frontend_ip_configuration {
name = "InternalIPAddress"
subnet_id = azurerm_subnet.app.id
private_ip_address_allocation = "Dynamic"
}

tags = var.tags
}

# Internal Load Balancer Backend Pool
resource "azurerm_lb_backend_address_pool" "internal" {
loadbalancer_id = azurerm_lb.internal.id
name = "InternalBackEndAddressPool"
}

# Internal Load Balancer Health Probe
resource "azurerm_lb_probe" "internal" {
loadbalancer_id = azurerm_lb.internal.id
name = "app-probe"
port = 8080
protocol = "Http"
request_path = "/health"
}

# Internal Load Balancer Rule
resource "azurerm_lb_rule" "internal" {
loadbalancer_id = azurerm_lb.internal.id
name = "AppLBRule"
protocol = "Tcp"
frontend_port = 8080
backend_port = 8080
frontend_ip_configuration_name = "InternalIPAddress"
backend_address_pool_ids = [azurerm_lb_backend_address_pool.internal.id]
probe_id = azurerm_lb_probe.internal.id
disable_outbound_snat = false
enable_floating_ip = false
idle_timeout_in_minutes = 4
}