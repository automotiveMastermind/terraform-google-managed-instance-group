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

resource "google_compute_instance_template" "default" {
  count          = var.module_enabled ? 1 : 0
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

  metadata = merge(
    {
      "startup-script" = var.startup_script
      "tf_depends_id"  = var.depends_id
    },
    var.metadata,
  )

  # scheduling must have automatic_restart be false when preemptible is true.
  scheduling {
    preemptible       = var.preemptible
    automatic_restart = ! var.preemptible
  }

  lifecycle {
    create_before_destroy = true
  }

  # dynamic "shielded_instance_config" {
  #   for_each = local.shielded_vm_configs
  #   content {
  #     enable_secure_boot          = lookup(var.shielded_instance_config, "enable_secure_boot", shielded_instance_config.value)
  #     enable_vtpm                 = lookup(var.shielded_instance_config, "enable_vtpm", shielded_instance_config.value)
  #     enable_integrity_monitoring = lookup(var.shielded_instance_config, "enable_integrity_monitoring", shielded_instance_config.value)
  #   }
  # }
}

provider "google-beta" {
  version = ">= 2.0.0"
}

resource "google_compute_instance_group_manager" "default" {
  provider           = google-beta
  count              = var.module_enabled && var.zonal ? 1 : 0
  project            = var.project
  name               = var.name
  description        = "compute VM Instance Group"
  wait_for_instances = var.wait_for_instances

  base_instance_name = var.name

  version {
    name              = "${var.name}-default"
    instance_template = google_compute_instance_template.default[0].self_link
  }

  zone = var.zone

  dynamic "update_policy" {
    for_each = var.update_policy
    content {
      max_surge_fixed         = lookup(update_policy.value, "max_surge_fixed", null)
      max_surge_percent       = lookup(update_policy.value, "max_surge_percent", null)
      max_unavailable_fixed   = lookup(update_policy.value, "max_unavailable_fixed", null)
      max_unavailable_percent = lookup(update_policy.value, "max_unavailable_percent", null)
      min_ready_sec           = lookup(update_policy.value, "min_ready_sec", null)
      minimal_action          = update_policy.value.minimal_action
      type                    = update_policy.value.type
    }
  }

  target_pools = var.target_pools
  target_size  = var.autoscaling ? var.min_replicas : var.size

  named_port {
    name = var.service_port_name
    port = var.service_port
  }

  auto_healing_policies {
    health_check = var.http_health_check ? element(
      concat(
        google_compute_health_check.mig-health-check.*.self_link,
        [""],
      ),
      0,
    ) : ""
    initial_delay_sec = var.hc_initial_delay
  }

  provisioner "local-exec" {
    when    = destroy
    command = ":"
  }

  provisioner "local-exec" {
    when    = create
    command = var.local_cmd_create
  }
}

resource "google_compute_autoscaler" "default" {
  count   = var.module_enabled && var.autoscaling && var.zonal ? 1 : 0
  name    = var.name
  zone    = var.zone
  project = var.project
  target  = google_compute_instance_group_manager.default[0].self_link

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = var.cooldown_period
    dynamic "cpu_utilization" {
      for_each = var.autoscaling_cpu
      content {
        target = cpu_utilization.value.target
      }
    }
    dynamic "metric" {
      for_each = var.autoscaling_metric
      content {
        name   = metric.value.name
        target = lookup(metric.value, "target", null)
        type   = lookup(metric.value, "type", null)
      }
    }
    dynamic "load_balancing_utilization" {
      for_each = var.autoscaling_lb
      content {
        target = load_balancing_utilization.value.target
      }
    }
  }
}

data "google_compute_zones" "available" {
  project = var.project
  region  = var.region
}

locals {
  distribution_zones = {
    default = [data.google_compute_zones.available.names]
    user    = [var.distribution_policy_zones]
  }

  dependency_id = element(
    concat(null_resource.region_dummy_dependency.*.id, ["disabled"]),
    0,
  )
}

