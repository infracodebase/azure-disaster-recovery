# Azure Multi-Tier Disaster Recovery Architecture
# Following Azure Well-Architected Framework principles

terraform {
  required_version = ">= 1.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.1"
    }
  }
}

# Configure the Microsoft Azure Provider
provider "azurerm" {
  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
    virtual_machine {
      delete_os_disk_on_deletion     = true
      graceful_shutdown              = false
      skip_shutdown_and_force_delete = false
    }
  }
}

# Random password for VMs
resource "random_password" "vm_password" {
  length  = 16
  special = true
}

# Data source for current client configuration
data "azurerm_client_config" "current" {}

# Primary region configuration
module "primary_region" {
  source = "./modules/region"

  environment            = var.environment
  project_name           = var.project_name
  location               = var.primary_location
  region_suffix          = "primary"
  address_space          = var.primary_vnet_address_space
  web_subnet_prefix      = var.primary_web_subnet_prefix
  app_subnet_prefix      = var.primary_app_subnet_prefix
  data_subnet_prefix     = var.primary_data_subnet_prefix
  vm_admin_username      = var.vm_admin_username
  vm_admin_password      = random_password.vm_password.result
  use_availability_zones = var.use_availability_zones

  # VMSS and Auto-scaling configuration
  enable_vmss              = var.enable_vmss
  vmss_orchestration_mode  = var.vmss_orchestration_mode
  enable_auto_scaling      = var.enable_auto_scaling
  auto_scaling_config      = var.auto_scaling_config

  tags = var.tags
}

# Secondary region (DR) configuration
module "secondary_region" {
  source = "./modules/region"

  environment            = var.environment
  project_name           = var.project_name
  location               = var.secondary_location
  region_suffix          = "secondary"
  address_space          = var.secondary_vnet_address_space
  web_subnet_prefix      = var.secondary_web_subnet_prefix
  app_subnet_prefix      = var.secondary_app_subnet_prefix
  data_subnet_prefix     = var.secondary_data_subnet_prefix
  vm_admin_username      = var.vm_admin_username
  vm_admin_password      = random_password.vm_password.result
  use_availability_zones = var.use_availability_zones
  is_dr_region           = true

  # VMSS and Auto-scaling configuration
  enable_vmss              = var.enable_vmss
  vmss_orchestration_mode  = var.vmss_orchestration_mode
  enable_auto_scaling      = var.enable_auto_scaling
  auto_scaling_config      = var.auto_scaling_config

  tags = var.tags
}

# Traffic Manager for global load balancing and failover
resource "azurerm_traffic_manager_profile" "main" {
  name                = "${var.project_name}-${var.environment}-tm"
  resource_group_name = module.primary_region.resource_group_name

  traffic_routing_method = "Priority"

  dns_config {
    relative_name = "${var.project_name}-${var.environment}"
    ttl           = 60
  }

  monitor_config {
    protocol                     = "HTTPS"
    port                         = 443
    path                         = "/health"
    interval_in_seconds          = 30
    timeout_in_seconds           = 10
    tolerated_number_of_failures = 3
  }

  tags = var.tags
}

# Primary endpoint for Traffic Manager
resource "azurerm_traffic_manager_azure_endpoint" "primary" {
  name               = "${var.project_name}-${var.environment}-primary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = module.primary_region.public_ip_id
  priority           = 1
  weight             = 100
}

# Secondary endpoint for Traffic Manager
resource "azurerm_traffic_manager_azure_endpoint" "secondary" {
  name               = "${var.project_name}-${var.environment}-secondary"
  profile_id         = azurerm_traffic_manager_profile.main.id
  target_resource_id = module.secondary_region.public_ip_id
  priority           = 2
  weight             = 100
}

