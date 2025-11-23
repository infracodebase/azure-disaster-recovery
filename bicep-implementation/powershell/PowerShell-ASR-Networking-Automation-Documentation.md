# Azure Site Recovery Networking Automation - PowerShell Documentation

## 📋 Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Scripts Overview](#scripts-overview)
4. [Installation & Setup](#installation--setup)
5. [Script Reference](#script-reference)
6. [Usage Examples](#usage-examples)
7. [Configuration Management](#configuration-management)
8. [Azure Automation Integration](#azure-automation-integration)
9. [Troubleshooting](#troubleshooting)
10. [Best Practices](#best-practices)
11. [Security Considerations](#security-considerations)
12. [Monitoring & Logging](#monitoring--logging)

---

## 📖 Overview

The Azure Site Recovery (ASR) Networking Automation PowerShell suite provides comprehensive automation for preserving and restoring VM networking configurations during disaster recovery scenarios. This solution ensures that after ASR failover, VMs maintain their exact networking configurations including Application Security Groups (ASG), static IP addresses, Load Balancer backend pools, and Application Gateway backend pools.

### Key Features

- **Complete Configuration Backup**: Captures all VM networking settings before failover
- **Intelligent Restoration**: Compares current state with saved configurations and applies missing settings
- **Cross-Region Mapping**: Automatically maps primary region resources to secondary region equivalents
- **Enterprise Integration**: Full support for Azure Automation runbooks and enterprise workflows
- **Comprehensive Logging**: Detailed audit trails and monitoring capabilities

---

## ⚡ Prerequisites

### Required Azure PowerShell Modules

```powershell
# Install required modules
Install-Module -Name Az.Accounts -Force
Install-Module -Name Az.Network -Force
Install-Module -Name Az.Compute -Force
Install-Module -Name Az.Resources -Force
Install-Module -Name Az.Storage -Force
Install-Module -Name Az.Automation -Force
```

### Required Permissions

The executing account must have the following Azure RBAC permissions:

- **Network Contributor** or **Contributor** on source and target resource groups
- **Reader** permissions on source networking resources
- **Storage Blob Data Contributor** on the storage account used for configuration persistence
- **Virtual Machine Contributor** for VM operations

### System Requirements

- PowerShell 5.1 or later
- Azure PowerShell Az module 9.0 or later
- Network connectivity to Azure
- Sufficient disk space for configuration files and logs

---

## 📂 Scripts Overview

### Core Scripts

| Script | Purpose | Execution Context |
|--------|---------|------------------|
| `Save-NetworkingConfig.ps1` | Pre-failover backup of networking configurations | Primary region, before failover |
| `Restore-NetworkingConfig.ps1` | Post-failover restoration and comparison | Secondary region, after failover |
| `ASR-NetworkingAutomation.ps1` | Azure Automation runbook integration | Azure Automation Account |

### Configuration Files

| File Type | Description | Location |
|-----------|-------------|----------|
| `MASTER-networking-config-*.json` | Master index of all VM configurations | Storage account or local path |
| `{VmName}-networking-config-*.json` | Individual VM networking configuration | Storage account or local path |
| `networking-config-backup-*.log` | Backup operation logs | Local or storage account |
| `networking-config-restore-*.log` | Restoration operation logs | Local or storage account |

---

## 🚀 Installation & Setup

### 1. Download Scripts

```powershell
# Download scripts from repository
$scriptPath = "C:\ASR\Scripts"
New-Item -Path $scriptPath -ItemType Directory -Force

# Place the three PowerShell scripts in the directory:
# - Save-NetworkingConfig.ps1
# - Restore-NetworkingConfig.ps1
# - ASR-NetworkingAutomation.ps1
```

### 2. Configure Storage Account

```powershell
# Create storage account for configuration persistence
$storageAccountName = "asrnetworkingconfigs"
$resourceGroupName = "shared-services-rg"
$location = "East US"

$storageAccount = New-AzStorageAccount `
    -ResourceGroupName $resourceGroupName `
    -Name $storageAccountName `
    -Location $location `
    -SkuName "Standard_LRS" `
    -Kind "StorageV2"

# Create container for configurations
$ctx = $storageAccount.Context
New-AzStorageContainer -Name "networking-configs" -Context $ctx -Permission Off
```

### 3. Set Execution Policy

```powershell
# Allow script execution (run as Administrator)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
```

---

## 📚 Script Reference

## Save-NetworkingConfig.ps1

### Synopsis
Captures and saves VM networking configurations before Site Recovery failover.

### Syntax

```powershell
.\Save-NetworkingConfig.ps1
    [-ResourceGroupName] <String>
    [-ConfigurationPath <String>]
    [-StorageAccountName <String>]
    [-StorageResourceGroupName <String>]
    [-VmNames <String[]>]
    [-SubscriptionId <String>]
    [-IncludeAppGateway]
    [-IncludeLoadBalancer]
    [-Detailed]
    [<CommonParameters>]
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ResourceGroupName` | String | Yes | Source resource group containing VMs to backup |
| `ConfigurationPath` | String | No | Local path to save configuration files (default: current directory) |
| `StorageAccountName` | String | No | Azure Storage Account for configuration persistence |
| `StorageResourceGroupName` | String | No | Resource group containing the storage account |
| `VmNames` | String[] | No | Specific VM names to backup (default: all VMs in RG) |
| `SubscriptionId` | String | No | Azure subscription ID |
| `IncludeAppGateway` | Switch | No | Include Application Gateway backend pool configurations |
| `IncludeLoadBalancer` | Switch | No | Include Load Balancer backend pool configurations |
| `Detailed` | Switch | No | Enable detailed logging output |

### Examples

```powershell
# Basic backup of all VMs in resource group
.\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg"

# Backup specific VMs with storage account persistence
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -VmNames @("web-vm-1", "web-vm-2", "app-vm-1") `
    -StorageAccountName "asrnetworkingconfigs" `
    -StorageResourceGroupName "shared-services-rg" `
    -IncludeAppGateway `
    -IncludeLoadBalancer

# Backup with detailed logging to custom path
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -ConfigurationPath "D:\ASR\Backups" `
    -Detailed
```

---

## Restore-NetworkingConfig.ps1

### Synopsis
Compares current networking configurations with saved state and restores missing configurations after failover.

### Syntax

```powershell
.\Restore-NetworkingConfig.ps1
    [-ResourceGroupName] <String>
    [-ConfigurationPath <String>]
    [-MasterConfigFile <String>]
    [-VmNames <String[]>]
    [-SubscriptionId <String>]
    [-DryRun]
    [-Force]
    [-Detailed]
    [<CommonParameters>]
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `ResourceGroupName` | String | Yes | Target resource group containing failed-over VMs |
| `ConfigurationPath` | String | No | Path containing saved configuration files |
| `MasterConfigFile` | String | No | Specific master configuration file path |
| `VmNames` | String[] | No | Specific VM names to restore (default: all from saved config) |
| `SubscriptionId` | String | No | Azure subscription ID |
| `DryRun` | Switch | No | Preview changes without applying them |
| `Force` | Switch | No | Skip confirmation prompts |
| `Detailed` | Switch | No | Enable detailed difference reporting |

### Examples

```powershell
# Basic restoration of all VMs
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-secondary-rg"

# Dry-run to preview changes
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -ConfigurationPath "C:\ASR\Configs" `
    -DryRun `
    -Detailed

# Force restoration without prompts for specific VMs
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -VmNames @("web-vm-1", "web-vm-2") `
    -Force

# Restore from specific configuration file
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -MasterConfigFile "C:\ASR\Configs\MASTER-networking-config-20241201-143022.json"
```

---

## ASR-NetworkingAutomation.ps1

### Synopsis
Azure Automation runbook for integrated ASR networking configuration management.

### Syntax

```powershell
.\ASR-NetworkingAutomation.ps1
    [-Operation] <String>
    [-ResourceGroupName] <String>
    [-StorageAccountName] <String>
    [-StorageResourceGroupName] <String>
    [-VmNames <String[]>]
    [-DryRun]
    [<CommonParameters>]
```

### Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `Operation` | String | Yes | Operation to perform: "Backup" or "Restore" |
| `ResourceGroupName` | String | Yes | Target resource group |
| `StorageAccountName` | String | Yes | Storage account for configuration persistence |
| `StorageResourceGroupName` | String | Yes | Resource group containing storage account |
| `VmNames` | String[] | No | Specific VM names to process |
| `DryRun` | Switch | No | Preview mode for restore operations |

### Examples

```powershell
# Backup operation in Azure Automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Backup" `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -StorageAccountName "asrnetworkingconfigs" `
    -StorageResourceGroupName "shared-services-rg"

# Restore operation in Azure Automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Restore" `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -StorageAccountName "asrnetworkingconfigs" `
    -StorageResourceGroupName "shared-services-rg"
```

---

## 🎯 Usage Examples

### Scenario 1: Manual Pre-Failover Backup

```powershell
# Step 1: Connect to Azure
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"

# Step 2: Backup all VM networking configurations
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-eastus-rg" `
    -StorageAccountName "drnetworkconfigs" `
    -StorageResourceGroupName "shared-services-rg" `
    -IncludeAppGateway `
    -IncludeLoadBalancer `
    -Detailed

# Output: Configuration files saved to storage account
# - MASTER-networking-config-20241201-143022.json
# - web-vm-1-networking-config-20241201-143022.json
# - web-vm-2-networking-config-20241201-143022.json
# - app-vm-1-networking-config-20241201-143022.json
```

### Scenario 2: Post-Failover Restoration with Validation

```powershell
# Step 1: Connect to secondary region
Connect-AzAccount
Set-AzContext -SubscriptionId "your-subscription-id"

# Step 2: Download configurations from storage (if needed)
$storageAccount = Get-AzStorageAccount -ResourceGroupName "shared-services-rg" -Name "drnetworkconfigs"
$configPath = "C:\ASR\RestoreConfigs"
New-Item -Path $configPath -ItemType Directory -Force

# Step 3: Preview restoration changes
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -ConfigurationPath $configPath `
    -DryRun `
    -Detailed

# Step 4: Apply configurations after review
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -ConfigurationPath $configPath `
    -Force
```

### Scenario 3: Selective VM Restoration

```powershell
# Restore only critical web tier VMs
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -VmNames @("web-vm-1", "web-vm-2", "web-vm-3") `
    -Force `
    -Detailed

# Verify specific VM configurations
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -VmNames @("app-vm-1") `
    -DryRun
```

---

## 🔧 Configuration Management

### Master Configuration File Structure

```json
{
  "Timestamp": "2024-12-01T14:30:22Z",
  "SourceSubscription": "subscription-guid",
  "PrimaryResourceGroup": "webapp-prod-eastus-rg",
  "SecondaryResourceGroup": "webapp-prod-westus2-rg",
  "ConfigurationFiles": [
    "web-vm-1-networking-config-20241201-143022.json",
    "web-vm-2-networking-config-20241201-143022.json",
    "app-vm-1-networking-config-20241201-143022.json"
  ],
  "Statistics": {
    "TotalVMs": 3,
    "TotalNICs": 6,
    "TotalASGs": 4,
    "TotalStaticIPs": 2
  }
}
```

### Individual VM Configuration File Structure

```json
{
  "VmName": "web-vm-1",
  "VmId": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Compute/virtualMachines/web-vm-1",
  "Timestamp": "2024-12-01T14:30:22Z",
  "NetworkInterfaces": [
    {
      "Name": "web-vm-1-nic",
      "ResourceGroup": "webapp-prod-eastus-rg",
      "ApplicationSecurityGroups": [
        {
          "IpConfigurationName": "ipconfig1",
          "AsgName": "web-tier-asg",
          "AsgId": "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/applicationSecurityGroups/web-tier-asg",
          "AsgResourceGroup": "webapp-prod-eastus-rg"
        }
      ],
      "StaticIpConfigurations": [
        {
          "IpConfigurationName": "ipconfig1",
          "StaticPrivateIpAddress": "10.1.1.10",
          "StaticPublicIpAddress": null
        }
      ],
      "LoadBalancerBackendPools": [
        {
          "IpConfigurationName": "ipconfig1",
          "LoadBalancerName": "web-lb-primary",
          "LoadBalancerResourceGroup": "webapp-prod-eastus-rg",
          "BackendPoolName": "web-backend-pool"
        }
      ],
      "ApplicationGatewayBackendPools": [
        {
          "IpConfigurationName": "ipconfig1",
          "ApplicationGatewayName": "web-appgw-primary",
          "ApplicationGatewayResourceGroup": "webapp-prod-eastus-rg",
          "BackendPoolName": "web-backend-pool"
        }
      ]
    }
  ]
}
```

---

## 🤖 Azure Automation Integration

### 1. Create Automation Account

```powershell
# Create Azure Automation Account
$automationAccount = New-AzAutomationAccount `
    -ResourceGroupName "shared-services-rg" `
    -Name "asr-networking-automation" `
    -Location "East US" `
    -Plan "Free"
```

### 2. Import Required Modules

```powershell
# Import PowerShell modules to Automation Account
$modules = @("Az.Accounts", "Az.Network", "Az.Compute", "Az.Resources", "Az.Storage")

foreach ($module in $modules) {
    Import-AzAutomationModule `
        -AutomationAccountName "asr-networking-automation" `
        -ResourceGroupName "shared-services-rg" `
        -Name $module
}
```

### 3. Create Automation Credentials

```powershell
# Create credential for service principal
$credential = Get-Credential -Message "Enter Service Principal credentials"
New-AzAutomationCredential `
    -AutomationAccountName "asr-networking-automation" `
    -ResourceGroupName "shared-services-rg" `
    -Name "ASR-ServicePrincipal" `
    -Value $credential
```

### 4. Create Runbooks

```powershell
# Import networking automation runbook
Import-AzAutomationRunbook `
    -AutomationAccountName "asr-networking-automation" `
    -ResourceGroupName "shared-services-rg" `
    -Path "C:\Scripts\ASR-NetworkingAutomation.ps1" `
    -Type "PowerShell" `
    -Name "ASR-NetworkingAutomation"

# Publish runbook
Publish-AzAutomationRunbook `
    -AutomationAccountName "asr-networking-automation" `
    -ResourceGroupName "shared-services-rg" `
    -Name "ASR-NetworkingAutomation"
```

### 5. ASR Recovery Plan Integration

```powershell
# Add pre-failover script to ASR Recovery Plan
$preScript = @{
    ScriptName = "ASR-NetworkingAutomation"
    FabricLocation = "Primary"
    Parameters = @{
        Operation = "Backup"
        ResourceGroupName = "webapp-prod-eastus-rg"
        StorageAccountName = "asrnetworkingconfigs"
        StorageResourceGroupName = "shared-services-rg"
    }
}

# Add post-failover script to ASR Recovery Plan
$postScript = @{
    ScriptName = "ASR-NetworkingAutomation"
    FabricLocation = "Secondary"
    Parameters = @{
        Operation = "Restore"
        ResourceGroupName = "webapp-prod-westus2-rg"
        StorageAccountName = "asrnetworkingconfigs"
        StorageResourceGroupName = "shared-services-rg"
    }
}
```

---

## 🔍 Troubleshooting

### Common Issues and Solutions

#### Issue 1: Authentication Failures

**Symptoms:**
```
ERROR: No Azure context found
ERROR: The client 'xxx' with object id 'xxx' does not have authorization to perform action
```

**Solutions:**
```powershell
# Re-authenticate to Azure
Connect-AzAccount -Force

# Verify current context
Get-AzContext

# Set correct subscription
Set-AzContext -SubscriptionId "your-subscription-id"

# Verify permissions
Get-AzRoleAssignment -SignInName "your-account@domain.com"
```

#### Issue 2: Configuration Files Not Found

**Symptoms:**
```
WARNING: Configuration file not found: web-vm-1-networking-config-20241201-143022.json
ERROR: No master configuration file found in C:\ASR\Configs
```

**Solutions:**
```powershell
# Verify file locations
Get-ChildItem -Path "C:\ASR\Configs" -Filter "*.json"

# Check storage account access
$storageAccount = Get-AzStorageAccount -ResourceGroupName "shared-services-rg" -Name "asrnetworkconfigs"
$ctx = $storageAccount.Context
Get-AzStorageBlob -Container "networking-configs" -Context $ctx

# Download configurations from storage
Get-AzStorageBlobContent `
    -Container "networking-configs" `
    -Blob "MASTER-networking-config-20241201-143022.json" `
    -Destination "C:\ASR\Configs\" `
    -Context $ctx
```

#### Issue 3: Resource Not Found Errors

**Symptoms:**
```
WARNING: Application Security Group web-tier-asg not found
WARNING: Load balancer web-lb-secondary not found
```

**Solutions:**
```powershell
# Check resource naming conventions
Get-AzApplicationSecurityGroup -ResourceGroupName "webapp-prod-westus2-rg" | Select-Object Name

# Verify cross-region resource mapping
$primaryLbName = "web-lb-primary"
$secondaryLbName = $primaryLbName -replace "-primary-", "-secondary-"
Get-AzLoadBalancer -ResourceGroupName "webapp-prod-westus2-rg" -Name $secondaryLbName

# Manual resource creation if needed
New-AzApplicationSecurityGroup `
    -ResourceGroupName "webapp-prod-westus2-rg" `
    -Name "web-tier-asg" `
    -Location "West US 2"
```

#### Issue 4: PowerShell Module Issues

**Symptoms:**
```
ERROR: The 'Az.Network' module is not available
ERROR: Command 'Get-AzNetworkInterface' not found
```

**Solutions:**
```powershell
# Check installed modules
Get-Module -Name Az.* -ListAvailable

# Install missing modules
Install-Module -Name Az.Network -Force -AllowClobber

# Import modules
Import-Module -Name Az.Network -Force

# Update modules to latest version
Update-Module -Name Az -Force
```

### Debug Mode Execution

```powershell
# Enable verbose output for debugging
$VerbosePreference = "Continue"
$DebugPreference = "Continue"

# Run script with detailed logging
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -Detailed `
    -DryRun `
    -Verbose
```

### Log Analysis

```powershell
# Analyze backup logs
$backupLog = Get-Content "networking-config-backup-20241201-143022.log" | Where-Object { $_ -match "ERROR|WARNING" }
$backupLog | Out-GridView

# Analyze restoration logs
$restoreLog = Get-Content "networking-config-restore-20241201-144515.log" | Where-Object { $_ -match "SUCCESS|FAILED" }
$restoreLog | Out-GridView

# Export logs for analysis
$backupLog | Export-Csv "backup-errors.csv" -NoTypeInformation
```

---

## 🛡️ Best Practices

### 1. Configuration Management

```powershell
# Always backup before major changes
.\Save-NetworkingConfig.ps1 -ResourceGroupName "production-rg" -Detailed

# Use version control for scripts
git add *.ps1
git commit -m "Updated ASR networking automation scripts"

# Test in non-production environment first
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "test-rg" -DryRun
```

### 2. Security Best Practices

```powershell
# Use service principals for automation
$servicePrincipal = New-AzADServicePrincipal -DisplayName "ASR-Networking-Automation"

# Assign minimal required permissions
New-AzRoleAssignment `
    -ObjectId $servicePrincipal.Id `
    -RoleDefinitionName "Network Contributor" `
    -ResourceGroupName "webapp-prod-eastus-rg"

# Store credentials securely in Key Vault
Set-AzKeyVaultSecret `
    -VaultName "asr-secrets-kv" `
    -Name "ASR-SP-Password" `
    -SecretValue $servicePrincipal.Secret
```

### 3. Monitoring and Alerting

```powershell
# Create custom metrics for monitoring
$customMetric = @{
    MetricName = "ASR-NetworkingRestore-Success"
    Value = 1
    TimeStamp = (Get-Date).ToUniversalTime()
}

# Send metrics to Azure Monitor
Send-AzMetric @customMetric

# Create alerts for failures
New-AzMetricAlertRule `
    -Name "ASR-NetworkingRestore-Failed" `
    -ResourceGroupName "monitoring-rg" `
    -Condition "ASR-NetworkingRestore-Success < 1"
```

### 4. Backup and Recovery

```powershell
# Regular configuration backups
$scheduleJob = Register-ScheduledJob -Name "ASR-Network-Backup" -ScriptBlock {
    .\Save-NetworkingConfig.ps1 `
        -ResourceGroupName "webapp-prod-eastus-rg" `
        -StorageAccountName "asrnetworkconfigs" `
        -StorageResourceGroupName "shared-services-rg"
} -Trigger (New-JobTrigger -Daily -At "2:00 AM")

# Retention policy for old configurations
$retentionDays = 30
$cutoffDate = (Get-Date).AddDays(-$retentionDays)
Get-AzStorageBlob -Container "networking-configs" -Context $storageContext |
    Where-Object { $_.LastModified -lt $cutoffDate } |
    Remove-AzStorageBlob
```

---

## 🔐 Security Considerations

### Authentication and Authorization

#### Service Principal Setup

```powershell
# Create dedicated service principal for ASR automation
$sp = New-AzADServicePrincipal -DisplayName "ASR-Networking-SP" -Role "Contributor"

# Limit permissions to specific resource groups
$resourceGroups = @("webapp-prod-eastus-rg", "webapp-prod-westus2-rg", "shared-services-rg")
foreach ($rg in $resourceGroups) {
    New-AzRoleAssignment -ObjectId $sp.Id -RoleDefinitionName "Network Contributor" -ResourceGroupName $rg
}
```

#### Managed Identity (Recommended)

```powershell
# Enable system-assigned managed identity for Automation Account
$automationAccount = Get-AzAutomationAccount -ResourceGroupName "shared-services-rg" -Name "asr-networking-automation"
$automationAccount | Set-AzAutomationAccount -AssignSystemIdentity

# Assign permissions to managed identity
$managedIdentity = Get-AzADServicePrincipal -DisplayName "asr-networking-automation"
New-AzRoleAssignment -ObjectId $managedIdentity.Id -RoleDefinitionName "Network Contributor" -Scope "/subscriptions/your-subscription-id"
```

### Data Protection

#### Configuration File Encryption

```powershell
# Encrypt sensitive configuration data
$configData = Get-Content "web-vm-1-networking-config.json" | ConvertFrom-Json
$encryptedConfig = $configData | ConvertTo-Json | ConvertTo-SecureString -AsPlainText -Force
$encryptedConfig | ConvertFrom-SecureString | Out-File "web-vm-1-networking-config.encrypted"

# Decrypt when needed
$encryptedData = Get-Content "web-vm-1-networking-config.encrypted" | ConvertTo-SecureString
$configData = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($encryptedData))
```

#### Storage Account Security

```powershell
# Enable storage account encryption
$storageAccount = Set-AzStorageAccount `
    -ResourceGroupName "shared-services-rg" `
    -Name "asrnetworkconfigs" `
    -EnableHttpsTrafficOnly $true `
    -MinimumTlsVersion "TLS1_2"

# Configure network access rules
Add-AzStorageAccountNetworkRule `
    -ResourceGroupName "shared-services-rg" `
    -Name "asrnetworkconfigs" `
    -VirtualNetworkResourceId "/subscriptions/{sub}/resourceGroups/{rg}/providers/Microsoft.Network/virtualNetworks/{vnet}/subnets/{subnet}"
```

### Audit and Compliance

#### Activity Logging

```powershell
# Enable diagnostic settings for Automation Account
$diagnosticSettings = @{
    Name = "ASR-Automation-Diagnostics"
    ResourceId = (Get-AzAutomationAccount -ResourceGroupName "shared-services-rg" -Name "asr-networking-automation").ResourceId
    WorkspaceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName "monitoring-rg" -Name "central-logs").ResourceId
    Log = @(
        @{ Category = "JobLogs"; Enabled = $true }
        @{ Category = "JobStreams"; Enabled = $true }
        @{ Category = "DscNodeStatus"; Enabled = $true }
    )
}
Set-AzDiagnosticSetting @diagnosticSettings
```

---

## 📊 Monitoring & Logging

### Log Analytics Integration

```powershell
# Create custom log table for ASR networking events
$customLogSchema = @{
    TableName = "ASRNetworkingEvents_CL"
    Schema = @(
        @{ Name = "Timestamp"; Type = "datetime" }
        @{ Name = "Operation"; Type = "string" }
        @{ Name = "VmName"; Type = "string" }
        @{ Name = "ResourceGroup"; Type = "string" }
        @{ Name = "Status"; Type = "string" }
        @{ Name = "Details"; Type = "string" }
    )
}

# Send custom events to Log Analytics
$logData = @{
    Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Operation = "NetworkingRestore"
    VmName = "web-vm-1"
    ResourceGroup = "webapp-prod-westus2-rg"
    Status = "Success"
    Details = "Successfully restored 3 ASG memberships and 1 static IP"
}

Send-AzOperationalInsightsDataCollector -WorkspaceId $workspaceId -SharedKey $sharedKey -Body ($logData | ConvertTo-Json) -LogType "ASRNetworkingEvents"
```

### Performance Monitoring

```powershell
# Track script execution times
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

# Execute script operations
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-secondary-rg"

$stopwatch.Stop()
Write-Host "Script execution time: $($stopwatch.Elapsed)"

# Log performance metrics
$performanceData = @{
    ScriptName = "Restore-NetworkingConfig"
    ExecutionTimeMs = $stopwatch.ElapsedMilliseconds
    VmCount = 5
    ConfigurationsRestored = 15
    Timestamp = Get-Date
}
$performanceData | Export-Csv "script-performance.csv" -Append -NoTypeInformation
```

### Alert Configuration

```kusto
// Log Analytics query for ASR networking failures
ASRNetworkingEvents_CL
| where Status == "Failed"
| where TimeGenerated > ago(1h)
| summarize FailureCount = count() by Operation, bin(TimeGenerated, 5m)
| where FailureCount > 0
```

```powershell
# Create alert rule for networking restoration failures
$alertRule = @{
    Name = "ASR-NetworkingRestore-Failures"
    ResourceGroupName = "monitoring-rg"
    TargetResourceId = (Get-AzOperationalInsightsWorkspace -ResourceGroupName "monitoring-rg" -Name "central-logs").ResourceId
    Query = "ASRNetworkingEvents_CL | where Status == 'Failed' | where TimeGenerated > ago(5m)"
    TimeAggregationOperator = "GreaterThan"
    Threshold = 0
    ActionGroupId = (Get-AzActionGroup -ResourceGroupName "monitoring-rg" -Name "critical-alerts").Id
}
New-AzScheduledQueryRule @alertRule
```

---

## 📞 Support and Troubleshooting

### Contact Information

- **Internal IT Support**: [Email/Teams Channel]
- **Azure Support**: [Azure Portal Support]
- **Emergency Contact**: [On-call engineer details]

### Documentation Updates

This documentation is maintained in the repository at:
- **Repository**: [Git repository URL]
- **Documentation Path**: `/docs/PowerShell-ASR-Networking-Automation-Documentation.md`
- **Last Updated**: 2024-12-01
- **Version**: 1.0.0

### Contributing

To contribute improvements to the scripts or documentation:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request
5. Request review from the infrastructure team

---

## 📋 Appendix

### Quick Reference Commands

```powershell
# Quick backup
.\Save-NetworkingConfig.ps1 -ResourceGroupName "prod-rg"

# Quick restore preview
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "dr-rg" -DryRun

# Quick restore execution
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "dr-rg" -Force

# Check Azure connection
Get-AzContext

# List saved configurations
Get-ChildItem -Filter "*networking-config*.json"
```

### Common File Locations

```
C:\ASR\Scripts\                     # Script files
C:\ASR\Configs\                     # Configuration files
C:\ASR\Logs\                        # Log files
D:\ASR\Backups\                     # Backup configurations
Azure Storage: networking-configs/  # Cloud storage
```

### Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2024-12-01 | Initial release with full ASR networking automation |

---

*This documentation covers the complete PowerShell automation suite for Azure Site Recovery networking configuration management. For additional support, please refer to the troubleshooting section or contact the infrastructure team.*