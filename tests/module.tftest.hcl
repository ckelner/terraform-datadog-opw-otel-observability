mock_provider "datadog" {
  mock_resource "datadog_monitor_json" {
    defaults = {
      id = "50001"
    }
  }
  mock_resource "datadog_downtime_schedule" {
    defaults = {
      id = "dt-00001"
    }
  }
}

mock_provider "restapi" {
  mock_resource "restapi_object" {
    defaults = {
      id = "90001"
    }
  }
}

# Give one notebook a distinct ID so tests can prove the Impact link and the runbook
# link resolve to different notebooks rather than coincidentally matching.
override_resource {
  target = module.notebook_assessing_impact.restapi_object.this
  values = {
    id = "90002"
  }
}

variables {
  datadog_site = "us5.datadoghq.com"
}

run "site_us1" {
  command = plan
  variables { datadog_site = "datadoghq.com" }
  assert {
    condition     = local.app_url == "https://app.datadoghq.com"
    error_message = "The datadoghq.com site must resolve to the app.datadoghq.com UI host."
  }
}

run "site_us3" {
  command = plan
  variables { datadog_site = "us3.datadoghq.com" }
  assert {
    condition     = local.app_url == "https://us3.datadoghq.com"
    error_message = "The us3 site must resolve to its own UI host."
  }
}

run "site_us5" {
  command = plan
  variables { datadog_site = "us5.datadoghq.com" }
  assert {
    condition     = local.app_url == "https://us5.datadoghq.com"
    error_message = "The us5 site must resolve to its own UI host."
  }
}

run "site_eu" {
  command = plan
  variables { datadog_site = "datadoghq.eu" }
  assert {
    condition     = local.app_url == "https://app.datadoghq.eu"
    error_message = "The datadoghq.eu site must resolve to the app.datadoghq.eu UI host."
  }
}

run "site_gov" {
  command = plan
  variables { datadog_site = "ddog-gov.com" }
  assert {
    condition     = local.app_url == "https://app.ddog-gov.com"
    error_message = "The ddog-gov.com site must resolve to the app.ddog-gov.com UI host."
  }
}

run "site_gov_us2" {
  command = plan
  variables { datadog_site = "us2.ddog-gov.com" }
  assert {
    condition     = local.app_url == "https://us2.ddog-gov.com"
    error_message = "The us2.ddog-gov.com site must resolve to its own UI host."
  }
}

run "site_ap1" {
  command = plan
  variables { datadog_site = "ap1.datadoghq.com" }
  assert {
    condition     = local.app_url == "https://ap1.datadoghq.com"
    error_message = "The ap1 site must resolve to its own UI host."
  }
}

run "site_ap2" {
  command = plan
  variables { datadog_site = "ap2.datadoghq.com" }
  assert {
    condition     = local.app_url == "https://ap2.datadoghq.com"
    error_message = "The ap2 site must resolve to its own UI host."
  }
}

run "site_uk1" {
  command = plan
  variables { datadog_site = "uk1.datadoghq.com" }
  assert {
    condition     = local.app_url == "https://uk1.datadoghq.com"
    error_message = "The uk1 site must resolve to its own UI host."
  }
}

