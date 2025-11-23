# Bicep Infrastructure - PowerShell ASR Integration Examples

## 🏗️ Bicep-Specific Configuration Examples

This guide provides detailed examples for using the PowerShell ASR networking automation with **Bicep-deployed** Azure infrastructure.

---

## 🎯 Typical Bicep Infrastructure Patterns

### Resource Naming Conventions

```bicep
// Bicep naming patterns that the scripts auto-detect:

param projectName string = 'webapp'
param environment string = 'prod'
param primaryRegion string = 'eastus'
param secondaryRegion string = 'westus2'

// VM naming: project-environment-region-tier-resource-index
resource webVm 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, webVmCount): {
  name: '${projectName}-${environment}-${primaryRegion}-web-vm-${i + 1}'
}]

// Load balancer naming: project-environment-region-tier-lb
resource webLoadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${projectName}-${environment}-${primaryRegion}-web-lb'
}

// Application Security Group: tier-asg (consistent across regions)
resource webTierAsg 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'web-tier-asg'
}
```

### Resource Group Structure

```bicep
// Primary region resource group
resource primaryRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-${environment}-${primaryRegion}-rg'
  location: primaryRegion
}

// Secondary region resource group
resource secondaryRg 'Microsoft.Resources/resourceGroups@2022-09-01' = {
  name: '${projectName}-${environment}-${secondaryRegion}-rg'
  location: secondaryRegion
}
```

---

## 📜 PowerShell Integration Examples

### 1. Basic Bicep Backup

```powershell
# Auto-detect Bicep infrastructure and backup all VMs
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -ProjectName "webapp" `
    -Environment "prod"

# Expected auto-detection output:
# [INFO] Auto-detected infrastructure type: bicep (TF indicators: 1, Bicep indicators: 7)
# [INFO] Cross-region mapping: eastus -> westus2
```

### 2. Explicit Bicep Configuration

```powershell
# Explicitly specify Bicep for optimal performance
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -SecondaryResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -ProjectName "webapp" `
    -Environment "prod" `
    -VmNames @(
        "webapp-prod-eastus-web-vm-1",
        "webapp-prod-eastus-web-vm-2",
        "webapp-prod-eastus-app-vm-1"
    ) `
    -StorageAccountName "webappasrconfigs" `
    -StorageResourceGroupName "shared-services-rg" `
    -IncludeAppGateway `
    -IncludeLoadBalancer `
    -Detailed
```

### 3. Bicep Restoration with Regional Mapping

```powershell
# Preview restoration for Bicep infrastructure
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -DryRun `
    -Detailed

# Sample output for Bicep:
# [INFO] Infrastructure type: bicep
# [INFO] Cross-region mapping detected: eastus -> westus2
# [ACTION] Would restore ASG membership: web-tier-asg
# [ACTION] Would restore LB pool membership: web-pool in webapp-prod-westus2-web-lb
```

### 4. Bicep Multi-Environment Application

```powershell
# Backup production environment in East US
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "ecommerce-prod-eastus-rg" `
    -InfrastructureType "bicep" `
    -ProjectName "ecommerce" `
    -Environment "prod" `
    -VmNames @(
        "ecommerce-prod-eastus-web-vm-1",
        "ecommerce-prod-eastus-web-vm-2",
        "ecommerce-prod-eastus-web-vm-3",
        "ecommerce-prod-eastus-app-vm-1",
        "ecommerce-prod-eastus-app-vm-2",
        "ecommerce-prod-eastus-db-vm-1"
    ) `
    -StorageAccountName "ecommerceasrconfigs" `
    -IncludeAppGateway `
    -IncludeLoadBalancer

# Restore to West US 2 during DR
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "ecommerce-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -StorageAccountName "ecommerceasrconfigs" `
    -StorageResourceGroupName "shared-services-rg"
```

---

## 🌍 Bicep Regional Mapping Examples

### Regional Resource Mapping

```yaml
# Bicep Regional Mapping (East US -> West US 2)
Primary (East US):
  - webapp-prod-eastus-web-vm-1     -> webapp-prod-westus2-web-vm-1
  - webapp-prod-eastus-web-lb       -> webapp-prod-westus2-web-lb
  - webapp-prod-eastus-app-gateway  -> webapp-prod-westus2-app-gateway
  - webapp-prod-eastus-web-nsg      -> webapp-prod-westus2-web-nsg

Secondary (West US 2):
  - webapp-prod-westus2-web-vm-1
  - webapp-prod-westus2-web-lb
  - webapp-prod-westus2-app-gateway
  - webapp-prod-westus2-web-nsg
