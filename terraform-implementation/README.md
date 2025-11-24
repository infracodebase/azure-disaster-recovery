# Terraform Implementation
## Azure Multi-Tier Disaster Recovery Architecture

This folder contains the complete Infrastructure as Code (IaC) implementation for the Azure multi-tier web application with cross-region disaster recovery.

---

## Directory: Folder Structure

```
terraform-implementation/
├── README.md # This file
├── main.tf # Main Terraform configuration
├── variables.tf # Input variables and validation
├── outputs.tf # Output values and endpoints
├── terraform.tfvars.example # Example variable values
├── .gitignore # Git ignore patterns
├── modules/ # Reusable Terraform modules
│ └── region/ # Regional deployment module
│ ├── main.tf # Regional infrastructure
│ ├── variables.tf # Regional variables
│ ├── outputs.tf # Regional outputs
│ ├── compute.tf # VM and compute resources
│ ├── vmss.tf # Virtual Machine Scale Sets
│ ├── autoscaling.tf # Auto-scaling rules and policies
│ └── scripts/ # VM initialization scripts
│ ├── web-setup.sh # Web tier configuration
│ ├── app-setup.sh # App tier configuration
│ └── data-setup-enhanced.sh # Database with replication
└── bicep/ # Alternative Bicep implementation
├── main.bicep # Main Bicep template
├── modules/ # Bicep modules
│ ├── region.bicep # Regional deployment
│ ├── vm.bicep # Virtual machine template
│ ├── recovery-services.bicep # Site Recovery configuration
│ ├── traffic-manager.bicep # Global load balancing
│ └── vnet-peering.bicep # Cross-region networking
└── scripts/ # VM initialization scripts
├── web-setup.sh # Web tier setup
├── app-setup.sh # App tier setup
└── data-setup-enhanced.sh # Enhanced database setup
```

---

## Quick Start

### **Prerequisites**
- Azure CLI installed and authenticated
- Terraform >= 1.0 installed
- Appropriate Azure subscription permissions

### **Deployment Steps**

#### **Option 1: Terraform Deployment**
```bash
# 1. Initialize Terraform
terraform init

# 2. Copy and configure variables
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values

# 3. Plan deployment
terraform plan

# 4. Deploy infrastructure
terraform apply
```

#### **Option 2: Bicep Deployment**
```bash
# 1. Navigate to Bicep folder
cd bicep/

# 2. Deploy main template
az deployment sub create \
--location "East US" \
--template-file main.bicep \
--parameters vmAdminPassword='YourSecurePassword123!'
```

---

## Architecture Overview

### **Infrastructure Components**
- **Virtual Machine Scale Sets (VMSS)** with auto-scaling (2-10 instances per tier)
- **Individual VMs** for database tier (persistent storage requirements)
- **Multi-tier architecture** (Web, App, Data)
- **Cross-region disaster recovery** with Azure Site Recovery
- **Database replication** with MySQL master-slave
- **Global load balancing** with Azure Traffic Manager
- **High availability** with Availability Zones

### **Key Features**
- DONE **99.99% SLA** with Availability Zones
- DONE **Intelligent Auto-Scaling** with CPU, memory, and network triggers
- DONE **Complete DR** with VM replication and database replication
- DONE **Security hardening** with NSGs and encryption
- DONE **Monitoring** with health checks and diagnostics
- DONE **Cost optimization** with dynamic scaling and configurable thresholds

---

## Configuration Options

### **Environment Variables**
| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Project identifier | `webapp` |
| `environment` | Environment (dev/staging/prod) | `prod` |
| `primary_location` | Primary Azure region | `East US` |
| `secondary_location` | Secondary Azure region | `West US 2` |
| `use_availability_zones` | Use AZ (true) or AS (false) | `true` |
| `vm_admin_password` | VM administrator password | (generated) |

### **VM Size Configuration**
```hcl
# Configurable VM sizes for cost optimization
vm_size_web = "Standard_D2s_v3" # 2 cores, 8GB RAM
vm_size_app = "Standard_D4s_v3" # 4 cores, 16GB RAM
vm_size_data = "Standard_D4s_v3" # 4 cores, 16GB RAM
```

### **Network Configuration**
```hcl
# Primary region network (configurable)
primary_vnet_address_space = ["10.0.0.0/16"]
primary_web_subnet_prefix = "10.0.1.0/24"
primary_app_subnet_prefix = "10.0.2.0/24"
primary_data_subnet_prefix = "10.0.3.0/24"

# Secondary region network (configurable)
secondary_vnet_address_space = ["10.1.0.0/16"]
secondary_web_subnet_prefix = "10.1.1.0/24"
secondary_app_subnet_prefix = "10.1.2.0/24"
secondary_data_subnet_prefix = "10.1.3.0/24"
```

