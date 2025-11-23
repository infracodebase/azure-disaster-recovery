// Region Module - Deploys multi-tier infrastructure in a single Azure region
// This module can be used for both primary and secondary (DR) regions

metadata description = 'Regional deployment module for multi-tier architecture'

// Parameters
@description('Project name for resource naming')
param projectName string

@description('Environment name')
param environment string

@description('Azure region for deployment')
param location string

@description('Region suffix (primary/secondary)')
param regionSuffix string

@description('VNet address space')
param addressSpace array

@description('Web subnet prefix')
param webSubnetPrefix string

@description('App subnet prefix')
param appSubnetPrefix string

@description('Data subnet prefix')
param dataSubnetPrefix string

@description('VM admin username')
param vmAdminUsername string

@description('VM admin password')
@secure()
param vmAdminPassword string

@description('Web VM size')
param vmSizeWeb string

@description('App VM size')
param vmSizeApp string

@description('Data VM size')
param vmSizeData string

@description('Use Availability Zones')
param useAvailabilityZones bool

@description('Enable VMSS deployment')
param enableVMSS bool = false

@description('Enable auto-scaling')
param enableAutoScaling bool = false

@description('Auto-scaling configuration')
param autoScalingConfig object = {}

@description('Is this a DR region')
param isDRRegion bool

@description('Resource tags')
param tags object

// Variables
var vmCount = 2
var availabilityZones = useAvailabilityZones ? ['1', '2'] : []

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-vnet'
  location: location
  tags: tags
  properties: {
    addressSpace: {
      addressPrefixes: addressSpace
    }
  }
}

// Subnets
resource webSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'web-subnet'
  properties: {
    addressPrefix: webSubnetPrefix
    networkSecurityGroup: {
      id: webNsg.id
    }
  }
}

resource appSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'app-subnet'
  properties: {
    addressPrefix: appSubnetPrefix
    networkSecurityGroup: {
      id: appNsg.id
    }
  }
}

resource dataSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: vnet
  name: 'data-subnet'
  properties: {
    addressPrefix: dataSubnetPrefix
    networkSecurityGroup: {
      id: dataNsg.id
    }
  }
}

// Network Security Groups
resource webNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-web-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'HTTP'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'HTTPS'
        properties: {
          priority: 1002
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'SSH'
        properties: {
          priority: 1003
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource appNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-app-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'AppPort'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '8080'
          sourceAddressPrefix: webSubnetPrefix
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'SSH'
        properties: {
          priority: 1002
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource dataNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-data-nsg'
  location: location
  tags: tags
  properties: {
    securityRules: [
      {
        name: 'MySQL'
        properties: {
          priority: 1001
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: appSubnetPrefix
          destinationAddressPrefix: '*'
          description: 'Allow MySQL from app tier'
        }
      }
      {
        name: 'SSH'
        properties: {
          priority: 1002
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          description: 'Allow SSH from private networks'
        }
      }
      {
        name: 'MySQL-Replication-CrossRegion'
        properties: {
          priority: 1003
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          description: 'Allow MySQL replication from other regions'
        }
      }
      {
        name: 'MySQL-Replication-Local'
        properties: {
          priority: 1004
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3306'
          sourceAddressPrefix: dataSubnetPrefix
          destinationAddressPrefix: '*'
          description: 'Allow MySQL replication within data tier'
        }
      }
      {
        name: 'MySQL-Monitoring'
        properties: {
          priority: 1005
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRanges: ['3306', '33060']
          sourceAddressPrefix: '10.0.0.0/8'
          destinationAddressPrefix: '*'
          description: 'Allow MySQL monitoring and X Protocol'
        }
      }
    ]
  }
}

// Public IP for Load Balancer
resource publicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-pip'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${projectName}-${environment}-${regionSuffix}'
    }
  }
}

// Load Balancer
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-lb'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'PublicIPAddress'
        properties: {
          publicIPAddress: {
            id: publicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'BackEndAddressPool'
      }
    ]
    probes: [
      {
        name: 'http-probe'
        properties: {
          protocol: 'Http'
          port: 80
          requestPath: '/health'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'LBRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${projectName}-${environment}-${regionSuffix}-lb', 'PublicIPAddress')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${projectName}-${environment}-${regionSuffix}-lb', 'BackEndAddressPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${projectName}-${environment}-${regionSuffix}-lb', 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 80
          backendPort: 80
          idleTimeoutInMinutes: 4
        }
      }
      {
        name: 'HTTPSRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${projectName}-${environment}-${regionSuffix}-lb', 'PublicIPAddress')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${projectName}-${environment}-${regionSuffix}-lb', 'BackEndAddressPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${projectName}-${environment}-${regionSuffix}-lb', 'http-probe')
          }
          protocol: 'Tcp'
          frontendPort: 443
          backendPort: 443
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// Internal Load Balancer for App Tier
resource internalLoadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${projectName}-${environment}-${regionSuffix}-internal-lb'
  location: location
  tags: tags
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'InternalIPAddress'
        properties: {
          subnet: {
            id: appSubnet.id
          }
          privateIPAllocationMethod: 'Dynamic'
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'InternalBackEndAddressPool'
      }
    ]
    probes: [
      {
        name: 'app-probe'
        properties: {
          protocol: 'Http'
          port: 8080
          requestPath: '/health'
          intervalInSeconds: 30
          numberOfProbes: 3
        }
      }
    ]
    loadBalancingRules: [
      {
        name: 'AppLBRule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${projectName}-${environment}-${regionSuffix}-internal-lb', 'InternalIPAddress')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${projectName}-${environment}-${regionSuffix}-internal-lb', 'InternalBackEndAddressPool')
          }
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${projectName}-${environment}-${regionSuffix}-internal-lb', 'app-probe')
          }
          protocol: 'Tcp'
          frontendPort: 8080
          backendPort: 8080
          idleTimeoutInMinutes: 4
        }
      }
    ]
  }
}

