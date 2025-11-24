# Variables for the region module

variable "environment" {
description = "The environment name"
type = string
}

variable "project_name" {
description = "The project name"
type = string
}

variable "location" {
description = "The Azure region for this deployment"
type = string
}

variable "region_suffix" {
description = "Suffix to identify the region (primary/secondary)"
type = string
}

variable "address_space" {
description = "Address space for the VNet"
type = list(string)
}

variable "web_subnet_prefix" {
description = "Address prefix for web tier subnet"
type = string
}

variable "app_subnet_prefix" {
description = "Address prefix for app tier subnet"
type = string
}

variable "data_subnet_prefix" {
description = "Address prefix for data tier subnet"
type = string
}

variable "vm_admin_username" {
description = "Admin username for virtual machines"
type = string
}

variable "vm_admin_password" {
description = "Admin password for virtual machines"
type = string
sensitive = true
}

variable "vm_size_web" {
description = "Size of web tier virtual machines"
type = string
default = "Standard_D2s_v3"
}

variable "vm_size_app" {
description = "Size of app tier virtual machines"
type = string
default = "Standard_D4s_v3"
}

variable "vm_size_data" {
description = "Size of data tier virtual machines"
type = string
default = "Standard_D4s_v3"
}

variable "use_availability_zones" {
description = "Whether to use Availability Zones (true) or Availability Sets (false)"
type = bool
default = true
}

variable "is_dr_region" {
description = "Whether this is the disaster recovery region (VMs not created initially)"
type = bool
default = false
}

variable "tags" {
description = "Tags to apply to all resources"
type = map(string)
default = {}
}

# VMSS Configuration
variable "enable_vmss" {
description = "Enable Virtual Machine Scale Sets instead of individual VMs"
type = bool
default = false
}

variable "vmss_orchestration_mode" {
description = "Orchestration mode for VMSS: Flexible (new recommended) or Uniform (legacy)"
type = string
default = "Flexible"
validation {
condition = contains(["Flexible", "Uniform"], var.vmss_orchestration_mode)
error_message = "Orchestration mode must be either 'Flexible' or 'Uniform'."
}
}

# Auto-scaling Configuration
variable "enable_auto_scaling" {
description = "Enable auto-scaling for Virtual Machine Scale Sets"
type = bool
default = false
}

variable "auto_scaling_config" {
description = "Auto-scaling configuration for VMSS"
type = object({
web_tier = optional(object({
min_instances = optional(number, 2)
max_instances = optional(number, 10)
default_instances = optional(number, 2)
scale_out_cpu_threshold = optional(number, 75)
scale_in_cpu_threshold = optional(number, 25)
scale_out_memory_threshold = optional(number, 80)
scale_in_memory_threshold = optional(number, 30)
scale_out_cooldown = optional(string, "PT5M")
scale_in_cooldown = optional(string, "PT10M")
}))
app_tier = optional(object({
min_instances = optional(number, 2)
max_instances = optional(number, 8)
default_instances = optional(number, 2)
scale_out_cpu_threshold = optional(number, 70)
scale_in_cpu_threshold = optional(number, 30)
scale_out_memory_threshold = optional(number, 75)
scale_in_memory_threshold = optional(number, 35)
scale_out_cooldown = optional(string, "PT5M")
scale_in_cooldown = optional(string, "PT15M")
}))
})
default = {}
}