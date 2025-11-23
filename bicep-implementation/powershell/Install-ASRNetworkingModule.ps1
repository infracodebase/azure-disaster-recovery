#Requires -RunAsAdministrator

<#
.SYNOPSIS
    Installs the Azure Site Recovery Networking Automation PowerShell module.

.DESCRIPTION
    This script installs the required Azure PowerShell modules and sets up the ASR Networking Automation module
    for use in Azure Site Recovery scenarios. It handles module dependencies and provides validation.

.PARAMETER Force
    Force installation of modules without prompting

.PARAMETER Scope
    Installation scope - CurrentUser or AllUsers (default: CurrentUser)

.PARAMETER ModulePath
    Custom path for module installation

.EXAMPLE
    .\Install-ASRNetworkingModule.ps1

.EXAMPLE
    .\Install-ASRNetworkingModule.ps1 -Force -Scope AllUsers

.NOTES
    Author: Azure Infrastructure Team
    Version: 1.0.0
    Requires: Administrator privileges for AllUsers scope
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateSet("CurrentUser", "AllUsers")]
    [string]$Scope = "CurrentUser",

    [Parameter(Mandatory = $false)]
    [string]$ModulePath
)

# Set strict mode for better error handling
Set-StrictMode -Version 3.0
$ErrorActionPreference = "Stop"

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

    switch ($Level) {
        "INFO"    { Write-Host $logMessage -ForegroundColor White }
        "WARNING" { Write-Host $logMessage -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
    }
}

function Test-Prerequisites {
    Write-Log "Checking prerequisites..." "INFO"

    # Check PowerShell version
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Write-Log "PowerShell 5.1 or later is required. Current version: $($PSVersionTable.PSVersion)" "ERROR"
        return $false
    }

    # Check execution policy
    $executionPolicy = Get-ExecutionPolicy -Scope CurrentUser
    if ($executionPolicy -eq "Restricted") {
        Write-Log "Execution policy is set to Restricted. Setting to RemoteSigned..." "WARNING"
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    }

    # Check if running as administrator for AllUsers scope
    if ($Scope -eq "AllUsers") {
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
        if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Write-Log "Administrator privileges required for AllUsers scope" "ERROR"
            return $false
        }
    }

    Write-Log "Prerequisites check completed successfully" "SUCCESS"
    return $true
}

function Install-RequiredModules {
    Write-Log "Installing required Azure PowerShell modules..." "INFO"

    $requiredModules = @(
        "Az.Accounts",
        "Az.Network",
        "Az.Compute",
        "Az.Resources",
        "Az.Storage",
        "Az.Automation"
    )

    $installParams = @{
        Force = $Force
        Scope = $Scope
        AllowClobber = $true
    }

    foreach ($module in $requiredModules) {
        try {
            Write-Log "Installing module: $module" "INFO"
            Install-Module -Name $module @installParams

            # Verify installation
            $installedModule = Get-Module -Name $module -ListAvailable | Select-Object -First 1
            if ($installedModule) {
                Write-Log "Successfully installed $module version $($installedModule.Version)" "SUCCESS"
            }
            else {
                Write-Log "Failed to verify installation of $module" "ERROR"
            }
        }
        catch {
            Write-Log "Failed to install $module`: $($_.Exception.Message)" "ERROR"
            throw
        }
    }
}