# VNet Peering between regions for replication traffic
resource "azurerm_virtual_network_peering" "primary_to_secondary" {
  name                      = "${var.project_name}-${var.environment}-primary-to-secondary"
  resource_group_name       = module.primary_region.resource_group_name
  virtual_network_name      = module.primary_region.vnet_name
  remote_virtual_network_id = module.secondary_region.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

resource "azurerm_virtual_network_peering" "secondary_to_primary" {
  name                      = "${var.project_name}-${var.environment}-secondary-to-primary"
  resource_group_name       = module.secondary_region.resource_group_name
  virtual_network_name      = module.secondary_region.vnet_name
  remote_virtual_network_id = module.primary_region.vnet_id

  allow_virtual_network_access = true
  allow_forwarded_traffic      = true
  allow_gateway_transit        = false
  use_remote_gateways          = false
}

# Recovery Services Vault for Azure Site Recovery
resource "azurerm_recovery_services_vault" "main" {
  name                         = "${var.project_name}-${var.environment}-rsv"
  location                     = var.primary_location
  resource_group_name          = module.primary_region.resource_group_name
  sku                          = "Standard"
  storage_mode_type            = "GeoRedundant"
  cross_region_restore_enabled = true

  tags = var.tags
}

# Site Recovery Fabric for primary region
resource "azurerm_site_recovery_fabric" "primary" {
  name                = "${var.project_name}-primary-fabric"
  resource_group_name = module.primary_region.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = var.primary_location
}

# Site Recovery Fabric for secondary region
resource "azurerm_site_recovery_fabric" "secondary" {
  name                = "${var.project_name}-secondary-fabric"
  resource_group_name = module.primary_region.resource_group_name
  recovery_vault_name = azurerm_recovery_services_vault.main.name
  location            = var.secondary_location
}

# Site Recovery Protection Container for primary region
resource "azurerm_site_recovery_protection_container" "primary" {
  name                 = "${var.project_name}-primary-protection-container"
  resource_group_name  = module.primary_region.resource_group_name
  recovery_vault_name  = azurerm_recovery_services_vault.main.name
  recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
}

# Site Recovery Protection Container for secondary region
resource "azurerm_site_recovery_protection_container" "secondary" {
  name                 = "${var.project_name}-secondary-protection-container"
  resource_group_name  = module.primary_region.resource_group_name
  recovery_vault_name  = azurerm_recovery_services_vault.main.name
  recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
}

# Replication Policy
resource "azurerm_site_recovery_replication_policy" "main" {
  name                                                 = "${var.project_name}-policy"
  resource_group_name                                  = module.primary_region.resource_group_name
  recovery_vault_name                                  = azurerm_recovery_services_vault.main.name
  recovery_point_retention_in_minutes                  = 24 * 60
  application_consistent_snapshot_frequency_in_minutes = 4 * 60
}

# Container mapping for replication
resource "azurerm_site_recovery_protection_container_mapping" "main" {
  name                                      = "${var.project_name}-container-mapping"
  resource_group_name                       = module.primary_region.resource_group_name
  recovery_vault_name                       = azurerm_recovery_services_vault.main.name
  recovery_fabric_name                      = azurerm_site_recovery_fabric.primary.name
  recovery_source_protection_container_name = azurerm_site_recovery_protection_container.primary.name
  recovery_target_protection_container_id   = azurerm_site_recovery_protection_container.secondary.id
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.main.id
}

# Storage account for boot diagnostics and caching
resource "azurerm_storage_account" "diagnostics" {
  name                     = "${lower(var.project_name)}${lower(var.environment)}diag${substr(random_password.vm_password.id, 0, 6)}"
  resource_group_name      = module.primary_region.resource_group_name
  location                 = var.primary_location
  account_tier             = "Standard"
  account_replication_type = "GRS" # Changed from LRS to GRS for geo-replication

  # Security settings
  min_tls_version                  = "TLS1_2"
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = true

  tags = var.tags
}

# Storage account for Site Recovery caching
resource "azurerm_storage_account" "cache" {
  name                     = "${lower(var.project_name)}${lower(var.environment)}cache${substr(random_password.vm_password.id, 0, 5)}"
  resource_group_name      = module.primary_region.resource_group_name
  location                 = var.primary_location
  account_tier             = "Standard"
  account_replication_type = "LRS" # Cache storage should be LRS for performance

  # Security settings
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false

  tags = merge(var.tags, {
    Purpose = "Site Recovery Cache"
  })
}

# Network mapping for Site Recovery
resource "azurerm_site_recovery_network_mapping" "main" {
  name                        = "${var.project_name}-network-mapping"
  resource_group_name         = module.primary_region.resource_group_name
  recovery_vault_name         = azurerm_recovery_services_vault.main.name
  source_recovery_fabric_name = azurerm_site_recovery_fabric.primary.name
  target_recovery_fabric_name = azurerm_site_recovery_fabric.secondary.name
  source_network_id           = module.primary_region.vnet_id
  target_network_id           = module.secondary_region.vnet_id

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.main
  ]
}

