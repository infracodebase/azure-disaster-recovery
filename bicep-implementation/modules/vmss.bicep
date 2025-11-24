// Virtual Machine Scale Sets (VMSS) Module for Bicep
// This module deploys Azure Virtual Machine Scale Sets with auto-scaling capabilities

metadata description = 'Azure Virtual Machine Scale Sets with auto-scaling for web and app tiers'
metadata author = 'Azure Infrastructure Team'
metadata version = '1.0.0'

// Parameters
@description('Project name for resource naming')
param projectName string

@description('Environment name')
param environment string

@description('Azure region for deployment')
param location string

@description('Region suffix (primary/secondary)')
param regionSuffix string

@description('Is this a DR region')
param isDRRegion bool

@description('Enable VMSS deployment')
param enableVMSS bool

@description('Enable auto-scaling')
param enableAutoScaling bool

@description('Web subnet ID')
param webSubnetId string

@description('App subnet ID')
param appSubnetId string

@description('Load balancer backend pool ID for web tier')
param webLoadBalancerBackendPoolId string

@description('Internal load balancer backend pool ID for app tier')
param appLoadBalancerBackendPoolId string

@description('VM admin username')
param vmAdminUsername string

@description('VM admin password')
@secure()
param vmAdminPassword string

@description('Web VM size')
param vmSizeWeb string

@description('App VM size')
param vmSizeApp string

@description('Use Availability Zones')
param useAvailabilityZones bool

@description('Auto-scaling configuration')
param autoScalingConfig object

@description('Resource tags')
param tags object

// Variables
var availabilityZones = useAvailabilityZones ? ['1', '2'] : []

// SSH Key Generation for VMSS (using deployment script)
resource sshKeyGeneration 'Microsoft.Resources/deploymentScripts@2023-08-01' = if (enableVMSS && !isDRRegion) {
name: '${projectName}-${environment}-${regionSuffix}-ssh-key-gen'
location: location
kind: 'AzureCLI'
tags: tags
properties: {
azCliVersion: '2.50.0'
scriptContent: '''
ssh-keygen -t rsa -b 4096 -f vmss_key -N ""
echo "{\"publicKey\": \"$(cat vmss_key.pub)\", \"privateKey\": \"$(cat vmss_key | base64 -w 0)\"}" > $AZ_SCRIPTS_OUTPUT_PATH
'''
timeout: 'PT10M'
retentionInterval: 'PT1H'
cleanupPreference: 'OnSuccess'
}
}

// Web Tier Virtual Machine Scale Set
resource webVMSS 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = if (enableVMSS && !isDRRegion) {
name: '${projectName}-${environment}-${regionSuffix}-web-vmss'
location: location
tags: merge(tags, {
Tier: 'Web'
ResourceType: 'VMSS'
})
sku: {
name: vmSizeWeb
capacity: autoScalingConfig.webTier.defaultInstances
}
properties: {
platformFaultDomainCount: 1
singlePlacementGroup: false
orchestrationMode: 'Flexible'

virtualMachineProfile: {
osProfile: {
computerNamePrefix: 'web'
adminUsername: vmAdminUsername
adminPassword: vmAdminPassword
linuxConfiguration: {
disablePasswordAuthentication: false
ssh: {
publicKeys: [
{
path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
keyData: enableVMSS && !isDRRegion ? json(sshKeyGeneration.properties.outputs).publicKey : ''
}
]
}
}
customData: loadFileAsBase64('../scripts/web-setup.sh')
}
storageProfile: {
osDisk: {
createOption: 'FromImage'
caching: 'ReadWrite'
managedDisk: {
storageAccountType: 'Premium_LRS'
}
}
imageReference: {
publisher: 'Canonical'
offer: '0001-com-ubuntu-server-focal'
sku: '20_04-lts-gen2'
version: 'latest'
}
}
networkProfile: {
networkInterfaceConfigurations: [
{
name: 'web-vmss-nic'
properties: {
primary: true
ipConfigurations: [
{
name: 'internal'
properties: {
primary: true
subnet: {
id: webSubnetId
}
loadBalancerBackendAddressPools: [
{
id: webLoadBalancerBackendPoolId
}
]
}
}
]
}
}
]
}
extensionProfile: {
extensions: [
{
name: 'HealthExtension'
properties: {
publisher: 'Microsoft.ManagedServices'
type: 'ApplicationHealthLinux'
typeHandlerVersion: '1.0'
autoUpgradeMinorVersion: true
settings: {
protocol: 'http'
port: 80
requestPath: '/'
}
}
}
]
}
}

// Zone configuration
zoneBalance: useAvailabilityZones
zones: useAvailabilityZones ? availabilityZones : null
}
}

// App Tier Virtual Machine Scale Set
resource appVMSS 'Microsoft.Compute/virtualMachineScaleSets@2023-09-01' = if (enableVMSS && !isDRRegion) {
name: '${projectName}-${environment}-${regionSuffix}-app-vmss'
location: location
tags: merge(tags, {
Tier: 'Application'
ResourceType: 'VMSS'
})
sku: {
name: vmSizeApp
capacity: autoScalingConfig.appTier.defaultInstances
}
properties: {
platformFaultDomainCount: 1
singlePlacementGroup: false
orchestrationMode: 'Flexible'

virtualMachineProfile: {
osProfile: {
computerNamePrefix: 'app'
adminUsername: vmAdminUsername
adminPassword: vmAdminPassword
linuxConfiguration: {
disablePasswordAuthentication: false
ssh: {
publicKeys: [
{
path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
keyData: enableVMSS && !isDRRegion ? json(sshKeyGeneration.properties.outputs).publicKey : ''
}
]
}
}
customData: loadFileAsBase64('../scripts/app-setup.sh')
}
storageProfile: {
osDisk: {
createOption: 'FromImage'
caching: 'ReadWrite'
managedDisk: {
storageAccountType: 'Premium_LRS'
}
}
imageReference: {
publisher: 'Canonical'
offer: '0001-com-ubuntu-server-focal'
sku: '20_04-lts-gen2'
version: 'latest'
}
}
networkProfile: {
networkInterfaceConfigurations: [
{
name: 'app-vmss-nic'
properties: {
primary: true
ipConfigurations: [
{
name: 'internal'
properties: {
primary: true
subnet: {
id: appSubnetId
}
loadBalancerBackendAddressPools: [
{
id: appLoadBalancerBackendPoolId
}
]
}
}
]
}
}
]
}
extensionProfile: {
extensions: [
{
name: 'HealthExtension'
properties: {
publisher: 'Microsoft.ManagedServices'
type: 'ApplicationHealthLinux'
typeHandlerVersion: '1.0'
autoUpgradeMinorVersion: true
settings: {
protocol: 'http'
port: 80
requestPath: '/health'
}
}
}
]
}
}

// Zone configuration
zoneBalance: useAvailabilityZones
zones: useAvailabilityZones ? availabilityZones : null
}
}

// Auto-scaling Settings for Web Tier
resource webAutoScaleSetting 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableVMSS && enableAutoScaling && !isDRRegion) {
name: '${projectName}-${environment}-${regionSuffix}-web-autoscale'
location: location
tags: tags
properties: {
profiles: [
// Default Profile
{
name: 'DefaultProfile'
capacity: {
minimum: string(autoScalingConfig.webTier.minInstances)
maximum: string(autoScalingConfig.webTier.maxInstances)
default: string(autoScalingConfig.webTier.defaultInstances)
}
rules: [
// CPU Scale-out rule
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'GreaterThan'
threshold: autoScalingConfig.webTier.scaleOutCpuThreshold
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT5M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.webTier.scaleOutCooldown
}
}
// CPU Scale-in rule
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'LessThan'
threshold: autoScalingConfig.webTier.scaleInCpuThreshold
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT10M'
statistic: 'Average'
}
scaleAction: {
direction: 'Decrease'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.webTier.scaleInCooldown
}
}
// Memory Scale-out rule
{
metricTrigger: {
metricName: 'Available Memory Bytes'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'LessThan'
threshold: 1073741824 // 1 GB in bytes
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT5M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.webTier.scaleOutCooldown
}
}
// Memory Scale-in rule
{
metricTrigger: {
metricName: 'Available Memory Bytes'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'GreaterThan'
threshold: 2147483648 // 2 GB in bytes
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT10M'
statistic: 'Average'
}
scaleAction: {
direction: 'Decrease'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.webTier.scaleInCooldown
}
}
]
}
// Weekend Profile with conservative scaling
{
name: 'WeekendProfile'
capacity: {
minimum: string(autoScalingConfig.webTier.minInstances)
maximum: string(autoScalingConfig.webTier.maxInstances)
default: string(autoScalingConfig.webTier.minInstances)
}
rules: [
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'GreaterThan'
threshold: 80
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT10M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: 'PT10M'
}
}
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
operator: 'LessThan'
threshold: 20
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT15M'
statistic: 'Average'
}
scaleAction: {
direction: 'Decrease'
type: 'ChangeCount'
value: '1'
cooldown: 'PT15M'
}
}
]
recurrence: {
frequency: 'Week'
schedule: {
timeZone: 'UTC'
days: ['Saturday', 'Sunday']
hours: [0]
minutes: [0]
}
}
}
]
enabled: true
targetResourceUri: enableVMSS && !isDRRegion ? webVMSS.id : ''
notifications: [
{
operation: 'Scale'
email: {
sendToSubscriptionAdministrator: false
sendToSubscriptionCoAdministrators: false
customEmails: []
}
webhooks: []
}
]
}
}

// Auto-scaling Settings for App Tier
resource appAutoScaleSetting 'Microsoft.Insights/autoscalesettings@2022-10-01' = if (enableVMSS && enableAutoScaling && !isDRRegion) {
name: '${projectName}-${environment}-${regionSuffix}-app-autoscale'
location: location
tags: tags
properties: {
profiles: [
// Default Profile
{
name: 'DefaultProfile'
capacity: {
minimum: string(autoScalingConfig.appTier.minInstances)
maximum: string(autoScalingConfig.appTier.maxInstances)
default: string(autoScalingConfig.appTier.defaultInstances)
}
rules: [
// CPU Scale-out rule
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'GreaterThan'
threshold: autoScalingConfig.appTier.scaleOutCpuThreshold
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT5M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.appTier.scaleOutCooldown
}
}
// CPU Scale-in rule
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'LessThan'
threshold: autoScalingConfig.appTier.scaleInCpuThreshold
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT15M'
statistic: 'Average'
}
scaleAction: {
direction: 'Decrease'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.appTier.scaleInCooldown
}
}
// Memory Scale-out rule
{
metricTrigger: {
metricName: 'Available Memory Bytes'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'LessThan'
threshold: 805306368 // 768 MB in bytes
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT5M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.appTier.scaleOutCooldown
}
}
// Memory Scale-in rule
{
metricTrigger: {
metricName: 'Available Memory Bytes'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'GreaterThan'
threshold: 2684354560 // 2.5 GB in bytes
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT15M'
statistic: 'Average'
}
scaleAction: {
direction: 'Decrease'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.appTier.scaleInCooldown
}
}
// Network Scale-out rule (App tier specific)
{
metricTrigger: {
metricName: 'Network In Total'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'GreaterThan'
threshold: 52428800 // 50 MB in bytes
timeAggregation: 'Total'
timeGrain: 'PT1M'
timeWindow: 'PT5M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: autoScalingConfig.appTier.scaleOutCooldown
}
}
]
}
// Business Hours Profile with aggressive scaling
{
name: 'BusinessHoursProfile'
capacity: {
minimum: string(autoScalingConfig.appTier.minInstances)
maximum: string(autoScalingConfig.appTier.maxInstances)
default: string(autoScalingConfig.appTier.defaultInstances)
}
rules: [
{
metricTrigger: {
metricName: 'Percentage CPU'
metricNamespace: 'Microsoft.Compute/virtualMachineScaleSets'
metricResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
operator: 'GreaterThan'
threshold: 60
timeAggregation: 'Average'
timeGrain: 'PT1M'
timeWindow: 'PT3M'
statistic: 'Average'
}
scaleAction: {
direction: 'Increase'
type: 'ChangeCount'
value: '1'
cooldown: 'PT3M'
}
}
]
recurrence: {
frequency: 'Week'
schedule: {
timeZone: 'UTC'
days: ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday']
hours: [9]
minutes: [0]
}
}
}
]
enabled: true
targetResourceUri: enableVMSS && !isDRRegion ? appVMSS.id : ''
notifications: [
{
operation: 'Scale'
email: {
sendToSubscriptionAdministrator: false
sendToSubscriptionCoAdministrators: false
customEmails: []
}
webhooks: []
}
]
}
}

// Outputs
output webVMSSId string = enableVMSS && !isDRRegion ? webVMSS.id : ''
output appVMSSId string = enableVMSS && !isDRRegion ? appVMSS.id : ''
output webVMSSName string = enableVMSS && !isDRRegion ? webVMSS.name : ''
output appVMSSName string = enableVMSS && !isDRRegion ? appVMSS.name : ''

output webAutoScaleSettingId string = enableVMSS && enableAutoScaling && !isDRRegion ? webAutoScaleSetting.id : ''
output appAutoScaleSettingId string = enableVMSS && enableAutoScaling && !isDRRegion ? appAutoScaleSetting.id : ''

output sshPublicKey string = enableVMSS && !isDRRegion ? json(sshKeyGeneration.properties.outputs).publicKey : ''

output vmssDeploymentSummary object = {
enableVMSS: enableVMSS
enableAutoScaling: enableAutoScaling
isDRRegion: isDRRegion
webVMSSDeployed: enableVMSS && !isDRRegion
appVMSSDeployed: enableVMSS && !isDRRegion
autoScalingEnabled: enableVMSS && enableAutoScaling && !isDRRegion
webTierConfig: autoScalingConfig.webTier
appTierConfig: autoScalingConfig.appTier
}