run "complete_bundle_without_notifications" {
  command = apply

  assert {
    condition     = length(output.monitor_ids) == 16
    error_message = "The module must manage exactly 16 monitors."
  }

  assert {
    condition     = length(output.notebook_ids) == 6
    error_message = "The module must manage exactly 6 notebooks."
  }

  assert {
    condition     = length([for id in keys(output.monitor_ids) : id if startswith(id, "monitor.opw-")]) == 9
    error_message = "Nine monitors must cover the Observability Pipelines Worker tier."
  }

  assert {
    condition     = length([for id in keys(output.monitor_ids) : id if startswith(id, "monitor.otelcol-")]) == 7
    error_message = "Seven monitors must cover the OpenTelemetry Collector tier."
  }

  # Every monitor body must resolve its runbook notebook link and the OP dashboard link.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "/notebook/")
    ])
    error_message = "Every monitor body must link to at least one runbook notebook."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "/dash/integration/32326")
    ])
    error_message = "Every monitor body must link to the Observability Pipelines dashboard."
  }

  # The Impact link points at assessing-impact, which the override gives a distinct ID.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "/notebook/90002")
    ])
    error_message = "Every monitor body must link to the assessing-impact notebook under Impact."
  }

  # No unresolved portable tokens may survive templating.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "$${")
    ])
    error_message = "No monitor body may contain an unresolved Terraform template token."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      contains(jsondecode(resource.monitor).tags, "managed-by:terraform-opw-otel")
    ])
    error_message = "Every monitor must carry the managed-by tag so the full set is findable."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      contains(jsondecode(resource.monitor).tags, "asset-id:${id}")
    ])
    error_message = "Every monitor must carry its own stable asset-id tag."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      contains(jsondecode(resource.monitor).tags, "service:byoc-pipeline")
    ])
    error_message = "Every monitor must carry the shared service tag."
  }

  # Pins Datadog API defaults so the plan is not perpetually dirty.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      jsondecode(resource.monitor).options.notify_audit == false
    ])
    error_message = "notify_audit must be pinned to false on every monitor."
  }

  # Without paging_handles there must be no conditional paging block anywhere.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "is_match")
    ])
    error_message = "With no paging handles configured, no monitor may emit a paging block."
  }

  # Internal self-telemetry components must be excluded from every OPW metric query.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).query, "!component_id:_*")
      if startswith(id, "monitor.opw-") && strcontains(jsondecode(resource.monitor).query, "component_id")
    ])
    error_message = "OPW queries scoped by component must exclude the Worker's internal pipeline."
  }

  # The two absence monitors must opt in to no-data notification.
  assert {
    condition = alltrue([
      for id in ["monitor.opw-source-buffer-metric-absent", "monitor.otelcol-telemetry-absent"] :
      jsondecode(datadog_monitor_json.this[id].monitor).options.on_missing_data == "show_and_notify_no_data"
    ])
    error_message = "Absence monitors must set on_missing_data to show_and_notify_no_data."
  }

  # Source buffer saturation must be a ratio against capacity, never a raw event count.
  assert {
    condition = (
      strcontains(jsondecode(datadog_monitor_json.this["monitor.opw-source-buffer-saturated"].monitor).query, "source_buffer_utilization_mean") &&
      strcontains(jsondecode(datadog_monitor_json.this["monitor.opw-source-buffer-saturated"].monitor).query, "source_buffer_max_size_events")
    )
    error_message = "Source buffer saturation must divide the EWMA occupancy by source_buffer_max_size_events, because the metric is an absolute event count."
  }

  # Metrics removed in OPW 2.22.0 must never appear.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).query, "buffer_byte_size") &&
      !strcontains(jsondecode(resource.monitor).query, "pipelines.buffer_events")
    ])
    error_message = "pipelines.buffer_byte_size and pipelines.buffer_events were removed in OPW 2.22.0 and must not be queried."
  }

  # utilization is not emitted for sources and inverts under backpressure; it must not
  # be the basis of any alert in this module.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).query, "pipelines.utilization")
    ])
    error_message = "pipelines.utilization must not be used as an alert condition; it is not emitted for sources."
  }

  # Counter-based monitors must aggregate as counts or rates, never as raw gauges.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).query, ".as_count()") || strcontains(jsondecode(resource.monitor).query, ".as_rate()")
      if strcontains(jsondecode(resource.monitor).query, "_total{")
    ])
    error_message = "Queries over _total metrics must apply as_count() or as_rate(), because they are Datadog count-type metrics."
  }

  assert {
    condition     = jsondecode(datadog_monitor_json.this["monitor.opw-source-buffer-saturated"].monitor).options.thresholds.warning == 0.7
    error_message = "A per-monitor warning threshold must survive the merge with class defaults."
  }

  assert {
    condition     = jsondecode(datadog_monitor_json.this["monitor.opw-source-buffer-saturated"].monitor).options.evaluation_delay == 120
    error_message = "A per-monitor options override must survive the merge with class defaults."
  }

  assert {
    condition     = jsondecode(datadog_monitor_json.this["monitor.opw-source-lag-high"].monitor).priority == 1
    error_message = "Paging monitors must carry priority 1."
  }

  assert {
    condition     = jsondecode(datadog_monitor_json.this["monitor.opw-request-admission-saturated"].monitor).priority == 3
    error_message = "Investigation monitors must carry priority 3."
  }

  assert {
    condition     = jsondecode(datadog_monitor_json.this["monitor.otelcol-terminal-data-loss"].monitor).type == "log alert"
    error_message = "Terminal data loss must be a log monitor, because no counter metric records it."
  }

  # Datadog's own template braces must survive Terraform templating untouched.
  assert {
    condition     = strcontains(jsondecode(datadog_monitor_json.this["monitor.opw-source-lag-high"].monitor).name, "{{pipeline_name.name}}")
    error_message = "Datadog template variables in monitor names must pass through Terraform templating intact."
  }

  assert {
    condition = alltrue([
      for id, url in output.notebook_urls :
      startswith(url, "https://us5.datadoghq.com/notebook/")
    ])
    error_message = "Notebook URLs must be built from the configured site host."
  }

  assert {
    condition     = strcontains(output.monitor_search_url, "managed-by%3Aterraform-opw-otel")
    error_message = "The monitor search output must query the managed-by tag."
  }

  # Monitors must ship muted so a new deployment cannot page on an unvalidated threshold.
  assert {
    condition     = length(datadog_downtime_schedule.initial_mute) == 1
    error_message = "Monitors must be created muted by default."
  }

  assert {
    condition     = output.monitors_muted == true
    error_message = "The monitors_muted output must report the muted posture."
  }

  assert {
    condition     = output.mute_downtime_id != null
    error_message = "The mute downtime ID must be exposed so the downtime can be found and cancelled."
  }

  # Selection is by tag, so the downtime covers exactly this module's monitors.
  assert {
    condition     = datadog_downtime_schedule.initial_mute[0].monitor_identifier.monitor_tags == toset(["managed-by:terraform-opw-otel"])
    error_message = "The mute must select monitors by this module's managed-by tag alone, so it cannot mute unrelated monitors."
  }

  # No end date means the downtime never expires on its own.
  assert {
    condition     = datadog_downtime_schedule.initial_mute[0].one_time_schedule.end == null
    error_message = "The mute downtime must have no end date, so it stays in effect until explicitly removed."
  }


  # Cancelling the mute should surface whatever is already firing.
  assert {
    condition     = contains(datadog_downtime_schedule.initial_mute[0].notify_end_states, "alert")
    error_message = "Ending the mute must notify for monitors already in alert, so unmuting surfaces current state."
  }
}