# VM Replication - Web Tier VMs
resource "azurerm_site_recovery_replicated_vm" "web_vms" {
  count                                     = 2
  name                                      = "${var.project_name}-${var.environment}-web-vm-${count.index + 1}-replication"
  resource_group_name                       = module.primary_region.resource_group_name
  recovery_vault_name                       = azurerm_recovery_services_vault.main.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_vm_id                              = module.primary_region.web_vm_ids[count.index]
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.main.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name

  target_resource_group_id                = module.secondary_region.resource_group_id
  target_recovery_fabric_id               = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id = azurerm_site_recovery_protection_container.secondary.id
  target_network_id                       = module.secondary_region.vnet_id
  test_network_id                         = module.secondary_region.vnet_id
  target_availability_set_id              = var.use_availability_zones ? null : module.secondary_region.web_availability_set_id
  target_zone                             = var.use_availability_zones ? tostring((count.index % 2) + 1) : null

  managed_disk {
    disk_id                    = module.primary_region.web_vm_os_disk_ids[count.index]
    staging_storage_account_id = azurerm_storage_account.cache.id
    target_resource_group_id   = module.secondary_region.resource_group_id
    target_disk_type           = "Premium_LRS"
    target_replica_disk_type   = "Premium_LRS"
  }

  network_interface {
    source_network_interface_id   = module.primary_region.web_vm_nic_ids[count.index]
    target_subnet_name            = "web-subnet"
    recovery_public_ip_address_id = module.secondary_region.public_ip_id
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.main,
    azurerm_site_recovery_network_mapping.main,
  ]
}

# VM Replication - App Tier VMs
resource "azurerm_site_recovery_replicated_vm" "app_vms" {
  count                                     = 2
  name                                      = "${var.project_name}-${var.environment}-app-vm-${count.index + 1}-replication"
  resource_group_name                       = module.primary_region.resource_group_name
  recovery_vault_name                       = azurerm_recovery_services_vault.main.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_vm_id                              = module.primary_region.app_vm_ids[count.index]
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.main.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name

  target_resource_group_id                = module.secondary_region.resource_group_id
  target_recovery_fabric_id               = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id = azurerm_site_recovery_protection_container.secondary.id
  target_network_id                       = module.secondary_region.vnet_id
  test_network_id                         = module.secondary_region.vnet_id
  target_availability_set_id              = var.use_availability_zones ? null : module.secondary_region.app_availability_set_id
  target_zone                             = var.use_availability_zones ? tostring((count.index % 2) + 1) : null

  managed_disk {
    disk_id                    = module.primary_region.app_vm_os_disk_ids[count.index]
    staging_storage_account_id = azurerm_storage_account.cache.id
    target_resource_group_id   = module.secondary_region.resource_group_id
    target_disk_type           = "Premium_LRS"
    target_replica_disk_type   = "Premium_LRS"
  }

  network_interface {
    source_network_interface_id = module.primary_region.app_vm_nic_ids[count.index]
    target_subnet_name          = "app-subnet"
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.main,
    azurerm_site_recovery_network_mapping.main,
  ]
}

# VM Replication - Data Tier VMs
resource "azurerm_site_recovery_replicated_vm" "data_vms" {
  count                                     = 2
  name                                      = "${var.project_name}-${var.environment}-data-vm-${count.index + 1}-replication"
  resource_group_name                       = module.primary_region.resource_group_name
  recovery_vault_name                       = azurerm_recovery_services_vault.main.name
  source_recovery_fabric_name               = azurerm_site_recovery_fabric.primary.name
  source_vm_id                              = module.primary_region.data_vm_ids[count.index]
  recovery_replication_policy_id            = azurerm_site_recovery_replication_policy.main.id
  source_recovery_protection_container_name = azurerm_site_recovery_protection_container.primary.name

  target_resource_group_id                = module.secondary_region.resource_group_id
  target_recovery_fabric_id               = azurerm_site_recovery_fabric.secondary.id
  target_recovery_protection_container_id = azurerm_site_recovery_protection_container.secondary.id
  target_network_id                       = module.secondary_region.vnet_id
  test_network_id                         = module.secondary_region.vnet_id
  target_availability_set_id              = var.use_availability_zones ? null : module.secondary_region.data_availability_set_id
  target_zone                             = var.use_availability_zones ? tostring((count.index % 2) + 1) : null

  managed_disk {
    disk_id                    = module.primary_region.data_vm_os_disk_ids[count.index]
    staging_storage_account_id = azurerm_storage_account.cache.id
    target_resource_group_id   = module.secondary_region.resource_group_id
    target_disk_type           = "Premium_LRS"
    target_replica_disk_type   = "Premium_LRS"
  }

  # Replicate data disks for database VMs
  dynamic "managed_disk" {
    for_each = module.primary_region.data_vm_data_disk_ids[count.index] != null ? [1] : []
    content {
      disk_id                    = module.primary_region.data_vm_data_disk_ids[count.index]
      staging_storage_account_id = azurerm_storage_account.cache.id
      target_resource_group_id   = module.secondary_region.resource_group_id
      target_disk_type           = "Premium_LRS"
      target_replica_disk_type   = "Premium_LRS"
    }
  }

  network_interface {
    source_network_interface_id = module.primary_region.data_vm_nic_ids[count.index]
    target_subnet_name          = "data-subnet"
  }

  depends_on = [
    azurerm_site_recovery_protection_container_mapping.main,
    azurerm_site_recovery_network_mapping.main,
  ]
}