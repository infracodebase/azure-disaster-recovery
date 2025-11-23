# Virtual Machine Scale Sets (VMSS) Implementation Guide - Bicep

This guide explains how to use the Azure Virtual Machine Scale Sets (VMSS) implementation with auto-scaling capabilities in your multi-tier Azure architecture using Bicep.

## Overview

The Bicep VMSS implementation provides:
- **Flexible orchestration mode** (recommended for modern deployments)
- **CPU and memory-based auto-scaling**
- **Time-based scaling profiles** (business hours, weekends)
- **Network traffic-based scaling** (app tier)
- **Health monitoring** with application health extensions
- **Automatic SSH key generation**

## Architecture

### VMSS Deployment Strategy

- **Web Tier**: Uses Flexible orchestration mode with HTTP health monitoring
- **App Tier**: Uses Flexible orchestration mode with application-specific health checks
- **Data Tier**: Always uses individual VMs (databases require persistent storage and careful scaling)

### Key Features

#### Flexible Orchestration Mode
- Better fault domain distribution across Availability Zones
- Zone-balanced deployment automatically maintained
- Compatible with Azure Load Balancer
- Supports mixed instance sizes (future enhancement)

#### Auto-scaling Profiles
1. **Default Profile**: Standard scaling based on CPU, memory, and network
2. **Weekend Profile**: Conservative scaling for cost optimization
3. **Business Hours Profile**: Aggressive scaling for peak performance

## Configuration

### Enable VMSS in Bicep

Update your `main.bicepparam` file:

```bicep
// VMSS Configuration
param enableVMSS = true          // Enable Virtual Machine Scale Sets
param enableAutoScaling = true   // Enable auto-scaling rules

// Auto-scaling Configuration
param autoScalingConfig = {
  webTier: {
    minInstances: 2
    maxInstances: 10
    defaultInstances: 3
    scaleOutCpuThreshold: 75    // Scale out when CPU > 75%
    scaleInCpuThreshold: 25     // Scale in when CPU < 25%
    scaleOutMemoryThreshold: 80 // Scale out when memory usage > 80%
    scaleInMemoryThreshold: 30  // Scale in when memory usage < 30%
    scaleOutCooldown: 'PT5M'    // 5 minutes
    scaleInCooldown: 'PT10M'    // 10 minutes
  }
  appTier: {
    minInstances: 2
    maxInstances: 8
    defaultInstances: 2
    scaleOutCpuThreshold: 70    // Scale out when CPU > 70%
    scaleInCpuThreshold: 30     // Scale in when CPU < 30%
    scaleOutMemoryThreshold: 75 // Scale out when memory usage > 75%
    scaleInMemoryThreshold: 35  // Scale in when memory usage < 35%
    scaleOutCooldown: 'PT5M'    // 5 minutes
    scaleInCooldown: 'PT15M'    // 15 minutes
  }
}
```

### Deployment Modes

The implementation supports two deployment modes:

#### Mode 1: Individual VMs (Traditional)
```bicep
param enableVMSS = false
```
- Deploys 2 VMs per tier (web, app, data)
- Uses Availability Sets or Zones for high availability
- Fixed capacity with predictable costs

#### Mode 2: VMSS with Auto-scaling
```bicep
param enableVMSS = true
param enableAutoScaling = true
```
- Deploys VMSS for web and app tiers
- Individual VMs for data tier (databases)
- Dynamic scaling based on demand
- Cost optimization through intelligent scaling

## Auto-scaling Rules

### CPU-based Scaling

#### Web Tier
```yaml
Scale-out triggers:
  - CPU > 75% for 5 minutes
  - Action: Add 1 instance
  - Cooldown: 5 minutes

Scale-in triggers:
  - CPU < 25% for 10 minutes
  - Action: Remove 1 instance
  - Cooldown: 10 minutes
```

#### App Tier
```yaml
Scale-out triggers:
  - CPU > 70% for 5 minutes
  - Action: Add 1 instance
  - Cooldown: 5 minutes

Scale-in triggers:
  - CPU < 30% for 15 minutes
  - Action: Remove 1 instance
  - Cooldown: 15 minutes
```

### Memory-based Scaling

