# PowerShell ASR Networking Automation - Universal Infrastructure Support

## 🌐 Universal Infrastructure Compatibility

This PowerShell automation suite provides **comprehensive networking configuration backup and restoration** for Azure Site Recovery (ASR) scenarios, working seamlessly with **both Terraform and Bicep** infrastructure deployments.

### 🎯 Key Innovation: Infrastructure-Agnostic Design

Unlike traditional disaster recovery solutions that work with only one infrastructure type, this suite **automatically detects** whether your infrastructure is deployed via:

- **🔧 Terraform** - Hyphen-separated naming with primary/secondary patterns
- **🏗️ Bicep** - Environment-region specific naming with region-based mapping
- **🤖 Auto-Detection** - Intelligently identifies infrastructure type and applies appropriate logic

---

## 📁 Complete Solution Structure

```
powershell-asr-automation/
├── 📜 Core Scripts (Infrastructure-Agnostic)
│   ├── Save-NetworkingConfig.ps1              # Universal backup script
│   ├── Restore-NetworkingConfig.ps1           # Universal restoration script
│   └── ASR-NetworkingAutomation.ps1           # Azure Automation runbook
│
├── 📚 Documentation & Guides
│   ├── README.md                               # This comprehensive guide
│   ├── TERRAFORM_EXAMPLES.md                  # Terraform-specific examples
│   ├── BICEP_EXAMPLES.md                      # Bicep-specific examples
│   └── ARCHITECTURE_GUIDE.md                  # Technical architecture details
│
└── 🛠️ Setup & Installation
    ├── Install-Module.ps1                     # Automated installer
    └── Test-Infrastructure.ps1                # Infrastructure compatibility test
```

---

## 🚀 Quick Start Guide

### Prerequisites

```powershell
# Install required Azure PowerShell modules
Install-Module -Name Az.Accounts, Az.Network, Az.Compute, Az.Resources, Az.Storage -Force

# Connect to Azure
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

### Universal Usage (Works with Both TF and Bicep)

```powershell
# 🔍 Auto-detect infrastructure type and backup
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "your-resource-group" `
    -ProjectName "webapp" `
    -Environment "prod"

# 🔄 Auto-detect infrastructure type and restore
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "your-dr-resource-group"

# 👁️ Preview changes before applying (recommended)
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "your-dr-resource-group" `
    -DryRun `
    -Detailed
```

---

## 🏗️ Infrastructure-Specific Examples

### Terraform Infrastructure

```powershell
# Terraform naming: web-vm-1, app-lb-primary, web-tier-asg
# Primary RG: webapp-prod-primary-rg
# Secondary RG: webapp-prod-secondary-rg

# Backup (explicitly specify Terraform)
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -SecondaryResourceGroupName "webapp-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -ProjectName "webapp" `
    -Environment "prod"

# Restore with Terraform cross-region mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -Force
```

### Bicep Infrastructure

```powershell
# Bicep naming: webapp-prod-eastus-web-vm-1, webapp-prod-eastus-lb, web-tier-asg
# Primary RG: webapp-prod-eastus-rg
# Secondary RG: webapp-prod-westus2-rg

# Backup (explicitly specify Bicep)
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -InfrastructureType "bicep" `
    -ProjectName "webapp" `
    -Environment "prod" `
    -StorageAccountName "asrnetworkconfigs"

# Restore with Bicep region-based mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -InfrastructureType "bicep" `
    -StorageAccountName "asrnetworkconfigs" `
    -StorageResourceGroupName "shared-services-rg"
```

---

## 🤖 Intelligent Infrastructure Detection

### Auto-Detection Algorithm

The scripts use sophisticated pattern recognition to identify infrastructure type:

```powershell
# Terraform Patterns Detected:
# - Simple hyphen-separated names: web-vm-1, app-lb, db-nsg
# - Primary/secondary explicit naming: web-lb-primary, app-gateway-secondary
# - Resource-type suffixes: web-vm, app-lb, db-subnet

# Bicep Patterns Detected:
# - Environment-region format: webapp-prod-eastus-web-vm-1
# - Region identifiers: eastus, westus2, centralus, northeurope
# - Project-environment prefixes: webapp-prod-, api-staging-, portal-dev-
```

### Cross-Region Resource Mapping

| Infrastructure | Primary Resource | Secondary Resource | Mapping Logic |
|---------------|------------------|-------------------|---------------|
| **Terraform** | `web-lb-primary` | `web-lb-secondary` | Primary/Secondary replacement |
| **Terraform** | `web-lb` | `web-lb-secondary` | Add secondary suffix |
| **Bicep** | `webapp-prod-eastus-lb` | `webapp-prod-westus2-lb` | Region-based replacement |
| **Bicep** | `webapp-prod-centralus-vm` | `webapp-prod-eastus2-vm` | Intelligent region mapping |

---

## 🎛️ Advanced Features

### Comprehensive Configuration Coverage

