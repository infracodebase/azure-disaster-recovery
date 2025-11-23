# Variables for Azure Multi-Tier Disaster Recovery Architecture

variable "environment" {
  description = "The environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "The project name used for resource naming"
  type        = string
  default     = "webapp"

  validation {
    condition     = can(regex("^[a-z0-9-]{2,20}$", var.project_name))
    error_message = "Project name must be 2-20 characters, lowercase letters, numbers, and hyphens only."
  }
}

variable "primary_location" {
  description = "The primary Azure region"
  type        = string
  default     = "East US"
}

variable "secondary_location" {
  description = "The secondary Azure region for disaster recovery"
  type        = string
  default     = "West US 2"
}

variable "use_availability_zones" {
  description = "Whether to use Availability Zones (true) or Availability Sets (false)"
  type        = bool
  default     = true
}

# Networking Configuration
variable "primary_vnet_address_space" {
  description = "Address space for primary region VNet"
  type        = list(string)
  default     = ["10.0.0.0/16"]
}

variable "primary_web_subnet_prefix" {
  description = "Address prefix for web tier subnet in primary region"
  type        = string
  default     = "10.0.1.0/24"
}

variable "primary_app_subnet_prefix" {
  description = "Address prefix for app tier subnet in primary region"
  type        = string
  default     = "10.0.2.0/24"
}

variable "primary_data_subnet_prefix" {
  description = "Address prefix for data tier subnet in primary region"
  type        = string
  default     = "10.0.3.0/24"
}

variable "secondary_vnet_address_space" {
  description = "Address space for secondary region VNet"
  type        = list(string)
  default     = ["10.1.0.0/16"]
}

variable "secondary_web_subnet_prefix" {
  description = "Address prefix for web tier subnet in secondary region"
  type        = string
  default     = "10.1.1.0/24"
}

variable "secondary_app_subnet_prefix" {
  description = "Address prefix for app tier subnet in secondary region"
  type        = string
  default     = "10.1.2.0/24"
}

variable "secondary_data_subnet_prefix" {
  description = "Address prefix for data tier subnet in secondary region"
  type        = string
  default     = "10.1.3.0/24"
}

# Virtual Machine Configuration
variable "vm_admin_username" {
  description = "Admin username for virtual machines"
  type        = string
  default     = "azureadmin"

  validation {
    condition     = can(regex("^[a-zA-Z][a-zA-Z0-9]{2,19}$", var.vm_admin_username))
    error_message = "VM admin username must start with a letter and be 3-20 characters long."
  }
}

variable "vm_size_web" {
  description = "Size of web tier virtual machines"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "vm_size_app" {
  description = "Size of app tier virtual machines"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "vm_size_data" {
  description = "Size of data tier virtual machines"
  type        = string
  default     = "Standard_D4s_v3"
}

# Security Configuration
variable "allowed_ip_ranges" {
  description = "IP ranges allowed to access the load balancer"
  type        = list(string)
  default     = ["0.0.0.0/0"] # Restrict this in production
}

# Tagging
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "DisasterRecovery"
    Environment = "Production"
    CreatedBy   = "Terraform"
    Purpose     = "Multi-tier Web Application"
  }
}

# VMSS Configuration
variable "enable_vmss" {
  description = "Enable Virtual Machine Scale Sets instead of individual VMs"
  type        = bool
  default     = false
}

variable "vmss_orchestration_mode" {
  description = "Orchestration mode for VMSS: Flexible (recommended) or Uniform (legacy)"
  type        = string
  default     = "Flexible"
  validation {
    condition     = contains(["Flexible", "Uniform"], var.vmss_orchestration_mode)
    error_message = "Orchestration mode must be either 'Flexible' or 'Uniform'."
  }
}

# Auto-scaling Configuration
variable "enable_auto_scaling" {
  description = "Enable auto-scaling for Virtual Machine Scale Sets"
  type        = bool
  default     = false
}

variable "auto_scaling_config" {
  description = "Auto-scaling configuration for VMSS"
  type = object({
    web_tier = optional(object({
      min_instances        = optional(number, 2)
      max_instances        = optional(number, 10)
      default_instances    = optional(number, 2)
      scale_out_cpu_threshold = optional(number, 75)
      scale_in_cpu_threshold  = optional(number, 25)
      scale_out_memory_threshold = optional(number, 80)
      scale_in_memory_threshold  = optional(number, 30)
      scale_out_cooldown   = optional(string, "PT5M")
      scale_in_cooldown    = optional(string, "PT10M")
    }))
    app_tier = optional(object({
      min_instances        = optional(number, 2)
      max_instances        = optional(number, 8)
      default_instances    = optional(number, 2)
      scale_out_cpu_threshold = optional(number, 70)
      scale_in_cpu_threshold  = optional(number, 30)
      scale_out_memory_threshold = optional(number, 75)
      scale_in_memory_threshold  = optional(number, 35)
      scale_out_cooldown   = optional(string, "PT5M")
      scale_in_cooldown    = optional(string, "PT15M")
    }))
  })
  default = {}
}