#### Web Tier
```yaml
Scale-out triggers:
  - Available memory < 1GB for 5 minutes
  - Action: Add 1 instance

Scale-in triggers:
  - Available memory > 2GB for 10 minutes
  - Action: Remove 1 instance
```

#### App Tier
```yaml
Scale-out triggers:
  - Available memory < 768MB for 5 minutes
  - Action: Add 1 instance

Scale-in triggers:
  - Available memory > 2.5GB for 15 minutes
  - Action: Remove 1 instance
```

### Network Traffic Scaling (App Tier Only)

```yaml
Scale-out triggers:
  - Network In > 50MB for 5 minutes
  - Action: Add 1 instance
  - Cooldown: 5 minutes
```

### Time-based Scaling Profiles

#### Weekend Profile (Web Tier)
- **Schedule**: Saturday-Sunday
- **CPU Threshold**: 80% (conservative)
- **Cooldown**: 10-15 minutes (longer for cost optimization)
- **Default Capacity**: Minimum instances

#### Business Hours Profile (App Tier)
- **Schedule**: Monday-Friday, 9 AM UTC
- **CPU Threshold**: 60% (aggressive)
- **Cooldown**: 3 minutes (faster response)
- **Enhanced scaling during peak hours**

## Health Monitoring

### Application Health Extensions

The implementation includes automatic health monitoring:

#### Web Tier Health Check
```bicep
settings: {
  protocol: 'http'
  port: 80
  requestPath: '/'
}
```

#### App Tier Health Check
```bicep
settings: {
  protocol: 'http'
  port: 80
  requestPath: '/health'
}
```

### Health Extension Benefits
- **Automatic Instance Replacement**: Unhealthy instances are automatically replaced
- **Load Balancer Integration**: Only healthy instances receive traffic
- **Scaling Decision Input**: Health status influences scaling decisions

## Deployment Options

### Option 1: Deploy with VMSS Enabled

```bash
# 1. Navigate to Bicep implementation
cd bicep-implementation/

# 2. Update parameters to enable VMSS
# Edit main.bicepparam:
# enableVMSS = true
# enableAutoScaling = true

# 3. Deploy to Azure
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters vmAdminPassword='YourSecurePassword123!'
```

### Option 2: Deploy Individual VMs (Traditional)

```bash
# 1. Keep VMSS disabled in main.bicepparam
# enableVMSS = false

# 2. Deploy to Azure
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters vmAdminPassword='YourSecurePassword123!'
```

### Expected Deployment Time
- **Individual VMs**: 25-35 minutes
- **VMSS with Auto-scaling**: 35-45 minutes
- **Complete multi-region**: 45-60 minutes

## Security Features

### SSH Key Management
- **Automatic Generation**: SSH keys generated during deployment
- **Secure Storage**: Private keys stored in deployment script outputs
- **No Hardcoded Keys**: No SSH keys embedded in templates

### Network Security
- **NSG Integration**: VMSS instances inherit subnet NSG rules
- **Load Balancer Security**: Only load balancer can reach VMSS instances
- **Internal Communication**: App tier accessible only from web tier

### Password Security
- **Secure Parameters**: VM passwords marked as @secure()
- **No Plaintext Storage**: Passwords not stored in deployment outputs
- **Complex Requirements**: Azure-enforced password complexity

## Monitoring and Observability

### Built-in Metrics

The implementation provides extensive monitoring:

#### Auto-scaling Metrics
- Scale-out/Scale-in events
- Scaling trigger reasons
- Instance count over time
- Scaling rule effectiveness

#### Performance Metrics
- CPU utilization per instance
- Memory usage per instance
- Network throughput
- Application response times

#### Health Metrics
- Healthy instance count
- Failed health checks
- Instance replacement rate

### Azure Monitor Integration

```bicep
notifications: [
  {
    operation: 'Scale'
    email: {
      sendToSubscriptionAdministrator: false
      sendToSubscriptionCoAdministrators: false
      customEmails: []
    }
    webhooks: []
  }
]
```

## Cost Optimization

### VMSS Cost Benefits

| Scenario | Individual VMs | VMSS with Auto-scaling | Savings |
|----------|----------------|------------------------|---------|
| Off-hours | 6 VMs running | 4 VMs running (min) | 33% |
| Weekend | 6 VMs running | 4 VMs running | 33% |
| Variable load | 6 VMs running | 4-12 VMs (dynamic) | 40-60% |
| Peak hours | 6 VMs running | 8-12 VMs (scaled up) | Better performance |

