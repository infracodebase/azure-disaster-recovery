#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources

<#
.SYNOPSIS
Restores networking configuration of VMs after Site Recovery failover for both Terraform and Bicep deployments.

.DESCRIPTION
This script compares current networking configurations with saved pre-failover configurations and applies
any missing configurations. It works with infrastructure deployed via either Terraform or Bicep, automatically
detecting resource naming conventions and restoring Application Security Group memberships, static IP assignments,
Application Gateway backend pool memberships, and other network settings after Azure Site Recovery failover.

Supports cross-region resource mapping for both Terraform (primary/secondary) and Bicep (region-based) naming patterns.

.PARAMETER ConfigurationPath
Path where configuration files were saved during pre-failover backup

.PARAMETER MasterConfigFile
Path to the master configuration file (auto-detected if not specified)

.PARAMETER ResourceGroupName
Target resource group containing the failed-over VMs

.PARAMETER DryRun
If specified, only compares configurations without making changes

.PARAMETER Force
Skip confirmation prompts for applying changes

.PARAMETER VmNames
Array of specific VM names to restore (if empty, processes all VMs from saved configuration)

.PARAMETER InfrastructureType
Infrastructure deployment type: "terraform", "bicep", or "auto" for automatic detection (default: auto)

.PARAMETER StorageAccountName
Optional Azure Storage Account name where configurations were saved

.PARAMETER StorageResourceGroupName
Resource group containing the storage account

.PARAMETER SubscriptionId
Azure subscription ID

.PARAMETER Detailed
Enable detailed difference reporting and logging

.EXAMPLE
.\Restore-NetworkingConfig.ps1 -ConfigurationPath "C:\ASR\Configs" -ResourceGroupName "webapp-prod-secondary-rg"

.EXAMPLE
.\Restore-NetworkingConfig.ps1 -MasterConfigFile "C:\ASR\Configs\MASTER-networking-config-20241201-143022.json" -ResourceGroupName "webapp-prod-westus2-rg" -DryRun

.EXAMPLE
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-secondary-rg" -VmNames @("web-vm-1", "web-vm-2") -InfrastructureType "terraform" -Force

.EXAMPLE
.\Restore-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-eastus-rg" -StorageAccountName "asrnetworkconfigs" -InfrastructureType "bicep"

.NOTES
Author: Azure Infrastructure Team
Version: 1.0.0
Compatible with: Terraform and Bicep infrastructure deployments
Requires: Azure PowerShell modules (Az.Accounts, Az.Network, Az.Compute, Az.Resources)

This script automatically handles different naming conventions:
- Terraform: Uses hyphen-separated naming with primary/secondary patterns
- Bicep: Uses environment-region specific naming with region-based mapping

Works with both infrastructure types to provide consistent DR restoration.
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $false)]
[string]$ConfigurationPath = ".",

[Parameter(Mandatory = $false)]
[string]$MasterConfigFile,

[Parameter(Mandatory = $true)]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)]
[switch]$DryRun,

[Parameter(Mandatory = $false)]
[switch]$Force,

[Parameter(Mandatory = $false)]
[string[]]$VmNames = @(),

[Parameter(Mandatory = $false)]
[ValidateSet("terraform", "bicep", "auto")]
[string]$InfrastructureType = "auto",

[Parameter(Mandatory = $false)]
[string]$StorageAccountName,

[Parameter(Mandatory = $false)]
[string]$StorageResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$SubscriptionId,

[Parameter(Mandatory = $false)]
[switch]$Detailed
)

# Set strict mode for better error handling
Set-StrictMode -Version 3.0

# Global variables
$ErrorActionPreference = "Stop"
$RestoreTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $ConfigurationPath "networking-config-restore-$RestoreTimestamp.log"

#region Helper Functions

function Write-Log {
param(
[Parameter(Mandatory = $true)]
[string]$Message,

[Parameter(Mandatory = $false)]
[ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS", "ACTION")]
[string]$Level = "INFO"
)

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$logMessage = "[$timestamp] [$Level] $Message"

# Write to console with colors
switch ($Level) {
"INFO" { Write-Host $logMessage -ForegroundColor White }
"WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
"ERROR" { Write-Host $logMessage -ForegroundColor Red }
"SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
"ACTION" { Write-Host $logMessage -ForegroundColor Cyan }
}

# Write to log file
Add-Content -Path $LogFile -Value $logMessage
}

function Test-AzureConnection {
try {
$context = Get-AzContext
if (-not $context) {
throw "No Azure context found"
}

if ($SubscriptionId) {
Set-AzContext -SubscriptionId $SubscriptionId | Out-Null
}

Write-Log "Connected to Azure subscription: $((Get-AzContext).Subscription.Name)" "SUCCESS"
return $true
}
catch {
Write-Log "Azure connection failed: $($_.Exception.Message)" "ERROR"
return $false
}
}

function Get-CrossRegionMapping {
param(
[Parameter(Mandatory = $true)]
[string]$ResourceName,

[Parameter(Mandatory = $true)]
[string]$InfraType
)

switch ($InfraType) {
"terraform" {
# Terraform naming: web-lb-primary -> web-lb-secondary
$mappedName = $ResourceName -replace "-primary", "-secondary" -replace "primary", "secondary"
return $mappedName
}
"bicep" {
# Bicep naming: webapp-prod-eastus-web-lb -> webapp-prod-westus2-web-lb
$mappedName = $ResourceName -replace "eastus", "westus2" -replace "westus2", "eastus"
$mappedName = $mappedName -replace "eastus2", "westus2" -replace "westus", "eastus2"
$mappedName = $mappedName -replace "centralus", "eastus2" -replace "northcentralus", "southcentralus"
$mappedName = $mappedName -replace "westeurope", "northeurope" -replace "northeurope", "westeurope"

# Fallback to primary/secondary if no region found
if ($mappedName -eq $ResourceName) {
$mappedName = $ResourceName -replace "primary", "secondary"
}

return $mappedName
}
default {
return $ResourceName -replace "primary", "secondary"
}
}
}

function Download-ConfigurationFromStorage {
param(
[Parameter(Mandatory = $true)]
[string]$StorageAccountName,

[Parameter(Mandatory = $true)]
[string]$StorageResourceGroupName,

[Parameter(Mandatory = $true)]
[string]$ConfigurationPath
)

try {
$storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
Write-Log "Storage account $StorageAccountName not found" "WARNING"
return $false
}

$ctx = $storageAccount.Context
$containerName = "networking-configs"

# Get all configuration blobs
$blobs = Get-AzStorageBlob -Container $containerName -Context $ctx -ErrorAction SilentlyContinue
if (-not $blobs) {
Write-Log "No configuration files found in storage container $containerName" "WARNING"
return $false
}

$downloadCount = 0
foreach ($blob in $blobs) {
if ($blob.Name -like "*.json") {
$destinationPath = Join-Path $ConfigurationPath $blob.Name
Get-AzStorageBlobContent -Container $containerName -Blob $blob.Name -Destination $destinationPath -Context $ctx -Force | Out-Null
Write-Log "Downloaded configuration: $($blob.Name)" "INFO"
$downloadCount++
}
}

Write-Log "Downloaded $downloadCount configuration files from storage" "SUCCESS"
return $true
}
catch {
Write-Log "Failed to download from storage: $($_.Exception.Message)" "WARNING"
return $false
}
}

function Find-MasterConfigFile {
param(
[Parameter(Mandatory = $true)]
[string]$SearchPath
)

if ($MasterConfigFile -and (Test-Path $MasterConfigFile)) {
return $MasterConfigFile
}

$masterFiles = Get-ChildItem -Path $SearchPath -Filter "MASTER-networking-config-*.json" | Sort-Object LastWriteTime -Descending

if ($masterFiles.Count -eq 0) {
throw "No master configuration file found in $SearchPath"
}

$latestFile = $masterFiles[0].FullName
Write-Log "Using latest master config file: $latestFile" "INFO"
return $latestFile
}

function Get-SavedConfigurations {
param(
[Parameter(Mandatory = $true)]
[string]$MasterConfigPath
)

try {
$masterConfig = Get-Content -Path $MasterConfigPath -Raw | ConvertFrom-Json
$savedConfigs = @{}

Write-Log "Master config timestamp: $($masterConfig.Timestamp)" "INFO"
Write-Log "Infrastructure type: $($masterConfig.InfrastructureType)" "INFO"
Write-Log "Primary RG: $($masterConfig.PrimaryResourceGroup)" "INFO"
Write-Log "Secondary RG: $($masterConfig.SecondaryResourceGroup)" "INFO"

foreach ($configFile in $masterConfig.ConfigurationFiles) {
$configPath = Join-Path (Split-Path $MasterConfigPath -Parent) $configFile
if (Test-Path $configPath) {
$config = Get-Content -Path $configPath -Raw | ConvertFrom-Json
$savedConfigs[$config.VmName] = $config
}
else {
Write-Log "Configuration file not found: $configFile" "WARNING"
}
}

return @{
Configurations = $savedConfigs
InfrastructureType = $masterConfig.InfrastructureType
MasterConfig = $masterConfig
}
}
catch {
Write-Log "Failed to load saved configurations: $($_.Exception.Message)" "ERROR"
throw
}
}

function Compare-ApplicationSecurityGroups {
param(
[Parameter(Mandatory = $true)]
[object]$SavedConfig,

[Parameter(Mandatory = $true)]
[object]$CurrentNic,

[Parameter(Mandatory = $true)]
[string]$VmName,

[Parameter(Mandatory = $true)]
[string]$InfraType
)

$differences = @()

foreach ($nicConfig in $SavedConfig.NetworkInterfaces) {
if ($nicConfig.Name -ne $CurrentNic.Name) { continue }

foreach ($asgMembership in $nicConfig.ApplicationSecurityGroups) {
$ipConfigName = $asgMembership.IpConfigurationName
$asgName = $asgMembership.AsgName

# Check if this ASG membership exists in current configuration
$currentIpConfig = $CurrentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }
if ($currentIpConfig) {
$currentAsg = $currentIpConfig.ApplicationSecurityGroups | Where-Object { $_.Name -eq $asgName }
if (-not $currentAsg) {
$differences += @{
Type = "ApplicationSecurityGroup"
Action = "Add"
VmName = $VmName
NicName = $CurrentNic.Name
IpConfigName = $ipConfigName
AsgName = $asgName
AsgResourceGroup = $asgMembership.AsgResourceGroup
InfrastructureType = $InfraType
Details = "Missing ASG membership: $asgName"
}
}
}
}
}

return $differences
}

function Compare-LoadBalancerBackendPools {
param(
[Parameter(Mandatory = $true)]
[object]$SavedConfig,

[Parameter(Mandatory = $true)]
[object]$CurrentNic,

[Parameter(Mandatory = $true)]
[string]$VmName,

[Parameter(Mandatory = $true)]
[string]$InfraType
)

$differences = @()

foreach ($nicConfig in $SavedConfig.NetworkInterfaces) {
if ($nicConfig.Name -ne $CurrentNic.Name) { continue }

foreach ($lbPoolMembership in $nicConfig.LoadBalancerBackendPools) {
$ipConfigName = $lbPoolMembership.IpConfigurationName
$lbName = $lbPoolMembership.LoadBalancerName
$poolName = $lbPoolMembership.BackendPoolName

# Get the target load balancer name for this region
$targetLbName = if ($lbPoolMembership.SecondaryLoadBalancerName) {
$lbPoolMembership.SecondaryLoadBalancerName
}
else {
Get-CrossRegionMapping -ResourceName $lbName -InfraType $InfraType
}

# Check if this LB backend pool membership exists in current configuration
$currentIpConfig = $CurrentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }
if ($currentIpConfig) {
$currentLbPool = $currentIpConfig.LoadBalancerBackendAddressPools | Where-Object { $_.Name -eq $poolName }
if (-not $currentLbPool) {
$differences += @{
Type = "LoadBalancerBackendPool"
Action = "Add"
VmName = $VmName
NicName = $CurrentNic.Name
IpConfigName = $ipConfigName
LoadBalancerName = $targetLbName
LoadBalancerResourceGroup = $ResourceGroupName
BackendPoolName = $poolName
InfrastructureType = $InfraType
Details = "Missing LB backend pool membership: $poolName in $targetLbName"
}
}
}
}
}

return $differences
}

function Compare-StaticIpConfigurations {
param(
[Parameter(Mandatory = $true)]
[object]$SavedConfig,

[Parameter(Mandatory = $true)]
[object]$CurrentNic,

[Parameter(Mandatory = $true)]
[string]$VmName
)

$differences = @()

foreach ($nicConfig in $SavedConfig.NetworkInterfaces) {
if ($nicConfig.Name -ne $CurrentNic.Name) { continue }

foreach ($staticIpConfig in $nicConfig.StaticIpConfigurations) {
$ipConfigName = $staticIpConfig.IpConfigurationName

# Check current IP configuration
$currentIpConfig = $CurrentNic.IpConfigurations | Where-Object { $_.Name -eq $ipConfigName }
if ($currentIpConfig) {
# Check private IP static configuration
if ($staticIpConfig.StaticPrivateIpAddress -and
($currentIpConfig.PrivateIpAllocationMethod -ne "Static" -or
$currentIpConfig.PrivateIpAddress -ne $staticIpConfig.StaticPrivateIpAddress)) {

$differences += @{
Type = "StaticPrivateIp"
Action = "Set"
VmName = $VmName
NicName = $CurrentNic.Name
IpConfigName = $ipConfigName
RequiredIpAddress = $staticIpConfig.StaticPrivateIpAddress
CurrentIpAddress = $currentIpConfig.PrivateIpAddress
CurrentAllocationMethod = $currentIpConfig.PrivateIpAllocationMethod
Details = "Static private IP mismatch: required=$($staticIpConfig.StaticPrivateIpAddress), current=$($currentIpConfig.PrivateIpAddress)"
}
}

# Check public IP static configuration
if ($staticIpConfig.StaticPublicIpAddress -and $currentIpConfig.PublicIpAddress) {
$currentPublicIp = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $currentIpConfig.PublicIpAddress.Name -ErrorAction SilentlyContinue
if ($currentPublicIp -and
($currentPublicIp.PublicIpAllocationMethod -ne "Static" -or
$currentPublicIp.IpAddress -ne $staticIpConfig.StaticPublicIpAddress)) {

$differences += @{
Type = "StaticPublicIp"
Action = "Set"
VmName = $VmName
NicName = $CurrentNic.Name
IpConfigName = $ipConfigName
PublicIpName = $currentPublicIp.Name
RequiredIpAddress = $staticIpConfig.StaticPublicIpAddress
CurrentIpAddress = $currentPublicIp.IpAddress
Details = "Static public IP mismatch: required=$($staticIpConfig.StaticPublicIpAddress), current=$($currentPublicIp.IpAddress)"
}
}
}
}
}
}

return $differences
}

#endregion

#region Restoration Functions

function Restore-ApplicationSecurityGroupMembership {
param(
[Parameter(Mandatory = $true)]
[object]$Difference
)

try {
Write-Log " Restoring ASG membership: $($Difference.AsgName) for $($Difference.NicName)/$($Difference.IpConfigName)" "ACTION"

if ($DryRun) {
Write-Log " [DRY-RUN] Would add ASG membership" "INFO"
return $true
}

# Get the network interface
$nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $Difference.NicName

# Find the IP configuration
$ipConfig = $nic.IpConfigurations | Where-Object { $_.Name -eq $Difference.IpConfigName }
if (-not $ipConfig) {
Write-Log " IP configuration $($Difference.IpConfigName) not found" "ERROR"
return $false
}

# Get the ASG - try current resource group first, then original resource group
$asg = Get-AzApplicationSecurityGroup -ResourceGroupName $ResourceGroupName -Name $Difference.AsgName -ErrorAction SilentlyContinue
if (-not $asg) {
$asg = Get-AzApplicationSecurityGroup -ResourceGroupName $Difference.AsgResourceGroup -Name $Difference.AsgName -ErrorAction SilentlyContinue
}

if (-not $asg) {
Write-Log " Application Security Group $($Difference.AsgName) not found" "WARNING"
return $false
}

# Add ASG to IP configuration
if (-not $ipConfig.ApplicationSecurityGroups) {
$ipConfig.ApplicationSecurityGroups = @()
}

$ipConfig.ApplicationSecurityGroups += $asg

# Update the network interface
Set-AzNetworkInterface -NetworkInterface $nic | Out-Null
Write-Log " Successfully added ASG membership" "SUCCESS"
return $true
}
catch {
Write-Log " Failed to restore ASG membership: $($_.Exception.Message)" "ERROR"
return $false
}
}

