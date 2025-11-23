#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources, Az.RecoveryServices

<#
.SYNOPSIS
    Azure Site Recovery automation script for networking configuration backup and restoration.

.DESCRIPTION
    This script is designed to be executed as part of Azure Site Recovery automation.
    It can be called pre-failover to save configurations or post-failover to restore them.
    The script automatically detects the execution context and performs the appropriate action.

.PARAMETER Operation
    Specifies the operation to perform: 'Backup' to save configurations, 'Restore' to restore them, or 'Auto' to detect based on context

.PARAMETER RecoveryPlanName
    Name of the Recovery Plan (used for context detection)

.PARAMETER ResourceGroupName
    Source resource group name (for backup) or target resource group name (for restore)

.PARAMETER ConfigurationStorageAccount
    Storage account name for storing configuration files

.PARAMETER ConfigurationContainer
    Storage container name for configuration files (default: 'asr-networking-configs')

.PARAMETER ProjectName
    Project name used in resource naming convention

.PARAMETER Environment
    Environment name (prod, staging, dev)

.PARAMETER AutomationAccountName
    Name of the Azure Automation Account (for credential access)

.EXAMPLE
    # Pre-failover backup
    .\ASR-NetworkingAutomation.ps1 -Operation "Backup" -ResourceGroupName "webapp-prod-primary-rg" -ConfigurationStorageAccount "asrconfigs" -ProjectName "webapp" -Environment "prod"

.EXAMPLE
    # Post-failover restore
    .\ASR-NetworkingAutomation.ps1 -Operation "Restore" -ResourceGroupName "webapp-prod-secondary-rg" -ConfigurationStorageAccount "asrconfigs" -ProjectName "webapp" -Environment "prod"

.EXAMPLE
    # Auto-detection mode (for ASR automation)
    .\ASR-NetworkingAutomation.ps1 -Operation "Auto" -RecoveryPlanName "webapp-recovery-plan" -ConfigurationStorageAccount "asrconfigs"

.NOTES
    Author: Azure Infrastructure Team
    Version: 1.0.0

    This script is designed to run in Azure Automation as part of ASR runbooks.
    It requires appropriate service principal permissions for resource management.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Backup", "Restore", "Auto")]
    [string]$Operation,

    [Parameter(Mandatory = $false)]
    [string]$RecoveryPlanName,

    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$ConfigurationStorageAccount,

    [Parameter(Mandatory = $false)]
    [string]$ConfigurationContainer = "asr-networking-configs",

    [Parameter(Mandatory = $false)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$AutomationAccountName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

    [Parameter(Mandatory = $false)]
    [switch]$DetailedLogging
)

# Set strict mode for better error handling
Set-StrictMode -Version 3.0

# Global variables
$ErrorActionPreference = "Stop"
$ExecutionTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TempPath = $env:TEMP

#region Helper Functions

function Write-AsrLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "CRITICAL")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [ASR-AUTOMATION] [$Level] $Message"

    # Write to output stream for Azure Automation
    switch ($Level) {
        "INFO"     { Write-Output $logMessage }
        "WARNING"  { Write-Warning $logMessage }
        "ERROR"    { Write-Error $logMessage }
        "SUCCESS"  { Write-Output $logMessage }
        "CRITICAL" { Write-Error $logMessage; throw $Message }
    }
}

function Connect-AzureWithRetry {
    param(
        [Parameter(Mandatory = $false)]
        [int]$MaxRetries = 3
    )

    for ($i = 1; $i -le $MaxRetries; $i++) {
        try {
            Write-AsrLog "Attempting Azure connection (attempt $i of $MaxRetries)" "INFO"

            if ($AutomationAccountName) {
                # Running in Azure Automation - use managed identity or service principal
                $context = Get-AzContext
                if (-not $context) {
                    Connect-AzAccount -Identity | Out-Null
                }
            }
            else {
                # Running outside Azure Automation
                $context = Get-AzContext
                if (-not $context) {
                    throw "No Azure context available. Please authenticate first."
                }
            }

            if ($SubscriptionId) {
                Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
            }

            $currentContext = Get-AzContext
            Write-AsrLog "Connected to Azure subscription: $($currentContext.Subscription.Name)" "SUCCESS"
            return $true
        }
        catch {
            Write-AsrLog "Azure connection attempt $i failed: $($_.Exception.Message)" "WARNING"
            if ($i -eq $MaxRetries) {
                Write-AsrLog "All Azure connection attempts failed" "CRITICAL"
                return $false
            }
            Start-Sleep -Seconds 10
        }
    }
}