run "unmuted_when_disabled" {
  command = apply

  variables {
    start_monitors_muted = false
  }

  assert {
    condition     = length(datadog_downtime_schedule.initial_mute) == 0
    error_message = "Setting start_monitors_muted to false must remove the mute downtime entirely."
  }

  assert {
    condition     = output.mute_downtime_id == null
    error_message = "The mute downtime ID must be null once monitors are unmuted."
  }

  assert {
    condition     = output.monitors_muted == false
    error_message = "The monitors_muted output must report the unmuted posture."
  }

  # Unmuting must not disturb the monitors themselves.
  assert {
    condition     = length(output.monitor_ids) == 16
    error_message = "Unmuting must leave all 16 monitors in place."
  }
}

run "reject_empty_mute_message" {
  command = plan
  variables { mute_message = "   " }
  expect_failures = [var.mute_message]
}

run "paging_routing_and_tags" {
  command = apply

  variables {
    notification_handles         = ["@team-observability", "@slack-byoc"]
    paging_handles               = ["@pagerduty-observability"]
    monitor_tags                 = ["env:prod", "service:byoc-pipeline"]
    paging_pipeline_name_include = ["prod", "prd"]
    paging_pipeline_name_exclude = ["pre-prod", "non-prod", "pre-prd", "non-prd"]
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "@team-observability") &&
      strcontains(jsondecode(resource.monitor).message, "@slack-byoc")
    ])
    error_message = "Standard notification handles must appear on every monitor."
  }

  # OPW monitors group by pipeline_name, so their paging block must be environment gated.
  # Datadog requires each state conditional to own its message block; attribute
  # conditionals may only be nested INSIDE them, never wrapped around them.
  # https://docs.datadoghq.com/monitors/notify/variables/
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "{{#is_alert}}{{#is_match \"pipeline_name.name\" \"prod\" \"PROD\" \"Prod\" \"prd\" \"PRD\" \"Prd\"}}{{^is_match \"pipeline_name.name\" ") &&
      strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability{{/is_match}}{{/is_match}}{{/is_alert}}") &&
      strcontains(jsondecode(resource.monitor).message, "{{#is_alert_recovery}}{{#is_match \"pipeline_name.name\" \"prod\"") &&
      strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability{{/is_match}}{{/is_match}}{{/is_alert_recovery}}")
      if startswith(id, "monitor.opw-") && jsondecode(resource.monitor).priority == 1
    ])
    error_message = "Paging OPW monitors must nest is_match inside the state conditional, not around it, and gate on the production pipeline_name pattern."
  }

  # An is_match that wraps a state conditional is invalid Datadog syntax.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "{{#is_match \"pipeline_name.name\"") ||
      strcontains(jsondecode(resource.monitor).message, "{{#is_alert}}{{#is_match")
    ])
    error_message = "A state conditional must never be nested inside an is_match block; is_match goes inside the state block."
  }

  # The exclude list must sit inside the include list, not beside it, or a name
  # like pre-prod would satisfy the include and still page.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "{{^is_match \"pipeline_name.name\"") &&
      strcontains(jsondecode(resource.monitor).message, "{{/is_match}}{{/is_match}}") &&
      !strcontains(jsondecode(resource.monitor).message, "{{/is_match}}{{^is_match")
      if startswith(id, "monitor.opw-") && jsondecode(resource.monitor).priority == 1
    ])
    error_message = "The exclude list must be nested inside the include list, not placed beside it, or a name like pre-prod would satisfy the include and still page."
  }

  # Collector metrics carry no pipeline_name tag, so those monitors must page unconditionally.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "is_match") &&
      strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability")
      if startswith(id, "monitor.otelcol-") && jsondecode(resource.monitor).priority == 1
    ])
    error_message = "Paging Collector monitors must page unconditionally, because pipeline_name is not available on Collector metrics."
  }

  # Investigation monitors never page.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability")
      if jsondecode(resource.monitor).priority == 3
    ])
    error_message = "Investigation monitors must not carry paging recipients."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      contains(jsondecode(resource.monitor).tags, "env:prod")
    ])
    error_message = "Caller-supplied monitor tags must be appended to every monitor."
  }

  # A tag supplied by the caller that duplicates a class default must not appear twice.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      length([for tag in jsondecode(resource.monitor).tags : tag if tag == "service:byoc-pipeline"]) == 1
    ])
    error_message = "Duplicate tags must collapse to a single entry."
  }
}

