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
├── .gitignore                         # Git ignore patterns
├── modules/                           # Reusable Bicep modules
│   ├── region.bicep                   # Regional deployment module
│   ├── vm.bicep                       # Virtual machine template
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
- **6 Virtual Machines** across 2 regions (3 per region)
- **Multi-tier architecture** (Web, App, Data)
- **Cross-region disaster recovery** with Azure Site Recovery
- **Database replication** with MySQL master-slave
- **Global load balancing** with Azure Traffic Manager
- **High availability** with Availability Zones

### **Key Features**
- ✅ **99.99% SLA** with Availability Zones
- ✅ **Complete DR** with VM replication and database replication
- ✅ **Security hardening** with NSGs and encryption
- ✅ **Monitoring** with health checks and diagnostics
- ✅ **Cost optimization** with configurable VM sizes

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
| `vmAdminPassword` | VM administrator password | (required) |

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

### **Scaling Operations**
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

## 📚 Bicep Resources

### **Official Documentation**
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Bicep Language Reference](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/bicep-functions)
- [Azure Resource Reference](https://docs.microsoft.com/en-us/azure/templates/)

### **Best Practices**
- [Bicep Best Practices](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices)
- [Azure Naming Conventions](https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/naming-and-tagging)
- [Security Best Practices](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/best-practices#security)

---

**Last Updated**: $(date)
**Version**: 1.0.0
**Bicep Version**: Latest
**Maintainer**: Platform Engineering Team