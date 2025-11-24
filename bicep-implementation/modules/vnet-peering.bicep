// VNet Peering Module - Creates bidirectional VNet peering between regions

metadata description = 'Creates VNet peering between primary and secondary regions'

targetScope = 'subscription'

// Parameters
@description('Primary resource group name')
param primaryResourceGroupName string

@description('Secondary resource group name')
param secondaryResourceGroupName string

@description('Primary VNet name')
param primaryVnetName string

@description('Secondary VNet name')
param secondaryVnetName string

@description('Primary VNet ID')
param primaryVnetId string

@description('Secondary VNet ID')
param secondaryVnetId string

@description('Project name for resource naming')
param projectName string

@description('Environment name')
param environment string

// Primary to Secondary Peering
resource primaryToSecondaryPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
scope: resourceGroup(primaryResourceGroupName)
name: '${primaryVnetName}/${projectName}-${environment}-primary-to-secondary'
properties: {
allowVirtualNetworkAccess: true
allowForwardedTraffic: true
allowGatewayTransit: false
useRemoteGateways: false
remoteVirtualNetwork: {
id: secondaryVnetId
}
}
}

// Secondary to Primary Peering
resource secondaryToPrimaryPeering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
scope: resourceGroup(secondaryResourceGroupName)
name: '${secondaryVnetName}/${projectName}-${environment}-secondary-to-primary'
properties: {
allowVirtualNetworkAccess: true
allowForwardedTraffic: true
allowGatewayTransit: false
useRemoteGateways: false
remoteVirtualNetwork: {
id: primaryVnetId
}
}
}

// Outputs
output primaryToSecondaryPeeringName string = primaryToSecondaryPeering.name
output secondaryToPrimaryPeeringName string = secondaryToPrimaryPeering.name