resource "google_compute_region_instance_group_manager" "default" {
  count              = var.module_enabled && false == var.zonal ? 1 : 0
  project            = var.project
  name               = var.name
  description        = "compute VM Instance Group"
  wait_for_instances = var.wait_for_instances
  base_instance_name = var.name
  region             = var.region

  version {
    instance_template = google_compute_instance_template.default[0].self_link
  }

  dynamic "update_policy" {
    for_each = var.update_policy
    content {
      minimal_action               = update_policy.value.minimal_action
      type                         = update_policy.value.type
      instance_redistribution_type = lookup(update_policy.value, "instance_redistribution_type", null)
      max_surge_fixed              = lookup(update_policy.value, "max_surge_fixed", null)
      max_surge_percent            = lookup(update_policy.value, "max_surge_percent", null)
      max_unavailable_fixed        = lookup(update_policy.value, "max_unavailable_fixed", null)
      max_unavailable_percent      = lookup(update_policy.value, "max_unavailable_percent", null)
      min_ready_sec                = lookup(update_policy.value, "min_ready_sec", null)
    }
  }

  distribution_policy_zones = local.distribution_zones[length(var.distribution_policy_zones) == 0 ? "default" : "user"]

  target_pools = var.target_pools
  target_size  = var.autoscaling ? var.min_replicas : var.size

  auto_healing_policies {
    health_check = var.http_health_check ? element(
      concat(
        google_compute_health_check.mig-health-check.*.self_link,
        [""],
      ),
      0,
    ) : ""
    initial_delay_sec = var.hc_initial_delay
  }

  named_port {
    name = var.service_port_name
    port = var.service_port
  }

  provisioner "local-exec" {
    when    = destroy
    command = ":"
  }

  provisioner "local-exec" {
    when    = create
    command = var.local_cmd_create
  }

  // Initial instance verification can take 10-15m when a health check is present.
  timeouts {
    create = var.http_health_check ? "15m" : "5m"
  }
}

resource "google_compute_region_autoscaler" "default" {
  count   = var.module_enabled && var.autoscaling && false == var.zonal ? 1 : 0
  name    = var.name
  region  = var.region
  project = var.project
  target  = google_compute_region_instance_group_manager.default[0].self_link

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = var.cooldown_period
    dynamic "cpu_utilization" {
      for_each = var.autoscaling_cpu
      content {
        target = cpu_utilization.value.target
      }
    }
    dynamic "metric" {
      for_each = var.autoscaling_metric
      content {
        name   = metric.value.name
        target = lookup(metric.value, "target", null)
        type   = lookup(metric.value, "type", null)
      }
    }
    dynamic "load_balancing_utilization" {
      for_each = var.autoscaling_lb
      content {
        target = load_balancing_utilization.value.target
      }
    }
  }
}

resource "null_resource" "dummy_dependency" {
  count      = var.module_enabled && var.zonal ? 1 : 0
  depends_on = [google_compute_instance_group_manager.default]

  triggers = {
    instance_template = element(google_compute_instance_template.default.*.self_link, 0)
  }
}

resource "null_resource" "region_dummy_dependency" {
  count      = var.module_enabled && false == var.zonal ? 1 : 0
  depends_on = [google_compute_region_instance_group_manager.default]

  triggers = {
    instance_template = element(google_compute_instance_template.default.*.self_link, 0)
  }
}

resource "google_compute_firewall" "default-ssh" {
  count   = var.module_enabled && var.ssh_fw_rule ? 1 : 0
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

resource "google_compute_health_check" "mig-health-check" {
  count   = var.module_enabled && var.http_health_check ? 1 : 0
  name    = var.name
  project = var.project

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
  count   = var.module_enabled && var.http_health_check ? 1 : 0
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

data "google_compute_instance_group" "zonal" {
  count   = var.zonal ? 1 : 0
  zone    = var.zone
  project = var.project

  // Use the dependency id which is recreated whenever the instance template changes to signal when to re-read the data source.
  name = element(
    split(
      "|",
      "${local.dependency_id}|${element(
        concat(
          google_compute_instance_group_manager.default.*.name,
          ["unused"],
        ),
        0,
      )}",
    ),
    1,
  )
}

