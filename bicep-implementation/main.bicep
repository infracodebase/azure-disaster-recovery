// Azure Multi-Tier Disaster Recovery Architecture - Main Bicep Template
// Following Azure Well-Architected Framework principles

metadata description = 'Deploys a multi-tier web application with high availability and disaster recovery across two Azure regions'
metadata author = 'Azure Infrastructure Team'
metadata version = '1.0.0'

targetScope = 'subscription'

// Parameters
@description('The project name used for resource naming')
@minLength(2)
@maxLength(20)
param projectName string = 'webapp'

@description('The environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Primary Azure region for deployment')
param primaryLocation string = 'East US'

@description('Secondary Azure region for disaster recovery')
param secondaryLocation string = 'West US 2'

@description('Whether to use Availability Zones (true) or Availability Sets (false)')
param useAvailabilityZones bool = true

@description('Enable Virtual Machine Scale Sets')
param enableVMSS bool = false

@description('Enable auto-scaling for VMSS')
param enableAutoScaling bool = false

@description('Auto-scaling configuration for VMSS')
param autoScalingConfig object = {
webTier: {
minInstances: 2
maxInstances: 10
defaultInstances: 3
scaleOutCpuThreshold: 75
scaleInCpuThreshold: 25
scaleOutMemoryThreshold: 80
scaleInMemoryThreshold: 30
scaleOutCooldown: 'PT5M'
scaleInCooldown: 'PT10M'
}
appTier: {
minInstances: 2
maxInstances: 8
defaultInstances: 2
scaleOutCpuThreshold: 70
scaleInCpuThreshold: 30
scaleOutMemoryThreshold: 75
scaleInMemoryThreshold: 35
scaleOutCooldown: 'PT5M'
scaleInCooldown: 'PT15M'
}
}

@description('Admin username for virtual machines')
@minLength(3)
@maxLength(20)
param vmAdminUsername string = 'azureadmin'

@description('Admin password for virtual machines')
@secure()
@minLength(8)
@maxLength(123)
param vmAdminPassword string

// Network Configuration - Primary Region
@description('Address space for primary region VNet')
param primaryVnetAddressSpace array = ['10.0.0.0/16']

@description('Web subnet prefix in primary region')
param primaryWebSubnetPrefix string = '10.0.1.0/24'

@description('App subnet prefix in primary region')
param primaryAppSubnetPrefix string = '10.0.2.0/24'

@description('Data subnet prefix in primary region')
param primaryDataSubnetPrefix string = '10.0.3.0/24'

// Network Configuration - Secondary Region
@description('Address space for secondary region VNet')
param secondaryVnetAddressSpace array = ['10.1.0.0/16']

@description('Web subnet prefix in secondary region')
param secondaryWebSubnetPrefix string = '10.1.1.0/24'

@description('App subnet prefix in secondary region')
param secondaryAppSubnetPrefix string = '10.1.2.0/24'

@description('Data subnet prefix in secondary region')
param secondaryDataSubnetPrefix string = '10.1.3.0/24'

// VM Configuration
@description('Size of web tier virtual machines')
param vmSizeWeb string = 'Standard_D2s_v3'

@description('Size of app tier virtual machines')
param vmSizeApp string = 'Standard_D4s_v3'

@description('Size of data tier virtual machines')
param vmSizeData string = 'Standard_D4s_v3'

@description('Tags to apply to all resources')
param tags object = {
Project: 'Azure Multi-Tier DR'
Environment: environment
CreatedBy: 'Bicep'
Purpose: 'Disaster Recovery Demo'
}

// Variables
var uniqueString = uniqueString(subscription().subscriptionId, projectName, environment)
var primaryResourceGroupName = '${projectName}-${environment}-primary-rg'
var secondaryResourceGroupName = '${projectName}-${environment}-secondary-rg'

// Resource Groups
resource primaryResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
name: primaryResourceGroupName
location: primaryLocation
tags: tags
}

resource secondaryResourceGroup 'Microsoft.Resources/resourceGroups@2023-07-01' = {
name: secondaryResourceGroupName
location: secondaryLocation
tags: tags
}