run "paging_without_env_gate" {
  command = apply

  variables {
    paging_handles               = ["@pagerduty-observability"]
    paging_pipeline_name_include = []
    paging_pipeline_name_exclude = []
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      !strcontains(jsondecode(resource.monitor).message, "is_match")
      if jsondecode(resource.monitor).priority == 1
    ])
    error_message = "A null paging pattern must page on every group with no is_match gate."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability")
      if jsondecode(resource.monitor).priority == 1
    ])
    error_message = "A null paging pattern must still attach paging recipients to paging monitors."
  }
}

run "query_scoping" {
  command = apply

  variables {
    pipeline_name_filter          = "example-prd-*"
    byoc_exporter_filter          = "otlphttp/byoc"
    collector_group_by_tag        = "kube_namespace"
    memory_limiter_refused_metric = "otelcol_processor_memory_limiter_refused_log_records"
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).query, "pipeline_name:example-prd-*")
      if startswith(id, "monitor.opw-")
    ])
    error_message = "Every OPW query must be scoped by the configured pipeline_name filter."
  }

  assert {
    condition = alltrue([
      for id in ["monitor.otelcol-exporter-enqueue-failed", "monitor.otelcol-exporter-send-failed"] :
      strcontains(jsondecode(datadog_monitor_json.this[id].monitor).query, "exporter:otlphttp/byoc")
    ])
    error_message = "Exporter-tier Collector queries must be scoped by the configured BYOC exporter."
  }

  # The attribution monitor must stay unscoped so every exporter is comparable.
  assert {
    condition     = !strcontains(jsondecode(datadog_monitor_json.this["monitor.otelcol-exporter-queue-saturated"].monitor).query, "exporter:otlphttp/byoc")
    error_message = "The exporter queue saturation monitor must remain unfiltered so queues can be compared across destinations."
  }

  assert {
    condition     = strcontains(jsondecode(datadog_monitor_json.this["monitor.otelcol-exporter-queue-saturated"].monitor).query, "by {exporter,kube_namespace}")
    error_message = "The exporter queue saturation monitor must group by exporter to support attribution."
  }

  assert {
    condition     = strcontains(jsondecode(datadog_monitor_json.this["monitor.otelcol-memory-limiter-refusing"].monitor).query, "otelcol_processor_memory_limiter_refused_log_records")
    error_message = "The configured memory_limiter metric name must be used verbatim."
  }

  assert {
    condition     = strcontains(jsondecode(datadog_monitor_json.this["monitor.otelcol-receiver-refusing"].monitor).query, "by {receiver,kube_namespace}")
    error_message = "The configured collector group-by tag must propagate into Collector queries."
  }

  # The shared-fate monitors must be labelled as such.
  assert {
    condition = alltrue([
      for id in ["monitor.otelcol-memory-limiter-refusing", "monitor.otelcol-receiver-refusing"] :
      contains(jsondecode(datadog_monitor_json.this[id].monitor).tags, "scope:shared-with-other-destinations")
    ])
    error_message = "Collector signals that cannot be attributed to a single destination must be tagged as shared."
  }
}