| Configuration Type | Terraform Support | Bicep Support | Auto-Mapping | Notes |
|-------------------|------------------|---------------|-------------|-------|
| **Application Security Groups** | ✅ | ✅ | ✅ | Full ASG membership preservation |
| **Static Private IPs** | ✅ | ✅ | ✅ | Subnet-aware IP restoration |
| **Static Public IPs** | ✅ | ✅ | ✅ | Public IP allocation preservation |
| **Load Balancer Backend Pools** | ✅ | ✅ | ✅ | Cross-region LB pool mapping |
| **Application Gateway Pools** | ✅ | ✅ | ✅ | App Gateway backend associations |
| **Network Security Groups** | ✅ | ✅ | ℹ️ | NSG association documentation |

### Storage Integration

```powershell
# Persistent configuration storage across regions
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "prod-rg" `
    -StorageAccountName "globalasrconfigs" `
    -StorageResourceGroupName "shared-services-rg"

# Download and restore from storage
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "dr-rg" `
    -StorageAccountName "globalasrconfigs" `
    -StorageResourceGroupName "shared-services-rg"
```

### Selective Operations

```powershell
# Process specific VMs only
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "prod-rg" `
    -VmNames @("critical-vm-1", "critical-vm-2", "database-vm")

# Target specific networking components
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "prod-rg" `
    -IncludeAppGateway `
    -IncludeLoadBalancer `
    -Detailed
```

---

## 🔧 Azure Automation Integration

### Universal Runbook Support

The `ASR-NetworkingAutomation.ps1` script works with both infrastructure types in Azure Automation:

```powershell
# Pre-failover backup (works with any infrastructure)
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Backup" `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -StorageAccountName "asrnetworkconfigs" `
    -StorageResourceGroupName "shared-services-rg"

# Post-failover restoration (auto-detects infrastructure type)
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Restore" `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -StorageAccountName "asrnetworkconfigs" `
    -StorageResourceGroupName "shared-services-rg"

# Specify infrastructure type for optimal performance
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Restore" `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -StorageAccountName "asrnetworkconfigs" `
    -InfrastructureType "bicep" `
    -DryRun $false
```

### ASR Recovery Plan Integration

#### For Terraform Infrastructure
```json
{
  "PreFailoverScript": {
    "ScriptName": "ASR-NetworkingAutomation",
    "Parameters": {
      "Operation": "Backup",
      "ResourceGroupName": "webapp-prod-primary-rg",
      "StorageAccountName": "asrnetworkconfigs",
      "InfrastructureType": "terraform"
    }
  },
  "PostFailoverScript": {
    "ScriptName": "ASR-NetworkingAutomation",
    "Parameters": {
      "Operation": "Restore",
      "ResourceGroupName": "webapp-prod-secondary-rg",
      "StorageAccountName": "asrnetworkconfigs",
      "InfrastructureType": "terraform"
    }
  }
}
```

#### For Bicep Infrastructure
```json
{
  "PreFailoverScript": {
    "Parameters": {
      "Operation": "Backup",
      "ResourceGroupName": "webapp-prod-eastus-rg",
      "InfrastructureType": "bicep"
    }
  },
  "PostFailoverScript": {
    "Parameters": {
      "Operation": "Restore",
      "ResourceGroupName": "webapp-prod-westus2-rg",
      "InfrastructureType": "bicep"
    }
  }
}
```

---

## 📊 Configuration File Examples

### Master Configuration (Universal Format)

```json
{
  "Timestamp": "20241201-143022",
  "InfrastructureType": "terraform",
  "ProjectName": "webapp",
  "Environment": "prod",
  "PrimaryResourceGroup": "webapp-prod-primary-rg",
  "SecondaryResourceGroup": "webapp-prod-secondary-rg",
  "ConfigurationFiles": [
    "web-vm-1-networking-config-20241201-143022.json",
    "web-vm-2-networking-config-20241201-143022.json"
  ],
  "CrossRegionMapping": {
    "InfrastructureType": "terraform",
    "MappingRules": {
      "Pattern": "Simple primary/secondary replacement",
      "Example": "web-lb-primary -> web-lb-secondary"
    }
  }
}
```

### VM Configuration (Enhanced with Infrastructure Context)

```json
{
  "VmName": "web-vm-1",
  "VmId": "/subscriptions/.../virtualMachines/web-vm-1",
  "InfrastructureType": "terraform",
  "ProjectName": "webapp",
  "Environment": "prod",
  "NetworkInterfaces": [
    {
      "Name": "web-vm-1-nic",
      "InfrastructureType": "terraform",
      "ApplicationSecurityGroups": [
        {
          "AsgName": "web-tier-asg",
          "IpConfigurationName": "ipconfig1"
        }
      ],
      "LoadBalancerBackendPools": [
        {
          "LoadBalancerName": "web-lb-primary",
          "SecondaryLoadBalancerName": "web-lb-secondary",
          "BackendPoolName": "web-backend-pool"
        }
      ]
    }
  ]
}
```

---

## 🛡️ Security & Enterprise Features

### Multi-Infrastructure Security

```powershell
# Managed Identity support (works with both TF and Bicep)
Connect-AzAccount -Identity

