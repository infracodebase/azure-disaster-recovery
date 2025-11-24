#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources

<#
.SYNOPSIS
Saves networking configuration of VMs before Site Recovery failover for both Terraform and Bicep deployments.

.DESCRIPTION
This script captures and saves complete networking configurations for VMs before Azure Site Recovery failover.
It works with infrastructure deployed via either Terraform or Bicep, automatically detecting resource naming
conventions and saving Application Security Group memberships, Network Interface configurations, static IP assignments,
and Application Gateway/Load Balancer backend pool memberships to enable post-failover restoration.

.PARAMETER ResourceGroupName
Primary resource group containing the source VMs and networking resources

.PARAMETER SecondaryResourceGroupName
Secondary (DR) resource group where configurations will be restored

.PARAMETER ConfigurationPath
Path where configuration files will be saved (default: current directory)

.PARAMETER VmNames
Array of VM names to save configurations for (if empty, processes all VMs in resource group)

.PARAMETER ProjectName
Project name used in resource naming convention (works with both TF and Bicep naming patterns)

.PARAMETER Environment
Environment name (prod, staging, dev)

.PARAMETER InfrastructureType
Infrastructure deployment type: "terraform", "bicep", or "auto" for automatic detection (default: auto)

.PARAMETER StorageAccountName
Optional Azure Storage Account name for configuration persistence

.PARAMETER StorageResourceGroupName
Resource group containing the storage account

.PARAMETER SubscriptionId
Azure subscription ID

.PARAMETER IncludeAppGateway
Include Application Gateway backend pool configurations

.PARAMETER IncludeLoadBalancer
Include Load Balancer backend pool configurations

.PARAMETER Detailed
Enable detailed logging output

.EXAMPLE
.\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg" -ProjectName "webapp" -Environment "prod"

.EXAMPLE
.\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-eastus-rg" -SecondaryResourceGroupName "webapp-prod-westus2-rg" -InfrastructureType "terraform"

.EXAMPLE
.\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg" -InfrastructureType "bicep" -StorageAccountName "asrnetworkconfigs" -IncludeAppGateway -IncludeLoadBalancer

.NOTES
Author: Azure Infrastructure Team
Version: 1.0.0
Compatible with: Terraform and Bicep infrastructure deployments
Requires: Azure PowerShell modules (Az.Accounts, Az.Network, Az.Compute, Az.Resources)

This script automatically detects Terraform vs Bicep naming conventions:
- Terraform: Uses hyphen-separated naming (web-vm-1, app-lb-primary)
- Bicep: Uses environment-specific naming (webapp-prod-eastus-web-vm-1)

Works with both infrastructure types to provide consistent DR automation.
#>

[CmdletBinding()]
param(
[Parameter(Mandatory = $true)]
[string]$ResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$SecondaryResourceGroupName,

[Parameter(Mandatory = $false)]
[string]$ConfigurationPath = ".",

[Parameter(Mandatory = $false)]
[string[]]$VmNames = @(),

[Parameter(Mandatory = $false)]
[string]$ProjectName,

[Parameter(Mandatory = $false)]
[string]$Environment,

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
[switch]$IncludeAppGateway,

[Parameter(Mandatory = $false)]
[switch]$IncludeLoadBalancer,

[Parameter(Mandatory = $false)]
[switch]$Detailed
)

# Set strict mode for better error handling
Set-StrictMode -Version 3.0

# Global variables
$ErrorActionPreference = "Stop"
$ConfigTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$LogFile = Join-Path $ConfigurationPath "networking-config-backup-$ConfigTimestamp.log"

#region Helper Functions

