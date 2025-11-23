#Requires -Version 5.1
#Requires -Modules Az.Accounts, Az.Network, Az.Compute, Az.Resources

<#
.SYNOPSIS
    Saves networking configuration of VMs before Site Recovery failover including ASG, NIC, and Application Gateway configurations.

.DESCRIPTION
    This script captures and saves complete networking configurations for VMs before Azure Site Recovery failover.
    It saves Application Security Group memberships, Network Interface configurations, static IP assignments,
    and Application Gateway backend pool memberships to enable post-failover restoration.

.PARAMETER ResourceGroupName
    Primary resource group containing the source VMs and networking resources

.PARAMETER SecondaryResourceGroupName
    Secondary (DR) resource group where configurations will be restored

.PARAMETER ConfigurationPath
    Path where configuration files will be saved (default: current directory)

.PARAMETER VmNames
    Array of VM names to save configurations for (if empty, processes all VMs in resource group)

.PARAMETER ProjectName
    Project name used in resource naming convention

.PARAMETER Environment
    Environment name (prod, staging, dev)

.EXAMPLE
    .\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg" -SecondaryResourceGroupName "webapp-prod-secondary-rg" -ProjectName "webapp" -Environment "prod"

.EXAMPLE
    .\Save-NetworkingConfig.ps1 -ResourceGroupName "webapp-prod-primary-rg" -SecondaryResourceGroupName "webapp-prod-secondary-rg" -VmNames @("web-vm-1", "web-vm-2") -ConfigurationPath "C:\ASR\Configs"

.NOTES
    Author: Azure Infrastructure Team
    Version: 1.0.0
    Requires: Azure PowerShell modules (Az.Accounts, Az.Network, Az.Compute, Az.Resources)

    This script is designed to run in Azure Automation or as part of Azure Site Recovery automation.
    Ensure the execution account has appropriate permissions to read networking configurations.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SecondaryResourceGroupName,

    [Parameter(Mandatory = $false)]
    [string]$ConfigurationPath = ".",

    [Parameter(Mandatory = $false)]
    [string[]]$VmNames = @(),

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$SubscriptionId,

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
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
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

function Get-NetworkSecurityGroupRules {
    param(
        [Parameter(Mandatory = $true)]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkInterface]$NetworkInterface
    )

    $nsgConfig = @()

    # Check subnet-level NSG
    if ($NetworkInterface.IpConfigurations[0].Subnet.NetworkSecurityGroup) {
        $subnetNsgId = $NetworkInterface.IpConfigurations[0].Subnet.NetworkSecurityGroup.Id
        $subnetNsgName = $subnetNsgId.Split('/')[-1]
        $subnetNsgResourceGroup = $subnetNsgId.Split('/')[4]

        $nsgConfig += @{
            Type = "Subnet"
            NsgName = $subnetNsgName
            NsgResourceGroup = $subnetNsgResourceGroup
            NsgId = $subnetNsgId
        }
    }

    # Check NIC-level NSG
    if ($NetworkInterface.NetworkSecurityGroup) {
        $nicNsgConfig = @{
            Type = "NetworkInterface"
            NsgName = $NetworkInterface.NetworkSecurityGroup.Name
            NsgResourceGroup = $NetworkInterface.NetworkSecurityGroup.ResourceGroupName
            NsgId = $NetworkInterface.NetworkSecurityGroup.Id
        }
        $nsgConfig += $nicNsgConfig
    }

    return $nsgConfig
}

#endregion

#region Main Functions

