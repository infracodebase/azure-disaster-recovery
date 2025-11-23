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

// Recovery Services Vault (Primary Region - East US)
resource recoveryServicesVault 'Microsoft.RecoveryServices/vaults@2023-08-01' = {
  name: '${projectName}-${environment}-eastus-recovery-vault'
  location: location
  tags: merge(tags, {
    Purpose: 'Cross-region disaster recovery'
    SourceRegion: 'East US'
    TargetRegion: 'West US 2'
  })
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

// Site Recovery Fabric for Primary Region (East US)
resource primaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-${environment}-primary-eastus-fabric'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: location
    }
  }
}

// Site Recovery Fabric for Secondary Region (West US 2)
resource secondaryFabric 'Microsoft.RecoveryServices/vaults/replicationFabrics@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-${environment}-secondary-westus2-fabric'
  properties: {
    customDetails: {
      instanceType: 'Azure'
      location: secondaryLocation
    }
  }
}

// Protection Container for Primary Region (East US)
resource primaryProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers@2023-08-01' = {
  parent: primaryFabric
  name: '${projectName}-${environment}-primary-eastus-protection-container'
  properties: {
    providerSpecificDetails: [
      {
        instanceType: 'A2A'
      }
    ]
  }
}

// Protection Container for Secondary Region (West US 2)
resource secondaryProtectionContainer 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers@2023-08-01' = {
  parent: secondaryFabric
  name: '${projectName}-${environment}-secondary-westus2-protection-container'
  properties: {
    providerSpecificDetails: [
      {
        instanceType: 'A2A'
      }
    ]
  }
}

// Replication Policy (Cross-region: East US → West US 2)
resource replicationPolicy 'Microsoft.RecoveryServices/vaults/replicationPolicies@2023-08-01' = {
  parent: recoveryServicesVault
  name: '${projectName}-${environment}-eastus-to-westus2-replication-policy'
  properties: {
    providerSpecificDetails: {
      instanceType: 'A2A'
      recoveryPointRetentionInMinutes: 1440 // 24 hours retention
      appConsistentFrequencyInMinutes: 240  // 4 hours app-consistent snapshots
      multiVmSyncStatus: 'Enable'            // Enable multi-VM consistency
    }
  }
}

// Protection Container Mapping (Primary → Secondary)
resource protectionContainerMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationProtectionContainers/replicationProtectionContainerMappings@2023-08-01' = {
  parent: primaryProtectionContainer
  name: '${projectName}-${environment}-eastus-to-westus2-container-mapping'
  properties: {
    targetProtectionContainerId: secondaryProtectionContainer.id
    policyId: replicationPolicy.id
    providerSpecificDetails: {
      instanceType: 'A2A'
    }
  }
}

// Network Mapping (East US VNet → West US 2 VNet)
resource networkMapping 'Microsoft.RecoveryServices/vaults/replicationFabrics/replicationNetworks/replicationNetworkMappings@2023-08-01' = {
  name: '${recoveryServicesVault.name}/${primaryFabric.name}/${last(split(primaryVnetId, '/'))}/eastus-to-westus2-vnet-mapping'
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
  name: '${projectName}-${environment}-recovery-vault-diagnostics'
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

// Log Analytics Workspace for Site Recovery monitoring
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: '${projectName}-${environment}-siterecovery-logs'
  location: location
  tags: merge(tags, {
    Purpose: 'Site Recovery monitoring and diagnostics'
    Component: 'Log Analytics'
  })
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