# Bicep Implementation
## Azure Multi-Tier Disaster Recovery Architecture

This folder contains the complete Azure Bicep Infrastructure as Code (IaC) implementation for the Azure multi-tier web application with cross-region disaster recovery.

---

## 📁 Folder Structure

```
bicep-implementation/
├── README.md                          # This file
├── main.bicep                         # Main Bicep template
├── main.bicepparam                    # Bicep parameters file
├── VMSS_GUIDE.md                      # VMSS implementation guide
├── .gitignore                         # Git ignore patterns
├── modules/                           # Reusable Bicep modules
│   ├── region.bicep                   # Regional deployment module
│   ├── vm.bicep                       # Virtual machine template
│   ├── vmss.bicep                     # Virtual Machine Scale Sets module
│   ├── recovery-services.bicep        # Site Recovery configuration
│   ├── traffic-manager.bicep          # Global load balancing
│   └── vnet-peering.bicep            # Cross-region networking
└── scripts/                          # VM initialization scripts
    ├── web-setup.sh                  # Web tier configuration
    ├── app-setup.sh                  # App tier configuration
    └── data-setup-enhanced.sh        # Database with replication
```

---

## 🚀 Quick Start

### **Prerequisites**
- Azure CLI installed and authenticated
- Bicep CLI installed (or use Azure CLI with Bicep support)
- Appropriate Azure subscription permissions

### **Deployment Steps**

```bash
# 1. Navigate to Bicep implementation folder
cd bicep-implementation/

# 2. Login to Azure (if not already authenticated)
az login

# 3. Set your subscription
az account set --subscription "your-subscription-id"

# 4. Deploy the main template
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters vmAdminPassword='YourSecurePassword123!'

# Alternative: Use parameters file
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### **Expected Deployment Time**: 45-60 minutes for complete infrastructure

---

## 🏗️ Architecture Overview

### **Infrastructure Components**
- **Flexible Deployment** - Individual VMs or VMSS with auto-scaling
- **Multi-tier architecture** (Web, App, Data)
- **Cross-region disaster recovery** with Azure Site Recovery
- **Database replication** with MySQL master-slave
- **Global load balancing** with Azure Traffic Manager
- **High availability** with Availability Zones

### **VMSS Auto-scaling Features**
- **🚀 Virtual Machine Scale Sets** for web and app tiers
- **📊 Auto-scaling** based on CPU, memory, and network metrics
- **⏰ Time-based scaling** profiles (business hours, weekends)
- **💰 Cost optimization** through intelligent scaling (25-40% savings)
- **🔍 Health monitoring** with application health extensions

### **Key Features**
- ✅ **99.99% SLA** with Availability Zones
- ✅ **Complete DR** with VM replication and database replication
- ✅ **Security hardening** with NSGs and encryption
- ✅ **Monitoring** with health checks and diagnostics
- ✅ **Cost optimization** with configurable VM sizes and auto-scaling
- ✅ **VMSS implementation** with Bicep-native auto-scaling rules

---

## 🔧 Configuration Options

### **Main Template Parameters**
| Parameter | Description | Default |
|-----------|-------------|---------|
| `projectName` | Project identifier | `webapp` |
| `environment` | Environment (dev/staging/prod) | `prod` |
| `primaryLocation` | Primary Azure region | `East US` |
| `secondaryLocation` | Secondary Azure region | `West US 2` |
| `useAvailabilityZones` | Use AZ (true) or AS (false) | `true` |
| `enableVMSS` | Enable VMSS deployment | `false` |
| `enableAutoScaling` | Enable auto-scaling | `false` |
| `vmAdminPassword` | VM administrator password | (required) |

### **VMSS Configuration**
```bicep
// Enable VMSS with auto-scaling
param enableVMSS = true
param enableAutoScaling = true

