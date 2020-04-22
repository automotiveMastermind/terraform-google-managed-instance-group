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

provider "google-beta" {
  version = ">= 2.0.0"
}

################
# Data Sources
###############

data "google_compute_instance_group" "default" {
  project = var.project
  zone    = var.zone
  name    = google_compute_instance_group_manager.default.name
}

data "google_compute_zones" "available" {
  project = var.project
  region  = var.region
}

#########
# Locals
#########

locals {
  healthchecks = concat(
    google_compute_health_check.mig-health-check.*.self_link,
  )

  boot_disk = [
    {
      source_image = var.source_image
      disk_size_gb = var.disk_size_gb
      disk_type    = var.disk_type
      auto_delete  = var.auto_delete
      boot         = "true"
    },
  ]

  all_disks = concat(local.boot_disk, var.additional_disks)

  # NOTE: Even if all the shielded_instance_config values are false, if the
  # config block exists and an unsupported image is chosen, the apply will fail
  # so we use a single-value array with the default value to initialize the block
  # only if it is enabled.
  shielded_vm_configs = var.enable_shielded_vm ? [true] : []
}

resource "google_compute_instance_template" "default" {
  name_prefix    = "default-"
  project        = var.project
  machine_type   = var.machine_type
  labels         = var.instance_labels
  tags           = concat(["allow-ssh"], var.target_tags)
  can_ip_forward = var.can_ip_forward
  region         = var.region

  network_interface {
    network    = var.subnetwork == "" ? var.network : ""
    subnetwork = var.subnetwork
    dynamic "access_config" {
      for_each = var.access_config
      content {
        nat_ip       = access_config.value.nat_ip
        network_tier = access_config.value.network_tier
      }
    }
    network_ip         = var.network_ip
    subnetwork_project = var.subnetwork_project == "" ? var.project : var.subnetwork_project
  }

  dynamic "disk" {
    for_each = local.all_disks
    content {
      auto_delete  = lookup(disk.value, "auto_delete", null)
      boot         = lookup(disk.value, "boot", null)
      device_name  = lookup(disk.value, "device_name", null)
      disk_name    = lookup(disk.value, "disk_name", null)
      disk_size_gb = lookup(disk.value, "disk_size_gb", null)
      disk_type    = lookup(disk.value, "disk_type", null)
      interface    = lookup(disk.value, "interface", null)
      mode         = lookup(disk.value, "mode", null)
      source       = lookup(disk.value, "source", null)
      source_image = lookup(disk.value, "source_image", null)
      type         = lookup(disk.value, "type", null)

      dynamic "disk_encryption_key" {
        for_each = lookup(disk.value, "disk_encryption_key", [])
        content {
          kms_key_self_link = lookup(disk_encryption_key.value, "kms_key_self_link", null)
        }
      }
    }
  }

  dynamic "service_account" {
    for_each = [var.service_account]
    content {
      email  = lookup(service_account.value, "email", null)
      scopes = lookup(service_account.value, "scopes", null)
    }
  }

  lifecycle {
    create_before_destroy = "true"
  }

  # scheduling must have automatic_restart be false when preemptible is true.
  scheduling {
    preemptible       = var.preemptible
    automatic_restart = ! var.preemptible
  }

  dynamic "shielded_instance_config" {
    for_each = local.shielded_vm_configs
    content {
      enable_secure_boot          = lookup(var.shielded_instance_config, "enable_secure_boot", shielded_instance_config.value)
      enable_vtpm                 = lookup(var.shielded_instance_config, "enable_vtpm", shielded_instance_config.value)
      enable_integrity_monitoring = lookup(var.shielded_instance_config, "enable_integrity_monitoring", shielded_instance_config.value)
    }
  }
}

