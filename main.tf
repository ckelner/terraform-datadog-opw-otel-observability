locals {
  # Site parameters and URLs: https://docs.datadoghq.com/getting_started/site/.
  # Add new sites here; the datadog_site validation uses this map's keys.
  app_urls = {
    "datadoghq.com"     = "https://app.datadoghq.com"
    "us3.datadoghq.com" = "https://us3.datadoghq.com"
    "us5.datadoghq.com" = "https://us5.datadoghq.com"
    "datadoghq.eu"      = "https://app.datadoghq.eu"
    "ddog-gov.com"      = "https://app.ddog-gov.com"
    "us2.ddog-gov.com"  = "https://us2.ddog-gov.com"
    "ap1.datadoghq.com" = "https://ap1.datadoghq.com"
    "ap2.datadoghq.com" = "https://ap2.datadoghq.com"
    "uk1.datadoghq.com" = "https://uk1.datadoghq.com"
  }
  app_url = var.datadog_custom_host == null ? local.app_urls[var.datadog_site] : "https://${var.datadog_custom_host}"

  # Out-of-the-box Observability Pipelines Overview dashboard.
  op_dashboard_url = "${local.app_url}/dash/integration/32326"

  # Query fragments shared by every monitor. `!component_id:_*` excludes the Worker's
  # own internal telemetry pipeline, whose component IDs are underscore-prefixed.
  pipeline_scope  = "!component_id:_*,pipeline_name:${var.pipeline_name_filter}"
  worker_scope    = "pipeline_name:${var.pipeline_name_filter}"
  exporter_scope  = "exporter:${var.byoc_exporter_filter}"
  collector_group = var.collector_group_by_tag

  monitor_search_queries = {
    for id in keys(local.monitor_items) : id => urlencode("tag:\"asset-id:${id}\"")
  }
  monitor_search_links = {
    for key, asset_id in jsondecode(file("${path.module}/assets/monitor-searches.json")) : key =>
    asset_id == "" ? "" : " · [Find the monitor](${local.app_url}/monitors/manage?q=${local.monitor_search_queries[asset_id]}&p=1)"
  }
}