### **VMSS Auto-Scaling Configuration**
```hcl
# Enable VMSS with auto-scaling
enable_vmss = true
enable_auto_scaling = true

# Auto-scaling configuration
auto_scaling_config = {
web_tier = {
min_instances = 2
max_instances = 10
default_instances = 3
scale_out_cpu_threshold = 75 # Scale out when CPU > 75%
scale_in_cpu_threshold = 25 # Scale in when CPU < 25%
scale_out_memory_threshold = 80 # Scale out when memory > 80%
scale_in_memory_threshold = 30 # Scale in when memory < 30%
scale_out_cooldown = "PT5M" # 5 minutes
scale_in_cooldown = "PT10M" # 10 minutes
}
app_tier = {
min_instances = 2
max_instances = 8
default_instances = 2
scale_out_cpu_threshold = 70
scale_in_cpu_threshold = 30
scale_out_memory_threshold = 75
scale_in_memory_threshold = 35
scale_out_cooldown = "PT5M"
scale_in_cooldown = "PT15M"
}
}
```

### **VMSS Features**
- **Flexible Orchestration**: Better fault tolerance and mixed instance support
- **Intelligent Scaling**: CPU, memory, and network traffic triggers
- **Time-based Profiles**: Different scaling behaviors for business hours vs. weekends
- **Predictive Scaling**: Machine learning-based scaling for production environments
- **Health Monitoring**: Application health extensions with automatic instance replacement
- **Cost Optimization**: Dynamic scaling reduces costs by 30-50% during off-hours

---

## Security Features

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
- **No hardcoded credentials** - all passwords generated
- **Secure parameter handling** in both Terraform and Bicep
- **SSH access** restricted to private networks only

---

## Monitoring & Health Checks

### **Health Monitoring**
- **Load balancer health probes** for web and app tiers
- **Database replication monitoring** with automated health checks
- **Site Recovery monitoring** with application-consistent snapshots
- **Boot diagnostics** enabled for all VMs

### **Backup Strategy**
- **VM replication** via Azure Site Recovery (RPO: 1 hour)
- **Database backups** automated daily with retention
- **Application-consistent snapshots** every 4 hours
- **Cross-region replication** for all critical data

---

## TARGET Disaster Recovery

### **Recovery Capabilities**
- **RTO Target**: <4 hours for complete failover
- **RPO Target**: <1 hour with continuous replication
- **Automated Failover**: DNS-based with Traffic Manager
- **Data Consistency**: Application-consistent snapshots

### **DR Testing**
```bash
# Test failover procedure
az site-recovery protected-item test-failover \
--resource-group webapp-prod-primary-rg \
--vault-name webapp-prod-rsv \
--fabric-name primary-fabric \
--protection-container primary-protection-container \
--protected-item-name webapp-prod-primary-web-vm-1-replication
```

---

## Management Operations

### **Scaling Operations**
```bash
# Scale VMs (requires VMSS implementation)
terraform apply -var="vm_count=4"

# Update VM sizes for cost optimization
terraform apply -var="vm_size_web=Standard_D1s_v3"
```

### **Backup Operations**
```bash
# Manual backup trigger
az backup protection backup-now \
--resource-group webapp-prod-primary-rg \
--vault-name webapp-prod-rsv \
--container-name primary-vms \
--item-name webapp-prod-primary-web-vm-1
```

### **Monitoring Commands**
```bash
# Check replication health
az site-recovery protected-item show \
--resource-group webapp-prod-primary-rg \
--vault-name webapp-prod-rsv \
--fabric-name primary-fabric \
--protection-container primary-protection-container \
--protected-item-name vm-replication
```

---

## Deployment Outputs

### **Key Endpoints**
```
Global Endpoint: https://<traffic-manager-fqdn>
Primary Endpoint: https://<primary-lb-fqdn>
Secondary Endpoint: https://<secondary-lb-fqdn>
```

### **Management URLs**
```
Traffic Manager: https://portal.azure.com/#@/resource<tm-resource-id>
Recovery Vault: https://portal.azure.com/#@/resource<rsv-resource-id>
Primary RG: https://portal.azure.com/#@/resource<primary-rg-id>
Secondary RG: https://portal.azure.com/#@/resource<secondary-rg-id>
```

---

## Troubleshooting

### **Common Issues**
1. **VM Authentication**: Ensure password meets complexity requirements
2. **Network Connectivity**: Verify NSG rules and subnet routing
3. **Site Recovery**: Check replication status and network mapping
4. **Database Replication**: Monitor MySQL master-slave sync status

### **Validation Commands**
```bash
# Validate Terraform configuration
terraform validate

# Check Azure provider authentication
az account show

# Test network connectivity
az vm run-command invoke \
--resource-group webapp-prod-primary-rg \
--name webapp-prod-primary-web-vm-1 \
--command-id RunShellScript \
--scripts "ping webapp-prod-primary-app-vm-1"
```

---

## Additional Resources

- [Azure Well-Architected Framework](https://docs.microsoft.com/en-us/azure/architecture/framework/)
- [Azure Site Recovery Documentation](https://docs.microsoft.com/en-us/azure/site-recovery/)
- [Terraform Azure Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest)
- [Azure Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)

---

**Last Updated**: $(date)
**Version**: 1.0.0
**Maintainer**: Platform Engineering Team