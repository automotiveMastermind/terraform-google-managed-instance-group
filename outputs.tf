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

output "name" {
  description = "Pass through of input `name`."
  value       = var.name
}

output "instance_template" {
  description = "Link to the instance_template for the group"
  value       = google_compute_instance_template.default.self_link
}

output "instance_group" {
  description = "Link to the `instance_group` property of the instance group manager resource."
  value       = google_compute_instance_group_manager.default.instance_group
}

output "instance_group_target_size" {
  description = "Set target size of the instance group manager."
  value       = google_compute_instance_group_manager.default.target_size
}

output "target_tags" {
  description = "Pass through of input `target_tags`."
  value       = var.target_tags
}

output "service_port" {
  description = "Pass through of input `service_port`."
  value       = var.service_port
}

output "service_port_name" {
  description = "Pass through of input `service_port_name`."
  value       = var.service_port_name
}

output "network_ip" {
  description = "Pass through of input `network_ip`."
  value       = var.network_ip
}

output "health_check" {
  description = "The healthcheck for the managed instance group"
  value = try(
    google_compute_health_check.mig-health-check.0.self_link,
    ""
  )
}