# Role-based access control validation
$requiredRoles = @("Network Contributor", "Virtual Machine Contributor")

# Cross-region security group verification
Test-AzurePermissions -ResourceGroups @("primary-rg", "secondary-rg")
```

### Audit and Compliance

```powershell
# Comprehensive logging with infrastructure context
[2024-12-01 14:30:22] [INFO] Infrastructure type: terraform
[2024-12-01 14:30:23] [INFO] Cross-region mapping: primary -> secondary
[2024-12-01 14:30:24] [SUCCESS] Backed up web-vm-1: 2 ASGs, 1 static IP, 2 LB pools
```

---

## 🔍 Testing & Validation

### Infrastructure Compatibility Testing

```powershell
# Test script to validate your infrastructure compatibility
.\Test-Infrastructure.ps1 `
    -ResourceGroupName "your-rg" `
    -TestInfrastructureDetection `
    -TestCrossRegionMapping `
    -ValidateResources
```

### Dry-Run Validation

```powershell
# Safe testing without making changes
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "test-rg" `
    -DryRun `
    -Detailed `
    -Force

# Output shows what would be changed:
# [INFO] Infrastructure type: bicep
# [ACTION] Would restore ASG membership: web-tier-asg
# [ACTION] Would restore LB pool: web-pool in webapp-prod-westus2-lb
```

---

## 🚀 Migration Scenarios

### Terraform to Bicep Migration

```powershell
# 1. Backup from Terraform infrastructure
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "terraform-rg" `
    -InfrastructureType "terraform"

# 2. Deploy new Bicep infrastructure

# 3. Restore to Bicep infrastructure (with manual mapping)
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "bicep-rg" `
    -InfrastructureType "bicep" `
    -DryRun
```

### Cross-Cloud Provider Preparation

```powershell
# Export configuration in universal format
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "azure-rg" `
    -ExportUniversalFormat `
    -OutputPath "cross-cloud-configs/"
```

---

## 📞 Support & Troubleshooting

### Infrastructure-Specific Troubleshooting

| Issue | Terraform Solution | Bicep Solution |
|-------|-------------------|----------------|
| **Resource not found** | Check primary/secondary naming | Verify region mapping |
| **ASG membership fails** | Validate ASG exists in secondary RG | Check ASG cross-region replication |
| **LB pool mapping fails** | Confirm LB naming convention | Validate region-based LB names |

### Debug Commands

```powershell
# Enable verbose logging
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Test infrastructure detection
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "test-rg" `
    -InfrastructureType "auto" `
    -Detailed `
    -Verbose

# Validate cross-region mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "test-rg" `
    -DryRun `
    -Detailed `
    -Verbose
```

---

## 🎉 Production Deployment Checklist

### Universal Deployment Steps

- [ ] **✅ Test both infrastructure types** in your environment
- [ ] **✅ Validate auto-detection** works correctly
- [ ] **✅ Configure storage account** for cross-region persistence
- [ ] **✅ Set up Azure Automation** with managed identity
- [ ] **✅ Test ASR Recovery Plans** with both infrastructure types
- [ ] **✅ Configure monitoring** for both Terraform and Bicep scenarios
- [ ] **✅ Train team** on infrastructure-agnostic operations
- [ ] **✅ Document environment-specific** resource naming conventions

### Infrastructure-Specific Validation

#### Terraform Checklist
- [ ] Verify primary/secondary resource naming patterns
- [ ] Test cross-region resource group mapping
- [ ] Validate Load Balancer naming conventions
- [ ] Confirm Application Gateway naming patterns

#### Bicep Checklist
- [ ] Verify region-based resource naming patterns
- [ ] Test region-to-region mapping rules
- [ ] Validate environment-region prefix patterns
- [ ] Confirm project naming consistency

---

## 🌟 Benefits of Universal Infrastructure Support

### ✅ **Unified Operations**
- Single set of scripts for all infrastructure types
- Consistent disaster recovery procedures
- Reduced training and maintenance overhead

### ✅ **Future-Proof Architecture**
- Easy migration between infrastructure tools
- Support for mixed environments (TF + Bicep)
- Adaptable to new Azure deployment patterns

### ✅ **Enterprise Flexibility**
- Works with existing Terraform deployments
- Compatible with new Bicep implementations
- Supports gradual infrastructure modernization

### ✅ **Operational Excellence**
- Intelligent auto-detection reduces errors
- Cross-infrastructure knowledge transfer
- Simplified disaster recovery testing

---

## 📋 Version Information

- **Version**: 1.0.0
- **Compatibility**: Terraform 0.12+ and Bicep 0.4+
- **PowerShell**: 5.1+ required
- **Azure PowerShell**: Az module 9.0+ required
- **Infrastructure Types**: Terraform, Bicep, Auto-detection
- **Author**: Azure Infrastructure Team

---

*This universal PowerShell automation suite provides seamless disaster recovery for any Azure infrastructure deployment method, ensuring your networking configurations are preserved regardless of whether you use Terraform, Bicep, or a combination of both.*