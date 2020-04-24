/*
 * Copyright 2017 Google Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

variable "name" {
  description = "Name of the managed instance group."
}

variable "project" {
  description = "The project to deploy to, if not set the default provider project is used."
  default     = ""
}

variable "region" {
  description = "Region for cloud resources."
  default     = ""
}

variable "zone" {
  description = "Zone for managed instance groups."
  default     = ""
}

variable "zonal" {
  description = "Create a single-zone managed instance group. If false, a regional managed instance group is created."
  default     = true
}

####################
# Instance Template
###################
variable "can_ip_forward" {
  description = "Allow ip forwarding."
  default     = false
}

variable "machine_type" {
  description = "Machine type for the VMs in the instance group."
  default     = "f1-micro"
}

variable "network_ip" {
  description = "Set the network IP of the instance in the template. Useful for instance groups of size 1."
  default     = ""
}

variable "preemptible" {
  description = "Use preemptible instances - lower price but short-lived instances. See https://cloud.google.com/compute/docs/instances/preemptible for more details"
  default     = "false"
}

variable "wait_for_instances" {
  description = "Wait for all instances to be created/updated before returning"
  default     = true
}

###########################
# Public IP / Access Config
###########################

variable "access_config" {
  description = "Access configurations, i.e. IPs via which the VM instance can be accessed via the Internet."
  type = list(object({
    nat_ip       = string
    network_tier = string
  }))
  default = []
}

#################
# Source Image
#################

variable "source_image" {
  description = "Image used for compute VMs."
  default     = ""
}


variable "device_name" {
  default = "persistent-disk-0"
}

variable "interface" {
  description = "Disk Interface"
  default     = "SCSI"
}

variable "disk_type" {
  description = "Boot disk type, can be either pd-ssd, local-ssd, or pd-standard"
  default     = "pd-ssd"
}

variable "disk_size_gb" {
  description = "Size in GB"
  default     = "0"
}

variable "auto_delete" {
  description = "Whether or not the boot disk should be auto-deleted"
  default     = "true"
}

variable "boot_type" {
  description = "Disk Type"
  default     = "PERSISTENT"
}

variable "additional_disks" {
  description = "List of maps of additional disks. See https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#disk_name"
  type = list(object({
    auto_delete  = bool
    boot         = bool
    disk_size_gb = number
    disk_type    = string
  }))
  default = []
}

variable "mode" {
  description = "The mode in which to attach this disk, either READ_WRITE or READ_ONLY."
  default     = "READ_WRITE"
}

variable "automatic_restart" {
  description = "Automatically restart the instance if terminated by GCP - Set to false if using preemptible instances"
  default     = "true"
}

####################
# network_interface
####################

variable "network" {
  description = "Name of the network to deploy instances to."
  default     = "default"
}

variable "subnetwork" {
  description = "The subnetwork to deploy to"
  default     = "default"
}

variable "subnetwork_project" {
  description = "The project the subnetwork belongs to. If not set, var.project is used instead."
  default     = ""
}

###########
# metadata
###########

variable "metadata" {
  type        = map(string)
  description = "Map of metadata values to pass to instances."
  default     = {}
}

variable "startup_script" {}

#################
# IG Manager
#################

variable target_tags {
  description = "Tag added to instances for firewall and networking."
  type        = list
  default     = ["allow-service"]
}

variable instance_labels {
  description = "Labels added to instances."
  type        = map
  default     = {}
}

variable target_pools {
  description = "The target load balancing pools to assign this group to."
  type        = list
  default     = []
}

variable "target_size" {
  description = "Target size of the managed instance group."
  default     = 1
}

variable "named_ports" {
  description = "Named name and named port. https://cloud.google.com/load-balancing/docs/backend-service#named_ports"
  type = list(object({
    name = string
    port = number
  }))
}

#################
# Rolling Update
#################

variable update_policy {
  description = "The upgrade policy to apply when the instance template changes."
  type = list(object({
    type                  = string
    minimal_action        = string
    max_surge_fixed       = number
    max_unavailable_fixed = number
    min_ready_sec         = number
  }))
  default = []
}

##############
# Healthcheck
##############

variable "health_check" {
  description = "Health check to determine whether instances are responsive and able to do work"
  type = object({
    type                = string
    initial_delay_sec   = number
    check_interval_sec  = number
    healthy_threshold   = number
    timeout_sec         = number
    unhealthy_threshold = number
    response            = string
    proxy_header        = string
    port                = number
    request             = string
    request_path        = string
    host                = string
  })
  default = {
    type                = ""
    initial_delay_sec   = 30
    check_interval_sec  = 30
    healthy_threshold   = 1
    timeout_sec         = 10
    unhealthy_threshold = 5
    response            = ""
    proxy_header        = "NONE"
    port                = 80
    request             = ""
    request_path        = "/"
    host                = ""
  }
}

##############
# Firewall
##############
variable "service_port" {
  description = "Port the service is listening on."
}

variable "service_port_name" {
  description = "Name of the port the service is listening on."
}

variable "ssh_fw_rule" {
  description = "Whether or not the SSH Firewall Rule should be created"
  default     = true
}

variable "ssh_source_ranges" {
  description = "Network ranges to allow SSH from"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

##################
# service_account
##################

variable "service_account" {
  description = "Service account to attach to the instance. See https://www.terraform.io/docs/providers/google/r/compute_instance_template.html#service_account."
  type = object({
    email  = string
    scopes = set(string)
  })
}

###########################
# Shielded VMs
###########################

variable "enable_shielded_vm" {
  default     = false
  description = "Whether to enable the Shielded VM configuration on the instance. Note that the instance image must support Shielded VMs. See https://cloud.google.com/compute/docs/images"
}

variable "shielded_instance_config" {
  description = "Not used unless enable_shielded_vm is true. Shielded VM configuration for the instance."
  type = object({
    enable_secure_boot          = bool
    enable_vtpm                 = bool
    enable_integrity_monitoring = bool
  })

  default = {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

#############
# Autoscaler
#############

variable "autoscaling_enabled" {
  description = "Creates an autoscaler for the managed instance group"
  default     = false
}

#############
# Healthcheck
#############

variable http_health_check {
  description = "Enable or disable the http health check for auto healing."
  default     = true
}

variable hc_initial_delay {
  description = "Health check, intial delay in seconds."
  default     = 30
}

variable hc_interval {
  description = "Health check, check interval in seconds."
  default     = 30
}

variable hc_timeout {
  description = "Health check, timeout in seconds."
  default     = 10
}

variable hc_healthy_threshold {
  description = "Health check, healthy threshold."
  default     = 1
}

variable hc_unhealthy_threshold {
  description = "Health check, unhealthy threshold."
  default     = 10
}

variable hc_port {
  description = "Health check, health check port, if different from var.service_port, if not given, var.service_port is used."
  default     = ""
}

variable hc_path {
  description = "Health check, the http path to check."
  default     = "/"
}
