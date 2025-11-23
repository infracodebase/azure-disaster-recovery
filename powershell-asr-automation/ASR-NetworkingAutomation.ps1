#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources, Az.Storage

<#
.SYNOPSIS
    Azure Automation runbook for ASR networking configuration management compatible with Terraform and Bicep.

.DESCRIPTION
    This runbook provides unified backup and restoration of VM networking configurations for Azure Site Recovery
    scenarios. It works seamlessly with infrastructure deployed via either Terraform or Bicep by automatically
    detecting naming conventions and handling cross-region resource mapping.

    Designed to run in Azure Automation with managed identity authentication, supporting both pre-failover
    backup and post-failover restoration operations.

.PARAMETER Operation
    Operation to perform: "Backup" or "Restore"

.PARAMETER ResourceGroupName
    Target resource group containing the VMs

.PARAMETER StorageAccountName
    Azure Storage Account name for configuration persistence

.PARAMETER StorageResourceGroupName
    Resource group containing the storage account

.PARAMETER VmNames
    Comma-separated list of VM names to process (optional)

.PARAMETER InfrastructureType
    Infrastructure deployment type: "terraform", "bicep", or "auto" for automatic detection (default: auto)

.PARAMETER DryRun
    For restore operations, preview changes without applying them (default: false)

.PARAMETER ProjectName
    Project name used in resource naming convention (for backup operations)

.PARAMETER Environment
    Environment name (prod, staging, dev) (for backup operations)

.PARAMETER SecondaryResourceGroupName
    Secondary resource group name (for backup operations)

.PARAMETER SubscriptionId
    Azure subscription ID (optional, uses current context if not specified)

.EXAMPLE
    # Backup operation for Terraform infrastructure
    .\ASR-NetworkingAutomation.ps1 -Operation "Backup" -ResourceGroupName "webapp-prod-primary-rg" -StorageAccountName "asrnetworkconfigs" -StorageResourceGroupName "shared-services-rg" -InfrastructureType "terraform"

.EXAMPLE
    # Restore operation for Bicep infrastructure
    .\ASR-NetworkingAutomation.ps1 -Operation "Restore" -ResourceGroupName "webapp-prod-westus2-rg" -StorageAccountName "asrnetworkconfigs" -StorageResourceGroupName "shared-services-rg" -InfrastructureType "bicep"

.EXAMPLE
    # Backup with auto-detection and specific VMs
    .\ASR-NetworkingAutomation.ps1 -Operation "Backup" -ResourceGroupName "webapp-prod-eastus-rg" -StorageAccountName "asrconfigs" -VmNames "web-vm-1,web-vm-2,app-vm-1"

.NOTES
    Author: Azure Infrastructure Team
    Version: 1.0.0
    Compatible with: Terraform and Bicep infrastructure deployments
    Requires: Azure PowerShell modules, Azure Automation with Managed Identity

    This runbook automatically detects infrastructure type and applies appropriate cross-region mapping:
    - Terraform: primary/secondary resource name patterns
    - Bicep: region-based resource name patterns

    Designed for integration with Azure Site Recovery recovery plans as pre/post-failover scripts.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Backup", "Restore")]
    [string]$Operation,

    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$StorageAccountName,

    [Parameter(Mandatory = $true)]
    [string]$StorageResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$VmNames,

    [Parameter(Mandatory = $false)]
    [ValidateSet("terraform", "bicep", "auto")]
    [string]$InfrastructureType = "auto",

    [Parameter(Mandatory = $false)]
    [bool]$DryRun = $false,

    [Parameter(Mandatory = $false)]
    [string]$ProjectName,

    [Parameter(Mandatory = $false)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$SecondaryResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId
)

# Set strict mode and error handling
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"
$VerbosePreference = "Continue"

# Global variables
$RunbookTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$TempPath = $env:TEMP
$ConfigurationPath = Join-Path $TempPath "ASR-NetworkingConfigs-$RunbookTimestamp"