// Availability Sets (when not using Availability Zones)
resource webAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = if (!useAvailabilityZones) {
  name: '${projectName}-${environment}-${regionSuffix}-web-as'
  location: location
  tags: merge(tags, { Tier: 'Web' })
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
}

resource appAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = if (!useAvailabilityZones) {
  name: '${projectName}-${environment}-${regionSuffix}-app-as'
  location: location
  tags: merge(tags, { Tier: 'Application' })
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
}

resource dataAvailabilitySet 'Microsoft.Compute/availabilitySets@2023-09-01' = if (!useAvailabilityZones) {
  name: '${projectName}-${environment}-${regionSuffix}-data-as'
  location: location
  tags: merge(tags, { Tier: 'Data' })
  sku: {
    name: 'Aligned'
  }
  properties: {
    platformFaultDomainCount: 2
    platformUpdateDomainCount: 2
  }
}

// Data Disks for Database Storage
resource dataDisks 'Microsoft.Compute/disks@2023-10-02' = [for i in range(0, vmCount): if (!isDRRegion) {
  name: '${projectName}-${environment}-${regionSuffix}-data-vm-${i + 1}-data-disk'
  location: location
  tags: merge(tags, { Tier: 'Data' })
  sku: {
    name: 'Premium_LRS'
  }
  properties: {
    creationData: {
      createOption: 'Empty'
    }
    diskSizeGB: 128
  }
}]

// Web Tier VMs (only deployed when VMSS is disabled)
module webVMs 'vm.bicep' = [for i in range(0, vmCount): if (!isDRRegion && !enableVMSS) {
  name: 'webVM${i + 1}'
  params: {
    vmName: '${projectName}-${environment}-${regionSuffix}-web-vm-${i + 1}'
    location: location
    vmSize: vmSizeWeb
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    subnetId: webSubnet.id
    loadBalancerBackendPoolId: '${loadBalancer.id}/backendAddressPools/BackEndAddressPool'
    availabilitySetId: useAvailabilityZones ? null : webAvailabilitySet.id
    availabilityZone: useAvailabilityZones ? availabilityZones[i % length(availabilityZones)] : null
    tier: 'web'
    tags: merge(tags, { Tier: 'Web' })
    customData: loadFileAsBase64('../scripts/web-setup.sh')
  }
}]

// App Tier VMs (only deployed when VMSS is disabled)
module appVMs 'vm.bicep' = [for i in range(0, vmCount): if (!isDRRegion && !enableVMSS) {
  name: 'appVM${i + 1}'
  params: {
    vmName: '${projectName}-${environment}-${regionSuffix}-app-vm-${i + 1}'
    location: location
    vmSize: vmSizeApp
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    subnetId: appSubnet.id
    loadBalancerBackendPoolId: '${internalLoadBalancer.id}/backendAddressPools/InternalBackEndAddressPool'
    availabilitySetId: useAvailabilityZones ? null : appAvailabilitySet.id
    availabilityZone: useAvailabilityZones ? availabilityZones[i % length(availabilityZones)] : null
    tier: 'app'
    tags: merge(tags, { Tier: 'Application' })
    customData: loadFileAsBase64('../scripts/app-setup.sh')
  }
}]

// Data Tier VMs (always deployed as individual VMs for database persistence)
module dataVMs 'vm.bicep' = [for i in range(0, vmCount): if (!isDRRegion) {
  name: 'dataVM${i + 1}'
  params: {
    vmName: '${projectName}-${environment}-${regionSuffix}-data-vm-${i + 1}'
    location: location
    vmSize: vmSizeData
    adminUsername: vmAdminUsername
    adminPassword: vmAdminPassword
    subnetId: dataSubnet.id
    loadBalancerBackendPoolId: null
    availabilitySetId: useAvailabilityZones ? null : dataAvailabilitySet.id
    availabilityZone: useAvailabilityZones ? availabilityZones[i % length(availabilityZones)] : null
    tier: 'data'
    tags: merge(tags, { Tier: 'Data' })
    customData: loadFileAsBase64('../scripts/data-setup-enhanced.sh')
    dataDiskId: !isDRRegion ? dataDisks[i].id : null
  }
}]

