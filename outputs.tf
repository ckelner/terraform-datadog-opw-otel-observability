output "monitor_ids" {
  description = "Monitor IDs keyed by stable asset ID."
  value       = { for id, resource in datadog_monitor_json.this : id => resource.id }
}

output "notebook_ids" {
  description = "Notebook IDs keyed by stable asset ID."
  value       = local.notebook_ids
}

output "notebook_urls" {
  description = "Notebook URLs keyed by stable asset ID."
  value       = { for id, remote_id in local.notebook_ids : id => "${local.app_url}/notebook/${remote_id}" }
}

output "start_here_url" {
  description = "Runbook navigation entrypoint."
  value       = module.notebook_start_here.url
}

output "monitor_search_url" {
  description = "Datadog monitor search listing every monitor this module manages."
  value       = "${local.app_url}/monitors/manage?q=${urlencode("tag:\"managed-by:terraform-opw-otel\"")}&p=1"
}

output "monitors_muted" {
  description = "Whether the module is holding every monitor muted through its initial-mute downtime."
  value       = var.start_monitors_muted
}

output "mute_downtime_id" {
  description = "ID of the indefinite downtime muting every monitor, or null when start_monitors_muted is false."
  value       = one(datadog_downtime_schedule.initial_mute[*].id)
}