#region Helper Functions

function Write-RunbookLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO"
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"

    # Write to verbose stream for Azure Automation logging
    Write-Verbose $logMessage

    # Also write to appropriate streams
    switch ($Level) {
        "INFO"    { Write-Output $logMessage }
        "WARNING" { Write-Warning $logMessage }
        "ERROR"   { Write-Error $logMessage }
        "SUCCESS" { Write-Output $logMessage }
    }
}

function Connect-AzureWithManagedIdentity {
    try {
        Write-RunbookLog "Connecting to Azure with Managed Identity..." "INFO"

        # Connect using managed identity
        $null = Connect-AzAccount -Identity -ErrorAction Stop

        # Set subscription context if specified
        if ($SubscriptionId) {
            $null = Set-AzContext -SubscriptionId $SubscriptionId -ErrorAction Stop
            Write-RunbookLog "Set subscription context to: $SubscriptionId" "INFO"
        }

        $context = Get-AzContext
        Write-RunbookLog "Connected to Azure subscription: $($context.Subscription.Name)" "SUCCESS"
        Write-RunbookLog "Using tenant: $($context.Tenant.Id)" "INFO"

        return $true
    }
    catch {
        Write-RunbookLog "Failed to connect to Azure: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Detect-InfrastructureType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroupName
    )

    if ($InfrastructureType -ne "auto") {
        Write-RunbookLog "Infrastructure type manually set to: $InfrastructureType" "INFO"
        return $InfrastructureType
    }

    try {
        Write-RunbookLog "Auto-detecting infrastructure type..." "INFO"

        # Get a sample of resources to analyze naming patterns
        $resources = Get-AzResource -ResourceGroupName $ResourceGroupName | Select-Object -First 10

        $terraformIndicators = 0
        $bicepIndicators = 0

        foreach ($resource in $resources) {
            $name = $resource.Name.ToLower()

            # Terraform naming patterns
            if ($name -match '^[a-z]+-[a-z]+-[0-9]+$' -or
                $name -match '^[a-z]+-lb' -or
                $name -match '^[a-z]+-nsg' -or
                $name -match 'primary|secondary') {
                $terraformIndicators++
            }

            # Bicep naming patterns
            if ($name -match '^[a-z]+-[a-z]+-[a-z0-9]+-[a-z]+-[a-z0-9-]+$' -or
                $name -match 'eastus|westus|centralus|northeurope|westeurope' -or
                $name -match '^[a-z]+-prod-|^[a-z]+-staging-|^[a-z]+-dev-') {
                $bicepIndicators++
            }
        }

        $detectedType = if ($bicepIndicators > $terraformIndicators) { "bicep" } else { "terraform" }
        Write-RunbookLog "Auto-detected infrastructure type: $detectedType (TF: $terraformIndicators, Bicep: $bicepIndicators)" "INFO"

        return $detectedType
    }
    catch {
        Write-RunbookLog "Could not auto-detect infrastructure type, defaulting to terraform: $($_.Exception.Message)" "WARNING"
        return "terraform"
    }
}

function Get-CrossRegionResourceGroupMapping {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrimaryResourceGroup,

        [Parameter(Mandatory = $true)]
        [string]$InfraType
    )

    switch ($InfraType) {
        "terraform" {
            # Terraform: simple primary/secondary replacement
            return $PrimaryResourceGroup -replace "primary", "secondary"
        }
        "bicep" {
            # Bicep: region-based replacement
            $mapped = $PrimaryResourceGroup -replace "eastus", "westus2" -replace "westus2", "eastus"
            $mapped = $mapped -replace "eastus2", "westus2" -replace "westus", "eastus2"
            $mapped = $mapped -replace "centralus", "eastus2"
            return $mapped
        }
        default {
            return $PrimaryResourceGroup -replace "primary", "secondary"
        }
    }
}