// Primary Region Deployment
module primaryRegion 'modules/region.bicep' = {
scope: primaryResourceGroup
name: 'primaryRegionDeployment'
params: {
projectName: projectName
environment: environment
location: primaryLocation
regionSuffix: 'primary'
addressSpace: primaryVnetAddressSpace
webSubnetPrefix: primaryWebSubnetPrefix
appSubnetPrefix: primaryAppSubnetPrefix
dataSubnetPrefix: primaryDataSubnetPrefix
vmAdminUsername: vmAdminUsername
vmAdminPassword: vmAdminPassword
vmSizeWeb: vmSizeWeb
vmSizeApp: vmSizeApp
vmSizeData: vmSizeData
useAvailabilityZones: useAvailabilityZones
enableVMSS: enableVMSS
enableAutoScaling: enableAutoScaling
autoScalingConfig: autoScalingConfig
isDRRegion: false
tags: tags
}
}

// Secondary Region Deployment
module secondaryRegion 'modules/region.bicep' = {
scope: secondaryResourceGroup
name: 'secondaryRegionDeployment'
params: {
projectName: projectName
environment: environment
location: secondaryLocation
regionSuffix: 'secondary'
addressSpace: secondaryVnetAddressSpace
webSubnetPrefix: secondaryWebSubnetPrefix
appSubnetPrefix: secondaryAppSubnetPrefix
dataSubnetPrefix: secondaryDataSubnetPrefix
vmAdminUsername: vmAdminUsername
vmAdminPassword: vmAdminPassword
vmSizeWeb: vmSizeWeb
vmSizeApp: vmSizeApp
vmSizeData: vmSizeData
useAvailabilityZones: useAvailabilityZones
enableVMSS: enableVMSS
enableAutoScaling: enableAutoScaling
autoScalingConfig: autoScalingConfig
isDRRegion: true
tags: tags
}
}

// Traffic Manager Profile for global load balancing
module trafficManager 'modules/traffic-manager.bicep' = {
scope: primaryResourceGroup
name: 'trafficManagerDeployment'
params: {
projectName: projectName
environment: environment
primaryEndpointResourceId: primaryRegion.outputs.publicIpId
secondaryEndpointResourceId: secondaryRegion.outputs.publicIpId
tags: tags
}
dependsOn: [
primaryRegion
secondaryRegion
]
}

// VNet Peering between regions
module vnetPeering 'modules/vnet-peering.bicep' = {
name: 'vnetPeeringDeployment'
params: {
primaryResourceGroupName: primaryResourceGroupName
secondaryResourceGroupName: secondaryResourceGroupName
primaryVnetName: primaryRegion.outputs.vnetName
secondaryVnetName: secondaryRegion.outputs.vnetName
primaryVnetId: primaryRegion.outputs.vnetId
secondaryVnetId: secondaryRegion.outputs.vnetId
projectName: projectName
environment: environment
}
dependsOn: [
primaryRegion
secondaryRegion
]
}

// Recovery Services Vault and Site Recovery
module recoveryServices 'modules/recovery-services.bicep' = {
scope: primaryResourceGroup
name: 'recoveryServicesDeployment'
params: {
projectName: projectName
environment: environment
location: primaryLocation
secondaryLocation: secondaryLocation
primaryResourceGroupName: primaryResourceGroupName
secondaryResourceGroupName: secondaryResourceGroupName
primaryVnetId: primaryRegion.outputs.vnetId
secondaryVnetId: secondaryRegion.outputs.vnetId
tags: tags
}
dependsOn: [
primaryRegion
secondaryRegion
]
}

// Cache Storage Account for Site Recovery
resource cacheStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
name: 'cache${take(uniqueString, 8)}'
location: primaryLocation
kind: 'StorageV2'
sku: {
name: 'Standard_LRS'
}
tags: merge(tags, {
Purpose: 'Site Recovery Cache'
})
properties: {
supportsHttpsTrafficOnly: true
minimumTlsVersion: 'TLS1_2'
allowBlobPublicAccess: false
}
}

