# Outputs for Azure Multi-Tier Disaster Recovery Architecture

# Traffic Manager outputs
output "traffic_manager_fqdn" {
description = "The fully qualified domain name of the Traffic Manager"
value = azurerm_traffic_manager_profile.main.fqdn
}

output "traffic_manager_profile_name" {
description = "The name of the Traffic Manager profile"
value = azurerm_traffic_manager_profile.main.name
}

# Primary region outputs
output "primary_region" {
description = "Primary region configuration and endpoints"
value = {
location = var.primary_location
resource_group_name = module.primary_region.resource_group_name
vnet_name = module.primary_region.vnet_name
load_balancer_fqdn = module.primary_region.load_balancer_fqdn
public_ip_address = module.primary_region.public_ip_address
web_vm_names = module.primary_region.web_vm_names
app_vm_names = module.primary_region.app_vm_names
data_vm_names = module.primary_region.data_vm_names
}
sensitive = false
}

# Secondary region outputs
output "secondary_region" {
description = "Secondary region configuration and endpoints"
value = {
location = var.secondary_location
resource_group_name = module.secondary_region.resource_group_name
vnet_name = module.secondary_region.vnet_name
load_balancer_fqdn = module.secondary_region.load_balancer_fqdn
public_ip_address = module.secondary_region.public_ip_address
web_vm_names = module.secondary_region.web_vm_names
app_vm_names = module.secondary_region.app_vm_names
data_vm_names = module.secondary_region.data_vm_names
}
sensitive = false
}

# Recovery Services Vault
output "recovery_services_vault" {
description = "Recovery Services Vault information"
value = {
name = azurerm_recovery_services_vault.main.name
id = azurerm_recovery_services_vault.main.id
location = azurerm_recovery_services_vault.main.location
}
}

# Site Recovery configuration
output "site_recovery_configuration" {
description = "Site Recovery configuration details"
value = {
primary_fabric_name = azurerm_site_recovery_fabric.primary.name
secondary_fabric_name = azurerm_site_recovery_fabric.secondary.name
replication_policy_name = azurerm_site_recovery_replication_policy.main.name
}
}

# Network connectivity
output "vnet_peering" {
description = "VNet peering configuration"
value = {
primary_to_secondary = azurerm_virtual_network_peering.primary_to_secondary.name
secondary_to_primary = azurerm_virtual_network_peering.secondary_to_primary.name
}
}

# Security and access
output "vm_admin_username" {
description = "Administrator username for VMs"
value = var.vm_admin_username
sensitive = false
}

# Application URLs for testing
output "application_endpoints" {
description = "Application endpoints for testing"
value = {
global_endpoint = "https://${azurerm_traffic_manager_profile.main.fqdn}"
primary_endpoint = "https://${module.primary_region.load_balancer_fqdn}"
secondary_endpoint = "https://${module.secondary_region.load_balancer_fqdn}"
}
}

# Azure Portal links
output "azure_portal_links" {
description = "Direct links to Azure Portal for resource management"
value = {
traffic_manager = "https://portal.azure.com/#@/resource${azurerm_traffic_manager_profile.main.id}"
recovery_vault = "https://portal.azure.com/#@/resource${azurerm_recovery_services_vault.main.id}"
primary_rg = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${module.primary_region.resource_group_name}"
secondary_rg = "https://portal.azure.com/#@/resource/subscriptions/${data.azurerm_client_config.current.subscription_id}/resourceGroups/${module.secondary_region.resource_group_name}"
}
}

# Cost monitoring
output "estimated_monthly_cost" {
description = "Estimated monthly cost breakdown (approximate)"
value = {
note = "These are rough estimates. Actual costs may vary based on usage, region pricing, and current Azure rates."
components = {
virtual_machines = "~$400-800/month (6 VMs total across both regions)"
load_balancers = "~$40-60/month (2 Standard Load Balancers)"
traffic_manager = "~$5-10/month"
storage = "~$20-50/month (depends on data volume)"
networking = "~$10-30/month (bandwidth and VNet peering)"
site_recovery = "~$25/month per protected VM"
}
}
}