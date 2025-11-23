# Terraform Infrastructure - PowerShell ASR Integration Examples

## 🔧 Terraform-Specific Configuration Examples

This guide provides detailed examples for using the PowerShell ASR networking automation with **Terraform-deployed** Azure infrastructure.

---

## 🏗️ Typical Terraform Infrastructure Patterns

### Resource Naming Conventions

```hcl
# Terraform naming patterns that the scripts auto-detect:

resource "azurerm_virtual_machine" "web" {
  name = "web-vm-${count.index + 1}"    # web-vm-1, web-vm-2
}

resource "azurerm_lb" "web" {
  name = "web-lb-${var.environment}"    # web-lb-primary, web-lb-secondary
}

resource "azurerm_application_security_group" "web_tier" {
  name = "web-tier-asg"                 # web-tier-asg
}
```

### Resource Group Structure

```hcl
# Primary region resource group
resource "azurerm_resource_group" "primary" {
  name     = "${var.project_name}-${var.environment}-primary-rg"
  location = var.primary_location
}

# Secondary region resource group
resource "azurerm_resource_group" "secondary" {
  name     = "${var.project_name}-${var.environment}-secondary-rg"
  location = var.secondary_location
}
```

---

## 📜 PowerShell Integration Examples

### 1. Basic Terraform Backup

```powershell
# Auto-detect Terraform infrastructure and backup all VMs
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -SecondaryResourceGroupName "webapp-prod-secondary-rg" `
    -ProjectName "webapp" `
    -Environment "prod"

# Expected auto-detection output:
# [INFO] Auto-detected infrastructure type: terraform (TF indicators: 8, Bicep indicators: 2)
# [INFO] Cross-region mapping: primary -> secondary
```

### 2. Explicit Terraform Configuration

```powershell
# Explicitly specify Terraform for optimal performance
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "ecommerce-prod-primary-rg" `
    -SecondaryResourceGroupName "ecommerce-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -ProjectName "ecommerce" `
    -Environment "prod" `
    -VmNames @("web-vm-1", "web-vm-2", "app-vm-1", "db-vm-1") `
    -StorageAccountName "ecommerceasrconfigs" `
    -StorageResourceGroupName "shared-services-rg" `
    -IncludeAppGateway `
    -IncludeLoadBalancer `
    -Detailed
```

### 3. Terraform Restoration with Validation

```powershell
# Preview restoration for Terraform infrastructure
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -DryRun `
    -Detailed

# Sample output for Terraform:
# [INFO] Infrastructure type: terraform
# [INFO] Cross-region mapping detected: primary -> secondary
# [ACTION] Would restore ASG membership: web-tier-asg
# [ACTION] Would restore LB pool membership: web-pool in web-lb-secondary
```

### 4. Terraform Multi-Tier Application

```powershell
# Backup complete 3-tier application
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -InfrastructureType "terraform" `
    -ProjectName "webapp" `
    -Environment "prod" `
    -VmNames @(
        "web-vm-1", "web-vm-2", "web-vm-3",      # Web tier
        "app-vm-1", "app-vm-2",                  # App tier
        "db-vm-1"                                # Database tier
    ) `
    -StorageAccountName "webappasrconfigs" `
    -IncludeAppGateway `
    -IncludeLoadBalancer
```

---

## 🎯 Terraform Resource Mapping Examples

### Load Balancer Mapping

```yaml
# Terraform Primary Resources -> Secondary Resources
Primary:
  - web-lb-primary          -> web-lb-secondary
  - app-lb-primary          -> app-lb-secondary
  - db-lb                   -> db-lb-secondary
  - internal-lb             -> internal-lb-secondary

Secondary:
  - web-lb-secondary
  - app-lb-secondary
  - db-lb-secondary
  - internal-lb-secondary
```

### Application Gateway Mapping

```yaml
# Application Gateway cross-region mapping
Primary:
  - web-appgw-primary       -> web-appgw-secondary
  - api-gateway-primary     -> api-gateway-secondary
  - public-appgw            -> public-appgw-secondary

Secondary:
  - web-appgw-secondary
  - api-gateway-secondary
  - public-appgw-secondary
```

---

## 🔄 Terraform ASR Automation Integration

### Azure Automation Runbook for Terraform

```powershell
# Pre-failover backup automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Backup" `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -StorageAccountName "webappasrautomation" `
    -StorageResourceGroupName "automation-rg" `
    -InfrastructureType "terraform" `
    -ProjectName "webapp" `
    -Environment "prod" `
    -SecondaryResourceGroupName "webapp-prod-secondary-rg"

# Post-failover restoration automation
.\ASR-NetworkingAutomation.ps1 `
    -Operation "Restore" `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -StorageAccountName "webappasrautomation" `
    -StorageResourceGroupName "automation-rg" `
    -InfrastructureType "terraform"
```