```

### Cross-Region Patterns

```yaml
# Regional replacement patterns
EastUS ↔ WestUS2:
  - eastus        -> westus2
  - westus2       -> eastus

EastUS2 ↔ WestUS:
  - eastus2       -> westus
  - westus        -> eastus2

CentralUS ↔ EastUS2:
  - centralus     -> eastus2
  - eastus2       -> centralus

Europe Regions:
  - westeurope    -> northeurope
  - northeurope   -> westeurope
```

---

## 🔄 Bicep ASR Automation Integration

### Azure Automation Runbook for Bicep

```powershell
# Pre-failover backup automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Backup" `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -StorageAccountName "webappasrautomation" `
    -StorageResourceGroupName "automation-rg" `
    -InfrastructureType "bicep" `
    -ProjectName "webapp" `
    -Environment "prod"

# Post-failover restoration automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Restore" `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -StorageAccountName "webappasrautomation" `
    -StorageResourceGroupName "automation-rg" `
    -InfrastructureType "bicep"
```

### ASR Recovery Plan JSON for Bicep

```json
{
  "RecoveryPlanName": "bicep-webapp-dr-plan",
  "PrimaryFabric": "eastus-site-recovery",
  "RecoveryFabric": "westus2-site-recovery",
  "Groups": [
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "webapp-prod-eastus-web-vm-1",
        "webapp-prod-eastus-web-vm-2",
        "webapp-prod-eastus-web-vm-3"
      ]
    },
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "webapp-prod-eastus-app-vm-1",
        "webapp-prod-eastus-app-vm-2"
      ]
    },
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "webapp-prod-eastus-db-vm-1"
      ]
    }
  ],
  "PreFailoverActions": [
    {
      "ActionName": "BackupNetworkingConfig",
      "ActionType": "ScriptAction",
      "FailoverTypes": ["PlannedFailover", "UnplannedFailover"],
      "ScriptName": "ASR-NetworkingAutomation",
      "Parameters": {
        "Operation": "Backup",
        "ResourceGroupName": "webapp-prod-eastus-rg",
        "StorageAccountName": "webappasrautomation",
        "StorageResourceGroupName": "automation-rg",
        "InfrastructureType": "bicep"
      }
    }
  ],
  "PostFailoverActions": [
    {
      "ActionName": "RestoreNetworkingConfig",
      "ActionType": "ScriptAction",
      "FailoverTypes": ["PlannedFailover", "UnplannedFailover"],
      "ScriptName": "ASR-NetworkingAutomation",
      "Parameters": {
        "Operation": "Restore",
        "ResourceGroupName": "webapp-prod-westus2-rg",
        "StorageAccountName": "webappasrautomation",
        "StorageResourceGroupName": "automation-rg",
        "InfrastructureType": "bicep"
      }
    }
  ]
}
```

---

## 📊 Bicep Template Examples

### Main Bicep Template with Networking

```bicep
@description('Project name used in resource naming')
param projectName string = 'webapp'

@description('Environment designation')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Primary Azure region')
param primaryRegion string = 'eastus'

@description('Secondary Azure region for DR')
param secondaryRegion string = 'westus2'

@description('Enable static IP addresses for VMs')
param enableStaticIps bool = true

@description('Number of web tier VMs')
param webVmCount int = 3

@description('Number of app tier VMs')
param appVmCount int = 2

// Variables for consistent naming
var regionSuffix = primaryRegion
var resourcePrefix = '${projectName}-${environment}-${regionSuffix}'

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${resourcePrefix}-vnet'
  location: primaryRegion
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.1.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'web-subnet'
        properties: {
          addressPrefix: '10.1.1.0/24'
          networkSecurityGroup: {
            id: webNsg.id
          }
        }
      }
      {
        name: 'app-subnet'
        properties: {
          addressPrefix: '10.1.2.0/24'
          networkSecurityGroup: {
            id: appNsg.id
          }
        }
      }
    ]
  }
}

// Application Security Groups
resource webTierAsg 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'web-tier-asg'
  location: primaryRegion
  properties: {}
}

resource appTierAsg 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'app-tier-asg'
  location: primaryRegion
  properties: {}
}

