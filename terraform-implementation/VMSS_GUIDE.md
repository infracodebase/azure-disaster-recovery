# Virtual Machine Scale Sets (VMSS) Implementation Guide

This guide explains how to use the Azure Virtual Machine Scale Sets (VMSS) implementation with auto-scaling capabilities in your multi-tier Azure architecture.

## Overview

The VMSS implementation provides:
- **Flexible and Uniform orchestration modes**
- **CPU and memory-based auto-scaling**
- **Time-based scaling profiles** (business hours, weekends)
- **Predictive scaling** for production environments
- **Health monitoring** with application health extensions
- **Network traffic-based scaling**

## Architecture

### VMSS Deployment Strategy

- **Web Tier**: Uses Flexible orchestration mode (recommended for new deployments)
- **App Tier**: Configurable between Flexible and Uniform modes
- **Data Tier**: Always uses individual VMs (databases require persistent storage and careful scaling)

### Orchestration Modes

#### Flexible Mode (Recommended)
- Better fault domain distribution
- Mixed instance sizes support
- Zone-balanced deployment
- Compatible with Azure Load Balancer and Application Gateway

#### Uniform Mode (Legacy)
- Traditional scaling model
- Identical VM instances
- Automatic OS upgrade support
- Suitable for stateless applications

## Configuration

### Enable VMSS

Set the following variables in your `terraform.tfvars`:

```hcl
enable_vmss             = true
vmss_orchestration_mode = "Flexible"
enable_auto_scaling     = true
```

### Auto-scaling Configuration

```hcl
auto_scaling_config = {
  web_tier = {
    min_instances               = 2      # Minimum instances
    max_instances               = 10     # Maximum instances
    default_instances           = 3      # Default/starting instances
    scale_out_cpu_threshold     = 75     # Scale out when CPU > 75%
    scale_in_cpu_threshold      = 25     # Scale in when CPU < 25%
    scale_out_memory_threshold  = 80     # Scale out when memory > 80%
    scale_in_memory_threshold   = 30     # Scale in when memory < 30%
    scale_out_cooldown          = "PT5M" # 5 minute cooldown for scale-out
    scale_in_cooldown           = "PT10M"# 10 minute cooldown for scale-in
  }
  app_tier = {
    min_instances               = 2
    max_instances               = 8
    default_instances           = 2
    scale_out_cpu_threshold     = 70
    scale_in_cpu_threshold      = 30
    scale_out_memory_threshold  = 75
    scale_in_memory_threshold   = 35
    scale_out_cooldown          = "PT5M"
    scale_in_cooldown           = "PT15M"
  }
}
```

## Auto-scaling Profiles

### 1. Default Profile
- **Purpose**: Standard auto-scaling behavior
- **CPU Thresholds**: Configurable scale-out/scale-in thresholds
- **Memory Thresholds**: Available memory byte-based scaling
- **Network Scaling**: High network traffic triggers (App tier only)

### 2. Business Hours Profile (App Tier)
- **Schedule**: Monday-Friday, 9 AM UTC
- **Behavior**: More aggressive scaling with lower thresholds
- **CPU Threshold**: 60% (lower for faster response)
- **Faster Cooldown**: 3-minute scale-out cooldown

### 3. Weekend Profile (Web Tier)
- **Schedule**: Saturday-Sunday
- **Behavior**: Reduced sensitivity, cost optimization
- **CPU Threshold**: 80% (higher threshold)
- **Longer Cooldown**: 10-15 minute cooldowns

### 4. Predictive Scaling (Production)
- **Availability**: Production environments only
- **Look-ahead**: 10 minutes
- **Mode**: Enabled (automatic scaling based on predictions)

## Scaling Rules

### CPU-based Scaling

```yaml
Scale-out triggers:
  - CPU > threshold for 5 minutes
  - Action: Add 1 instance
  - Cooldown: 5 minutes

Scale-in triggers:
  - CPU < threshold for 5-15 minutes (tier dependent)
  - Action: Remove 1 instance
  - Cooldown: 10-15 minutes (longer to prevent flapping)
```

### Memory-based Scaling

```yaml
Scale-out triggers:
  - Available memory < 1GB (Web) / 768MB (App)
  - Evaluation: 5 minutes
  - Action: Add 1 instance

Scale-in triggers:
  - Available memory > 2GB (Web) / 2.5GB (App)
  - Evaluation: 10-15 minutes
  - Action: Remove 1 instance
```

### Network Traffic Scaling (App Tier)

```yaml
Scale-out triggers:
  - Network In > 50MB for 5 minutes
  - Action: Add 1 instance
  - Cooldown: 5 minutes
```

## Health Monitoring

### Application Health Extensions

**Web Tier:**
```json
{
  "protocol": "http",
  "port": 80,
  "requestPath": "/"
}
```

**App Tier:**
```json
{
  "protocol": "http",
  "port": 80,
  "requestPath": "/health"
}
```

## Deployment Options

### Option 1: Enable VMSS for New Deployment

```bash
# Copy example configuration
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars
enable_vmss = true
enable_auto_scaling = true

# Deploy infrastructure
terraform plan
terraform apply
```

### Option 2: Migrate Existing VMs to VMSS