function Invoke-BackupOperation {
    try {
        Write-RunbookLog "=== STARTING BACKUP OPERATION ===" "INFO"

        # Detect infrastructure type
        $detectedInfraType = Detect-InfrastructureType -ResourceGroupName $ResourceGroupName

        # Prepare VM names array
        $vmNamesArray = @()
        if ($VmNames) {
            $vmNamesArray = $VmNames -split ',' | ForEach-Object { $_.Trim() }
            Write-RunbookLog "Processing specific VMs: $($vmNamesArray -join ', ')" "INFO"
        }

        # Determine secondary resource group if not provided
        if (-not $SecondaryResourceGroupName) {
            $SecondaryResourceGroupName = Get-CrossRegionResourceGroupMapping -PrimaryResourceGroup $ResourceGroupName -InfraType $detectedInfraType
            Write-RunbookLog "Auto-determined secondary RG: $SecondaryResourceGroupName" "INFO"
        }

        # Create temporary configuration directory
        New-Item -ItemType Directory -Path $ConfigurationPath -Force | Out-Null

        # Build backup script parameters
        $backupParams = @{
            ResourceGroupName = $ResourceGroupName
            ConfigurationPath = $ConfigurationPath
            InfrastructureType = $detectedInfraType
            StorageAccountName = $StorageAccountName
            StorageResourceGroupName = $StorageResourceGroupName
            IncludeAppGateway = $true
            IncludeLoadBalancer = $true
            Detailed = $true
        }

        if ($SecondaryResourceGroupName) {
            $backupParams.SecondaryResourceGroupName = $SecondaryResourceGroupName
        }

        if ($ProjectName) {
            $backupParams.ProjectName = $ProjectName
        }

        if ($Environment) {
            $backupParams.Environment = $Environment
        }

        if ($vmNamesArray.Count -gt 0) {
            $backupParams.VmNames = $vmNamesArray
        }

        # Execute backup by calling the main backup script logic inline
        Write-RunbookLog "Executing networking configuration backup..." "INFO"

        # Get list of VMs to process
        if ($vmNamesArray.Count -eq 0) {
            $vms = Get-AzVM -ResourceGroupName $ResourceGroupName
            $vmNamesArray = $vms | ForEach-Object { $_.Name }
        }

        if ($vmNamesArray.Count -eq 0) {
            Write-RunbookLog "No VMs found to process" "WARNING"
            return
        }

        Write-RunbookLog "Found $($vmNamesArray.Count) VMs to backup" "INFO"

        # Process each VM (simplified version for runbook)
        $successCount = 0
        $savedConfigurations = @()

        foreach ($vmName in $vmNamesArray) {
            try {
                Write-RunbookLog "Backing up VM: $vmName" "INFO"

                # Get VM and its network interfaces
                $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName
                $nics = @()

                foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
                    $nicName = $nicRef.Id.Split('/')[-1]
                    $nicResourceGroup = $nicRef.Id.Split('/')[4]
                    $nic = Get-AzNetworkInterface -ResourceGroupName $nicResourceGroup -Name $nicName
                    $nics += $nic
                }

                # Create VM configuration object
                $vmConfig = @{
                    VmName = $vmName
                    VmId = $vm.Id
                    VmResourceGroup = $ResourceGroupName
                    InfrastructureType = $detectedInfraType
                    Timestamp = $RunbookTimestamp
                    NetworkInterfaces = @()
                }

                foreach ($nic in $nics) {
                    # Simplified NIC configuration capture
                    $nicConfig = @{
                        Name = $nic.Name
                        ResourceGroup = $nic.ResourceGroupName
                        Id = $nic.Id
                        ApplicationSecurityGroups = @()
                        StaticIpConfigurations = @()
                        LoadBalancerBackendPools = @()
                        ApplicationGatewayBackendPools = @()
                    }

                    # Capture ASG memberships
                    foreach ($ipConfig in $nic.IpConfigurations) {
                        if ($ipConfig.ApplicationSecurityGroups) {
                            foreach ($asg in $ipConfig.ApplicationSecurityGroups) {
                                $nicConfig.ApplicationSecurityGroups += @{
                                    IpConfigurationName = $ipConfig.Name
                                    AsgName = $asg.Name
                                    AsgResourceGroup = $asg.ResourceGroupName
                                    AsgId = $asg.Id
                                }
                            }
                        }

                        # Capture static IP configurations
                        if ($ipConfig.PrivateIpAllocationMethod -eq "Static") {
                            $nicConfig.StaticIpConfigurations += @{
                                IpConfigurationName = $ipConfig.Name
                                StaticPrivateIpAddress = $ipConfig.PrivateIpAddress
                                SubnetId = $ipConfig.Subnet.Id
                            }
                        }

                        # Capture Load Balancer backend pools
                        if ($ipConfig.LoadBalancerBackendAddressPools) {
                            foreach ($pool in $ipConfig.LoadBalancerBackendAddressPools) {
                                $lbResourceId = $pool.Id -replace '/backendAddressPools/.*', ''
                                $lbName = $lbResourceId.Split('/')[-1]
                                $nicConfig.LoadBalancerBackendPools += @{
                                    IpConfigurationName = $ipConfig.Name
                                    LoadBalancerName = $lbName
                                    BackendPoolName = $pool.Name
                                }
                            }
                        }

                        # Capture Application Gateway backend pools
                        if ($ipConfig.ApplicationGatewayBackendAddressPools) {
                            foreach ($pool in $ipConfig.ApplicationGatewayBackendAddressPools) {
                                $appGwResourceId = $pool.Id -replace '/backendAddressPools/.*', ''
                                $appGwName = $appGwResourceId.Split('/')[-1]
                                $nicConfig.ApplicationGatewayBackendPools += @{
                                    IpConfigurationName = $ipConfig.Name
                                    ApplicationGatewayName = $appGwName
                                    BackendPoolName = $pool.Name
                                }
                            }
                        }
                    }

                    $vmConfig.NetworkInterfaces += $nicConfig
                }

                # Save configuration to file and storage
                $configFileName = "$vmName-networking-config-$RunbookTimestamp.json"
                $configFilePath = Join-Path $ConfigurationPath $configFileName

                $vmConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Encoding UTF8

                # Upload to storage
                $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $StorageAccountName
                $ctx = $storageAccount.Context

                # Create container if needed
                $containerName = "networking-configs"
                $container = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
                if (-not $container) {
                    New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off | Out-Null
                }

                Set-AzStorageBlobContent -File $configFilePath -Container $containerName -Blob $configFileName -Context $ctx -Force | Out-Null

                $savedConfigurations += $configFileName
                $successCount++

                Write-RunbookLog "Successfully backed up VM: $vmName" "SUCCESS"
            }
            catch {
                Write-RunbookLog "Failed to backup VM $vmName`: $($_.Exception.Message)" "ERROR"
            }
        }

        # Create and upload master configuration
        if ($savedConfigurations.Count -gt 0) {
            $masterConfig = @{
                Timestamp = $RunbookTimestamp
                ProjectName = $ProjectName
                Environment = $Environment
                InfrastructureType = $detectedInfraType
                PrimaryResourceGroup = $ResourceGroupName
                SecondaryResourceGroup = $SecondaryResourceGroupName
                ConfigurationFiles = $savedConfigurations
                Statistics = @{
                    TotalVMs = $savedConfigurations.Count
                }
                Azure = @{
                    SubscriptionId = (Get-AzContext).Subscription.Id
                    SubscriptionName = (Get-AzContext).Subscription.Name
                }
            }

            $masterConfigFileName = "MASTER-networking-config-$RunbookTimestamp.json"
            $masterConfigFilePath = Join-Path $ConfigurationPath $masterConfigFileName

            $masterConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $masterConfigFilePath -Encoding UTF8

            # Upload master config to storage
            Set-AzStorageBlobContent -File $masterConfigFilePath -Container $containerName -Blob $masterConfigFileName -Context $ctx -Force | Out-Null

            Write-RunbookLog "Master configuration uploaded: $masterConfigFileName" "SUCCESS"
        }

        Write-RunbookLog "=== BACKUP SUMMARY ===" "INFO"
        Write-RunbookLog "Infrastructure type: $detectedInfraType" "INFO"
        Write-RunbookLog "Successfully backed up: $successCount VMs" "SUCCESS"
        Write-RunbookLog "Configurations stored in: $StorageAccountName" "INFO"
    }
    catch {
        Write-RunbookLog "Backup operation failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Invoke-RestoreOperation {
    try {
        Write-RunbookLog "=== STARTING RESTORE OPERATION ===" "INFO"

        # Create temporary configuration directory
        New-Item -ItemType Directory -Path $ConfigurationPath -Force | Out-Null

        # Download configurations from storage
        Write-RunbookLog "Downloading configurations from storage..." "INFO"

        $storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $StorageAccountName
        $ctx = $storageAccount.Context
        $containerName = "networking-configs"

        # Download all configuration files
        $blobs = Get-AzStorageBlob -Container $containerName -Context $ctx | Where-Object { $_.Name -like "*.json" }

        if (-not $blobs) {
            Write-RunbookLog "No configuration files found in storage" "WARNING"
            return
        }

        $downloadCount = 0
        foreach ($blob in $blobs) {
            $destinationPath = Join-Path $ConfigurationPath $blob.Name
            Get-AzStorageBlobContent -Container $containerName -Blob $blob.Name -Destination $destinationPath -Context $ctx -Force | Out-Null
            $downloadCount++
        }

        Write-RunbookLog "Downloaded $downloadCount configuration files" "INFO"

        # Find and load master configuration
        $masterFiles = Get-ChildItem -Path $ConfigurationPath -Filter "MASTER-networking-config-*.json" | Sort-Object LastWriteTime -Descending
        if ($masterFiles.Count -eq 0) {
            throw "No master configuration file found"
        }

        $masterConfigPath = $masterFiles[0].FullName
        $masterConfig = Get-Content -Path $masterConfigPath -Raw | ConvertFrom-Json

        Write-RunbookLog "Loaded master config from: $($masterFiles[0].Name)" "INFO"
        Write-RunbookLog "Infrastructure type: $($masterConfig.InfrastructureType)" "INFO"

        # Load individual VM configurations
        $savedConfigurations = @{}
        foreach ($configFile in $masterConfig.ConfigurationFiles) {
            $configPath = Join-Path $ConfigurationPath $configFile
            if (Test-Path $configPath) {
                $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
                $savedConfigurations[$config.VmName] = $config
            }
        }

        Write-RunbookLog "Loaded configurations for $($savedConfigurations.Keys.Count) VMs" "INFO"

        # Filter VMs if specific names provided
        if ($VmNames) {
            $vmNamesArray = $VmNames -split ',' | ForEach-Object { $_.Trim() }
            $filteredConfigs = @{}
            foreach ($vmName in $vmNamesArray) {
                if ($savedConfigurations.ContainsKey($vmName)) {
                    $filteredConfigs[$vmName] = $savedConfigurations[$vmName]
                }
            }
            $savedConfigurations = $filteredConfigs
            Write-RunbookLog "Filtered to process $($savedConfigurations.Keys.Count) VMs" "INFO"
        }

        # Process each VM for restoration (simplified for runbook)
        $totalRestorations = 0
        $infraType = $masterConfig.InfrastructureType

        foreach ($vmName in $savedConfigurations.Keys) {
            try {
                Write-RunbookLog "Analyzing VM: $vmName" "INFO"
                $savedConfig = $savedConfigurations[$vmName]

                # Get current VM
                $vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction SilentlyContinue
                if (-not $vm) {
                    Write-RunbookLog "VM $vmName not found in $ResourceGroupName" "WARNING"
                    continue
                }

                $restorationsMade = 0

                # Process each NIC
                foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
                    $nicName = $nicRef.Id.Split('/')[-1]
                    $currentNic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction SilentlyContinue

                    if (-not $currentNic) { continue }

                    # Find saved NIC configuration
                    $savedNicConfig = $savedConfig.NetworkInterfaces | Where-Object { $_.Name -eq $nicName }
                    if (-not $savedNicConfig) { continue }

                    # Restore ASG memberships (simplified check)
                    foreach ($asgMembership in $savedNicConfig.ApplicationSecurityGroups) {
                        $ipConfigName = $asgMembership.IpConfigurationName
                        $asgName = $asgMembership.AsgName

                        $currentIpConfig = $currentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }
                        if ($currentIpConfig) {
                            $currentAsg = $currentIpConfig.ApplicationSecurityGroups | Where-Object { $_.Name -eq $asgName }
                            if (-not $currentAsg) {
                                if (-not $DryRun) {
                                    # Try to find and add ASG
                                    $asg = Get-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $asgName -ErrorAction SilentlyContinue
                                    if ($asg) {
                                        if (-not $currentIpConfig.ApplicationSecurityGroups) {
                                            $currentIpConfig.ApplicationSecurityGroups = @()
                                        }
                                        $currentIpConfig.ApplicationSecurityGroups += $asg
                                        Set-AzNetworkInterface -NetworkInterface $currentNic | Out-Null
                                        Write-RunbookLog "Restored ASG membership: $asgName for $vmName" "SUCCESS"
                                        $restorationsMade++
                                    }
                                }
                                else {
                                    Write-RunbookLog "[DRY-RUN] Would restore ASG: $asgName for $vmName" "INFO"
                                    $restorationsMade++
                                }
                            }
                        }
                    }

                    # Restore static IP configurations
                    foreach ($staticIpConfig in $savedNicConfig.StaticIpConfigurations) {
                        $ipConfigName = $staticIpConfig.IpConfigurationName
                        $currentIpConfig = $currentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }

                        if ($currentIpConfig -and $staticIpConfig.StaticPrivateIpAddress) {
                            if ($currentIpConfig.PrivateIpAllocationMethod -ne "Static" -or
                                $currentIpConfig.PrivateIpAddress -ne $staticIpConfig.StaticPrivateIpAddress) {

                                if (-not $DryRun) {
                                    $currentIpConfig.PrivateIpAddress = $staticIpConfig.StaticPrivateIpAddress
                                    $currentIpConfig.PrivateIpAllocationMethod = "Static"
                                    Set-AzNetworkInterface -NetworkInterface $currentNic | Out-Null
                                    Write-RunbookLog "Restored static IP: $($staticIpConfig.StaticPrivateIpAddress) for $vmName" "SUCCESS"
                                    $restorationsMade++
                                }
                                else {
                                    Write-RunbookLog "[DRY-RUN] Would restore static IP: $($staticIpConfig.StaticPrivateIpAddress) for $vmName" "INFO"
                                    $restorationsMade++
                                }
                            }
                        }
                    }

                    # Restore Load Balancer backend pools
                    foreach ($lbPoolMembership in $savedNicConfig.LoadBalancerBackendPools) {
                        $ipConfigName = $lbPoolMembership.IpConfigurationName
                        $lbName = $lbPoolMembership.LoadBalancerName
                        $poolName = $lbPoolMembership.BackendPoolName

                        # Get target LB name for this region
                        $targetLbName = switch ($infraType) {
                            "terraform" { $lbName -replace "primary", "secondary" }
                            "bicep" {
                                $mapped = $lbName -replace "eastus", "westus2" -replace "westus2", "eastus"
                                if ($mapped -eq $lbName) { $lbName -replace "primary", "secondary" } else { $mapped }
                            }
                            default { $lbName -replace "primary", "secondary" }
                        }

                        $currentIpConfig = $currentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }
                        if ($currentIpConfig) {
                            $currentLbPool = $currentIpConfig.LoadBalancerBackendAddressPools | Where-Object { $_.Name -eq $poolName }
                            if (-not $currentLbPool) {
                                if (-not $DryRun) {
                                    # Try to find and add LB pool
                                    $lb = Get-AzLoadBalancer -ResourceGroupName $ResourceGroupName -Name $targetLbName -ErrorAction SilentlyContinue
                                    if ($lb) {
                                        $backendPool = $lb.BackendAddressPools | Where-Object { $_.Name -eq $poolName }
                                        if ($backendPool) {
                                            if (-not $currentIpConfig.LoadBalancerBackendAddressPools) {
                                                $currentIpConfig.LoadBalancerBackendAddressPools = @()
                                            }
                                            $currentIpConfig.LoadBalancerBackendAddressPools += $backendPool
                                            Set-AzNetworkInterface -NetworkInterface $currentNic | Out-Null
                                            Write-RunbookLog "Restored LB pool: $poolName in $targetLbName for $vmName" "SUCCESS"
                                            $restorationsMade++
                                        }
                                    }
                                }
                                else {
                                    Write-RunbookLog "[DRY-RUN] Would restore LB pool: $poolName in $targetLbName for $vmName" "INFO"
                                    $restorationsMade++
                                }
                            }
                        }
                    }
                }

                $totalRestorations += $restorationsMade
                if ($restorationsMade -gt 0) {
                    Write-RunbookLog "Applied $restorationsMade restorations for VM: $vmName" "SUCCESS"
                }
                else {
                    Write-RunbookLog "No restorations needed for VM: $vmName" "INFO"
                }
            }
            catch {
                Write-RunbookLog "Failed to process VM $vmName`: $($_.Exception.Message)" "ERROR"
            }
        }

        Write-RunbookLog "=== RESTORE SUMMARY ===" "INFO"
        Write-RunbookLog "Infrastructure type: $infraType" "INFO"
        Write-RunbookLog "Total restorations applied: $totalRestorations" "SUCCESS"
        if ($DryRun) {
            Write-RunbookLog "DRY-RUN MODE: No actual changes were made" "WARNING"
        }
    }
    catch {
        Write-RunbookLog "Restore operation failed: $($_.Exception.Message)" "ERROR"
        throw
    }
}

#endregion

#region Main Execution

function Main {
    try {
        Write-RunbookLog "=== Azure Site Recovery Networking Automation Runbook ===" "INFO"
        Write-RunbookLog "Compatible with Terraform and Bicep Infrastructure" "INFO"
        Write-RunbookLog "Operation: $Operation" "INFO"
        Write-RunbookLog "Resource Group: $ResourceGroupName" "INFO"
        Write-RunbookLog "Storage Account: $StorageAccountName" "INFO"
        Write-RunbookLog "Infrastructure Type: $InfrastructureType" "INFO"
        Write-RunbookLog "Started at: $(Get-Date)" "INFO"

        # Connect to Azure
        Connect-AzureWithManagedIdentity

        # Execute requested operation
        switch ($Operation) {
            "Backup" {
                Invoke-BackupOperation
            }
            "Restore" {
                Invoke-RestoreOperation
            }
            default {
                throw "Unknown operation: $Operation"
            }
        }

        Write-RunbookLog "Operation completed successfully at: $(Get-Date)" "SUCCESS"
    }
    catch {
        Write-RunbookLog "Runbook execution failed: $($_.Exception.Message)" "ERROR"
        Write-RunbookLog "Stack trace: $($_.ScriptStackTrace)" "ERROR"
        throw
    }
    finally {
        # Cleanup temporary files
        if (Test-Path $ConfigurationPath) {
            Remove-Item -Path $ConfigurationPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-RunbookLog "Cleaned up temporary files" "INFO"
        }
    }
}

# Execute main function
Main

#endregion