function Write-Log {
param(
[Parameter(Mandatory = $true)]
[string]$Message,

[Parameter(Mandatory = $false)]
[ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
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

function Detect-InfrastructureType {
param(
[Parameter(Mandatory = $true)]
[string]$ResourceGroupName
)

if ($InfrastructureType -ne "auto") {
Write-Log "Infrastructure type manually set to: $InfrastructureType" "INFO"
return $InfrastructureType
}

try {
# Get a sample of resources to analyze naming patterns
$resources = Get-AzResource -ResourceGroupName $ResourceGroupName | Select-Object -First 10

$terraformIndicators = 0
$bicepIndicators = 0

foreach ($resource in $resources) {
$name = $resource.Name.ToLower()

# Terraform naming patterns (hyphen-separated, shorter names)
if ($name -match '^[a-z]+-[a-z]+-[0-9]+$' -or
$name -match '^[a-z]+-lb$' -or
$name -match '^[a-z]+-nsg$' -or
$name -match '^[a-z]+-subnet$') {
$terraformIndicators++
}

# Bicep naming patterns (project-environment-region-resource format)
if ($name -match '^[a-z]+-[a-z]+-[a-z0-9]+-[a-z]+-[a-z0-9-]+$' -or
$name -match 'eastus|westus|centralus|northeurope|westeurope' -or
$name -match '^[a-z]+-prod-|^[a-z]+-staging-|^[a-z]+-dev-') {
$bicepIndicators++
}
}

$detectedType = if ($bicepIndicators > $terraformIndicators) { "bicep" } else { "terraform" }
Write-Log "Auto-detected infrastructure type: $detectedType (TF indicators: $terraformIndicators, Bicep indicators: $bicepIndicators)" "INFO"

return $detectedType
}
catch {
Write-Log "Could not auto-detect infrastructure type, defaulting to terraform: $($_.Exception.Message)" "WARNING"
return "terraform"
}
}

function Get-CrossRegionMapping {
param(
[Parameter(Mandatory = $true)]
[string]$ResourceName,

[Parameter(Mandatory = $true)]
[string]$DetectedInfraType
)

switch ($DetectedInfraType) {
"terraform" {
# Terraform naming: web-lb, app-gateway, web-vm-1
# Simple pattern replacement for primary/secondary
$mappedName = $ResourceName -replace "-primary-", "-secondary-"
if ($mappedName -eq $ResourceName) {
# If no explicit primary/secondary, add secondary suffix to base name
$mappedName = $ResourceName -replace "^([a-z-]+)$", "`$1-secondary"
}
return $mappedName
}
"bicep" {
# Bicep naming: webapp-prod-eastus-web-lb, webapp-prod-eastus-app-gateway
# Region-based replacement
$mappedName = $ResourceName -replace "eastus", "westus2" -replace "westus2", "eastus"
$mappedName = $mappedName -replace "eastus2", "westus2" -replace "westus", "eastus2"
$mappedName = $mappedName -replace "centralus", "eastus2" -replace "northcentralus", "southcentralus"
$mappedName = $mappedName -replace "westeurope", "northeurope" -replace "northeurope", "westeurope"

# If no region detected, use primary/secondary pattern
if ($mappedName -eq $ResourceName) {
$mappedName = $ResourceName -replace "-primary-", "-secondary-" -replace "primary", "secondary"
}

return $mappedName
}
default {
return $ResourceName -replace "-primary", "-secondary"
}
}
}

function Get-VmNetworkInterfaces {
param(
[Parameter(Mandatory = $true)]
[string]$VmName,

[Parameter(Mandatory = $true)]
[string]$ResourceGroup
)

try {
$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -ErrorAction Stop
$nics = @()

foreach ($nicRef in $vm.NetworkProfile.NetworkInterfaces) {
$nicResourceId = $nicRef.Id
$nicName = $nicResourceId.Split('/')[-1]
$nicResourceGroup = $nicResourceId.Split('/')[4]

$nic = Get-AzNetworkInterface -ResourceGroupName $nicResourceGroup -Name $nicName -ErrorAction Stop
$nics += $nic
}

return $nics
}
catch {
Write-Log "Failed to get network interfaces for VM $VmName`: $($_.Exception.Message)" "ERROR"
return @()
}
}

function Get-ApplicationSecurityGroups {
param(
[Parameter(Mandatory = $true)]
[Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]$NetworkInterface
)

$asgMemberships = @()

foreach ($ipConfig in $NetworkInterface.IpConfigurations) {
if ($ipConfig.ApplicationSecurityGroups) {
foreach ($asg in $ipConfig.ApplicationSecurityGroups) {
$asgMemberships += @{
IpConfigurationName = $ipConfig.Name
AsgName = $asg.Name
AsgResourceGroup = $asg.ResourceGroupName
AsgId = $asg.Id
}
}
}
}

return $asgMemberships
}

function Get-StaticIpConfigurations {
param(
[Parameter(Mandatory = $true)]
[Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]$NetworkInterface
)

$staticIpConfigs = @()

foreach ($ipConfig in $NetworkInterface.IpConfigurations) {
if ($ipConfig.PrivateIpAllocationMethod -eq "Static") {
$staticIpConfigs += @{
IpConfigurationName = $ipConfig.Name
StaticPrivateIpAddress = $ipConfig.PrivateIpAddress
SubnetId = $ipConfig.Subnet.Id
IsPrimary = $ipConfig.Primary
}
}

# Check for public IP
if ($ipConfig.PublicIpAddress) {
$publicIp = Get-AzPublicIpAddress -ResourceGroupName $NetworkInterface.ResourceGroupName -Name $ipConfig.PublicIpAddress.Name -ErrorAction SilentlyContinue
if ($publicIp -and $publicIp.PublicIpAllocationMethod -eq "Static") {
$staticIpConfigs += @{
IpConfigurationName = $ipConfig.Name
StaticPublicIpAddress = $publicIp.IpAddress
PublicIpName = $publicIp.Name
PublicIpResourceGroup = $publicIp.ResourceGroupName
PublicIpId = $publicIp.Id
}
}
}
}

return $staticIpConfigs
}

function Get-ApplicationGatewayBackendPools {
param(
[Parameter(Mandatory = $true)]
[Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]$NetworkInterface
)

$backendPoolMemberships = @()

foreach ($ipConfig in $NetworkInterface.IpConfigurations) {
if ($ipConfig.ApplicationGatewayBackendAddressPools) {
foreach ($backendPool in $ipConfig.ApplicationGatewayBackendAddressPools) {
# Extract Application Gateway information from backend pool ID
$appGwResourceId = $backendPool.Id -replace '/backendAddressPools/.*', ''
$appGwName = $appGwResourceId.Split('/')[-1]
$appGwResourceGroup = $appGwResourceId.Split('/')[4]

$backendPoolMemberships += @{
IpConfigurationName = $ipConfig.Name
ApplicationGatewayName = $appGwName
ApplicationGatewayResourceGroup = $appGwResourceGroup
BackendPoolName = $backendPool.Name
BackendPoolId = $backendPool.Id
}
}
}
}

return $backendPoolMemberships
}

function Get-LoadBalancerBackendPools {
param(
[Parameter(Mandatory = $true)]
[Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]$NetworkInterface
)

$lbBackendPoolMemberships = @()

foreach ($ipConfig in $NetworkInterface.IpConfigurations) {
if ($ipConfig.LoadBalancerBackendAddressPools) {
foreach ($backendPool in $ipConfig.LoadBalancerBackendAddressPools) {
# Extract Load Balancer information from backend pool ID
$lbResourceId = $backendPool.Id -replace '/backendAddressPools/.*', ''
$lbName = $lbResourceId.Split('/')[-1]
$lbResourceGroup = $lbResourceId.Split('/')[4]

$lbBackendPoolMemberships += @{
IpConfigurationName = $ipConfig.Name
LoadBalancerName = $lbName
LoadBalancerResourceGroup = $lbResourceGroup
BackendPoolName = $backendPool.Name
BackendPoolId = $backendPool.Id
}
}
}
}

return $lbBackendPoolMemberships
}

function Upload-ConfigurationToStorage {
param(
[Parameter(Mandatory = $true)]
[string]$FilePath,

[Parameter(Mandatory = $true)]
[string]$StorageAccountName,

[Parameter(Mandatory = $true)]
[string]$StorageResourceGroupName
)

try {
if (-not $StorageAccountName) {
return $false
}

$storageAccount = Get-AzStorageAccount -ResourceGroupName $StorageResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (-not $storageAccount) {
Write-Log "Storage account $StorageAccountName not found" "WARNING"
return $false
}

$ctx = $storageAccount.Context
$containerName = "networking-configs"

# Create container if it doesn't exist
$container = Get-AzStorageContainer -Name $containerName -Context $ctx -ErrorAction SilentlyContinue
if (-not $container) {
New-AzStorageContainer -Name $containerName -Context $ctx -Permission Off | Out-Null
Write-Log "Created storage container: $containerName" "INFO"
}

$blobName = Split-Path $FilePath -Leaf
Set-AzStorageBlobContent -File $FilePath -Container $containerName -Blob $blobName -Context $ctx -Force | Out-Null

Write-Log "Uploaded configuration to storage: $blobName" "SUCCESS"
return $true
}
catch {
Write-Log "Failed to upload to storage: $($_.Exception.Message)" "WARNING"
return $false
}
}

#endregion

#region Main Functions

function Save-VmNetworkingConfiguration {
param(
[Parameter(Mandatory = $true)]
[string]$VmName,

[Parameter(Mandatory = $true)]
[string]$ResourceGroup,

[Parameter(Mandatory = $true)]
[string]$DetectedInfraType
)

Write-Log "Processing VM: $VmName" "INFO"

try {
# Get VM information
$vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $VmName -ErrorAction Stop
$networkInterfaces = Get-VmNetworkInterfaces -VmName $VmName -ResourceGroup $ResourceGroup

if ($networkInterfaces.Count -eq 0) {
Write-Log "No network interfaces found for VM $VmName" "WARNING"
return
}

$vmConfig = @{
VmName = $VmName
VmId = $vm.Id
VmResourceGroup = $ResourceGroup
VmLocation = $vm.Location
VmSize = $vm.HardwareProfile.VmSize
Timestamp = $ConfigTimestamp
InfrastructureType = $DetectedInfraType
ProjectName = $ProjectName
Environment = $Environment
NetworkInterfaces = @()
}

foreach ($nic in $networkInterfaces) {
Write-Log " Processing NIC: $($nic.Name)" "INFO"

$nicConfig = @{
Name = $nic.Name
ResourceGroup = $nic.ResourceGroupName
Location = $nic.Location
Id = $nic.Id
ApplicationSecurityGroups = Get-ApplicationSecurityGroups -NetworkInterface $nic
StaticIpConfigurations = Get-StaticIpConfigurations -NetworkInterface $nic
LoadBalancerBackendPools = Get-LoadBalancerBackendPools -NetworkInterface $nic
EnableAcceleratedNetworking = $nic.EnableAcceleratedNetworking
EnableIPForwarding = $nic.EnableIPForwarding
DnsSettings = $nic.DnsSettings
InfrastructureType = $DetectedInfraType
}

# Add Application Gateway backend pools if requested
if ($IncludeAppGateway) {
$nicConfig.ApplicationGatewayBackendPools = Get-ApplicationGatewayBackendPools -NetworkInterface $nic
}

# Add cross-region mapping for resources
if ($nicConfig.LoadBalancerBackendPools) {
foreach ($lbPool in $nicConfig.LoadBalancerBackendPools) {
$lbPool.SecondaryLoadBalancerName = Get-CrossRegionMapping -ResourceName $lbPool.LoadBalancerName -DetectedInfraType $DetectedInfraType
}
}

if ($IncludeAppGateway -and $nicConfig.ApplicationGatewayBackendPools) {
foreach ($appGwPool in $nicConfig.ApplicationGatewayBackendPools) {
$appGwPool.SecondaryApplicationGatewayName = Get-CrossRegionMapping -ResourceName $appGwPool.ApplicationGatewayName -DetectedInfraType $DetectedInfraType
}
}

$vmConfig.NetworkInterfaces += $nicConfig
}

# Save configuration to JSON file
$configFileName = "$VmName-networking-config-$ConfigTimestamp.json"
$configFilePath = Join-Path $ConfigurationPath $configFileName

$vmConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Encoding UTF8

Write-Log " Saved configuration for $VmName to: $configFilePath" "SUCCESS"

# Upload to storage if specified
if ($StorageAccountName) {
Upload-ConfigurationToStorage -FilePath $configFilePath -StorageAccountName $StorageAccountName -StorageResourceGroupName $StorageResourceGroupName
}

# Log summary statistics
$totalNics = $vmConfig.NetworkInterfaces.Count
$totalAsgMemberships = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.ApplicationSecurityGroups }).Count
$totalStaticIps = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.StaticIpConfigurations }).Count
$totalLbPools = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.LoadBalancerBackendPools }).Count