// Network Security Groups
resource webNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${resourcePrefix}-web-nsg'
  location: primaryRegion
  properties: {
    securityRules: [
      {
        name: 'AllowHTTP'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationApplicationSecurityGroups: [
            {
              id: webTierAsg.id
            }
          ]
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Load Balancer
resource webLoadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${resourcePrefix}-web-lb'
  location: primaryRegion
  sku: {
    name: 'Standard'
  }
  properties: {
    frontendIPConfigurations: [
      {
        name: 'web-frontend'
        properties: {
          publicIPAddress: {
            id: webPublicIp.id
          }
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'web-backend-pool'
      }
    ]
    loadBalancingRules: [
      {
        name: 'web-lb-rule'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/loadBalancers/frontendIPConfigurations', '${resourcePrefix}-web-lb', 'web-frontend')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', '${resourcePrefix}-web-lb', 'web-backend-pool')
          }
          protocol: 'TCP'
          frontendPort: 80
          backendPort: 80
          probe: {
            id: resourceId('Microsoft.Network/loadBalancers/probes', '${resourcePrefix}-web-lb', 'web-health-probe')
          }
        }
      }
    ]
    probes: [
      {
        name: 'web-health-probe'
        properties: {
          protocol: 'HTTP'
          port: 80
          requestPath: '/health'
          intervalInSeconds: 15
          numberOfProbes: 2
        }
      }
    ]
  }
}

// Public IP for Load Balancer
resource webPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${resourcePrefix}-web-lb-pip'
  location: primaryRegion
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${projectName}-${environment}-${primaryRegion}-web'
    }
  }
}

// Web tier VMs with networking
resource webNic 'Microsoft.Network/networkInterfaces@2023-09-01' = [for i in range(0, webVmCount): {
  name: '${resourcePrefix}-web-vm-${i + 1}-nic'
  location: primaryRegion
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'web-subnet')
          }
          privateIPAllocationMethod: enableStaticIps ? 'Static' : 'Dynamic'
          privateIPAddress: enableStaticIps ? '10.1.1.${10 + i}' : null
          loadBalancerBackendAddressPools: [
            {
              id: resourceId('Microsoft.Network/loadBalancers/backendAddressPools', webLoadBalancer.name, 'web-backend-pool')
            }
          ]
          applicationSecurityGroups: [
            {
              id: webTierAsg.id
            }
          ]
        }
      }
    ]
  }
}]

resource webVm 'Microsoft.Compute/virtualMachines@2023-09-01' = [for i in range(0, webVmCount): {
  name: '${resourcePrefix}-web-vm-${i + 1}'
  location: primaryRegion
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v3'
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: webNic[i].id
        }
      ]
    }
    osProfile: {
      computerName: '${resourcePrefix}-web-vm-${i + 1}'
      adminUsername: 'azureuser'
      adminPassword: 'P@ssword123!' // Use Key Vault in production
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        name: '${resourcePrefix}-web-vm-${i + 1}-osdisk'
        caching: 'ReadWrite'
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
  }
}]

// Application Gateway
resource appGateway 'Microsoft.Network/applicationGateways@2023-09-01' = {
  name: '${resourcePrefix}-app-gateway'
  location: primaryRegion
  properties: {
    sku: {
      name: 'Standard_v2'
      tier: 'Standard_v2'
      capacity: 2
    }
    gatewayIPConfigurations: [
      {
        name: 'appgw-ip-config'
        properties: {
          subnet: {
            id: resourceId('Microsoft.Network/virtualNetworks/subnets', vnet.name, 'appgw-subnet')
          }
        }
      }
    ]
    frontendIPConfigurations: [
      {
        name: 'appgw-frontend-ip'
        properties: {
          publicIPAddress: {
            id: appGwPublicIp.id
          }
        }
      }
    ]
    frontendPorts: [
      {
        name: 'port-80'
        properties: {
          port: 80
        }
      }
    ]
    backendAddressPools: [
      {
        name: 'web-backend-pool'
        properties: {}
      }
    ]
    backendHttpSettingsCollection: [
      {
        name: 'web-backend-settings'
        properties: {
          port: 80
          protocol: 'Http'
          cookieBasedAffinity: 'Disabled'
          requestTimeout: 30
        }
      }
    ]
    httpListeners: [
      {
        name: 'web-listener'
        properties: {
          frontendIPConfiguration: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendIPConfigurations', '${resourcePrefix}-app-gateway', 'appgw-frontend-ip')
          }
          frontendPort: {
            id: resourceId('Microsoft.Network/applicationGateways/frontendPorts', '${resourcePrefix}-app-gateway', 'port-80')
          }
          protocol: 'Http'
        }
      }
    ]
    requestRoutingRules: [
      {
        name: 'web-routing-rule'
        properties: {
          ruleType: 'Basic'
          priority: 100
          httpListener: {
            id: resourceId('Microsoft.Network/applicationGateways/httpListeners', '${resourcePrefix}-app-gateway', 'web-listener')
          }
          backendAddressPool: {
            id: resourceId('Microsoft.Network/applicationGateways/backendAddressPools', '${resourcePrefix}-app-gateway', 'web-backend-pool')
          }
          backendHttpSettings: {
            id: resourceId('Microsoft.Network/applicationGateways/backendHttpSettingsCollection', '${resourcePrefix}-app-gateway', 'web-backend-settings')
          }
        }
      }
    ]
  }
}