function Restore-LoadBalancerBackendPoolMembership {
param(
[Parameter(Mandatory = $true)]
[object]$Difference
)

try {
Write-Log " Restoring LB pool membership: $($Difference.BackendPoolName) for $($Difference.NicName)/$($Difference.IpConfigName)" "ACTION"

if ($DryRun) {
Write-Log " [DRY-RUN] Would add LB backend pool membership" "INFO"
return $true
}

# Get the load balancer
$lb = Get-AzLoadBalancer -ResourceGroupName $Difference.LoadBalancerResourceGroup -Name $Difference.LoadBalancerName -ErrorAction SilentlyContinue
if (-not $lb) {
Write-Log " Load balancer $($Difference.LoadBalancerName) not found" "WARNING"
return $false
}

# Get the backend pool
$backendPool = $lb.BackendAddressPools | Where-Object { $_.Name -eq $Difference.BackendPoolName }
if (-not $backendPool) {
Write-Log " Backend pool $($Difference.BackendPoolName) not found" "WARNING"
return $false
}

# Get the network interface
$nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $Difference.NicName

# Find the IP configuration
$ipConfig = $nic.IpConfigurations | Where-Object { $_.Name -eq $Difference.IpConfigName }
if (-not $ipConfig) {
Write-Log " IP configuration $($Difference.IpConfigName) not found" "ERROR"
return $false
}

# Add backend pool to IP configuration
if (-not $ipConfig.LoadBalancerBackendAddressPools) {
$ipConfig.LoadBalancerBackendAddressPools = @()
}

$ipConfig.LoadBalancerBackendAddressPools += $backendPool

# Update the network interface
Set-AzNetworkInterface -NetworkInterface $nic | Out-Null
Write-Log " Successfully added LB backend pool membership" "SUCCESS"
return $true
}
catch {
Write-Log " Failed to restore LB backend pool membership: $($_.Exception.Message)" "ERROR"
return $false
}
}

function Restore-StaticIpConfiguration {
param(
[Parameter(Mandatory = $true)]
[object]$Difference
)

try {
Write-Log " Restoring static IP: $($Difference.RequiredIpAddress) for $($Difference.NicName)/$($Difference.IpConfigName)" "ACTION"

if ($DryRun) {
Write-Log " [DRY-RUN] Would set static IP configuration" "INFO"
return $true
}

if ($Difference.Type -eq "StaticPrivateIp") {
# Get the network interface
$nic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $Difference.NicName

# Find the IP configuration
$ipConfig = $nic.IpConfigurations | Where-Object { $_.Name -eq $Difference.IpConfigName }
if (-not $ipConfig) {
Write-Log " IP configuration $($Difference.IpConfigName) not found" "ERROR"
return $false
}

# Set static private IP
$ipConfig.PrivateIpAddress = $Difference.RequiredIpAddress
$ipConfig.PrivateIpAllocationMethod = "Static"

# Update the network interface
Set-AzNetworkInterface -NetworkInterface $nic | Out-Null
Write-Log " Successfully set static private IP" "SUCCESS"
return $true
}
elseif ($Difference.Type -eq "StaticPublicIp") {
# Get the public IP address
$publicIp = Get-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Name $Difference.PublicIpName

# Set static allocation method
$publicIp.PublicIpAllocationMethod = "Static"
if ($Difference.RequiredIpAddress) {
$publicIp.IpAddress = $Difference.RequiredIpAddress
}

# Update the public IP
Set-AzPublicIpAddress -PublicIpAddress $publicIp | Out-Null
Write-Log " Successfully set static public IP" "SUCCESS"
return $true
}
}
catch {
Write-Log " Failed to restore static IP: $($_.Exception.Message)" "ERROR"
return $false
}
}

