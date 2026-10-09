locals {
  monitor_source = jsondecode(templatefile("${path.module}/assets/monitors.json.tftpl", {
    pipeline_scope        = local.pipeline_scope
    worker_scope          = local.worker_scope
    exporter_scope        = local.exporter_scope
    collector_group       = local.collector_group
    memory_limiter_metric = var.memory_limiter_refused_metric
    collector_log_query   = var.collector_log_query
  }))
  monitor_items = { for item in local.monitor_source.monitors : item.asset_id => item }

  # A monitor can only route by environment when `pipeline_name` is in its group-by,
  # because that is what makes {{pipeline_name.name}} resolvable in the message. OPW
  # monitors group by it; OpenTelemetry Collector metrics do not carry the tag at all,
  # so those monitors page unconditionally.
  monitor_env_scoped = {
    for id, item in local.monitor_items : id => can(regex("by \\{[^}]*pipeline_name", item.payload.query))
  }

  monitor_base = {
    for id, item in local.monitor_items : id => merge(
      local.monitor_source.defaults[item.class], item.payload,
      {
        options = merge(
          { notify_audit = false },
          contains(keys(merge(local.monitor_source.defaults[item.class].options, try(item.payload.options, {}))), "new_group_delay") ? {} : { new_host_delay = 300 },
          local.monitor_source.defaults[item.class].options,
          try(item.payload.options, {}),
          {
            thresholds = merge(
              try(local.monitor_source.defaults[item.class].options.thresholds, {}),
              try(item.payload.options.thresholds, {})
            )
          }
        )
        tags = distinct(concat(
          local.monitor_source.defaults[item.class].tags,
          try(item.payload.tags, []),
          var.monitor_tags,
          ["managed-by:terraform-opw-otel", "asset-id:${id}"]
        ))
      }
    )
  }

  monitor_template_variables = merge(
    {
      app_url          = local.app_url
      op_dashboard_url = local.op_dashboard_url
      byoc_exporter    = var.byoc_exporter_filter
      collector_group  = local.collector_group
    },
    { for id, value in local.notebook_ids : "${replace(replace(id, ".", "_"), "-", "_")}_url" => "${local.app_url}/notebook/${value}" },
    { for id, query in local.monitor_search_queries : "${replace(replace(id, ".", "_"), "-", "_")}_search_query" => query }
  )

  # Paging recipients are added only on alert and alert recovery. For pipeline-scoped
  # monitors they are further gated on the pipeline_name substring, so pre-production
  # pipelines notify without waking anyone.
  #
  # State conditionals (is_alert, is_alert_recovery) must each own their message block
  # and cannot be combined with one another, but attribute conditionals may be nested
  # inside them. So is_match goes within the state block, never around it.
  # https://docs.datadoghq.com/monitors/notify/variables/
  paging_recipients = join(" ", var.paging_handles)

  # Substring matching cannot express "contains prod but not pre-prod", so an
  # include list alone is not enough: "prod" is a substring of "pre-prod" and
  # "non-prod". The exclude list is applied as a nested inverted section.
  #
  # NOTE: nesting two is_match sections is not documented by Datadog, and
  # closing-tag resolution for same-named sections is unspecified. Verify with
  # a real test notification before relying on it. Setting
  # paging_pipeline_name_include = [] renders the exclude-only form, which uses
  # a single documented construct and fails toward paging rather than silence.
  # Datadog does not document case handling for is_match, so each marker is
  # expanded into its realistic casings: lower, UPPER, Title-Of-Each-Segment,
  # and Sentence case. title() does not treat underscore as a word separator,
  # so segments are split explicitly on -, _, . and space.
  paging_include_variants = distinct(flatten([
    for s in var.paging_pipeline_name_include : [
      lower(s),
      upper(s),
      join("", [for part in regexall("[^-_. ]+|[-_. ]", lower(s)) : title(part)]),
      "${upper(substr(lower(s), 0, 1))}${substr(lower(s), 1, length(s) - 1)}",
    ]
  ]))
  paging_exclude_variants = distinct(flatten([
    for s in var.paging_pipeline_name_exclude : [
      lower(s),
      upper(s),
      join("", [for part in regexall("[^-_. ]+|[-_. ]", lower(s)) : title(part)]),
      "${upper(substr(lower(s), 0, 1))}${substr(lower(s), 1, length(s) - 1)}",
    ]
  ]))

  paging_include_args = join(" ", [for s in local.paging_include_variants : format("%q", s)])
  paging_exclude_args = join(" ", [for s in local.paging_exclude_variants : format("%q", s)])

  paging_open = join("", compact([
    length(var.paging_pipeline_name_include) == 0 ? "" : "{{#is_match \"pipeline_name.name\" ${local.paging_include_args}}}",
    length(var.paging_pipeline_name_exclude) == 0 ? "" : "{{^is_match \"pipeline_name.name\" ${local.paging_exclude_args}}}",
  ]))
  paging_close = join("", compact([
    length(var.paging_pipeline_name_exclude) == 0 ? "" : "{{/is_match}}",
    length(var.paging_pipeline_name_include) == 0 ? "" : "{{/is_match}}",
  ]))

  monitor_paging_blocks = {
    for id, item in local.monitor_items : id => (
      item.class != "paging" || length(var.paging_handles) == 0 ? "" : (
        local.monitor_env_scoped[id] && local.paging_open != ""
        ? join("\n", [
          "{{#is_alert}}${local.paging_open}${local.paging_recipients}${local.paging_close}{{/is_alert}}",
          "{{#is_alert_recovery}}${local.paging_open}${local.paging_recipients}${local.paging_close}{{/is_alert_recovery}}",
        ])
        : join("\n", [
          "{{#is_alert}}${local.paging_recipients}{{/is_alert}}",
          "{{#is_alert_recovery}}${local.paging_recipients}{{/is_alert_recovery}}",
        ])
      )
    )
  }

  # Datadog rejects any monitor whose notify_by covers every group key in the
  # query: "The notify_by list may not include all of the query's group keys."
  # notify_by has to be a strict subset, which is what makes alerts coalesce
  # across at least one dimension instead of paging per group. Checked at plan
  # time because the API only reports it on create.
  monitor_group_keys = {
    for id, item in local.monitor_items : id => toset([
      for k in(
        length(regexall("by \\{([^}]*)\\}", item.payload.query)) > 0
        ? split(",", regexall("by \\{([^}]*)\\}", item.payload.query)[0][0])
        : []
      ) : trimspace(k)
    ])
  }
  monitor_notify_by = {
    for id, item in local.monitor_items : id => toset(try(item.payload.options.notify_by, []))
  }

  monitor_messages = {
    for id, item in local.monitor_items : id => join("\n", compact([
      trimspace(templatefile("${path.module}/assets/monitors/${trimprefix(id, "monitor.")}.md.tftpl", local.monitor_template_variables)),
      join("\n", var.notification_handles),
      local.monitor_paging_blocks[id],
    ]))
  }
}

resource "datadog_monitor_json" "this" {
  for_each = local.monitor_items

  # Create the mute first so there is no window in which a monitor exists unmuted.
  # Resolves to an empty dependency when start_monitors_muted is false.
  depends_on = [datadog_downtime_schedule.initial_mute]

  monitor = jsonencode(merge(local.monitor_base[each.key], {
    message = local.monitor_messages[each.key]
  }))

  lifecycle {
    precondition {
      condition = length(local.monitor_notify_by[each.key]) == 0 || (
        length(setsubtract(local.monitor_notify_by[each.key], local.monitor_group_keys[each.key])) == 0 &&
        length(local.monitor_notify_by[each.key]) < length(local.monitor_group_keys[each.key])
      )
      error_message = "${each.key}: notify_by must be a strict subset of the query's group keys. Datadog rejects a monitor whose notify_by covers all of them."
    }
  }
}