run "custom_host_links" {
  command = apply

  variables {
    datadog_custom_host = "dd.internal.example.com"
  }

  assert {
    condition = alltrue([
      for id, url in output.notebook_urls :
      startswith(url, "https://dd.internal.example.com/notebook/")
    ])
    error_message = "A custom host must replace the standard site host in generated links."
  }

  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "https://dd.internal.example.com")
    ])
    error_message = "A custom host must be used in every generated monitor body link."
  }
}

run "reject_unknown_site" {
  command = plan
  variables { datadog_site = "app.datadoghq.com" }
  expect_failures = [var.datadog_site]
}

run "reject_custom_host_with_scheme" {
  command = plan
  variables { datadog_custom_host = "https://dd.example.com" }
  expect_failures = [var.datadog_custom_host]
}

run "reject_single_label_custom_host" {
  command = plan
  variables { datadog_custom_host = "localhost" }
  expect_failures = [var.datadog_custom_host]
}

run "reject_empty_pipeline_name_filter" {
  command = plan
  variables { pipeline_name_filter = "  " }
  expect_failures = [var.pipeline_name_filter]
}

run "reject_blank_paging_include_entry" {
  command = plan
  variables { paging_pipeline_name_include = ["prod", "  "] }
  expect_failures = [var.paging_pipeline_name_include]
}

run "reject_empty_exporter_filter" {
  command = plan
  variables { byoc_exporter_filter = "" }
  expect_failures = [var.byoc_exporter_filter]
}