### Cost Optimization Features

#### Dynamic Scaling
- **Automatic Scale-in**: Reduces instances during low demand
- **Time-based Profiles**: Different scaling behavior for business vs. off hours
- **Conservative Weekend Scaling**: Reduced sensitivity during weekends

#### Instance Optimization
- **Flexible Orchestration**: Better VM placement for cost efficiency
- **Zone Distribution**: Optimal distribution across availability zones
- **Premium Storage**: High-performance storage with cost monitoring

### Expected Monthly Costs

| Component | Individual VMs | VMSS (Average) | VMSS (Peak) |
|-----------|----------------|----------------|-------------|
| Compute | $800-900/month | $550-650/month | $900-1200/month |
| Storage | $120-150/month | $120-150/month | $150-200/month |
| Networking | $50-80/month | $50-80/month | $80-120/month |
| **Total** | **$970-1130/month** | **$720-880/month** | **$1130-1520/month** |

*Savings of 25-40% during normal operations*

## Best Practices

### Scaling Configuration

#### Conservative Scale-in
```bicep
scaleInCooldown: 'PT15M'  // Longer cooldowns prevent flapping
scaleInCpuThreshold: 25   // Lower threshold for conservative scale-in
```

#### Aggressive Scale-out
```bicep
scaleOutCooldown: 'PT5M'  // Quick response to load increases
scaleOutCpuThreshold: 75  // Reasonable threshold for scale-out
```

#### Memory Thresholds
```bicep
scaleOutMemoryThreshold: 80  // Scale out before memory exhaustion
scaleInMemoryThreshold: 30   // Conservative scale-in based on memory
```

### Deployment Best Practices

#### Pre-deployment
1. **Validate Parameters**: Ensure all scaling thresholds are reasonable
2. **Check Quotas**: Verify VM quota limits for max instances
3. **Network Planning**: Ensure subnet has sufficient IP addresses
4. **Testing Strategy**: Plan for gradual rollout and testing

#### Post-deployment
1. **Monitor Scaling**: Watch initial scaling behavior
2. **Tune Thresholds**: Adjust based on actual application behavior
3. **Cost Tracking**: Monitor costs during different scaling scenarios
4. **Performance Testing**: Load test to validate scaling effectiveness

### Security Best Practices

#### SSH Access
```bash
# Retrieve SSH private key (sensitive operation)
az deployment sub show \
  --name primaryRegionDeployment \
  --query 'properties.outputs.vmssDeploymentSummary.value' \
  --output json
```

#### Password Management
```bash
# Use Azure Key Vault for password storage
az deployment sub create \
  --parameters vmAdminPassword='@Microsoft.KeyVault(SecretUri=https://vault.vault.azure.net/secrets/vm-password/version)'
```

## Troubleshooting

### Common Issues

#### Scaling Not Triggering
**Symptoms**: VMSS not scaling despite load
**Solutions**:
1. Check metric collection is working
2. Verify threshold values are appropriate
3. Review cooldown periods
4. Check Azure Monitor logs

#### Too Aggressive Scaling
**Symptoms**: Frequent scale-out/scale-in cycles
**Solutions**:
1. Increase cooldown periods
2. Adjust thresholds (wider gap between scale-out/scale-in)
3. Implement time-based profiles
4. Add more metrics for scaling decisions

#### Health Check Failures
**Symptoms**: Instances marked unhealthy
**Solutions**:
1. Verify application endpoints are responding
2. Check NSG rules allow health check traffic
3. Review application logs for errors
4. Validate health check paths

#### Deployment Failures
**Symptoms**: Bicep deployment fails
**Solutions**:
1. Check parameter validation
2. Verify resource quotas
3. Review deployment error details
4. Check subnet IP address availability

### Diagnostic Commands

#### Check VMSS Status
```bash
# List VMSS in resource group
az vmss list --resource-group <resource-group> --output table

# Get VMSS details
az vmss show --resource-group <rg> --name <vmss-name>

# Check instance health
az vmss list-instances --resource-group <rg> --name <vmss-name> --output table
```