if ($Detailed) {
Write-Log " NICs: $totalNics, ASG memberships: $totalAsgMemberships, Static IPs: $totalStaticIps, LB pools: $totalLbPools" "INFO"
Write-Log " Infrastructure type: $DetectedInfraType" "INFO"
}

return $configFilePath
}
catch {
Write-Log "Failed to save configuration for VM $VmName`: $($_.Exception.Message)" "ERROR"
throw
}
}

function Save-MasterConfiguration {
param(
[Parameter(Mandatory = $true)]
[array]$SavedConfigurations,

[Parameter(Mandatory = $true)]
[string]$DetectedInfraType
)

$masterConfig = @{
Timestamp = $ConfigTimestamp
ProjectName = $ProjectName
Environment = $Environment
InfrastructureType = $DetectedInfraType
PrimaryResourceGroup = $ResourceGroupName
SecondaryResourceGroup = $SecondaryResourceGroupName
ConfigurationFiles = $SavedConfigurations
Statistics = @{
TotalVMs = $SavedConfigurations.Count
TotalNICs = 0
TotalASGs = 0
TotalStaticIPs = 0
}
CrossRegionMapping = @{
InfrastructureType = $DetectedInfraType
MappingRules = switch ($DetectedInfraType) {
"terraform" { @{
Pattern = "Simple primary/secondary replacement"
Example = "web-lb -> web-lb-secondary"
}}
"bicep" { @{
Pattern = "Region-based replacement"
Example = "webapp-prod-eastus-lb -> webapp-prod-westus2-lb"
}}
}
}
Script = @{
Version = "1.0.0"
ExecutedBy = $env:USERNAME
ExecutedFrom = $env:COMPUTERNAME
CompatibleWith = "Terraform and Bicep"
}
Azure = @{
SubscriptionId = (Get-AzContext).Subscription.Id
SubscriptionName = (Get-AzContext).Subscription.Name
TenantId = (Get-AzContext).Tenant.Id
}
}

$masterConfigFileName = "MASTER-networking-config-$ConfigTimestamp.json"
$masterConfigFilePath = Join-Path $ConfigurationPath $masterConfigFileName

$masterConfig | ConvertTo-Json -Depth 5 | Out-File -FilePath $masterConfigFilePath -Encoding UTF8

# Upload to storage if specified
if ($StorageAccountName) {
Upload-ConfigurationToStorage -FilePath $masterConfigFilePath -StorageAccountName $StorageAccountName -StorageResourceGroupName $StorageResourceGroupName
}

Write-Log "Master configuration saved to: $masterConfigFilePath" "SUCCESS"
return $masterConfigFilePath
}