function Get-ASRContext {
    param(
        [Parameter(Mandatory = $false)]
        [string]$RecoveryPlanName
    )

    try {
        Write-AsrLog "Detecting ASR execution context" "INFO"

        # Try to get context from environment variables (set by ASR)
        $asrContext = @{
            RecoveryPlanName = $env:RecoveryPlanName ?? $RecoveryPlanName
            FailoverType = $env:FailoverType ?? "Unknown"
            FailoverDirection = $env:FailoverDirection ?? "Unknown"
            PrimaryResourceGroup = $env:PrimaryResourceGroup
            SecondaryResourceGroup = $env:SecondaryResourceGroup
            ProtectedVMs = $env:ProtectedVMs -split "," | Where-Object { $_ }
        }

        # Derive project and environment from recovery plan name if not provided
        if (-not $ProjectName -and $asrContext.RecoveryPlanName) {
            $parts = $asrContext.RecoveryPlanName -split "-"
            if ($parts.Count -ge 2) {
                $ProjectName = $parts[0]
                $Environment = $parts[1]
            }
        }

        # Auto-detect operation based on failover type
        if ($Operation -eq "Auto") {
            switch ($asrContext.FailoverType.ToLower()) {
                "plannedFailover" { $Operation = "Backup" }
                "unplannedFailover" { $Operation = "Restore" }
                "testFailover" { $Operation = "Restore" }
                "commitFailover" { $Operation = "Restore" }
                "failback" { $Operation = "Restore" }
                default {
                    Write-AsrLog "Unknown failover type: $($asrContext.FailoverType). Defaulting to Backup" "WARNING"
                    $Operation = "Backup"
                }
            }
        }

        # Determine resource groups
        if (-not $ResourceGroupName) {
            if ($Operation -eq "Backup") {
                $ResourceGroupName = $asrContext.PrimaryResourceGroup ?? "$ProjectName-$Environment-primary-rg"
            }
            else {
                $ResourceGroupName = $asrContext.SecondaryResourceGroup ?? "$ProjectName-$Environment-secondary-rg"
            }
        }

        Write-AsrLog "ASR Context detected:" "INFO"
        Write-AsrLog "  Recovery Plan: $($asrContext.RecoveryPlanName)" "INFO"
        Write-AsrLog "  Failover Type: $($asrContext.FailoverType)" "INFO"
        Write-AsrLog "  Operation: $Operation" "INFO"
        Write-AsrLog "  Resource Group: $ResourceGroupName" "INFO"
        Write-AsrLog "  Project: $ProjectName, Environment: $Environment" "INFO"

        return @{
            Context = $asrContext
            Operation = $Operation
            ResourceGroupName = $ResourceGroupName
            ProjectName = $ProjectName
            Environment = $Environment
        }
    }
    catch {
        Write-AsrLog "Failed to detect ASR context: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Download-ConfigurationFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$LocalPath
    )

    try {
        Write-AsrLog "Downloading configuration files from storage account: $StorageAccountName" "INFO"

        # Get storage account context
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }
        if (-not $storageAccount) {
            throw "Storage account $StorageAccountName not found"
        }

        $ctx = $storageAccount.Context

        # Ensure local directory exists
        if (-not (Test-Path $LocalPath)) {
            New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
        }

        # Download all JSON configuration files
        $blobs = Get-AzStorageBlob -Container $ContainerName -Context $ctx | Where-Object { $_.Name.EndsWith('.json') }

        $downloadedFiles = @()
        foreach ($blob in $blobs) {
            $localFile = Join-Path $LocalPath $blob.Name
            Get-AzStorageBlobContent -Blob $blob.Name -Container $ContainerName -Destination $localFile -Context $ctx -Force | Out-Null
            $downloadedFiles += $localFile
            Write-AsrLog "  Downloaded: $($blob.Name)" "INFO"
        }

        Write-AsrLog "Downloaded $($downloadedFiles.Count) configuration files" "SUCCESS"
        return $downloadedFiles
    }
    catch {
        Write-AsrLog "Failed to download configuration files: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Upload-ConfigurationFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StorageAccountName,

        [Parameter(Mandatory = $true)]
        [string]$ContainerName,

        [Parameter(Mandatory = $true)]
        [string]$LocalPath
    )

    try {
        Write-AsrLog "Uploading configuration files to storage account: $StorageAccountName" "INFO"

        # Get storage account context
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $StorageAccountName }
        if (-not $storageAccount) {
            throw "Storage account $StorageAccountName not found"
        }

        $ctx = $storageAccount.Context

        # Ensure container exists
        $container = Get-AzStorageContainer -Name $ContainerName -Context $ctx -ErrorAction SilentlyContinue
        if (-not $container) {
            New-AzStorageContainer -Name $ContainerName -Context $ctx -Permission Off | Out-Null
            Write-AsrLog "Created storage container: $ContainerName" "INFO"
        }

        # Upload all JSON files
        $configFiles = Get-ChildItem -Path $LocalPath -Filter "*.json"
        $uploadedFiles = @()

        foreach ($file in $configFiles) {
            $blobName = "$ExecutionTimestamp/$($file.Name)"
            Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Blob $blobName -Context $ctx -Force | Out-Null
            $uploadedFiles += $blobName
            Write-AsrLog "  Uploaded: $blobName" "INFO"
        }

        # Upload log files
        $logFiles = Get-ChildItem -Path $LocalPath -Filter "*.log"
        foreach ($file in $logFiles) {
            $blobName = "$ExecutionTimestamp/logs/$($file.Name)"
            Set-AzStorageBlobContent -File $file.FullName -Container $ContainerName -Blob $blobName -Context $ctx -Force | Out-Null
            Write-AsrLog "  Uploaded log: $blobName" "INFO"
        }

        Write-AsrLog "Uploaded $($uploadedFiles.Count) configuration files and $($logFiles.Count) log files" "SUCCESS"
        return $uploadedFiles
    }
    catch {
        Write-AsrLog "Failed to upload configuration files: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Invoke-BackupOperation {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    try {
        Write-AsrLog "=== STARTING BACKUP OPERATION ===" "INFO"

        $tempConfigPath = Join-Path $TempPath "asr-config-backup-$ExecutionTimestamp"
        New-Item -ItemType Directory -Path $tempConfigPath -Force | Out-Null

        # Determine secondary resource group for backup operation
        $secondaryResourceGroup = $Context.ResourceGroupName -replace "-primary-", "-secondary-"

        # Execute backup script
        $backupScript = Join-Path $PSScriptRoot "Save-NetworkingConfig.ps1"
        if (-not (Test-Path $backupScript)) {
            throw "Backup script not found: $backupScript"
        }

        Write-AsrLog "Executing networking configuration backup..." "INFO"
        $backupParams = @{
            ResourceGroupName = $Context.ResourceGroupName
            SecondaryResourceGroupName = $secondaryResourceGroup
            ConfigurationPath = $tempConfigPath
            ProjectName = $Context.ProjectName
            Environment = $Context.Environment
        }

        & $backupScript @backupParams

        if ($LASTEXITCODE -ne 0) {
            throw "Backup script failed with exit code: $LASTEXITCODE"
        }

        # Upload to storage account
        Upload-ConfigurationFiles -StorageAccountName $ConfigurationStorageAccount -ContainerName $ConfigurationContainer -LocalPath $tempConfigPath

        Write-AsrLog "Backup operation completed successfully" "SUCCESS"
    }
    catch {
        Write-AsrLog "Backup operation failed: $($_.Exception.Message)" "ERROR"
        throw
    }
    finally {
        # Cleanup temp files
        if (Test-Path $tempConfigPath) {
            Remove-Item -Path $tempConfigPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-RestoreOperation {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Context
    )

    try {
        Write-AsrLog "=== STARTING RESTORE OPERATION ===" "INFO"

        $tempConfigPath = Join-Path $TempPath "asr-config-restore-$ExecutionTimestamp"
        New-Item -ItemType Directory -Path $tempConfigPath -Force | Out-Null

        # Download latest configuration files
        Download-ConfigurationFiles -StorageAccountName $ConfigurationStorageAccount -ContainerName $ConfigurationContainer -LocalPath $tempConfigPath

        # Find the most recent master config file
        $masterConfigFiles = Get-ChildItem -Path $tempConfigPath -Filter "MASTER-networking-config-*.json" | Sort-Object LastWriteTime -Descending
        if ($masterConfigFiles.Count -eq 0) {
            throw "No master configuration file found in downloaded files"
        }

        $masterConfigFile = $masterConfigFiles[0].FullName
        Write-AsrLog "Using master config file: $($masterConfigFiles[0].Name)" "INFO"

        # Execute restore script
        $restoreScript = Join-Path $PSScriptRoot "Restore-NetworkingConfig.ps1"
        if (-not (Test-Path $restoreScript)) {
            throw "Restore script not found: $restoreScript"
        }

        Write-AsrLog "Executing networking configuration restoration..." "INFO"
        $restoreParams = @{
            MasterConfigFile = $masterConfigFile
            ResourceGroupName = $Context.ResourceGroupName
            ConfigurationPath = $tempConfigPath
            Force = $true  # Skip confirmation in automation
        }

        & $restoreScript @restoreParams

        if ($LASTEXITCODE -ne 0) {
            Write-AsrLog "Restore script completed with warnings (exit code: $LASTEXITCODE)" "WARNING"
        }

        # Upload logs back to storage
        Upload-ConfigurationFiles -StorageAccountName $ConfigurationStorageAccount -ContainerName $ConfigurationContainer -LocalPath $tempConfigPath

        Write-AsrLog "Restore operation completed" "SUCCESS"
    }
    catch {
        Write-AsrLog "Restore operation failed: $($_.Exception.Message)" "ERROR"
        throw
    }
    finally {
        # Cleanup temp files
        if (Test-Path $tempConfigPath) {
            Remove-Item -Path $tempConfigPath -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

#endregion

#region Main Execution

function Main {
    try {
        Write-AsrLog "=== Azure Site Recovery Networking Automation ===" "INFO"
        Write-AsrLog "Version: 1.0.0" "INFO"
        Write-AsrLog "Execution started at: $(Get-Date)" "INFO"
        Write-AsrLog "Operation: $Operation" "INFO"

        # Connect to Azure
        if (-not (Connect-AzureWithRetry)) {
            throw "Failed to connect to Azure"
        }

        # Get execution context
        $context = Get-ASRContext -RecoveryPlanName $RecoveryPlanName

        # Validate required parameters
        if (-not $context.ProjectName -or -not $context.Environment) {
            throw "ProjectName and Environment are required. Either provide them as parameters or ensure they can be derived from RecoveryPlanName"
        }

        if (-not $context.ResourceGroupName) {
            throw "ResourceGroupName could not be determined. Please provide it as a parameter."
        }

        # Validate storage account exists
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $ConfigurationStorageAccount }
        if (-not $storageAccount) {
            throw "Configuration storage account '$ConfigurationStorageAccount' not found"
        }

        Write-AsrLog "Using storage account: $($storageAccount.StorageAccountName) in RG: $($storageAccount.ResourceGroupName)" "INFO"

        # Execute operation
        switch ($context.Operation) {
            "Backup" {
                Invoke-BackupOperation -Context $context
            }
            "Restore" {
                Invoke-RestoreOperation -Context $context
            }
            default {
                throw "Unknown operation: $($context.Operation)"
            }
        }

        Write-AsrLog "=== AUTOMATION COMPLETED SUCCESSFULLY ===" "SUCCESS"
        Write-AsrLog "Execution completed at: $(Get-Date)" "INFO"

        # Return success object for ASR
        return @{
            Status = "Success"
            Operation = $context.Operation
            ResourceGroup = $context.ResourceGroupName
            Timestamp = $ExecutionTimestamp
            Message = "Networking automation completed successfully"
        }
    }
    catch {
        Write-AsrLog "=== AUTOMATION FAILED ===" "ERROR"
        Write-AsrLog "Error: $($_.Exception.Message)" "ERROR"
        Write-AsrLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"

        # Return failure object for ASR
        return @{
            Status = "Failed"
            Operation = $Operation
            ResourceGroup = $ResourceGroupName
            Timestamp = $ExecutionTimestamp
            Error = $_.Exception.Message
            Message = "Networking automation failed"
        }
    }
}

# Execute main function and return result
$result = Main
Write-Output ($result | ConvertTo-Json -Depth 3)

# Exit with appropriate code
if ($result.Status -eq "Success") {
    exit 0
}
else {
    exit 1
}

#endregion