run "reject_uppercase_group_by_tag" {
  command = plan
  variables { collector_group_by_tag = "KubeNamespace" }
  expect_failures = [var.collector_group_by_tag]
}

run "reject_unknown_memory_limiter_metric" {
  command = plan
  variables { memory_limiter_refused_metric = "otelcol_processor_refused_records" }
  expect_failures = [var.memory_limiter_refused_metric]
}

run "reject_empty_collector_log_query" {
  command = plan
  variables { collector_log_query = " " }
  expect_failures = [var.collector_log_query]
}

run "reject_handle_without_at" {
  command = plan
  variables { notification_handles = ["team-observability"] }
  expect_failures = [var.notification_handles]
}

run "reject_handle_with_whitespace" {
  command = plan
  variables { paging_handles = ["@team observability"] }
  expect_failures = [var.paging_handles]
}

run "exclude_only_paging" {
  command = apply

  variables {
    paging_handles               = ["@pagerduty-observability"]
    paging_pipeline_name_include = []
    paging_pipeline_name_exclude = ["pre-prod", "non-prod", "dev", "ppd"]
  }

  # One documented construct, no same-name nesting. Fails toward paging.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "{{#is_alert}}{{^is_match \"pipeline_name.name\" \"pre-prod\" \"PRE-PROD\" \"Pre-Prod\" \"Pre-prod\"") &&
      strcontains(jsondecode(resource.monitor).message, "@pagerduty-observability{{/is_match}}{{/is_alert}}") &&
      !strcontains(jsondecode(resource.monitor).message, "{{#is_match")
      if startswith(id, "monitor.opw-") && jsondecode(resource.monitor).priority == 1
    ])
    error_message = "With no include list, paging must use a single inverted is_match and no nesting."
  }
}

run "reject_quote_in_paging_exclude" {
  command = plan
  variables { paging_pipeline_name_exclude = ["pre\"prod"] }
  expect_failures = [var.paging_pipeline_name_exclude]
}

run "paging_case_variants_are_expanded" {
  command = apply

  variables {
    paging_handles               = ["@pagerduty-observability"]
    paging_pipeline_name_include = ["prod"]
    paging_pipeline_name_exclude = ["non_prod", "pre.prod"]
  }

  # Datadog does not document case handling for is_match, so every marker must
  # cover lower, UPPER, Title-Of-Each-Segment and Sentence casing.
  assert {
    condition = alltrue([
      for v in ["prod", "PROD", "Prod"] :
      contains(local.paging_include_variants, v)
    ])
    error_message = "Include markers must expand to lower, upper and title casings."
  }

  # title() does not treat underscore as a word separator, so Non_Prod only
  # appears if segments are split explicitly. This is the case that regressed.
  assert {
    condition = alltrue([
      for v in ["non_prod", "NON_PROD", "Non_Prod", "Non_prod"] :
      contains(local.paging_exclude_variants, v)
    ])
    error_message = "Underscore-separated markers must be title cased per segment, not just at the first letter."
  }

  assert {
    condition = alltrue([
      for v in ["pre.prod", "PRE.PROD", "Pre.Prod", "Pre.prod"] :
      contains(local.paging_exclude_variants, v)
    ])
    error_message = "Dot-separated markers must be title cased per segment."
  }

  # Expansion must not introduce duplicates.
  assert {
    condition     = length(local.paging_include_variants) == length(distinct(local.paging_include_variants))
    error_message = "Case expansion must not produce duplicate match arguments."
  }

  # The variants must actually reach the rendered message.
  assert {
    condition = alltrue([
      for id, resource in datadog_monitor_json.this :
      strcontains(jsondecode(resource.monitor).message, "\"PROD\"") &&
      strcontains(jsondecode(resource.monitor).message, "\"Non_Prod\"")
      if startswith(id, "monitor.opw-") && jsondecode(resource.monitor).priority == 1
    ])
    error_message = "Expanded case variants must appear in the rendered monitor message."
  }
}