function Restore-NetworkingConfiguration {
param(
[Parameter(Mandatory = $true)]
[string]$VmName,

[Parameter(Mandatory = $true)]
[object]$SavedConfig,

[Parameter(Mandatory = $true)]
[hashtable]$AllDifferences,

[Parameter(Mandatory = $true)]
[string]$InfraType
)

Write-Log "Restoring configuration for VM: $VmName (Infrastructure: $InfraType)" "INFO"

$vmDifferences = $AllDifferences[$VmName]
if (-not $vmDifferences -or $vmDifferences.Count -eq 0) {
Write-Log " No differences found for $VmName" "INFO"
return @{ Success = $true; Applied = 0; Failed = 0 }
}

$appliedCount = 0
$failedCount = 0

foreach ($diff in $vmDifferences) {
$success = $false

switch ($diff.Type) {
"ApplicationSecurityGroup" {
$success = Restore-ApplicationSecurityGroupMembership -Difference $diff
}
"StaticPrivateIp" {
$success = Restore-StaticIpConfiguration -Difference $diff
}
"StaticPublicIp" {
$success = Restore-StaticIpConfiguration -Difference $diff
}
"LoadBalancerBackendPool" {
$success = Restore-LoadBalancerBackendPoolMembership -Difference $diff
}
default {
Write-Log " Unknown difference type: $($diff.Type)" "WARNING"
}
}

if ($success) {
$appliedCount++
}
else {
$failedCount++
}
}

return @{
Success = ($failedCount -eq 0)
Applied = $appliedCount
Failed = $failedCount
}
}

#endregion

#region Main Execution

function Main {
Write-Log "=== Azure Site Recovery Networking Configuration Restoration ===" "INFO"
Write-Log "Compatible with Terraform and Bicep Infrastructure" "INFO"
Write-Log "Started at: $(Get-Date)" "INFO"

if ($DryRun) {
Write-Log "DRY-RUN MODE: No changes will be applied" "WARNING"
}

# Test Azure connection
if (-not (Test-AzureConnection)) {
Write-Log "Azure connection test failed. Exiting." "ERROR"
exit 1
}

try {
# Download configurations from storage if specified
if ($StorageAccountName) {
Download-ConfigurationFromStorage -StorageAccountName $StorageAccountName -StorageResourceGroupName $StorageResourceGroupName -ConfigurationPath $ConfigurationPath
}

# Find and load master configuration
$masterConfigPath = Find-MasterConfigFile -SearchPath $ConfigurationPath
$configData = Get-SavedConfigurations -MasterConfigPath $masterConfigPath

$savedConfigurations = $configData.Configurations
$infraType = $configData.InfrastructureType

# Override infrastructure type if manually specified
if ($InfrastructureType -ne "auto") {
$infraType = $InfrastructureType
Write-Log "Infrastructure type manually overridden to: $infraType" "INFO"
}

Write-Log "Loaded configurations for $($savedConfigurations.Keys.Count) VMs" "INFO"
Write-Log "Infrastructure type: $infraType" "INFO"

# Filter VMs if specific names provided
if ($VmNames.Count -gt 0) {
$filteredConfigs = @{}
foreach ($vmName in $VmNames) {
if ($savedConfigurations.ContainsKey($vmName)) {
$filteredConfigs[$vmName] = $savedConfigurations[$vmName]
}
else {
Write-Log "No saved configuration found for VM: $vmName" "WARNING"
}
}
$savedConfigurations = $filteredConfigs
}

if ($savedConfigurations.Keys.Count -eq 0) {
Write-Log "No VM configurations to process. Exiting." "WARNING"
exit 0
}

# Compare current state with saved configurations
Write-Log "Comparing current configurations with saved state..." "INFO"
$allDifferences = @{}
$totalDifferences = 0

foreach ($vmName in $savedConfigurations.Keys) {
try {
Write-Log "Analyzing VM: $vmName" "INFO"
$savedConfig = $savedConfigurations[$vmName]

# Get current VM and its NICs
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
Write-Log " VM $vmName not found in resource group $ResourceGroupName" "WARNING"
continue
}

$vmDifferences = @()

# Get current NICs for the VM
foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
$nicName = $nicRef.Id.Split('/')[-1]
$currentNic = Get-AzNetworkInterface -ResourceGroupName $ResourceGroupName -Name $nicName -ErrorAction SilentlyContinue

if ($currentNic) {
# Compare configurations
$vmDifferences += Compare-ApplicationSecurityGroups -SavedConfig $savedConfig -CurrentNic $currentNic -VmName $vmName -InfraType $infraType
$vmDifferences += Compare-StaticIpConfigurations -SavedConfig $savedConfig -CurrentNic $currentNic -VmName $vmName
$vmDifferences += Compare-LoadBalancerBackendPools -SavedConfig $savedConfig -CurrentNic $currentNic -VmName $vmName -InfraType $infraType
}
}

if ($vmDifferences.Count -gt 0) {
$allDifferences[$vmName] = $vmDifferences
$totalDifferences += $vmDifferences.Count
Write-Log " Found $($vmDifferences.Count) differences for $vmName" "WARNING"

if ($Detailed) {
foreach ($diff in $vmDifferences) {
Write-Log " $($diff.Type): $($diff.Details)" "INFO"
}
}
}
else {
Write-Log " No differences found for $vmName" "SUCCESS"
}
}
catch {
Write-Log "Failed to analyze VM $vmName`: $($_.Exception.Message)" "ERROR"
}
}

