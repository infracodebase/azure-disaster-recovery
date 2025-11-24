# PowerShell ASR Networking Automation - Quick Start Guide

## Quick Start Guide

### Prerequisites Checklist

- [ ] PowerShell 5.1 or later installed
- [ ] Azure PowerShell Az modules installed
- [ ] Azure subscription access with appropriate permissions
- [ ] Storage account for configuration persistence (optional)

### 5-Minute Setup

#### 1. Install Required Modules

```powershell
# Run as Administrator
Install-Module -Name Az.Accounts, Az.Network, Az.Compute, Az.Resources, Az.Storage -Force
```

#### 2. Connect to Azure

```powershell
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"
```

#### 3. Basic Usage

```powershell
# Backup all VMs in resource group (before failover)
.\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg"

# Restore configurations after failover
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-secondary-rg"
```

### Command Reference Card

| Task | Command |
|------|---------|
| **Backup all VMs** | `.\Save-NetworkingConfig.ps1 -ResourceGroupName "primary-rg"` |
| **Preview restore** | `.\Restore-NetworkingConfig.ps1 -ResourceGroupName "secondary-rg" -DryRun` |
| **Force restore** | `.\Restore-NetworkingConfig.ps1 -ResourceGroupName "secondary-rg" -Force` |
| **Specific VMs** | `.\Save-NetworkingConfig.ps1 -ResourceGroupName "rg" -VmNames @("vm1","vm2")` |
| **With storage** | `.\Save-NetworkingConfig.ps1 -ResourceGroupName "rg" -StorageAccountName "storage"` |

### Troubleshooting Quick Fixes

| Issue | Solution |
|-------|----------|
| **Authentication error** | `Connect-AzAccount -Force` |
| **Module not found** | `Install-Module -Name Az.Network -Force` |
| **Permission denied** | Verify Network Contributor role assignment |
| **Config not found** | Check file paths and storage account access |

### Emergency Recovery Steps

```powershell
# 1. Quick authentication check
Get-AzContext | Select-Object Account, Subscription

# 2. Emergency restore (no prompts)
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "dr-rg" -Force

# 3. Verify restoration
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "dr-rg" -DryRun -Detailed
```

### Support Contacts

- **Documentation**: [Full documentation link]
- **Repository**: [Script repository link]
- **Support**: [Support contact information]

---

*For detailed documentation, see [PowerShell-ASR-Networking-Automation-Documentation.md](./PowerShell-ASR-Networking-Automation-Documentation.md)*