# Azure Site Recovery Networking Automation - PowerShell Suite

## Overview

This PowerShell automation suite provides comprehensive networking configuration backup and restoration for Azure Site Recovery (ASR) scenarios. It ensures that after failover, VMs maintain their exact networking configurations including Application Security Groups (ASG), static IP addresses, Load Balancer backend pools, and Application Gateway backend pools.

---

## Directory: Files Included

### PowerShell Scripts

| Script | Size | Description |
|--------|------|-------------|
| **`Save-NetworkingConfig.ps1`** | 24KB | Pre-failover networking configuration backup script |
| **`Restore-NetworkingConfig.ps1`** | 31KB | Post-failover networking configuration restoration script |
| **`ASR-NetworkingAutomation.ps1`** | 19KB | Azure Automation runbook integration script |

### Documentation

| Document | Description |
|----------|-------------|
| **`PowerShell-ASR-Networking-Automation-Documentation.md`** | Complete technical reference (969 lines) |
| **`PowerShell-Quick-Start-Guide.md`** | Quick reference and emergency procedures |
| **`ASR-Integration-Guide.md`** | Azure Site Recovery integration instructions |

---

## Quick Start

### Prerequisites

```powershell
# Install required Azure PowerShell modules
Install-Module -Name Az.Accounts, Az.Network, Az.Compute, Az.Resources, Az.Storage -Force

# Connect to Azure
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

### Basic Usage

```powershell
# 1. Backup networking configurations (before failover)
.\Save-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-primary-rg" `
-SecondaryResourceGroupName "webapp-prod-secondary-rg" `
-ProjectName "webapp" `
-Environment "prod"

# 2. Restore networking configurations (after failover)
.\Restore-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-secondary-rg" `
-ConfigurationPath "."

# 3. Preview changes before applying (recommended)
.\Restore-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-secondary-rg" `
-DryRun `
-Detailed
```

---

## Key Features

### DONE Complete Configuration Backup
- **Application Security Groups** - ASG memberships and associations
- **Static IP Addresses** - Private and public IP configurations
- **Load Balancer Backend Pools** - LB backend pool memberships
- **Application Gateway Backend Pools** - App Gateway backend associations
- **Network Security Groups** - NSG rules and assignments
- **Network Interface Settings** - NIC configurations and properties

### DONE Intelligent Restoration
- **Configuration Comparison** - Automatic detection of missing configurations
- **Cross-Region Mapping** - Smart resource name mapping for failover regions
- **Selective Restoration** - Target specific VMs or configuration types
- **Dry-Run Mode** - Preview changes before applying
- **Force Mode** - Unattended execution for automation scenarios

### DONE Enterprise Integration
- **Azure Automation** - Full runbook integration with managed identity
- **Storage Persistence** - Configuration backup to Azure Storage
- **Comprehensive Logging** - Detailed audit trails and monitoring
- **Error Handling** - Robust error recovery and reporting

---

## Usage Scenarios

### Scenario 1: Manual Planned Failover

```powershell
# Step 1: Backup configurations before failover
.\Save-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-eastus-rg" `
-SecondaryResourceGroupName "webapp-prod-westus2-rg" `
-ProjectName "webapp" `
-Environment "prod" `
-StorageAccountName "asrnetworkconfigs" `
-StorageResourceGroupName "shared-services-rg" `
-IncludeAppGateway `
-IncludeLoadBalancer

# Step 2: Perform ASR failover (via Azure portal or automation)

# Step 3: Restore configurations in secondary region
.\Restore-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-westus2-rg" `
-Force
```

### Scenario 2: Automated ASR Integration

```powershell
# Azure Automation runbook execution
.\ASR-NetworkingAutomation.ps1 `
-Operation "Backup" `
-ResourceGroupName "webapp-prod-primary-rg" `
-StorageAccountName "asrnetworkconfigs" `
-StorageResourceGroupName "shared-services-rg"

# Post-failover automation
.\ASR-NetworkingAutomation.ps1 `
-Operation "Restore" `
-ResourceGroupName "webapp-prod-secondary-rg" `
-StorageAccountName "asrnetworkconfigs" `
-StorageResourceGroupName "shared-services-rg"
```

### Scenario 3: Selective VM Restoration

```powershell
# Restore only critical web tier VMs
.\Restore-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-secondary-rg" `
-VmNames @("web-vm-1", "web-vm-2", "web-vm-3") `
-Detailed `
-Force
```

---

## Configuration Examples

### Example Configuration Structure

```json
{
"VmName": "web-vm-1",
"VmId": "/subscriptions/.../virtualMachines/web-vm-1",
"NetworkInterfaces": [
{
"Name": "web-vm-1-nic",
"ApplicationSecurityGroups": [
{
"IpConfigurationName": "ipconfig1",
"AsgName": "web-tier-asg",
"AsgResourceGroup": "webapp-prod-eastus-rg"
}
],
"StaticIpConfigurations": [
{
"IpConfigurationName": "ipconfig1",
"StaticPrivateIpAddress": "10.1.1.10"
}
],
"LoadBalancerBackendPools": [
{
"IpConfigurationName": "ipconfig1",
"LoadBalancerName": "web-lb-primary",
"BackendPoolName": "web-backend-pool"
}
]
}
]
}
```

### Cross-Region Resource Mapping

The scripts automatically map primary region resources to secondary region equivalents:

```powershell
# Primary Region Resources → Secondary Region Resources
"web-lb-primary" → "web-lb-secondary"
"app-gateway-primary" → "app-gateway-secondary"
"web-tier-asg" → "web-tier-asg" (same name)
```

---

## Security Considerations

### Required Permissions

The executing account needs the following Azure RBAC roles:

- **Network Contributor** on source and target resource groups
- **Virtual Machine Contributor** for VM operations
- **Storage Blob Data Contributor** for configuration persistence
- **Reader** permissions on networking resources

### Authentication Methods

```powershell
# Option 1: Interactive login
Connect-AzAccount

