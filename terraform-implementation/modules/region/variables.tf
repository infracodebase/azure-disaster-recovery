# Variables for the region module

variable "environment" {
  description = "The environment name"
  type        = string
}

variable "project_name" {
  description = "The project name"
  type        = string
}

variable "location" {
  description = "The Azure region for this deployment"
  type        = string
}

variable "region_suffix" {
  description = "Suffix to identify the region (primary/secondary)"
  type        = string
}

variable "address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "web_subnet_prefix" {
  description = "Address prefix for web tier subnet"
  type        = string
}

variable "app_subnet_prefix" {
  description = "Address prefix for app tier subnet"
  type        = string
}

variable "data_subnet_prefix" {
  description = "Address prefix for data tier subnet"
  type        = string
}

variable "vm_admin_username" {
  description = "Admin username for virtual machines"
  type        = string
}

variable "vm_admin_password" {
  description = "Admin password for virtual machines"
  type        = string
  sensitive   = true
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

variable "use_availability_zones" {
  description = "Whether to use Availability Zones (true) or Availability Sets (false)"
  type        = bool
  default     = true
}

variable "is_dr_region" {
  description = "Whether this is the disaster recovery region (VMs not created initially)"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}