# Summary of differences
Write-Log "=== ANALYSIS SUMMARY ===" "INFO"
Write-Log "Infrastructure type: $infraType" "INFO"
Write-Log "Total differences found: $totalDifferences across $($allDifferences.Keys.Count) VMs" "INFO"

if ($totalDifferences -eq 0) {
Write-Log "No configuration differences found. All VMs are correctly configured." "SUCCESS"
exit 0
}

# Show what will be changed
if ($DryRun) {
Write-Log "=== DRY-RUN RESULTS ===" "INFO"
foreach ($vmName in $allDifferences.Keys) {
Write-Log "VM: $vmName" "INFO"
foreach ($diff in $allDifferences[$vmName]) {
Write-Log " Would restore: $($diff.Details)" "ACTION"
}
}
exit 0
}

# Confirm changes unless -Force is specified
if (-not $Force) {
Write-Log "The following changes will be applied:" "WARNING"
foreach ($vmName in $allDifferences.Keys) {
Write-Log " $vmName`: $($allDifferences[$vmName].Count) changes" "INFO"
}

$confirmation = Read-Host "Do you want to proceed with applying these changes? (Y/N)"
if ($confirmation -notmatch '^[Yy]') {
Write-Log "Operation cancelled by user." "INFO"
exit 0
}
}

# Apply configurations
Write-Log "=== APPLYING CONFIGURATIONS ===" "INFO"
$totalApplied = 0
$totalFailed = 0
$vmResults = @{}

foreach ($vmName in $allDifferences.Keys) {
$result = Restore-NetworkingConfiguration -VmName $vmName -SavedConfig $savedConfigurations[$vmName] -AllDifferences $allDifferences -InfraType $infraType
$vmResults[$vmName] = $result
$totalApplied += $result.Applied
$totalFailed += $result.Failed

if ($result.Success) {
Write-Log " $vmName`: Successfully applied $($result.Applied) changes" "SUCCESS"
}
else {
Write-Log " $vmName`: Applied $($result.Applied) changes, $($result.Failed) failed" "WARNING"
}
}

# Final summary
Write-Log "=== RESTORATION SUMMARY ===" "INFO"
Write-Log "Infrastructure type: $infraType" "INFO"
Write-Log "Total changes applied: $totalApplied" "SUCCESS"
Write-Log "Total changes failed: $totalFailed" "ERROR"
Write-Log "VMs processed: $($vmResults.Keys.Count)" "INFO"
Write-Log "Log file: $LogFile" "INFO"
Write-Log "Restoration completed at: $(Get-Date)" "SUCCESS"

if ($totalFailed -gt 0) {
Write-Log "Some configurations failed to apply. Check the log for details." "WARNING"
exit 1
}
else {
Write-Log "All configurations applied successfully!" "SUCCESS"
exit 0
}
}
catch {
Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
exit 1
}
}

# Execute main function
Main

#endregion