// Target Storage Account for replicated VMs (with GRS)
resource targetStorageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
name: 'target${take(uniqueString, 8)}'
location: secondaryLocation
kind: 'StorageV2'
sku: {
name: 'Standard_GRS' // GEO-REDUNDANT STORAGE for disaster recovery
}
tags: merge(tags, {
Purpose: 'Site Recovery Target'
})
properties: {
supportsHttpsTrafficOnly: true
minimumTlsVersion: 'TLS1_2'
allowBlobPublicAccess: false
geoReplicationStats: {
canFailover: true
}
}
}

// VM Replication for Web Tier
resource webVmReplication 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectedItems@2023-08-01' = [for i in range(0, 2): {
name: '${recoveryServices.outputs.vaultName}/${recoveryServices.outputs.primaryFabricName}/${projectName}-primary-protection-container/${projectName}-${environment}-web-vm-${i + 1}-replication'
properties: {
policyId: '${recoveryServices.outputs.vaultId}/replicationPolicies/${recoveryServices.outputs.replicationPolicyName}'
protectableItemId: primaryRegion.outputs.webVmIds[i]
providerSpecificDetails: {
instanceType: 'A2A'
fabricObjectId: primaryRegion.outputs.webVmIds[i]
recoveryContainerId: '${recoveryServices.outputs.vaultId}/replicationFabrics/${recoveryServices.outputs.secondaryFabricName}/replicationProtectionContainers/${projectName}-secondary-protection-container'
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryCloudServiceId: null
recoveryAvailabilitySetId: primaryRegion.outputs.webAvailabilitySetId
selectedRecoveryAzureNetworkId: secondaryRegion.outputs.vnetId
selectedSourceNicId: primaryRegion.outputs.webVmNicIds[i]
vmManagedDisks: [
{
diskId: primaryRegion.outputs.webVmOsDiskIds[i]
primaryStagingAzureStorageAccountId: cacheStorageAccount.id
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryReplicaDiskAccountType: 'Premium_LRS'
recoveryTargetDiskAccountType: 'Premium_LRS'
}
]
}
}
dependsOn: [
recoveryServices
primaryRegion
secondaryRegion
]
}]

// VM Replication for App Tier
resource appVmReplication 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectedItems@2023-08-01' = [for i in range(0, 2): {
name: '${recoveryServices.outputs.vaultName}/${recoveryServices.outputs.primaryFabricName}/${projectName}-primary-protection-container/${projectName}-${environment}-app-vm-${i + 1}-replication'
properties: {
policyId: '${recoveryServices.outputs.vaultId}/replicationPolicies/${recoveryServices.outputs.replicationPolicyName}'
protectableItemId: primaryRegion.outputs.appVmIds[i]
providerSpecificDetails: {
instanceType: 'A2A'
fabricObjectId: primaryRegion.outputs.appVmIds[i]
recoveryContainerId: '${recoveryServices.outputs.vaultId}/replicationFabrics/${recoveryServices.outputs.secondaryFabricName}/replicationProtectionContainers/${projectName}-secondary-protection-container'
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryCloudServiceId: null
recoveryAvailabilitySetId: primaryRegion.outputs.appAvailabilitySetId
selectedRecoveryAzureNetworkId: secondaryRegion.outputs.vnetId
selectedSourceNicId: primaryRegion.outputs.appVmNicIds[i]
vmManagedDisks: [
{
diskId: primaryRegion.outputs.appVmOsDiskIds[i]
primaryStagingAzureStorageAccountId: cacheStorageAccount.id
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryReplicaDiskAccountType: 'Premium_LRS'
recoveryTargetDiskAccountType: 'Premium_LRS'
}
]
}
}
dependsOn: [
recoveryServices
primaryRegion
secondaryRegion
]
}]