# Option 2: Service Principal (for automation)
$credential = Get-Credential
Connect-AzAccount -ServicePrincipal -Credential $credential -TenantId "tenant-id"

# Option 3: Managed Identity (in Azure Automation)
Connect-AzAccount -Identity
```

---

## Monitoring & Logging

### Log Files Generated

- **`networking-config-backup-{timestamp}.log`** - Backup operation logs
- **`networking-config-restore-{timestamp}.log`** - Restoration operation logs
- **Configuration JSON files** - Individual VM and master configurations

### Sample Log Output

```
[2024-12-01 14:30:22] [INFO] === Azure Site Recovery Networking Configuration Backup ===
[2024-12-01 14:30:23] [SUCCESS] Connected to Azure subscription: Production Subscription
[2024-12-01 14:30:24] [INFO] Processing VM: web-vm-1
[2024-12-01 14:30:25] [INFO] Processing NIC: web-vm-1-nic
[2024-12-01 14:30:26] [SUCCESS] Saved configuration for web-vm-1 to: web-vm-1-networking-config-20241201-143022.json
[2024-12-01 14:30:27] [INFO] NICs: 1, ASG memberships: 2, Static IPs: 1, LB pools: 1
```

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Authentication error** | `Connect-AzAccount -Force` |
| **Module not found** | `Install-Module -Name Az.Network -Force` |
| **Permission denied** | Verify Network Contributor role assignment |
| **Config not found** | Check file paths and storage account access |
| **Resource not found** | Verify cross-region resource naming conventions |

### Debug Mode

```powershell
# Enable verbose output for troubleshooting
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

.\Restore-NetworkingConfig.ps1 `
-ResourceGroupName "webapp-prod-secondary-rg" `
-Detailed `
-DryRun `
-Verbose
```

---

## Support & Documentation

### Quick Reference

| Task | Command |
|------|---------|
| **Backup all VMs** | `.\Save-NetworkingConfig.ps1 -ResourceGroupName "primary-rg"` |
| **Preview restore** | `.\Restore-NetworkingConfig.ps1 -ResourceGroupName "secondary-rg" -DryRun` |
| **Force restore** | `.\Restore-NetworkingConfig.ps1 -ResourceGroupName "secondary-rg" -Force` |
| **Specific VMs** | `.\Save-NetworkingConfig.ps1 -ResourceGroupName "rg" -VmNames @("vm1","vm2")` |

### Complete Documentation

- **[PowerShell-ASR-Networking-Automation-Documentation.md](./PowerShell-ASR-Networking-Automation-Documentation.md)** - Complete technical reference
- **[PowerShell-Quick-Start-Guide.md](./PowerShell-Quick-Start-Guide.md)** - Quick reference guide
- **[ASR-Integration-Guide.md](./ASR-Integration-Guide.md)** - Azure Site Recovery integration

---

## TARGET Production Deployment

### Checklist

- [ ] **Prerequisites installed** - PowerShell modules and Azure connectivity
- [ ] **Permissions assigned** - Network Contributor and required roles
- [ ] **Storage configured** - Azure Storage Account for configuration persistence
- [ ] **Testing completed** - Test failover and restoration validated
- [ ] **Automation integrated** - Azure Automation Account and runbooks configured
- [ ] **Monitoring enabled** - Log Analytics and alerting configured
- [ ] **Documentation reviewed** - Team training and procedures documented

### Deployment Steps

1. **Install and configure prerequisites**
2. **Test scripts in non-production environment**
3. **Configure Azure Automation Account and runbooks**
4. **Integrate with ASR Recovery Plans**
5. **Configure monitoring and alerting**
6. **Perform test failover validation**
7. **Document procedures and train team**

---

## Version Information

- **Version**: 1.0.0
- **Last Updated**: 2024-12-01
- **PowerShell**: 5.1+ required
- **Azure PowerShell**: Az module 9.0+ required
- **Author**: Azure Infrastructure Team

---

*This PowerShell suite provides complete automation for Azure Site Recovery networking configuration management, ensuring seamless disaster recovery with zero manual networking intervention required.*