// Public IP for Application Gateway
resource appGwPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${resourcePrefix}-appgw-pip'
  location: primaryRegion
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: '${projectName}-${environment}-${primaryRegion}-appgw'
    }
  }
}

// Outputs for PowerShell automation reference
output resourceGroupName string = resourceGroup().name
output virtualNetworkName string = vnet.name
output webLoadBalancerName string = webLoadBalancer.name
output applicationGatewayName string = appGateway.name
output webTierAsgName string = webTierAsg.name
output appTierAsgName string = appTierAsg.name
output vmNames array = [for i in range(0, webVmCount): '${resourcePrefix}-web-vm-${i + 1}']
```

### Parameters File for Bicep

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "projectName": {
      "value": "webapp"
    },
    "environment": {
      "value": "prod"
    },
    "primaryRegion": {
      "value": "eastus"
    },
    "secondaryRegion": {
      "value": "westus2"
    },
    "enableStaticIps": {
      "value": true
    },
    "webVmCount": {
      "value": 3
    },
    "appVmCount": {
      "value": 2
    }
  }
}
```

---

## 🧪 Testing Bicep Infrastructure

### Test Infrastructure Detection

```powershell
# Test auto-detection with Bicep resources
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -InfrastructureType "auto" `
    -Detailed `
    -VmNames @("webapp-prod-eastus-web-vm-1") # Test with single VM first

# Expected detection output:
# [INFO] Auto-detected infrastructure type: bicep (TF indicators: 0, Bicep indicators: 8)
# [INFO] Cross-region mapping: eastus -> westus2 patterns
```

### Validate Regional Mapping

```powershell
# Test restoration with dry-run to validate regional mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -DryRun `
    -Detailed

# Expected mapping output:
# [INFO] Infrastructure type: bicep
# [ACTION] Would restore LB pool: web-backend-pool in webapp-prod-westus2-web-lb
# [ACTION] Would restore App Gateway pool: web-backend-pool in webapp-prod-westus2-app-gateway
```

### Test Multi-Region Operations

```powershell
# Test with multiple regions
$regions = @("eastus", "westus2", "centralus", "eastus2")

foreach ($region in $regions) {
    Write-Host "Testing region mapping for: $region"
    $targetRegion = switch ($region) {
        "eastus" { "westus2" }
        "westus2" { "eastus" }
        "centralus" { "eastus2" }
        "eastus2" { "centralus" }
    }

    $primaryRg = "webapp-prod-$region-rg"
    $secondaryRg = "webapp-prod-$targetRegion-rg"

    Write-Host "  Primary: $primaryRg -> Secondary: $secondaryRg"
}
```

---

## 🔧 Troubleshooting Bicep-Specific Issues

### Regional Mapping Issues

```powershell
# Issue: Incorrect region mapping during restoration
# Solution: Verify region replacement logic

# Debug regional mapping
$primaryResourceName = "webapp-prod-eastus-web-lb"
$secondaryResourceName = $primaryResourceName -replace "eastus", "westus2"
Write-Host "Mapped: $primaryResourceName -> $secondaryResourceName"

# Verify secondary resources exist with correct naming
Get-AzLoadBalancer -ResourceGroupName "webapp-prod-westus2-rg" |
    Where-Object { $_.Name -like "*westus2*" } |
    Select-Object Name, Location
```

### ASG Cross-Region Issues

```powershell
# Issue: ASG not found in secondary region
# Solution: ASGs should use same names across regions

# Check ASG consistency across regions
$primaryRg = "webapp-prod-eastus-rg"
$secondaryRg = "webapp-prod-westus2-rg"

$primaryAsgs = Get-AzApplicationSecurityGroup -ResourceGroupName $primaryRg | Select-Object Name
$secondaryAsgs = Get-AzApplicationSecurityGroup -ResourceGroupName $secondaryRg | Select-Object Name

