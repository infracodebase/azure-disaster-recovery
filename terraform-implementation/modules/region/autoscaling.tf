# Auto-scaling Configuration for Virtual Machine Scale Sets
# This file contains auto-scaling rules and policies for VMSS

# Auto-scaling settings for Web Tier VMSS
resource "azurerm_monitor_autoscale_setting" "web" {
  count               = var.enable_vmss && var.enable_auto_scaling && !var.is_dr_region ? 1 : 0
  name                = "${var.project_name}-${var.environment}-${var.region_suffix}-web-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web[0].id

  # Default profile for auto-scaling
  profile {
    name = "default"

    capacity {
      default = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.default_instances : 2
      minimum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.min_instances : 2
      maximum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.max_instances : 10
    }

    # Scale-out rule based on CPU percentage
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_out_cpu_threshold : 75
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_out_cooldown : "PT5M"
      }
    }

    # Scale-in rule based on CPU percentage
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_in_cpu_threshold : 25
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_in_cooldown : "PT10M"
      }
    }

    # Scale-out rule based on Memory percentage
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 1073741824 # 1GB in bytes - indicates high memory usage
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_out_cooldown : "PT5M"
      }
    }

    # Scale-in rule based on Memory percentage
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 2147483648 # 2GB in bytes - indicates low memory usage
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.scale_in_cooldown : "PT10M"
      }
    }
  }

  # Weekend profile - different scaling during weekends
  profile {
    name = "weekend"

    capacity {
      default = var.auto_scaling_config.web_tier != null ? max(var.auto_scaling_config.web_tier.default_instances - 1, var.auto_scaling_config.web_tier.min_instances) : 2
      minimum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.min_instances : 2
      maximum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.max_instances : 10
    }

    recurrence {
      timezone = "UTC"
      days     = ["Saturday", "Sunday"]
      hours    = [0]
      minutes  = [0]
    }

    # Reduced sensitivity during weekends
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 80 # Higher threshold on weekends
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M" # Longer cooldown on weekends
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 20 # Lower threshold on weekends
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT15M" # Longer cooldown on weekends
      }
    }
  }

  # Notification configuration
  notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = []
    }
  }

  tags = merge(var.tags, {
    Tier         = "Web"
    ResourceType = "AutoScale"
  })

  depends_on = [azurerm_linux_virtual_machine_scale_set.web]
}

# Auto-scaling settings for App Tier VMSS
resource "azurerm_monitor_autoscale_setting" "app" {
  count               = var.enable_vmss && var.enable_auto_scaling && !var.is_dr_region ? 1 : 0
  name                = "${var.project_name}-${var.environment}-${var.region_suffix}-app-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.app[0].id

  # Default profile for auto-scaling
  profile {
    name = "default"

    capacity {
      default = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.default_instances : 2
      minimum = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.min_instances : 2
      maximum = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.max_instances : 8
    }

    # Scale-out rule based on CPU percentage
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_out_cpu_threshold : 70
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_out_cooldown : "PT5M"
      }
    }

    # Scale-in rule based on CPU percentage
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_in_cpu_threshold : 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_in_cooldown : "PT15M"
      }
    }

    # Scale-out rule based on Memory usage
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 805306368 # 768MB in bytes - indicates high memory usage
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_out_cooldown : "PT5M"
      }
    }

    # Scale-in rule based on Memory usage
    rule {
      metric_trigger {
        metric_name        = "Available Memory Bytes"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT15M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 2684354560 # 2.5GB in bytes - indicates low memory usage
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.scale_in_cooldown : "PT15M"
      }
    }

    # Custom metric rule - Network In (for traffic-based scaling)
    rule {
      metric_trigger {
        metric_name        = "Network In Total"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 52428800 # 50MB in bytes - high network traffic
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT5M"
      }
    }
  }

  # Business hours profile - more aggressive scaling during business hours
  profile {
    name = "business_hours"

    capacity {
      default = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.default_instances + 1 : 3
      minimum = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.min_instances : 2
      maximum = var.auto_scaling_config.app_tier != null ? var.auto_scaling_config.app_tier.max_instances : 8
    }

    recurrence {
      timezone = "UTC"
      days     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
      hours    = [9]  # 9 AM UTC
      minutes  = [0]
    }

    # More aggressive scaling during business hours
    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT3M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 60 # Lower threshold during business hours
      }

      scale_action {
        direction = "Increase"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT3M" # Faster scaling during business hours
      }
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.app[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 35
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  # Notification configuration
  notification {
    email {
      send_to_subscription_administrator    = false
      send_to_subscription_co_administrator = false
      custom_emails                         = []
    }
  }

  tags = merge(var.tags, {
    Tier         = "Application"
    ResourceType = "AutoScale"
  })

  depends_on = [azurerm_linux_virtual_machine_scale_set.app]
}

# Predictive scaling for Web tier (if supported in the region)
resource "azurerm_monitor_autoscale_setting" "web_predictive" {
  count               = var.enable_vmss && var.enable_auto_scaling && !var.is_dr_region && var.environment == "prod" ? 1 : 0
  name                = "${var.project_name}-${var.environment}-${var.region_suffix}-web-predictive-autoscale"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  target_resource_id  = azurerm_linux_virtual_machine_scale_set.web[0].id

  # Enable predictive scaling
  predictive {
    scale_mode      = "Enabled"
    look_ahead_time = "PT10M"
  }

  profile {
    name = "predictive"

    capacity {
      default = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.default_instances : 2
      minimum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.min_instances : 2
      maximum = var.auto_scaling_config.web_tier != null ? var.auto_scaling_config.web_tier.max_instances : 10
    }

    rule {
      metric_trigger {
        metric_name        = "Percentage CPU"
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT5M"
        time_aggregation   = "Average"
        operator           = "GreaterThan"
        threshold          = 70
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
        metric_resource_id = azurerm_linux_virtual_machine_scale_set.web[0].id
        time_grain         = "PT1M"
        statistic          = "Average"
        time_window        = "PT10M"
        time_aggregation   = "Average"
        operator           = "LessThan"
        threshold          = 30
      }

      scale_action {
        direction = "Decrease"
        type      = "ChangeCount"
        value     = "1"
        cooldown  = "PT10M"
      }
    }
  }

  tags = merge(var.tags, {
    Tier         = "Web"
    ResourceType = "PredictiveAutoScale"
  })

  depends_on = [azurerm_linux_virtual_machine_scale_set.web]
}