#### Monitor Auto-scaling
```bash
# List autoscale settings
az monitor autoscale list --resource-group <rg> --output table

# Get autoscale setting details
az monitor autoscale show --resource-group <rg> --name <autoscale-name>

# View autoscale history
az monitor activity-log list --resource-group <rg> --caller "Microsoft.Insights/AutoscaleSettings"
```

#### Manual Scaling (Testing)
```bash
# Scale VMSS manually
az vmss scale --resource-group <rg> --name <vmss-name> --new-capacity 5

# Update autoscale settings
az monitor autoscale update --resource-group <rg> --name <autoscale-name> --count 3
```

### Performance Monitoring

#### Key Metrics to Track
1. **Instance Count**: Track scaling events and instance counts
2. **CPU Utilization**: Monitor per-instance and aggregate CPU usage
3. **Memory Usage**: Track memory consumption patterns
4. **Network Throughput**: Monitor traffic patterns
5. **Application Response Time**: Track end-to-end performance

#### Monitoring Queries
```kql
// Auto-scaling events
AzureActivity
| where Category == "Autoscale"
| where ResourceGroup == "your-resource-group"
| project TimeGenerated, OperationName, ActivityStatus, Properties

// VMSS performance metrics
AzureMetrics
| where ResourceProvider == "MICROSOFT.COMPUTE"
| where MetricName in ("Percentage CPU", "Available Memory Bytes")
| where Resource contains "vmss"
```

## Migration Guide

### From Individual VMs to VMSS

#### Step 1: Backup and Plan
```bash
# Export current deployment
az deployment sub export --name <deployment-name> > current-deployment.json

# Review current VM configuration
az vm list --resource-group <rg> --output table
```

#### Step 2: Update Parameters
```bicep
// Update main.bicepparam
param enableVMSS = true
param enableAutoScaling = true
```

#### Step 3: Deploy Migration
```bash
# Deploy updated template
az deployment sub create \
  --location "East US" \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters vmAdminPassword='YourSecurePassword123!'
```

#### Step 4: Validate Migration
```bash
# Check VMSS deployment
az vmss list --resource-group <rg> --output table

# Verify autoscale settings
az monitor autoscale list --resource-group <rg> --output table

# Test application endpoints
curl https://<load-balancer-fqdn>/
```

### Migration Considerations

#### Data Persistence
- **Web/App Tiers**: Stateless, safe to migrate
- **Data Tier**: Always individual VMs, no migration needed
- **Custom Data**: Backup any custom configurations

#### Downtime Planning
- **Planned Maintenance Window**: 15-30 minutes
- **Blue-Green Deployment**: Deploy to new resource group first
- **Rolling Update**: Gradual migration with load balancer updates

## Advanced Configuration

### Custom Metrics
You can extend auto-scaling with custom application metrics:

```bicep
// Example custom metric rule
{
  metricTrigger: {
    metricName: 'Custom/DatabaseConnections'
    metricNamespace: 'Application'
    operator: 'GreaterThan'
    threshold: 80
  }
  scaleAction: {
    direction: 'Increase'
    type: 'ChangeCount'
    value: '1'
    cooldown: 'PT5M'
  }
}
```

### Multi-region VMSS
The implementation supports multi-region deployments:
- **Primary Region**: Active VMSS with full auto-scaling
- **Secondary Region**: Disaster recovery region (VMSS disabled by default)
- **Cross-region Failover**: Manual activation of secondary region VMSS

## Support and Documentation

### External Resources
- [Azure Virtual Machine Scale Sets Documentation](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [Azure Autoscale Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/autoscale/)
- [Bicep Documentation](https://docs.microsoft.com/en-us/azure/azure-resource-manager/bicep/)
- [Azure Load Balancer with VMSS](https://docs.microsoft.com/en-us/azure/load-balancer/load-balancer-standard-virtual-machine-scale-sets)

### Internal Documentation
- [../terraform-implementation/VMSS_GUIDE.md](../terraform-implementation/VMSS_GUIDE.md) - Terraform VMSS implementation
- [../cost-analysis/COST_BREAKDOWN.md](../cost-analysis/COST_BREAKDOWN.md) - Detailed cost analysis
- [../security-compliance/SECURITY_ANALYSIS.md](../security-compliance/SECURITY_ANALYSIS.md) - Security assessment

---

**Ready for production deployment with enterprise-grade auto-scaling! 🚀**