// VM Replication for Data Tier
resource dataVmReplication 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectedItems@2023-08-01' = [for i in range(0, 2): {
name: '${recoveryServices.outputs.vaultName}/${recoveryServices.outputs.primaryFabricName}/${projectName}-primary-protection-container/${projectName}-${environment}-data-vm-${i + 1}-replication'
properties: {
policyId: '${recoveryServices.outputs.vaultId}/replicationPolicies/${recoveryServices.outputs.replicationPolicyName}'
protectableItemId: primaryRegion.outputs.dataVmIds[i]
providerSpecificDetails: {
instanceType: 'A2A'
fabricObjectId: primaryRegion.outputs.dataVmIds[i]
recoveryContainerId: '${recoveryServices.outputs.vaultId}/replicationFabrics/${recoveryServices.outputs.secondaryFabricName}/replicationProtectionContainers/${projectName}-secondary-protection-container'
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryCloudServiceId: null
recoveryAvailabilitySetId: primaryRegion.outputs.dataAvailabilitySetId
selectedRecoveryAzureNetworkId: secondaryRegion.outputs.vnetId
selectedSourceNicId: primaryRegion.outputs.dataVmNicIds[i]
vmManagedDisks: [
{
diskId: primaryRegion.outputs.dataVmOsDiskIds[i]
primaryStagingAzureStorageAccountId: cacheStorageAccount.id
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryReplicaDiskAccountType: 'Premium_LRS'
recoveryTargetDiskAccountType: 'Premium_LRS'
}
{
diskId: primaryRegion.outputs.dataVmDataDiskIds[i]
primaryStagingAzureStorageAccountId: cacheStorageAccount.id
recoveryResourceGroupId: secondaryResourceGroup.id
recoveryReplicaDiskAccountType: 'Premium_LRS'
recoveryTargetDiskAccountType: 'Premium_LRS'
}
]
}
}
dependsOn: [
recoveryServices
primaryRegion
secondaryRegion
]
}]

// Outputs
output trafficManagerFqdn string = trafficManager.outputs.fqdn
output trafficManagerProfileName string = trafficManager.outputs.profileName

output primaryRegion object = {
location: primaryLocation
resourceGroupName: primaryResourceGroupName
vnetName: primaryRegion.outputs.vnetName
loadBalancerFqdn: primaryRegion.outputs.loadBalancerFqdn
publicIpAddress: primaryRegion.outputs.publicIpAddress
webVmNames: primaryRegion.outputs.webVmNames
appVmNames: primaryRegion.outputs.appVmNames
dataVmNames: primaryRegion.outputs.dataVmNames
webVMSSName: primaryRegion.outputs.webVMSSName
appVMSSName: primaryRegion.outputs.appVMSSName
autoScalingEnabled: enableAutoScaling
vmssDeploymentSummary: primaryRegion.outputs.vmssDeploymentSummary
}

output secondaryRegion object = {
location: secondaryLocation
resourceGroupName: secondaryResourceGroupName
vnetName: secondaryRegion.outputs.vnetName
loadBalancerFqdn: secondaryRegion.outputs.loadBalancerFqdn
publicIpAddress: secondaryRegion.outputs.publicIpAddress
webVmNames: secondaryRegion.outputs.webVmNames
appVmNames: secondaryRegion.outputs.appVmNames
dataVmNames: secondaryRegion.outputs.dataVmNames
}

output recoveryServicesVault object = {
name: recoveryServices.outputs.vaultName
id: recoveryServices.outputs.vaultId
location: primaryLocation
}

output applicationEndpoints object = {
globalEndpoint: 'https://${trafficManager.outputs.fqdn}'
primaryEndpoint: 'https://${primaryRegion.outputs.loadBalancerFqdn}'
secondaryEndpoint: 'https://${secondaryRegion.outputs.loadBalancerFqdn}'
}

output azurePortalLinks object = {
trafficManager: 'https://portal.azure.com/#@/resource${trafficManager.outputs.profileId}'
recoveryVault: 'https://portal.azure.com/#@/resource${recoveryServices.outputs.vaultId}'
primaryRg: 'https://portal.azure.com/#@/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${primaryResourceGroupName}'
secondaryRg: 'https://portal.azure.com/#@/resource/subscriptions/${subscription().subscriptionId}/resourceGroups/${secondaryResourceGroupName}'
}

output estimatedMonthlyCost object = {
note: 'These are rough estimates. Actual costs may vary based on usage, region pricing, and current Azure rates.'
components: {
virtualMachines: '~$400-800/month (6 VMs total across both regions)'
loadBalancers: '~$40-60/month (2 Standard Load Balancers)'
trafficManager: '~$5-10/month'
storage: '~$20-50/month (depends on data volume)'
networking: '~$10-30/month (bandwidth and VNet peering)'
siteRecovery: '~$25/month per protected VM'
}
}