Compare-Object $primaryAsgs.Name $secondaryAsgs.Name
```

### VM Naming Consistency

```powershell
# Issue: VM names don't follow expected Bicep patterns
# Solution: Ensure consistent naming across deployments

# Check VM naming consistency
Get-AzVM -ResourceGroupName "webapp-prod-eastus-rg" |
    Select-Object Name |
    Where-Object { $_.Name -match "^[a-z]+-[a-z]+-[a-z0-9]+-[a-z]+-vm-[0-9]+$" }

# Expected pattern: webapp-prod-eastus-web-vm-1
```

---

## 📋 Bicep Best Practices for ASR

### Consistent Naming Across Regions

```bicep
// Use consistent naming variables
var resourcePrefix = '${projectName}-${environment}-${region}'

// Ensure ASGs use same names across regions
resource webTierAsg 'Microsoft.Network/applicationSecurityGroups@2023-09-01' = {
  name: 'web-tier-asg' // Same name in both regions
  location: region
}

// Use regional prefixes for region-specific resources
resource loadBalancer 'Microsoft.Network/loadBalancers@2023-09-01' = {
  name: '${resourcePrefix}-web-lb' // Different per region
  location: region
}
```

### Parameter Standardization

```bicep
// Standard parameters for ASR compatibility
@description('Project name for resource naming')
param projectName string

@description('Environment designation')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for deployment')
param region string

@description('Enable ASR-compatible static IP allocation')
param enableStaticIpAllocation bool = true

@description('Enable ASR-compatible resource naming')
param useAsrCompatibleNaming bool = true
```

### Module Organization

```bicep
// main.bicep - Primary deployment
targetScope = 'subscription'

param primaryRegion string = 'eastus'
param secondaryRegion string = 'westus2'

module primaryDeployment 'modules/webapp.bicep' = {
  name: 'primary-deployment'
  scope: resourceGroup('webapp-prod-eastus-rg')
  params: {
    projectName: 'webapp'
    environment: 'prod'
    region: primaryRegion
    enableStaticIpAllocation: true
    useAsrCompatibleNaming: true
  }
}

module secondaryDeployment 'modules/webapp.bicep' = {
  name: 'secondary-deployment'
  scope: resourceGroup('webapp-prod-westus2-rg')
  params: {
    projectName: 'webapp'
    environment: 'prod'
    region: secondaryRegion
    enableStaticIpAllocation: true
    useAsrCompatibleNaming: true
  }
}
```

---

## 🚀 Production Deployment Workflow

### Step 1: Deploy Bicep Templates

```bash
# Deploy to primary region
az deployment group create \
  --resource-group webapp-prod-eastus-rg \
  --template-file main.bicep \
  --parameters @primary.parameters.json

# Deploy to secondary region
az deployment group create \
  --resource-group webapp-prod-westus2-rg \
  --template-file main.bicep \
  --parameters @secondary.parameters.json
```

### Step 2: Validate ASR Automation Compatibility

```powershell
# Test infrastructure detection
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -InfrastructureType "auto" `
    -Detailed

# Verify cross-region mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -DryRun `
    -Detailed
```

### Step 3: Configure ASR Integration

```powershell
# Import runbooks for Bicep infrastructure
Import-AzAutomationRunbook `
    -Path ".\ASR-NetworkingAutomation.ps1" `
    -Name "ASR-NetworkingAutomation-Bicep" `
    -Type PowerShell `
    -AutomationAccountName "webapp-asr-automation"

# Test runbook execution
Start-AzAutomationRunbook `
    -Name "ASR-NetworkingAutomation-Bicep" `
    -Parameters @{
        Operation = "Backup"
        ResourceGroupName = "webapp-prod-eastus-rg"
        InfrastructureType = "bicep"
        StorageAccountName = "webappasrconfigs"
        ProjectName = "webapp"
        Environment = "prod"
    }
```

### Step 4: Validation Testing

```powershell
# End-to-end testing workflow
Write-Host "Starting Bicep ASR validation..."

# 1. Backup configuration
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -InfrastructureType "bicep" `
    -StorageAccountName "validationconfigs" `
    -Detailed

# 2. Simulate restoration
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -StorageAccountName "validationconfigs" `
    -DryRun `
    -Detailed

Write-Host "Bicep ASR validation completed successfully!"
```

---

*This guide provides comprehensive examples for integrating the PowerShell ASR automation with Bicep-deployed Azure infrastructure, ensuring seamless disaster recovery with intelligent regional mapping and preserved networking configurations.*