function Save-VmNetworkingConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmName,

        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup
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
            VmResourceGroup = $ResourceGroup
            VmLocation = $vm.Location
            VmSize = $vm.HardwareProfile.VmSize
            Timestamp = $ConfigTimestamp
            NetworkInterfaces = @()
        }

        foreach ($nic in $networkInterfaces) {
            Write-Log "  Processing NIC: $($nic.Name)" "INFO"

            $nicConfig = @{
                Name = $nic.Name
                ResourceGroup = $nic.ResourceGroupName
                Location = $nic.Location
                Id = $nic.Id
                IpConfigurations = @()
                ApplicationSecurityGroups = Get-ApplicationSecurityGroups -NetworkInterface $nic
                StaticIpConfigurations = Get-StaticIpConfigurations -NetworkInterface $nic
                ApplicationGatewayBackendPools = Get-ApplicationGatewayBackendPools -NetworkInterface $nic
                LoadBalancerBackendPools = Get-LoadBalancerBackendPools -NetworkInterface $nic
                NetworkSecurityGroups = Get-NetworkSecurityGroupRules -NetworkInterface $nic
                EnableAcceleratedNetworking = $nic.EnableAcceleratedNetworking
                EnableIPForwarding = $nic.EnableIPForwarding
                DnsSettings = $nic.DnsSettings
            }

            # Save detailed IP configuration information
            foreach ($ipConfig in $nic.IpConfigurations) {
                $ipConfigDetail = @{
                    Name = $ipConfig.Name
                    PrivateIpAddress = $ipConfig.PrivateIpAddress
                    PrivateIpAllocationMethod = $ipConfig.PrivateIpAllocationMethod
                    Primary = $ipConfig.Primary
                    SubnetId = $ipConfig.Subnet.Id
                    SubnetName = $ipConfig.Subnet.Name
                    PublicIpAddress = $null
                    ApplicationGatewayBackendAddressPools = @()
                    LoadBalancerBackendAddressPools = @()
                    ApplicationSecurityGroups = @()
                }

                if ($ipConfig.PublicIpAddress) {
                    $ipConfigDetail.PublicIpAddress = @{
                        Name = $ipConfig.PublicIpAddress.Name
                        ResourceGroup = $ipConfig.PublicIpAddress.ResourceGroupName
                        Id = $ipConfig.PublicIpAddress.Id
                    }
                }

                if ($ipConfig.ApplicationGatewayBackendAddressPools) {
                    foreach ($pool in $ipConfig.ApplicationGatewayBackendAddressPools) {
                        $ipConfigDetail.ApplicationGatewayBackendAddressPools += @{
                            Name = $pool.Name
                            Id = $pool.Id
                        }
                    }
                }

                if ($ipConfig.LoadBalancerBackendAddressPools) {
                    foreach ($pool in $ipConfig.LoadBalancerBackendAddressPools) {
                        $ipConfigDetail.LoadBalancerBackendAddressPools += @{
                            Name = $pool.Name
                            Id = $pool.Id
                        }
                    }
                }

                if ($ipConfig.ApplicationSecurityGroups) {
                    foreach ($asg in $ipConfig.ApplicationSecurityGroups) {
                        $ipConfigDetail.ApplicationSecurityGroups += @{
                            Name = $asg.Name
                            Id = $asg.Id
                            ResourceGroup = $asg.ResourceGroupName
                        }
                    }
                }

                $nicConfig.IpConfigurations += $ipConfigDetail
            }

            $vmConfig.NetworkInterfaces += $nicConfig
        }

        # Save configuration to JSON file
        $configFileName = "$VmName-networking-config-$ConfigTimestamp.json"
        $configFilePath = Join-Path $ConfigurationPath $configFileName

        $vmConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Encoding UTF8

        Write-Log "  Saved configuration for $VmName to: $configFilePath" "SUCCESS"

        # Log summary statistics
        $totalNics = $vmConfig.NetworkInterfaces.Count
        $totalAsgMemberships = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.ApplicationSecurityGroups }).Count
        $totalStaticIps = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.StaticIpConfigurations }).Count
        $totalAppGwPools = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.ApplicationGatewayBackendPools }).Count
        $totalLbPools = ($vmConfig.NetworkInterfaces | ForEach-Object { $_.LoadBalancerBackendPools }).Count

        Write-Log "    NICs: $totalNics, ASG memberships: $totalAsgMemberships, Static IPs: $totalStaticIps, App Gateway pools: $totalAppGwPools, LB pools: $totalLbPools" "INFO"

        return $configFilePath
    }
    catch {
        Write-Log "Failed to save configuration for VM $VmName`: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Save-ApplicationGatewayConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ResourceGroup
    )

    Write-Log "Saving Application Gateway configurations in resource group: $ResourceGroup" "INFO"

    try {
        $appGateways = Get-AzApplicationGateway -ResourceGroupName $ResourceGroup -ErrorAction SilentlyContinue

        if ($appGateways.Count -eq 0) {
            Write-Log "No Application Gateways found in resource group $ResourceGroup" "INFO"
            return
        }

        foreach ($appGw in $appGateways) {
            Write-Log "  Processing Application Gateway: $($appGw.Name)" "INFO"

            $appGwConfig = @{
                Name = $appGw.Name
                ResourceGroup = $appGw.ResourceGroupName
                Location = $appGw.Location
                Id = $appGw.Id
                Timestamp = $ConfigTimestamp
                BackendAddressPools = @()
                BackendHttpSettings = @()
                HttpListeners = @()
                RequestRoutingRules = @()
                Probes = @()
                FrontendIpConfigurations = @()
                GatewayIpConfigurations = @()
            }

            # Save backend address pools with their members
            foreach ($pool in $appGw.BackendAddressPools) {
                $poolConfig = @{
                    Name = $pool.Name
                    Id = $pool.Id
                    BackendAddresses = @()
                    BackendIpConfigurations = @()
                }

                if ($pool.BackendAddresses) {
                    foreach ($address in $pool.BackendAddresses) {
                        $poolConfig.BackendAddresses += @{
                            IpAddress = $address.IpAddress
                            Fqdn = $address.Fqdn
                        }
                    }
                }

                if ($pool.BackendIpConfigurations) {
                    foreach ($ipConfig in $pool.BackendIpConfigurations) {
                        $poolConfig.BackendIpConfigurations += @{
                            Id = $ipConfig.Id
                            Name = $ipConfig.Name
                        }
                    }
                }

                $appGwConfig.BackendAddressPools += $poolConfig
            }

            # Save other configuration elements
            foreach ($setting in $appGw.BackendHttpSettingsCollection) {
                $appGwConfig.BackendHttpSettings += @{
                    Name = $setting.Name
                    Port = $setting.Port
                    Protocol = $setting.Protocol
                    CookieBasedAffinity = $setting.CookieBasedAffinity
                    RequestTimeout = $setting.RequestTimeout
                }
            }

            foreach ($listener in $appGw.HttpListeners) {
                $appGwConfig.HttpListeners += @{
                    Name = $listener.Name
                    FrontendIpConfiguration = $listener.FrontendIpConfiguration.Id
                    FrontendPort = $listener.FrontendPort.Id
                    Protocol = $listener.Protocol
                }
            }

            foreach ($rule in $appGw.RequestRoutingRules) {
                $appGwConfig.RequestRoutingRules += @{
                    Name = $rule.Name
                    RuleType = $rule.RuleType
                    HttpListener = $rule.HttpListener.Id
                    BackendAddressPool = $rule.BackendAddressPool.Id
                    BackendHttpSettings = $rule.BackendHttpSettings.Id
                }
            }

            # Save configuration to JSON file
            $configFileName = "$($appGw.Name)-appgateway-config-$ConfigTimestamp.json"
            $configFilePath = Join-Path $ConfigurationPath $configFileName

            $appGwConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $configFilePath -Encoding UTF8

            Write-Log "  Saved Application Gateway configuration to: $configFilePath" "SUCCESS"
        }
    }
    catch {
        Write-Log "Failed to save Application Gateway configurations: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Save-MasterConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [array]$SavedConfigurations
    )

    $masterConfig = @{
        Timestamp = $ConfigTimestamp
        ProjectName = $ProjectName
        Environment = $Environment
        PrimaryResourceGroup = $ResourceGroupName
        SecondaryResourceGroup = $SecondaryResourceGroupName
        ConfigurationFiles = $SavedConfigurations
        Script = @{
            Version = "1.0.0"
            ExecutedBy = $env:USERNAME
            ExecutedFrom = $env:COMPUTERNAME
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

    Write-Log "Master configuration saved to: $masterConfigFilePath" "SUCCESS"
    return $masterConfigFilePath
}

#endregion

#region Main Execution

function Main {
    Write-Log "=== Azure Site Recovery Networking Configuration Backup ===" "INFO"
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

        $savedConfigurations = @()
        $successCount = 0
        $errorCount = 0

        # Save configuration for each VM
        foreach ($vmName in $VmNames) {
            try {
                $configPath = Save-VmNetworkingConfiguration -VmName $vmName -ResourceGroup $ResourceGroupName
                $savedConfigurations += $configPath
                $successCount++
            }
            catch {
                Write-Log "Failed to process VM $vmName`: $($_.Exception.Message)" "ERROR"
                $errorCount++
            }
        }

        # Save Application Gateway configurations
        try {
            Save-ApplicationGatewayConfiguration -ResourceGroup $ResourceGroupName
        }
        catch {
            Write-Log "Failed to save Application Gateway configurations: $($_.Exception.Message)" "WARNING"
        }

        # Save master configuration
        $masterConfigPath = Save-MasterConfiguration -SavedConfigurations $savedConfigurations

        # Summary
        Write-Log "=== BACKUP SUMMARY ===" "INFO"
        Write-Log "Successfully processed: $successCount VMs" "SUCCESS"
        Write-Log "Failed to process: $errorCount VMs" "ERROR"
        Write-Log "Configuration files saved to: $ConfigurationPath" "INFO"
        Write-Log "Master configuration: $masterConfigPath" "INFO"
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