resource "google_compute_instance_group_manager" "default" {
  provider           = google-beta
  project            = var.project
  name               = var.name
  description        = "compute VM Instance Group"
  wait_for_instances = var.wait_for_instances
  base_instance_name = var.name

  version {
    name              = "${var.name}-default"
    instance_template = google_compute_instance_template.default.self_link
  }

  zone = var.zone

  target_pools = var.target_pools
  target_size  = var.autoscaling_enabled ? null : var.target_size

  dynamic "named_port" {
    for_each = var.named_ports
    content {
      name = lookup(named_port.value, "name", null)
      port = lookup(named_port.value, "port", null)
    }
  }

  dynamic "auto_healing_policies" {
    for_each = local.healthchecks
    content {
      health_check      = auto_healing_policies.value
      initial_delay_sec = var.health_check["initial_delay_sec"]
    }
  }

  dynamic "update_policy" {
    for_each = var.update_policy
    content {
      type                    = update_policy.value.type
      minimal_action          = update_policy.value.minimal_action
      max_surge_fixed         = lookup(update_policy.value, "max_surge_fixed", null)
      max_surge_percent       = lookup(update_policy.value, "max_surge_percent", null)
      max_unavailable_fixed   = lookup(update_policy.value, "max_unavailable_fixed", null)
      max_unavailable_percent = lookup(update_policy.value, "max_unavailable_percent", null)
      min_ready_sec           = lookup(update_policy.value, "min_ready_sec", null)
    }
  }
}

# resource "google_compute_region_instance_group_manager" "default" {
#   provider           = google-beta
#   project            = var.project
#   name               = var.name
#   description        = "compute VM Instance Group"
#   wait_for_instances = var.wait_for_instances
#   base_instance_name = var.name
#   region             = var.region

#   version {
#     name              = "${var.name}-default"
#     instance_template = google_compute_instance_template.default.self_link
#   }

#   target_pools = var.target_pools
#   target_size  = var.autoscaling_enabled ? null : var.target_size

#   dynamic "named_port" {
#     for_each = var.named_ports
#     content {
#       name = lookup(named_port.value, "name", null)
#       port = lookup(named_port.value, "port", null)
#     }
#   }

#   dynamic "auto_healing_policies" {
#     for_each = local.healthchecks
#     content {
#       health_check      = auto_healing_policies.value
#       initial_delay_sec = var.health_check["initial_delay_sec"]
#     }
#   }

#   dynamic "update_policy" {
#     for_each = var.update_policy
#     content {
#       max_surge_fixed         = lookup(update_policy.value, "max_surge_fixed", null)
#       max_surge_percent       = lookup(update_policy.value, "max_surge_percent", null)
#       max_unavailable_fixed   = lookup(update_policy.value, "max_unavailable_fixed", null)
#       max_unavailable_percent = lookup(update_policy.value, "max_unavailable_percent", null)
#       min_ready_sec           = lookup(update_policy.value, "min_ready_sec", null)
#       minimal_action          = update_policy.value.minimal_action
#       type                    = update_policy.value.type
#     }
#   }
# }

# resource "null_resource" "dummy_dependency" {
#   count      = var.zonal ? 1 : 0
#   depends_on = [google_compute_instance_group_manager.default]

#   triggers = {
#     instance_template = element(google_compute_instance_template.default.*.self_link, 0)
#   }
# }

# resource "null_resource" "region_dummy_dependency" {
#   count      = var.zonal ? 1 : 0
#   depends_on = [google_compute_region_instance_group_manager.default]

#   triggers = {
#     instance_template = element(google_compute_instance_template.default.*.self_link, 0)
#   }
# }

resource "google_compute_health_check" "mig-health-check" {
  count               = var.http_health_check ? 1 : 0
  name                = var.name
  project             = var.project
  check_interval_sec  = var.hc_interval
  timeout_sec         = var.hc_timeout
  healthy_threshold   = var.hc_healthy_threshold
  unhealthy_threshold = var.hc_unhealthy_threshold

  http_health_check {
    port         = var.hc_port == "" ? var.service_port : var.hc_port
    request_path = var.hc_path
  }
}

resource "google_compute_firewall" "mig-health-check" {
  count   = var.http_health_check ? 1 : 0
  project = var.subnetwork_project == "" ? var.project : var.subnetwork_project
  name    = "${var.name}-vm-hc"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = [var.hc_port == "" ? var.service_port : var.hc_port]
  }

  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = var.target_tags
}


resource "google_compute_firewall" "default-ssh" {
  count   = var.ssh_fw_rule ? 1 : 0
  project = var.subnetwork_project == "" ? var.project : var.subnetwork_project
  name    = "${var.name}-vm-ssh"
  network = var.network

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = var.ssh_source_ranges
  target_tags   = ["allow-ssh"]
}
