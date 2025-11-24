// VM Module - Creates a single virtual machine with optional data disk

metadata description = 'Creates a virtual machine for the multi-tier architecture'

// Parameters
@description('Virtual machine name')
param vmName string

@description('Azure region for deployment')
param location string

@description('VM size')
param vmSize string

@description('Admin username')
param adminUsername string

@description('Admin password')
@secure()
param adminPassword string

@description('Subnet ID for VM placement')
param subnetId string

@description('Load balancer backend pool ID (optional)')
param loadBalancerBackendPoolId string?

@description('Availability set ID (when not using zones)')
param availabilitySetId string?

@description('Availability zone (when using zones)')
param availabilityZone string?

@description('Tier type for the VM')
@allowed(['web', 'app', 'data'])
param tier string

@description('Resource tags')
param tags object

@description('Custom data for VM initialization')
param customData string

@description('Data disk ID for data tier VMs')
param dataDiskId string?

// Network Interface
resource networkInterface 'Microsoft.Network/networkInterfaces@2023-09-01' = {
name: '${vmName}-nic'
location: location
tags: tags
properties: {
ipConfigurations: [
{
name: 'internal'
properties: {
privateIPAllocationMethod: 'Dynamic'
subnet: {
id: subnetId
}
loadBalancerBackendAddressPools: loadBalancerBackendPoolId != null ? [
{
id: loadBalancerBackendPoolId
}
] : []
}
}
]
}
}

// Virtual Machine
resource virtualMachine 'Microsoft.Compute/virtualMachines@2024-03-01' = {
name: vmName
location: location
tags: tags
zones: availabilityZone != null ? [availabilityZone] : []
properties: {
availabilitySet: availabilitySetId != null ? {
id: availabilitySetId
} : null
hardwareProfile: {
vmSize: vmSize
}
osProfile: {
computerName: vmName
adminUsername: adminUsername
adminPassword: adminPassword
customData: customData
linuxConfiguration: {
disablePasswordAuthentication: false
provisionVMAgent: true
patchSettings: {
patchMode: 'ImageDefault'
assessmentMode: 'ImageDefault'
}
}
}
storageProfile: {
imageReference: {
publisher: 'Canonical'
offer: '0001-com-ubuntu-server-focal'
sku: '20_04-lts-gen2'
version: 'latest'
}
osDisk: {
name: '${vmName}-os-disk'
caching: 'ReadWrite'
createOption: 'FromImage'
managedDisk: {
storageAccountType: 'Premium_LRS'
}
deleteOption: 'Delete'
}
dataDisks: tier == 'data' && dataDiskId != null ? [
{
name: '${vmName}-data-disk'
lun: 0
createOption: 'Attach'
managedDisk: {
id: dataDiskId
}
caching: 'ReadWrite'
deleteOption: 'Delete'
}
] : []
}
networkProfile: {
networkInterfaces: [
{
id: networkInterface.id
properties: {
deleteOption: 'Delete'
}
}
]
}
diagnosticsProfile: {
bootDiagnostics: {
enabled: true
}
}
securityProfile: {
securityType: 'Standard'
}
}
}

// Outputs
output vmId string = virtualMachine.id
output vmName string = virtualMachine.name
output privateIPAddress string = networkInterface.properties.ipConfigurations[0].properties.privateIPAddress
output nicId string = networkInterface.id
output osDiskId string = virtualMachine.properties.storageProfile.osDisk.managedDisk.id