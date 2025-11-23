# Virtual Machine Scale Sets (VMSS) Configuration
# This file contains VMSS resources for web and app tiers
# VMSS is only created when var.enable_vmss is true

# SSH key generation for VMSS instances
resource "tls_private_key" "vmss_ssh" {
  count     = var.enable_vmss && !var.is_dr_region ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Web Tier Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "web" {
  count               = var.enable_vmss && !var.is_dr_region ? 1 : 0
  name                = "${var.project_name}-${var.environment}-${var.region_suffix}-web-vmss"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vm_size_web
  instances           = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.default_instances : 2

  # Only use zones if availability zones are enabled
  zones = var.use_availability_zones ? ["1", "2"] : null

  # Authentication configuration
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.vmss_ssh[0].public_key_openssh
  }

  # Source image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Network configuration
  network_interface {
    name    = "web-vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.web.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.main.id]
    }
  }

  # Custom data script
  custom_data = base64encode(templatefile("${path.module}/scripts/web-setup.sh", {
    tier = "web"
  }))

  # Health probe for auto-scaling
  health_probe_id = azurerm_lb_probe.main.id

  tags = merge(var.tags, {
    Tier         = "Web"
    ResourceType = "VMSS"
  })

  depends_on = [azurerm_lb_backend_address_pool.main]
}

# App Tier Virtual Machine Scale Set
resource "azurerm_linux_virtual_machine_scale_set" "app" {
  count               = var.enable_vmss && !var.is_dr_region ? 1 : 0
  name                = "${var.project_name}-${var.environment}-${var.region_suffix}-app-vmss"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku                 = var.vm_size_app
  instances           = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.default_instances : 2

  # Only use zones if availability zones are enabled
  zones = var.use_availability_zones ? ["1", "2"] : null

  # Authentication configuration
  admin_username                  = var.vm_admin_username
  disable_password_authentication = true

  admin_ssh_key {
    username   = var.vm_admin_username
    public_key = tls_private_key.vmss_ssh[0].public_key_openssh
  }

  # Source image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }

  # OS disk configuration
  os_disk {
    storage_account_type = "Premium_LRS"
    caching              = "ReadWrite"
  }

  # Network configuration
  network_interface {
    name    = "app-vmss-nic"
    primary = true

    ip_configuration {
      name                                   = "internal"
      primary                                = true
      subnet_id                              = azurerm_subnet.app.id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.internal.id]
    }
  }

  # Custom data script
  custom_data = base64encode(templatefile("${path.module}/scripts/app-setup.sh", {
    tier = "app"
  }))

  # Health probe for auto-scaling
  health_probe_id = azurerm_lb_probe.internal.id

  tags = merge(var.tags, {
    Tier         = "Application"
    ResourceType = "VMSS"
  })

  depends_on = [azurerm_lb_backend_address_pool.internal]
}

# Health extension for Web VMSS (Application Health for Linux)
resource "azurerm_virtual_machine_scale_set_extension" "web_health" {
  count                        = var.enable_vmss && !var.is_dr_region ? 1 : 0
  name                         = "HealthExtension"
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.web[0].id
  publisher                    = "Microsoft.ManagedServices"
  type                         = "ApplicationHealthLinux"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true

  settings = jsonencode({
    protocol    = "http"
    port        = 80
    requestPath = "/"
  })
}

# Health extension for App VMSS (Application Health for Linux)
resource "azurerm_virtual_machine_scale_set_extension" "app_health" {
  count                        = var.enable_vmss && !var.is_dr_region ? 1 : 0
  name                         = "HealthExtension"
  virtual_machine_scale_set_id = azurerm_linux_virtual_machine_scale_set.app[0].id
  publisher                    = "Microsoft.ManagedServices"
  type                         = "ApplicationHealthLinux"
  type_handler_version         = "1.0"
  auto_upgrade_minor_version   = true

  settings = jsonencode({
    protocol    = "http"
    port        = 80
    requestPath = "/health"
  })
}