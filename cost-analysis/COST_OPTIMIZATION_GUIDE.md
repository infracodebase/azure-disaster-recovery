# Azure Cost Optimization Guide
## Multi-Tier Disaster Recovery Architecture

**Optimization Target:** Reduce monthly costs from $2,180 to $1,500 (31% reduction)
**Timeline:** 3-6 months implementation
**ROI Target:** $8,160 annual savings

---

## 🎯 Immediate Cost Optimizations (0-30 days)

### **1. Reserved Instances Strategy**
**Potential Savings: $336/month (20-40% VM cost reduction)**

```yaml
Implementation Plan:
  Week 1: Analyze VM utilization patterns
  Week 2: Purchase 1-year RIs for production VMs
  Week 3: Configure auto-renewal policies
  Week 4: Monitor and validate savings

Reserved Instance Recommendations:
  Primary Region VMs (3x):
    - Standard_D2s_v3: 1-year RI → Save $14-28/month
    - Standard_D4s_v3: 1-year RI → Save $28-56/month each

  Secondary Region VMs (3x):
    - Standard_D2s_v3: 1-year RI → Save $7-14/month
    - Standard_D4s_v3: 1-year RI → Save $14-28/month each

Total RI Savings: $84-168/month per region
Annual Savings: $2,016-4,032
```

### **2. Storage Tier Optimization**
**Potential Savings: $53/month (20-30% storage cost reduction)**

```bash
# Storage optimization script
az storage account update \
  --name "cachestorage" \
  --access-tier Cool \
  --replication-type LRS

# Lifecycle management policy
{
  "rules": [
    {
      "name": "ArchiveOldSnapshots",
      "type": "Lifecycle",
      "definition": {
        "filters": {
          "blobTypes": ["blockBlob"]
        },
        "actions": {
          "baseBlob": {
            "tierToCool": {"daysAfterModificationGreaterThan": 30},
            "tierToArchive": {"daysAfterModificationGreaterThan": 90}
          }
        }
      }
    }
  ]
}
```

### **3. Network Traffic Optimization**
**Potential Savings: $25/month (30-45% bandwidth cost reduction)**

```yaml
Optimization Actions:
  CDN Implementation:
    - Azure CDN for static content
    - Reduce origin bandwidth by 60-80%
    - Monthly savings: $15-35

  Compression Enable:
    - Enable gzip compression on load balancers
    - Reduce traffic by 20-30%
    - Monthly savings: $5-15

  Regional Optimization:
    - Keep database replicas in same availability zone
    - Reduce cross-AZ charges
    - Monthly savings: $5-10
```

---

## ⚡ Auto-Scaling Implementation (30-60 days)

### **4. VM Auto-Scaling Configuration**
**Potential Savings: $315/month (30-60% compute cost reduction)**

```terraform
# Auto-scaling configuration
resource "azurerm_monitor_autoscale_setting" "web_tier" {
  name                = "web-tier-autoscale"
  resource_group_name = var.resource_group_name
  location           = var.location
  target_resource_id = azurerm_virtual_machine_scale_set.web.id

  profile {
    name = "default"

    capacity {
      default = 2
      minimum = 1
      maximum = 4
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator          = "GreaterThan"
        threshold         = 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_virtual_machine_scale_set.web.id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator          = "LessThan"
        threshold         = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }
}
```

### **5. Scheduled Shutdown/Startup**
**Potential Savings: $263/month (25% compute cost reduction)**

```bash
#!/bin/bash
# Auto-shutdown script for non-production hours

# Shutdown schedule (9 PM - 6 AM, Weekends)
az vm deallocate \
  --resource-group webapp-prod-primary-rg \
  --name webapp-prod-primary-web-vm-1 \
  --no-wait

az vm deallocate \
  --resource-group webapp-prod-primary-rg \
  --name webapp-prod-primary-app-vm-1 \
  --no-wait

# Startup schedule (6 AM weekdays)
az vm start \
  --resource-group webapp-prod-primary-rg \
  --name webapp-prod-primary-web-vm-1 \
  --no-wait

# Schedule via Azure Automation
{
  "schedule": {
    "shutdown": "21:00",
    "startup": "06:00",
    "timezone": "Eastern Standard Time",
    "weekdays_only": true
  }
}
```

---

## 🔄 Architecture Optimizations (60-120 days)

### **6. Container Migration Strategy**
**Potential Savings: $400/month (38% compute cost reduction)**

```yaml
Migration Plan:
  Phase 1: Web Tier Containerization (Month 2)
    - Convert web VMs to Azure Container Instances
    - Implement Azure Container Apps for auto-scaling
    - Expected savings: $150/month

  Phase 2: App Tier Microservices (Month 3)
    - Break app tier into microservices
    - Deploy on Azure Kubernetes Service (AKS)
    - Expected savings: $200/month

  Phase 3: Database Optimization (Month 4)
    - Migrate to Azure Database for MySQL
    - Implement read replicas instead of full VMs
    - Expected savings: $50/month

Container Cost Comparison:
  Current VM Cost: $1,050/month
  Container Cost: $650/month
  Net Savings: $400/month (38% reduction)
```

### **7. Serverless Migration Options**
**Potential Savings: $300/month (variable workload optimization)**

```typescript
// Azure Functions implementation example
import { AzureFunction, Context, HttpRequest } from "@azure/functions";

const httpTrigger: AzureFunction = async function (
  context: Context,
  req: HttpRequest
): Promise<void> {
  // API logic here - only pay when invoked
  context.res = {
    status: 200,
    body: "Response from serverless function"
  };
};

// Cost comparison:
// VM (24/7): $280/month
// Functions (typical load): $50/month
// Savings: $230/month per migrated component
```

---

## 📊 Cost Monitoring & Governance

### **8. Azure Cost Management Setup**
**Implementation: Week 1**

```bash
# Create cost budget with alerts
az consumption budget create \
  --resource-group webapp-prod-primary-rg \
  --budget-name "monthly-budget" \
  --amount 1500 \
  --time-grain Monthly \
  --start-date 2024-01-01 \
  --end-date 2025-12-31

# Cost anomaly detection
az monitor metrics alert create \
  --name "cost-spike-alert" \
  --resource-group webapp-prod-primary-rg \
  --scopes "/subscriptions/{subscription-id}" \
  --condition "Total Cost > 2000" \
  --description "Alert when monthly cost exceeds budget"
```

### **9. Resource Tagging for Cost Allocation**
**Implementation: Week 2**

```terraform
# Comprehensive tagging strategy
locals {
  common_tags = {
    Environment    = var.environment
    Project       = "webapp-dr"
    CostCenter    = "infrastructure"
    Owner         = "platform-team"
    CreatedBy     = "terraform"
    LastModified  = timestamp()

    # Cost allocation tags
    Application   = "web-application"
    Tier          = var.tier
    Region        = var.region_suffix
    BackupPolicy  = "standard"

    # Optimization tags
    AutoShutdown  = var.environment == "dev" ? "enabled" : "disabled"
    RIEligible    = var.environment == "prod" ? "yes" : "no"
    CriticalityLevel = var.tier == "data" ? "high" : "medium"
  }
}

# Apply to all resources
resource "azurerm_linux_virtual_machine" "web" {
  # ... other configuration
  tags = merge(local.common_tags, {
    Tier = "web"
    Function = "frontend"
  })
}
```

---

## 💰 Environment-Specific Optimizations

### **Development Environment (60% cost reduction)**
```yaml
Development Optimizations:
  VM Sizes: Use B-series burstable VMs
    - B2s instead of D2s_v3: Save $45/month per VM
    - B4ms instead of D4s_v3: Save $180/month per VM

  Storage: Standard SSD instead of Premium
    - Save 50-60% on storage costs
    - Monthly savings: $90-110

  Networking: Basic Load Balancer
    - Save $15-20 per load balancer
    - Monthly savings: $60-80

  Site Recovery: Disabled for dev
    - Save entire ASR cost: $175/month

Total Dev Savings: $560-735/month (60-70% reduction)
```

### **Staging Environment (40% cost reduction)**
```yaml
Staging Optimizations:
  Reduced Capacity: 1 VM per tier instead of 2
    - Save 50% VM costs: $262-525/month

  Standard Storage: Mix of Standard and Premium SSD
    - Save 30% storage costs: $55-77/month

  Limited Site Recovery: Weekly snapshots only
    - Save 60% ASR costs: $105/month

Total Staging Savings: $422-707/month (40-50% reduction)
```

---

## 🎯 Cost Optimization Roadmap

### **Month 1: Quick Wins**
- [ ] Purchase Reserved Instances (Production VMs)
- [ ] Implement storage lifecycle management
- [ ] Enable cost budgets and alerts
- [ ] Optimize network traffic with CDN

**Target Savings: $200-300/month**

### **Month 2: Auto-Scaling**
- [ ] Implement VM auto-scaling rules
- [ ] Deploy scheduled shutdown/startup
- [ ] Optimize database backup retention
- [ ] Review and righsize VM SKUs

**Target Savings: $400-500/month**

### **Month 3: Architecture Changes**
- [ ] Begin container migration (Web tier)
- [ ] Implement Azure Database for MySQL
- [ ] Deploy application performance monitoring
- [ ] Optimize cross-region replication

**Target Savings: $600-700/month**

### **Month 4: Advanced Optimizations**
- [ ] Complete container migration
- [ ] Implement serverless functions
- [ ] Deploy Azure Policy for cost governance
- [ ] Optimize disaster recovery strategy

**Target Savings: $800-1,000/month**

---

## 📋 Cost Optimization Checklist

### **Immediate Actions (This Week)**
- [ ] Enable Azure Cost Management
- [ ] Set up cost alerts and budgets
- [ ] Analyze VM utilization patterns
- [ ] Review storage access patterns
- [ ] Implement resource tagging strategy

### **Short Term (30 days)**
- [ ] Purchase Reserved Instances
- [ ] Configure storage lifecycle policies
- [ ] Enable CDN for static content
- [ ] Implement auto-shutdown for dev/test

### **Medium Term (90 days)**
- [ ] Deploy auto-scaling rules
- [ ] Migrate to container services
- [ ] Optimize database architecture
- [ ] Implement cost governance policies

### **Long Term (6+ months)**
- [ ] Evaluate serverless migration
- [ ] Consider hybrid cloud options
- [ ] Implement advanced monitoring
- [ ] Regular cost optimization reviews

---

## 🏆 Success Metrics

### **Cost Reduction Targets**
| Timeline | Current Cost | Target Cost | Savings | Reduction % |
|----------|-------------|-------------|---------|-------------|
| **Month 1** | $2,180 | $1,880 | $300 | 14% |
| **Month 3** | $2,180 | $1,680 | $500 | 23% |
| **Month 6** | $2,180 | $1,500 | $680 | 31% |
| **Year 1** | $2,180 | $1,300 | $880 | 40% |

### **Key Performance Indicators**
- Monthly cost variance < 5%
- Reserved Instance utilization > 90%
- Auto-scaling effectiveness > 80%
- Storage optimization ratio > 25%
- Network optimization > 30%

### **Annual Savings Target: $8,160**
**ROI on optimization effort: 300-500%**

---

*Cost optimization is an ongoing process. Regular reviews and adjustments ensure continued savings and optimal resource utilization.*