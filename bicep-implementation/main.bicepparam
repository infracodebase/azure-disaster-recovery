// Parameter file for the Azure Multi-Tier Disaster Recovery Architecture
using 'main.bicep'

// Project Configuration
param projectName = 'webapp'
param environment = 'prod'

// Azure Regions
param primaryLocation = 'East US'
param secondaryLocation = 'West US 2'

// High Availability Configuration
// Set to true for Availability Zones (99.99% SLA) or false for Availability Sets (99.95% SLA)
param useAvailabilityZones = true

// Network Configuration - Primary Region
param primaryVnetAddressSpace = ['10.0.0.0/16']
param primaryWebSubnetPrefix = '10.0.1.0/24'
param primaryAppSubnetPrefix = '10.0.2.0/24'
param primaryDataSubnetPrefix = '10.0.3.0/24'

// Network Configuration - Secondary Region
param secondaryVnetAddressSpace = ['10.1.0.0/16']
param secondaryWebSubnetPrefix = '10.1.1.0/24'
param secondaryAppSubnetPrefix = '10.1.2.0/24'
param secondaryDataSubnetPrefix = '10.1.3.0/24'

// Virtual Machine Configuration
param vmAdminUsername = 'azureadmin'
// Note: Set vmAdminPassword as a secure parameter during deployment

// VM Sizes (adjust based on your performance requirements)
param vmSizeWeb = 'Standard_D2s_v3'  // 2 vCPU, 8 GB RAM
param vmSizeApp = 'Standard_D4s_v3'  // 4 vCPU, 16 GB RAM
param vmSizeData = 'Standard_D4s_v3' // 4 vCPU, 16 GB RAM

// Resource Tags
param tags = {
  Project: 'Azure Multi-Tier DR'
  Environment: 'Production'
  CreatedBy: 'Bicep'
  Purpose: 'Disaster Recovery Demo'
  CostCenter: 'IT-Infrastructure'
  Owner: 'Platform Team'
}