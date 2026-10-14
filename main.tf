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
  #
  # A filter of "*" must emit NO term rather than `tag:*`. In Datadog, `tag:*`
  # matches only series that carry that tag, so a monitor scoped to a tag the
  # deployment does not emit returns no data and sits in OK forever. That is a
  # worse failure than no monitor at all, because it looks like coverage.
  pipeline_filtered = var.pipeline_name_filter != "*"
  pipeline_scope = join(",", compact([
    "!component_id:_*",
    local.pipeline_filtered ? "pipeline_name:${var.pipeline_name_filter}" : "",
  ]))
  worker_scope   = local.pipeline_filtered ? "pipeline_name:${var.pipeline_name_filter}" : "*"
  exporter_scope = var.byoc_exporter_filter == "*" ? "*" : "exporter:${var.byoc_exporter_filter}"

  # Environment gating needs pipeline_name in the group-by for
  # {{pipeline_name.name}} to resolve. Only add it when gating is actually on,
  # so deployments whose telemetry lacks the tag are not grouped by it.
  paging_gated   = length(var.paging_pipeline_name_include) > 0 || length(var.paging_pipeline_name_exclude) > 0
  pipeline_group = local.paging_gated ? "pipeline_id,pipeline_name" : "pipeline_id"
  pipeline_label = local.paging_gated ? "{{pipeline_name.name}}" : "{{pipeline_id.name}}"

  # Collector monitors always group by a tag intrinsic to the metric. The
  # caller's tag, if any, is appended.
  collector_group_suffix = var.collector_group_by_tag == null ? "" : ",${var.collector_group_by_tag}"
  collector_group_name   = var.collector_group_by_tag == null ? "" : "[{{${var.collector_group_by_tag}.name}}]"
  collector_log_group    = var.collector_group_by_tag == null ? "service" : var.collector_group_by_tag

  # Autoscaler-ceiling monitor. Two sources report the same four HPA gauges under
  # different names: the Datadog Agent's kubernetes_state_core check and the
  # OpenTelemetry k8sclusterreceiver. Neither is a dependency of this module, so the
  # monitor is omitted entirely unless a source is named.
  hpa_enabled = var.hpa_monitor_source != "none"
  hpa_metric_prefix = {
    none             = ""
    datadog_agent    = "kubernetes_state.hpa"
    otel_k8s_cluster = "k8s.hpa"
  }[var.hpa_monitor_source]
  # Same "*" rule as pipeline_scope: a literal tag:* matches only series carrying the
  # tag, so an unfiltered monitor must emit no term at all.
  hpa_scope = var.hpa_scope == "*" ? "*" : var.hpa_scope
  # The Agent tags HPAs with `hpa`; the k8sclusterreceiver maps the resource attribute
  # k8s.hpa.name onto `kube_hpa`. Grouping by the wrong one yields a single ungrouped
  # series, which still alerts but cannot name the autoscaler in the message.
  hpa_group = var.hpa_monitor_source == "otel_k8s_cluster" ? "kube_hpa" : "hpa"

  monitor_search_queries = {
    for id in keys(local.monitor_items) : id => urlencode("tag:\"asset-id:${id}\"")
  }
  monitor_search_links = {
    for key, asset_id in jsondecode(file("${path.module}/assets/monitor-searches.json")) : key =>
    asset_id == "" ? "" : " · [Find the monitor](${local.app_url}/monitors/manage?q=${local.monitor_search_queries[asset_id]}&p=1)"
  }
}