#endregion

#region Main Execution

function Main {
Write-Log "=== Azure Site Recovery Networking Configuration Backup ===" "INFO"
Write-Log "Compatible with Terraform and Bicep Infrastructure" "INFO"
Write-Log "Started at: $(Get-Date)" "INFO"
Write-Log "Configuration will be saved to: $ConfigurationPath" "INFO"

# Ensure configuration directory exists
if (-not (Test-Path $ConfigurationPath)) {
New-Item -ItemType Directory -Path $ConfigurationPath -Force | Out-Null
Write-Log "Created configuration directory: $ConfigurationPath" "INFO"
}

# Test Azure connection
if (-not (Test-AzureConnection)) {
Write-Log "Azure connection test failed. Exiting." "ERROR"
exit 1
}

try {
# Detect infrastructure type
$detectedInfraType = Detect-InfrastructureType -ResourceGroupName $ResourceGroupName

# Get list of VMs to process
if ($VmNames.Count -eq 0) {
Write-Log "No specific VMs specified, discovering all VMs in resource group: $ResourceGroupName" "INFO"
$vms = Get-AzVM -ResourceGroupName $ResourceGroupName -ErrorAction Stop
$VmNames = $vms | ForEach-Object { $_.Name }

if ($VmNames.Count -eq 0) {
Write-Log "No VMs found in resource group: $ResourceGroupName" "WARNING"
return
}
}

Write-Log "Processing $($VmNames.Count) VMs: $($VmNames -join ', ')" "INFO"
Write-Log "Detected infrastructure type: $detectedInfraType" "INFO"

$savedConfigurations = @()
$successCount = 0
$errorCount = 0

# Save configuration for each VM
foreach ($vmName in $VmNames) {
try {
$configPath = Save-VmNetworkingConfiguration -VmName $vmName -ResourceGroup $ResourceGroupName -DetectedInfraType $detectedInfraType
if ($configPath) {
$savedConfigurations += (Split-Path $configPath -Leaf)
$successCount++
}
}
catch {
Write-Log "Failed to process VM $vmName`: $($_.Exception.Message)" "ERROR"
$errorCount++
}
}

# Save master configuration
if ($savedConfigurations.Count -gt 0) {
$masterConfigPath = Save-MasterConfiguration -SavedConfigurations $savedConfigurations -DetectedInfraType $detectedInfraType
}

# Summary
Write-Log "=== BACKUP SUMMARY ===" "INFO"
Write-Log "Infrastructure type: $detectedInfraType" "INFO"
Write-Log "Successfully processed: $successCount VMs" "SUCCESS"
Write-Log "Failed to process: $errorCount VMs" "ERROR"
Write-Log "Configuration files saved to: $ConfigurationPath" "INFO"
if ($StorageAccountName) {
Write-Log "Configurations uploaded to storage account: $StorageAccountName" "INFO"
}
Write-Log "Log file: $LogFile" "INFO"
Write-Log "Backup completed at: $(Get-Date)" "SUCCESS"

if ($errorCount -gt 0) {
Write-Log "Some VMs failed to process. Check the log for details." "WARNING"
exit 1
}
else {
Write-Log "All VMs processed successfully!" "SUCCESS"
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