// VMSS Module (when enabled)
module vmssDeployment 'vmss.bicep' = if (enableVMSS) {
  name: 'vmssDeployment'
  params: {
    projectName: projectName
    environment: environment
    location: location
    regionSuffix: regionSuffix
    isDRRegion: isDRRegion
    enableVMSS: enableVMSS
    enableAutoScaling: enableAutoScaling
    webSubnetId: webSubnet.id
    appSubnetId: appSubnet.id
    webLoadBalancerBackendPoolId: '${loadBalancer.id}/backendAddressPools/BackEndAddressPool'
    appLoadBalancerBackendPoolId: '${internalLoadBalancer.id}/backendAddressPools/InternalBackEndAddressPool'
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
    vmSizeWeb: vmSizeWeb
    vmSizeApp: vmSizeApp
    useAvailabilityZones: useAvailabilityZones
    autoScalingConfig: autoScalingConfig
    tags: tags
  }
  dependsOn: [
    loadBalancer
    internalLoadBalancer
  ]
}

// Outputs
output resourceGroupName string = resourceGroup().name
output vnetName string = vnet.name
output vnetId string = vnet.id
output publicIpId string = publicIp.id
output publicIpAddress string = publicIp.properties.ipAddress
output loadBalancerFqdn string = publicIp.properties.dnsSettings.fqdn
output loadBalancerId string = loadBalancer.id
output internalLoadBalancerIp string = internalLoadBalancer.properties.frontendIPConfigurations[0].properties.privateIPAddress

output webSubnetId string = webSubnet.id
output appSubnetId string = appSubnet.id
output dataSubnetId string = dataSubnet.id

output webVmNames array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): webVMs[i].outputs.vmName] : []
output appVmNames array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): appVMs[i].outputs.vmName] : []
output dataVmNames array = !isDRRegion ? [for i in range(0, vmCount): dataVMs[i].outputs.vmName] : []

output webVmIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): webVMs[i].outputs.vmId] : []
output appVmIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): appVMs[i].outputs.vmId] : []
output dataVmIds array = !isDRRegion ? [for i in range(0, vmCount): dataVMs[i].outputs.vmId] : []

// VM Network Interface IDs for Site Recovery
output webVmNicIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): webVMs[i].outputs.nicId] : []
output appVmNicIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): appVMs[i].outputs.nicId] : []
output dataVmNicIds array = !isDRRegion ? [for i in range(0, vmCount): dataVMs[i].outputs.nicId] : []

// VM OS Disk IDs for Site Recovery
output webVmOsDiskIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): webVMs[i].outputs.osDiskId] : []
output appVmOsDiskIds array = (!isDRRegion && !enableVMSS) ? [for i in range(0, vmCount): appVMs[i].outputs.osDiskId] : []
output dataVmOsDiskIds array = !isDRRegion ? [for i in range(0, vmCount): dataVMs[i].outputs.osDiskId] : []

// VM Data Disk IDs for Site Recovery
output dataVmDataDiskIds array = !isDRRegion ? [for i in range(0, vmCount): dataDisks[i].id] : []

// Availability Set IDs for Site Recovery
output webAvailabilitySetId string = !useAvailabilityZones && !isDRRegion ? webAvailabilitySet.id : ''
output appAvailabilitySetId string = !useAvailabilityZones && !isDRRegion ? appAvailabilitySet.id : ''
output dataAvailabilitySetId string = !useAvailabilityZones && !isDRRegion ? dataAvailabilitySet.id : ''

// VMSS Outputs
output webVMSSName string = enableVMSS ? vmssDeployment.outputs.webVMSSName : ''
output appVMSSName string = enableVMSS ? vmssDeployment.outputs.appVMSSName : ''
output webVMSSId string = enableVMSS ? vmssDeployment.outputs.webVMSSId : ''
output appVMSSId string = enableVMSS ? vmssDeployment.outputs.appVMSSId : ''

output webAutoScaleSettingId string = enableVMSS && enableAutoScaling ? vmssDeployment.outputs.webAutoScaleSettingId : ''
output appAutoScaleSettingId string = enableVMSS && enableAutoScaling ? vmssDeployment.outputs.appAutoScaleSettingId : ''

output vmssDeploymentSummary object = enableVMSS ? vmssDeployment.outputs.vmssDeploymentSummary : {}

output regionSummary object = {
  location: location
  regionSuffix: regionSuffix
  isDRRegion: isDRRegion
  useAvailabilityZones: useAvailabilityZones
  enableVMSS: enableVMSS
  enableAutoScaling: enableAutoScaling
  webVmCount: (!isDRRegion && !enableVMSS) ? vmCount : 0
  appVmCount: (!isDRRegion && !enableVMSS) ? vmCount : 0
  dataVmCount: !isDRRegion ? vmCount : 0
  webVMSSEnabled: enableVMSS && !isDRRegion
  appVMSSEnabled: enableVMSS && !isDRRegion
  autoScalingEnabled: enableVMSS && enableAutoScaling && !isDRRegion
  totalVmCount: !isDRRegion ? (enableVMSS ? vmCount : vmCount * 3) : 0
}