function Install-ASRNetworkingModule {
    Write-Log "Installing ASR Networking Automation module..." "INFO"

    try {
        # Get current script directory
        $scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path

        # Determine target path
        if ($ModulePath) {
            $targetPath = $ModulePath
        }
        else {
            $modulePaths = $env:PSModulePath -split ';'
            if ($Scope -eq "AllUsers") {
                $targetPath = $modulePaths | Where-Object { $_ -like "*Program Files*" } | Select-Object -First 1
            }
            else {
                $targetPath = $modulePaths | Where-Object { $_ -like "*Documents*" } | Select-Object -First 1
            }
            $targetPath = Join-Path $targetPath "ASR-NetworkingAutomation"
        }

        # Create target directory
        if (-not (Test-Path $targetPath)) {
            New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            Write-Log "Created module directory: $targetPath" "INFO"
        }

        # Copy module files
        $moduleFiles = @(
            "ASR-NetworkingAutomation.psd1",
            "Save-NetworkingConfig.ps1",
            "Restore-NetworkingConfig.ps1",
            "ASR-NetworkingAutomation.ps1",
            "README.md",
            "PowerShell-ASR-Networking-Automation-Documentation.md",
            "PowerShell-Quick-Start-Guide.md",
            "ASR-Integration-Guide.md"
        )

        foreach ($file in $moduleFiles) {
            $sourcePath = Join-Path $scriptPath $file
            $destinationPath = Join-Path $targetPath $file

            if (Test-Path $sourcePath) {
                Copy-Item -Path $sourcePath -Destination $destinationPath -Force
                Write-Log "Copied $file to module directory" "INFO"
            }
            else {
                Write-Log "File not found: $file" "WARNING"
            }
        }

        # Import module to test
        Import-Module $targetPath -Force
        Write-Log "Successfully imported ASR Networking Automation module" "SUCCESS"

        # Display module information
        $moduleInfo = Get-Module -Name "ASR-NetworkingAutomation"
        if ($moduleInfo) {
            Write-Log "Module installed successfully:" "SUCCESS"
            Write-Log "  Name: $($moduleInfo.Name)" "INFO"
            Write-Log "  Version: $($moduleInfo.Version)" "INFO"
            Write-Log "  Path: $($moduleInfo.Path)" "INFO"
        }

        return $targetPath
    }
    catch {
        Write-Log "Failed to install ASR Networking module: $($_.Exception.Message)" "ERROR"
        throw
    }
}

function Test-Installation {
    param([string]$ModulePathInstalled)

    Write-Log "Testing module installation..." "INFO"

    try {
        # Test if scripts are accessible
        $scripts = @("Save-NetworkingConfig.ps1", "Restore-NetworkingConfig.ps1", "ASR-NetworkingAutomation.ps1")

        foreach ($script in $scripts) {
            $scriptPath = Join-Path $ModulePathInstalled $script
            if (Test-Path $scriptPath) {
                Write-Log "Found script: $script" "SUCCESS"
            }
            else {
                Write-Log "Missing script: $script" "ERROR"
                return $false
            }
        }

        # Test if documentation is accessible
        $docs = @("README.md", "PowerShell-ASR-Networking-Automation-Documentation.md")

        foreach ($doc in $docs) {
            $docPath = Join-Path $ModulePathInstalled $doc
            if (Test-Path $docPath) {
                Write-Log "Found documentation: $doc" "SUCCESS"
            }
            else {
                Write-Log "Missing documentation: $doc" "WARNING"
            }
        }

        Write-Log "Installation test completed successfully" "SUCCESS"
        return $true
    }
    catch {
        Write-Log "Installation test failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

function Show-NextSteps {
    param([string]$ModulePathInstalled)

    Write-Log "=== INSTALLATION COMPLETE ===" "SUCCESS"
    Write-Log "ASR Networking Automation module has been installed successfully" "SUCCESS"
    Write-Log "" "INFO"
    Write-Log "Next steps:" "INFO"
    Write-Log "1. Connect to Azure: Connect-AzAccount" "INFO"
    Write-Log "2. Set subscription: Set-AzContext -SubscriptionId 'your-subscription-id'" "INFO"
    Write-Log "3. Navigate to module directory: cd '$ModulePathInstalled'" "INFO"
    Write-Log "4. Review documentation: Get-Content README.md" "INFO"
    Write-Log "5. Test backup: .\Save-NetworkingConfig.ps1 -ResourceGroupName 'your-rg'" "INFO"
    Write-Log "" "INFO"
    Write-Log "Documentation files:" "INFO"
    Write-Log "- README.md - Module overview and quick start" "INFO"
    Write-Log "- PowerShell-ASR-Networking-Automation-Documentation.md - Complete reference" "INFO"
    Write-Log "- PowerShell-Quick-Start-Guide.md - Quick reference card" "INFO"
    Write-Log "- ASR-Integration-Guide.md - Azure Site Recovery integration" "INFO"
}

# Main execution
try {
    Write-Log "=== Azure Site Recovery Networking Automation Module Installer ===" "INFO"
    Write-Log "Installation scope: $Scope" "INFO"

    if (-not (Test-Prerequisites)) {
        exit 1
    }

    Install-RequiredModules
    $modulePathInstalled = Install-ASRNetworkingModule

    if (Test-Installation -ModulePathInstalled $modulePathInstalled) {
        Show-NextSteps -ModulePathInstalled $modulePathInstalled
        exit 0
    }
    else {
        Write-Log "Installation validation failed" "ERROR"
        exit 1
    }
}
catch {
    Write-Log "Installation failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}