// Auto-scaling thresholds
param autoScalingConfig = {
  webTier: {
    minInstances: 2
    maxInstances: 10
    scaleOutCpuThreshold: 75
    scaleInCpuThreshold: 25
  }
  appTier: {
    minInstances: 2
    maxInstances: 8
    scaleOutCpuThreshold: 70
    scaleInCpuThreshold: 30
  }
}
```

### **VM Size Configuration**
```bicep
// Configurable VM sizes for cost optimization
param vmSizeWeb string = 'Standard_D2s_v3'    // 2 cores, 8GB RAM
param vmSizeApp string = 'Standard_D4s_v3'    // 4 cores, 16GB RAM
param vmSizeData string = 'Standard_D4s_v3'   // 4 cores, 16GB RAM
```

---

## 🛡️ Security Features

### **Network Security**
- **NSG rules** with principle of least privilege
- **Tier isolation** with subnet-based segmentation
- **Enhanced database rules** for cross-region replication
- **Public access** limited to web tier only

### **Data Protection**
- **TLS 1.2 minimum** for all storage accounts
- **Geo-redundant storage** for disaster recovery
- **MySQL encryption** enabled by default
- **VM disk encryption** with Azure managed keys

### **Access Control**
- **Secure parameters** with `@secure()` annotation
- **Parameter validation** with constraints and allowed values
- **SSH access** restricted to private networks only

---

## 📊 Bicep-Specific Features

### **Strong Typing**
```bicep
@description('Environment name')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Admin password for virtual machines')
@secure()
@minLength(8)
@maxLength(123)
param vmAdminPassword string
```

### **Resource Validation**
```bicep
// Built-in validation for Azure resource names
@description('Project name for resource naming')
@minLength(2)
@maxLength(20)
param projectName string = 'webapp'
```

### **Conditional Deployment**
```bicep
// Deploy VMs only in primary region
resource webVMs 'Microsoft.Compute/virtualMachines@2024-03-01' = [for i in range(0, vmCount): if (!isDRRegion) {
  // VM configuration
}]
```

---

## 📈 Deployment Outputs

### **Key Endpoints**
The deployment provides comprehensive outputs including:
```bicep
output applicationEndpoints object = {
  globalEndpoint: 'https://${trafficManager.outputs.fqdn}'
  primaryEndpoint: 'https://${primaryRegion.outputs.loadBalancerFqdn}'
  secondaryEndpoint: 'https://${secondaryRegion.outputs.loadBalancerFqdn}'
}
```

---

## 🔍 Bicep Validation

### **Template Validation**
```bash
# Validate Bicep template
az deployment sub validate \
  --location "East US" \
  --template-file main.bicep \
  --parameters vmAdminPassword='TestPassword123!'

# Build and check for errors
az bicep build --file main.bicep
```

### **What-If Analysis**
```bash
# Preview changes before deployment
az deployment sub what-if \
  --location "East US" \
  --template-file main.bicep \
  --parameters vmAdminPassword='YourSecurePassword123!'
```

---

## 📋 Deployment Checklist

### **Pre-Deployment**
- [ ] Azure CLI installed and authenticated
- [ ] Bicep CLI installed or Azure CLI with Bicep support
- [ ] Review and customize parameters in `main.bicepparam`
- [ ] Validate network address spaces don't conflict

### **Deployment**
- [ ] Run `az deployment sub validate` to verify template
- [ ] Execute `az deployment sub what-if` to preview changes
- [ ] Deploy with `az deployment sub create`
- [ ] Monitor deployment progress in Azure portal

### **Post-Deployment**
- [ ] Test application endpoints and load balancing
- [ ] Verify Site Recovery replication status
- [ ] Test database replication and failover
- [ ] Configure monitoring and alerting

---

## 🛠️ Management Operations

### **VMSS Operations**
```bash
# Enable VMSS with auto-scaling
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters enableVMSS=true enableAutoScaling=true

# Manual scaling for testing
az vmss scale --resource-group webapp-prod-primary-rg \
  --name webapp-prod-primary-web-vmss --new-capacity 5

# View autoscale settings
az monitor autoscale show --resource-group webapp-prod-primary-rg \
  --name webapp-prod-primary-web-autoscale
```

### **VM Size Updates**
```bash
# Update VM sizes for cost optimization
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters vmAdminPassword='Password123!' vmSizeWeb='Standard_D1s_v3'
```

### **Environment Updates**
```bash
# Deploy to different environment
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters environment='staging' projectName='webapp-staging'
```

---

## 🐛 Troubleshooting

### **Common Issues**
1. **Template Validation Errors**: Check parameter types and constraints
2. **Deployment Failures**: Review activity log in Azure portal
3. **Resource Conflicts**: Ensure resource names are globally unique
4. **Permission Issues**: Verify Azure RBAC permissions for deployment

### **Debugging Commands**
```bash
# Get deployment details
az deployment sub show --name <deployment-name>

# Check deployment operations
az deployment operation sub list --name <deployment-name>

# View deployment logs
az monitor activity-log list --resource-group <resource-group-name>
```

---

## 📚 Documentation and Resources

### **Implementation Guides**
- [VMSS_GUIDE.md](./VMSS_GUIDE.md) - Complete VMSS implementation guide with auto-scaling
- [../terraform-implementation/VMSS_GUIDE.md](../terraform-implementation/VMSS_GUIDE.md) - Terraform VMSS equivalent
- [../cost-analysis/COST_BREAKDOWN.md](../cost-analysis/COST_BREAKDOWN.md) - Detailed cost analysis with VMSS

### **Official Documentation**
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [Azure Resource Reference](https://docs.microsoft.com/en-us/azure/templates/)
- [Azure VMSS Documentation](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)

### **Best Practices**
- [Bicep Best Practices](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)
- [Azure Naming Conventions](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
- [Security Best Practices](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices#security)
- [VMSS Auto-scaling Best Practices](https://docs.microsoft.com/en-us/azure/azure-monitor/autoscale/autoscale-best-practices)

---

**Last Updated**: $(date)
**Version**: 1.0.0
**Bicep Version**: Latest
**Maintainer**: Platform Engineering Team