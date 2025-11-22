// Recovery Services Module - Creates Recovery Services Vault and Site Recovery

metadata description = 'Creates Recovery Services Vault and configures Site Recovery for disaster recovery'

// Parameters
@description('Project name for resource naming')
param projectName string

@description('Environment name')
param environment string

@description('Primary region location')
param location string

@description('Secondary region location')
param secondaryLocation string

@description('Primary resource group name')
param primaryResourceGroupName string

@description('Secondary resource group name')
param secondaryResourceGroupName string

@description('Resource tags')
param tags object

@description('Primary VNet ID for network mapping')
param primaryVnetId string

@description('Secondary VNet ID for network mapping')
param secondaryVnetId string

// Recovery Services Vault
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-08-01' = {
  name: '${projectName}-${environment}-rsv'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
  }
}

// Vault Storage Configuration
resource vaultStorageConfig 'Microsoft.RecoveryServices/vaults/backupstorageconfig@2023-08-01' = {
  parent: recoveryServicesVault
  name: 'vaultstorageconfig'
  properties: {
    storageModelType: 'GeoRedundant'
    crossRegionRestoreFlag: true
  }
}

// Site Recovery Fabric for Primary Region
resource primaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-primary-fabric'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: location
    }
  }
}

// Site Recovery Fabric for Secondary Region
resource secondaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-secondary-fabric'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: secondaryLocation
    }
  }
}

// Protection Container for Primary Region
resource primaryProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers@2023-08-01' = {
  parent: primaryFabric
  name: '${projectName}-primary-protection-container'
  properties: {
    providerSpecificDetails: [
      {
        instanceType: 'A2A'
      }
    ]
  }
}

// Protection Container for Secondary Region
resource secondaryProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers@2023-08-01' = {
  parent: secondaryFabric
  name: '${projectName}-secondary-protection-container'
  properties: {
    providerSpecificDetails: [
      {
        instanceType: 'A2A'
      }
    ]
  }
}

// Replication Policy
resource replicationPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-policy'
  properties: {
    providerSpecificDetails: {
      instanceType: 'A2A'
      recoveryPointRetentionInMinutes: 1440 // 24 hours
      appConsistentFrequencyInMinutes: 240  // 4 hours
      multiVmSyncStatus: 'Enable'
    }
  }
}

// Protection Container Mapping
resource protectionContainerMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectionContainerMappings@2023-08-01' = {
  parent: primaryProtectionContainer
  name: '${projectName}-container-mapping'
  properties: {
    targetProtectionContainerId: secondaryProtectionContainer.id
    policyId: replicationPolicy.id
    providerSpecificDetails: {
      instanceType: 'A2A'
    }
  }
}

// Network Mapping from Primary to Secondary
resource networkMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationNetworks/replicationNetworkMappings@2023-08-01' = {
  name: '${recoveryServicesVault.name}/${primaryFabric.name}/${last(split(primaryVnetId, '/'))}/primary-to-secondary-network-mapping'
  properties: {
    recoveryFabricName: secondaryFabric.name
    recoveryNetworkId: secondaryVnetId
    fabricSpecificDetails: {
      instanceType: 'AzureToAzure'
      primaryNetworkId: primaryVnetId
    }
  }
  dependsOn: [
    primaryFabric
    secondaryFabric
  ]
}

// Diagnostic Settings for the Recovery Services Vault
resource diagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  scope: recoveryServicesVault
  name: '${projectName}-${environment}-rsv-diagnostics'
  properties: {
    logs: [
      {
        categoryGroup: 'allLogs'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    metrics: [
      {
        category: 'Health'
        enabled: true
        retentionPolicy: {
          enabled: true
          days: 30
        }
      }
    ]
    workspaceId: logAnalyticsWorkspace.id
  }
}

// Log Analytics Workspace for monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${projectName}-${environment}-logs'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Outputs
output vaultId string = recoveryServicesVault.id
output vaultName string = recoveryServicesVault.name
output primaryFabricName string = primaryFabric.name
output secondaryFabricName string = secondaryFabric.name
output replicationPolicyName string = replicationPolicy.name
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id