### ASR Recovery Plan JSON for Terraform

```json
{
  "RecoveryPlanName": "terraform-webapp-dr-plan",
  "PrimaryFabric": "eastus-site-recovery",
  "RecoveryFabric": "westus2-site-recovery",
  "Groups": [
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "web-vm-1",
        "web-vm-2",
        "web-vm-3"
      ]
    },
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "app-vm-1",
        "app-vm-2"
      ]
    },
    {
      "GroupType": "Boot",
      "ReplicationProtectedItems": [
        "db-vm-1"
      ]
    }
  ],
  "PreFailoverActions": [
    {
      "ActionName": "BackupNetworkingConfig",
      "ActionType": "ScriptAction",
      "FailoverTypes": ["PlannedFailover", "UnplannedFailover"],
      "ScriptName": "ASR-NetworkingAutomation",
      "Parameters": {
        "Operation": "Backup",
        "ResourceGroupName": "webapp-prod-primary-rg",
        "StorageAccountName": "webappasrautomation",
        "StorageResourceGroupName": "automation-rg",
        "InfrastructureType": "terraform"
      }
    }
  ],
  "PostFailoverActions": [
    {
      "ActionName": "RestoreNetworkingConfig",
      "ActionType": "ScriptAction",
      "FailoverTypes": ["PlannedFailover", "UnplannedFailover"],
      "ScriptName": "ASR-NetworkingAutomation",
      "Parameters": {
        "Operation": "Restore",
        "ResourceGroupName": "webapp-prod-secondary-rg",
        "StorageAccountName": "webappasrautomation",
        "StorageResourceGroupName": "automation-rg",
        "InfrastructureType": "terraform"
      }
    }
  ]
}
```

---

## 📊 Terraform Configuration Examples

### Sample terraform.tfvars for Primary Region

```hcl
# Primary region configuration
project_name = "webapp"
environment = "prod"
primary_location = "East US"
secondary_location = "West US 2"

# Resource naming
resource_suffix = "primary"
vm_name_prefix = "web-vm"
lb_name = "web-lb-primary"
app_gateway_name = "web-appgw-primary"

# Network configuration
vnet_address_space = ["10.1.0.0/16"]
web_subnet_address = ["10.1.1.0/24"]
app_subnet_address = ["10.1.2.0/24"]
data_subnet_address = ["10.1.3.0/24"]

# VM configuration
web_vm_count = 3
app_vm_count = 2
vm_size = "Standard_D2s_v3"

# Application Security Groups
create_web_asg = true
create_app_asg = true
create_data_asg = true
```

### Sample Terraform VM Configuration

```hcl
# Web tier VMs with networking
resource "azurerm_network_interface" "web" {
  count               = var.web_vm_count
  name                = "web-vm-${count.index + 1}-nic"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Static"
    private_ip_address           = "10.1.1.${10 + count.index}"

    # Load balancer backend pool association
    load_balancer_backend_address_pools_ids = [
      azurerm_lb_backend_address_pool.web.id
    ]
  }

  # Application Security Group association
  application_security_group_ids = [
    azurerm_application_security_group.web_tier.id
  ]
}

resource "azurerm_virtual_machine" "web" {
  count               = var.web_vm_count
  name                = "web-vm-${count.index + 1}"
  location            = azurerm_resource_group.primary.location
  resource_group_name = azurerm_resource_group.primary.name

  network_interface_ids = [
    azurerm_network_interface.web[count.index].id
  ]

  vm_size = var.vm_size
}
```

---

## 🧪 Testing Terraform Infrastructure

### Test Infrastructure Detection

```powershell
# Test auto-detection with Terraform resources
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -InfrastructureType "auto" `
    -Detailed `
    -VmNames @("web-vm-1") # Test with single VM first

# Expected detection output:
# [INFO] Auto-detected infrastructure type: terraform (TF indicators: 5, Bicep indicators: 0)
# [INFO] Cross-region mapping: primary -> secondary patterns
```

### Validate Cross-Region Mapping

```powershell
# Test restoration with dry-run to validate mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -DryRun `
    -Detailed

# Expected mapping output:
# [INFO] Infrastructure type: terraform
# [ACTION] Would restore LB pool: web-pool in web-lb-secondary
# [ACTION] Would restore App Gateway pool: web-pool in web-appgw-secondary
```

### Test Selective VM Operations

```powershell
# Test with specific Terraform-named VMs
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "ecommerce-prod-primary-rg" `
    -VmNames @("web-vm-1", "web-vm-2", "app-vm-1") `
    -InfrastructureType "terraform" `
    -Detailed

.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "ecommerce-prod-secondary-rg" `
    -VmNames @("web-vm-1", "web-vm-2", "app-vm-1") `
    -InfrastructureType "terraform" `
    -DryRun
```

---

## 🔧 Troubleshooting Terraform-Specific Issues

### Common Terraform Naming Issues

```powershell
# Issue: Resource not found during restoration
# Solution: Check primary/secondary naming consistency

# Debug mapping logic
$primaryLbName = "web-lb-primary"
$secondaryLbName = $primaryLbName -replace "primary", "secondary"
Write-Host "Mapped: $primaryLbName -> $secondaryLbName"

# Verify secondary resources exist
Get-AzLoadBalancer -ResourceGroupName "webapp-prod-secondary-rg" |
    Select-Object Name |
    Where-Object { $_.Name -like "*secondary*" }
```

### ASG Membership Issues

```powershell
# Issue: ASG not found in secondary region
# Solution: Verify ASG deployment in secondary region

# Check ASG availability
Get-AzApplicationSecurityGroup -ResourceGroupName "webapp-prod-secondary-rg" |
    Select-Object Name, ResourceGroupName

# Restore specific ASG memberships
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -VmNames @("web-vm-1") `
    -InfrastructureType "terraform" `
    -Force `
    -Detailed
```

### Load Balancer Pool Issues

```powershell
# Issue: LB backend pool mapping fails
# Solution: Verify LB naming and pool existence

# Check LB and pools in secondary region
$lb = Get-AzLoadBalancer -ResourceGroupName "webapp-prod-secondary-rg" -Name "web-lb-secondary"
$lb.BackendAddressPools | Select-Object Name, Id

# Test LB pool restoration
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -VmNames @("web-vm-1") `
    -DryRun `
    -Detailed
```

---

## 📋 Terraform Best Practices

### Resource Naming Standards

```hcl
# Consistent naming for cross-region mapping
locals {
  name_prefix = "${var.project_name}-${var.environment}"
  region_suffix = var.environment == "primary" ? "primary" : "secondary"
}

resource "azurerm_lb" "web" {
  name = "${local.name_prefix}-web-lb-${local.region_suffix}"
}

resource "azurerm_application_gateway" "web" {
  name = "${local.name_prefix}-web-appgw-${local.region_suffix}"
}
```

### Variable Configuration

```hcl
# terraform.tfvars
project_name = "webapp"
environment = "prod"

# Primary region
primary_location = "East US"
primary_suffix = "primary"

# Secondary region
secondary_location = "West US 2"
secondary_suffix = "secondary"

# Network settings
enable_static_ips = true
create_application_gateways = true
create_load_balancers = true
```

### Module Structure

```hcl
# modules/networking/main.tf
module "primary_networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment = var.environment
  location = var.primary_location
  region_suffix = "primary"

  # PowerShell ASR automation compatible naming
  use_asr_compatible_naming = true
}

module "secondary_networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment = var.environment
  location = var.secondary_location
  region_suffix = "secondary"

  # PowerShell ASR automation compatible naming
  use_asr_compatible_naming = true
}
```

---

## 🚀 Production Deployment Workflow

### Step 1: Deploy Terraform Infrastructure

```bash
# Deploy primary region
terraform workspace new primary
terraform apply -var-file="primary.tfvars"

# Deploy secondary region
terraform workspace new secondary
terraform apply -var-file="secondary.tfvars"
```

### Step 2: Configure ASR Networking Automation

```powershell
# Test infrastructure detection
.\Save-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-primary-rg" `
    -InfrastructureType "auto" `
    -VmNames @("web-vm-1") `
    -Detailed

# Verify cross-region mapping
.\Restore-NetworkingConfig.ps1 `
    -ResourceGroupName "webapp-prod-secondary-rg" `
    -InfrastructureType "terraform" `
    -VmNames @("web-vm-1") `
    -DryRun
```

### Step 3: Deploy Azure Automation

```powershell
# Create automation account and import runbooks
New-AzAutomationAccount -Name "webapp-asr-automation" -ResourceGroupName "automation-rg"

# Import networking automation runbook
Import-AzAutomationRunbook `
    -Path ".\ASR-NetworkingAutomation.ps1" `
    -Name "ASR-NetworkingAutomation" `
    -Type PowerShell
```

### Step 4: Configure ASR Recovery Plan

```powershell
# Create recovery plan with Terraform-optimized settings
New-AzRecoveryServicesAsrRecoveryPlan `
    -Name "terraform-webapp-dr-plan" `
    -PrimaryFabric $primaryFabric `
    -RecoveryFabric $secondaryFabric `
    -ReplicationProtectedItem $protectedItems
```

---

*This guide provides comprehensive examples for integrating the PowerShell ASR automation with Terraform-deployed Azure infrastructure, ensuring seamless disaster recovery with preserved networking configurations.*