```bash
# Enable VMSS in existing deployment
# Note: This requires careful migration planning

# 1. Enable VMSS
enable_vmss = true

# 2. Plan the migration
terraform plan

# 3. Apply changes (VMs will be replaced with VMSS)
terraform apply
```

## Monitoring and Observability

### Key Metrics to Monitor

1. **Auto-scaling Events**
   - Scale-out/Scale-in frequency
   - Scaling triggers and reasons
   - Instance count over time

2. **Performance Metrics**
   - CPU utilization per instance
   - Memory usage per instance
   - Network throughput
   - Application response times

3. **Health Metrics**
   - Healthy instance count
   - Failed health checks
   - Instance replacement rate

### Azure Monitor Integration

The implementation includes:
- **Auto-scale setting notifications**
- **Custom metrics for scaling decisions**
- **Integration with Azure Monitor logs**

## Best Practices

### Scaling Configuration

1. **Conservative Scale-in**: Use longer cooldowns for scale-in to prevent flapping
2. **Metric Combination**: Use both CPU and memory metrics for better scaling decisions
3. **Time-based Profiles**: Configure different profiles for business hours vs off-hours
4. **Instance Limits**: Set appropriate min/max instances based on your traffic patterns

### Cost Optimization

1. **Weekend Scaling**: Reduce instance counts during low-traffic periods
2. **Predictive Scaling**: Enable for cost-effective pre-scaling in production
3. **Instance Sizes**: Use appropriate VM sizes (D2s_v3 for web, D4s_v3 for app)
4. **Zone Distribution**: Use Flexible mode for better fault tolerance

### Security

1. **SSH Keys**: Auto-generated SSH keys for secure access
2. **Network Security**: NSG rules maintained for each tier
3. **Load Balancer Integration**: Automatic backend pool configuration
4. **Health Probes**: Application-level health monitoring

## Troubleshooting

### Common Issues

1. **Scaling Not Triggering**
   - Check metric thresholds
   - Verify cooldown periods
   - Review Azure Monitor logs

2. **Too Aggressive Scaling**
   - Increase thresholds
   - Extend cooldown periods
   - Add time-based profiles

3. **Health Check Failures**
   - Verify application endpoints
   - Check NSG rules
   - Review application logs

### Useful Commands

```bash
# View VMSS status
az vmss list --output table

# Check scaling activity
az monitor autoscale-setting list --resource-group <rg-name>

# View instance health
az vmss list-instances --resource-group <rg-name> --name <vmss-name>

# Manual scaling for testing
az vmss scale --resource-group <rg-name> --name <vmss-name> --new-capacity 5
```

## Cost Considerations

### VMSS vs Individual VMs

| Feature | Individual VMs | VMSS |
|---------|---------------|------|
| Base Cost | Fixed (2 VMs per tier) | Variable (2-10 instances) |
| Auto-scaling | Not available | Automatic cost optimization |
| High Availability | Manual setup | Built-in fault tolerance |
| Management Overhead | Higher | Lower |
| Predictable Costs | Yes | No (varies with load) |

### Expected Cost Savings

- **Off-hours scaling**: 30-50% cost reduction during low traffic
- **Weekend scaling**: 20-30% cost reduction on weekends
- **Traffic-based scaling**: 40-60% cost optimization during variable loads
- **Predictive scaling**: 15-25% additional savings in production

## Migration Guide

### From Individual VMs to VMSS

1. **Backup Current State**
   ```bash
   terraform plan -out=current.tfplan
   ```

2. **Update Configuration**
   ```bash
   # Set in terraform.tfvars
   enable_vmss = true
   enable_auto_scaling = true
   ```

3. **Plan Migration**
   ```bash
   terraform plan
   # Review the changes - VMs will be destroyed and VMSS created
   ```

4. **Execute Migration**
   ```bash
   terraform apply
   # Confirm the migration
   ```

5. **Verify Deployment**
   ```bash
   # Check VMSS status
   az vmss show --resource-group <rg> --name <vmss-name>

   # Test auto-scaling
   az monitor autoscale-setting show --resource-group <rg> --name <autoscale-name>
   ```

## Advanced Configuration

### Custom Metrics

You can extend the auto-scaling rules with custom application metrics:

```hcl
# Example: Database connection pool utilization
rule {
  metric_trigger {
    metric_name        = "ConnectionPoolUtilization"
    metric_namespace   = "Custom/Application"
    operator           = "GreaterThan"
    threshold          = 80
    time_aggregation   = "Average"
    time_grain         = "PT1M"
    time_window        = "PT5M"
  }

  scale_action {
    direction = "Increase"
    type      = "ChangeCount"
    value     = "1"
    cooldown  = "PT5M"
  }
}
```

### Multi-region VMSS

The implementation supports multi-region deployments:
- Primary region: Active VMSS with auto-scaling
- Secondary region: Standby mode (can be activated for DR)

## Support and Documentation

- [Azure VMSS Documentation](https://docs.microsoft.com/en-us/azure/virtual-machine-scale-sets/)
- [Azure Auto-scale Documentation](https://docs.microsoft.com/en-us/azure/azure-monitor/autoscale/)
- [Terraform AzureRM Provider](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs)