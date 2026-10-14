variable "datadog_site" {
  description = "Datadog site. Configure both providers for the same site and organization."
  type        = string
  default     = "datadoghq.com"
  validation {
    condition     = contains(keys(local.app_urls), var.datadog_site)
    error_message = "Use a Datadog site hostname, without a protocol or app/api prefix."
  }
}

variable "datadog_custom_host" {
  description = "Optional custom Datadog UI hostname for generated links, without a scheme, port, or path. Defaults to the standard host for datadog_site; does not change provider API endpoints."
  type        = string
  default     = null
  validation {
    condition = var.datadog_custom_host == null ? true : (
      length(var.datadog_custom_host) <= 253 &&
      can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)+$", var.datadog_custom_host))
    )
    error_message = "Use a bare DNS hostname with at least two labels, without a scheme, port, or path."
  }
}

variable "pipeline_name_filter" {
  description = "Tag-glob matched against the OPW `pipeline_name` tag to scope every pipeline monitor. `*` (the default) emits NO pipeline_name term at all, rather than `pipeline_name:*`, because `tag:*` matches only series that actually carry the tag and silently returns nothing when they do not. Monitors group by pipeline_id, so individual pipeline IDs are never needed."
  type        = string
  default     = "*"
  nullable    = false
  validation {
    condition     = length(trimspace(var.pipeline_name_filter)) > 0
    error_message = "pipeline_name_filter must not be empty. Use \"*\" to match every pipeline."
  }
}

variable "paging_pipeline_name_include" {
  description = "Substrings of `pipeline_name` that mark a pipeline as production. Matching is substring based. Each entry is automatically expanded into lower, UPPER, Title and Sentence casings, so supply markers in one casing only. Empty means do not filter on inclusion. Combined with paging_pipeline_name_exclude as: page if the name matches any include AND no exclude."
  type        = list(string)
  default     = ["prod", "production", "prd"]
  nullable    = false
  validation {
    condition     = alltrue([for s in var.paging_pipeline_name_include : length(trimspace(s)) > 0 && !strcontains(s, "\"")])
    error_message = "Include entries must be non-empty and must not contain a double quote."
  }
}

variable "paging_pipeline_name_exclude" {
  description = "Substrings of `pipeline_name` that disqualify a pipeline from paging even when it matches an include. Needed because substring matching alone cannot tell `prod` from `pre-prod`. Each entry is automatically expanded into lower, UPPER, Title and Sentence casings. Empty means do not filter on exclusion."
  type        = list(string)
  default = [
    "pre-prod", "preprod", "pre_prod", "pre.prod",
    "non-prod", "nonprod", "non_prod", "non.prod",
    "pre-prd", "preprd", "pre_prd",
    "non-prd", "nonprd", "non_prd",
  ]
  nullable = false
  validation {
    condition     = alltrue([for s in var.paging_pipeline_name_exclude : length(trimspace(s)) > 0 && !strcontains(s, "\"")])
    error_message = "Exclude entries must be non-empty and must not contain a double quote."
  }
}

variable "byoc_exporter_filter" {
  description = "Exact value of the OpenTelemetry Collector `exporter` attribute for the pipeline shipping to BYOC, scoping the exporter-tier monitors. Defaults to `*` (every exporter) deliberately: a wrong exporter name matches nothing and the monitor is silently inert, whereas `*` is merely noisy and therefore visible. Find yours with `otelcol_exporter_queue_size{*} by {exporter}`."
  type        = string
  default     = "*"
  nullable    = false
  validation {
    condition     = length(trimspace(var.byoc_exporter_filter)) > 0
    error_message = "byoc_exporter_filter must not be empty. Use \"*\" to match every exporter."
  }
}

variable "collector_group_by_tag" {
  description = "Optional ADDITIONAL tag to group OpenTelemetry Collector monitors by, identifying which workload a Collector belongs to. Collector monitors always group by a tag intrinsic to the metric (receiver, processor or exporter), so they work without this. Set it only to a tag your Collector telemetry actually carries: grouping by an absent tag yields a single N/A series. `null` (the default) adds no extra grouping."
  type        = string
  default     = null
  validation {
    condition     = var.collector_group_by_tag == null ? true : can(regex("^[a-z][a-z0-9_.-]*$", var.collector_group_by_tag))
    error_message = "collector_group_by_tag must be a lowercase Datadog tag key, or null."
  }
}

variable "memory_limiter_refused_metric" {
  description = "Metric name for memory_limiter processor refusals. Collector v0.155.0 and later use `otelcol_processor_memory_limiter_refused_log_records`; earlier versions use `otelcol_processor_refused_log_records`."
  type        = string
  default     = "otelcol_processor_refused_log_records"
  nullable    = false
  validation {
    condition = contains([
      "otelcol_processor_refused_log_records",
      "otelcol_processor_memory_limiter_refused_log_records",
    ], var.memory_limiter_refused_metric)
    error_message = "Use otelcol_processor_refused_log_records (before Collector v0.155.0) or otelcol_processor_memory_limiter_refused_log_records (v0.155.0 and later)."
  }
}

variable "collector_log_query" {
  description = "Datadog log search scoping the terminal-data-loss log monitor to OpenTelemetry Collector logs. Terminal loss after dequeue has no counter metric, so this log line is the only record of it."
  type        = string
  default     = "source:otelcol"
  nullable    = false
  validation {
    condition     = length(trimspace(var.collector_log_query)) > 0
    error_message = "collector_log_query must not be empty."
  }
}

variable "notification_handles" {
  description = "Datadog notification handles on every monitor. Empty means no explicit recipients."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for handle in var.notification_handles : can(regex("^@[^[:space:]]+$", handle))])
    error_message = "Every notification handle must start with @ and contain no whitespace."
  }
}

variable "paging_handles" {
  description = "Additional recipients on paging monitors, only on alert and alert recovery, and only for groups passing the paging_pipeline_name_include and paging_pipeline_name_exclude gate."
  type        = list(string)
  default     = []
  validation {
    condition     = alltrue([for handle in var.paging_handles : can(regex("^@[^[:space:]]+$", handle))])
    error_message = "Every paging handle must start with @ and contain no whitespace."
  }
}

variable "monitor_tags" {
  description = "Extra tags appended to each monitor."
  type        = list(string)
  default     = []
}

variable "start_monitors_muted" {
  description = "Create every monitor muted, indefinitely, via a Datadog downtime scoped to this module's managed-by tag. Leave true until thresholds have been observed against real traffic, then set to false and apply to begin alerting."
  type        = bool
  default     = true
  nullable    = false
}

variable "mute_message" {
  description = "Message attached to the initial-mute downtime, shown wherever the downtime surfaces in Datadog."
  type        = string
  default     = "OPW/OTel observability monitors are muted pending threshold validation. Unmute by setting start_monitors_muted = false in Terraform."
  nullable    = false
  validation {
    condition     = length(trimspace(var.mute_message)) > 0
    error_message = "mute_message must not be empty."
  }
}

variable "hpa_monitor_source" {
  description = <<-EOT
    Metric source for the autoscaler-ceiling monitor, which alerts when the HPA's desired
    replica count has reached its maximum. The OPW fleet sitting at maxReplicas while CPU
    is above target is the condition that precedes backpressure, and no OPW or Collector
    metric can see it.

    "none" omits the monitor. "datadog_agent" uses kubernetes_state.hpa.*, which requires
    the Agent's kubernetes_state_core check. "otel_k8s_cluster" uses k8s.hpa.*, emitted by
    the OpenTelemetry k8sclusterreceiver. Default is "none" because neither source is
    required by the rest of this module.
  EOT
  type        = string
  default     = "none"
  nullable    = false
  validation {
    condition     = contains(["none", "datadog_agent", "otel_k8s_cluster"], var.hpa_monitor_source)
    error_message = "hpa_monitor_source must be one of: none, datadog_agent, otel_k8s_cluster."
  }
}

variable "hpa_scope" {
  description = "Tag filter selecting the OPW HorizontalPodAutoscaler, e.g. \"kube_namespace:observability-pipelines\". Applied only when hpa_monitor_source is not \"none\". A value of \"*\" emits no term, matching every HPA the source reports."
  type        = string
  default     = "*"
  nullable    = false
}

variable "source_block_tail_critical_seconds" {
  description = <<-EOT
    Critical threshold, in seconds, for the worst single blocked send on an OPW source.
    Set this to the OTel Collector's exporter `timeout`, because a batch that blocks
    longer than the client's deadline is cancelled and lost in full, up to
    send_batch_max_size records.

    This is deliberately separate from the mean-based source-blocked monitor. The mean
    describes the pipeline's condition; the tail describes whether data is being dropped.
    A pipeline can have a healthy mean and still lose batches in bursts.

    Defaults to 30, the `otlphttp` exporter's own default. Override it if yours differs.
  EOT
  type        = number
  default     = 30
  nullable    = false
  validation {
    condition     = var.source_block_tail_critical_seconds > 0
    error_message = "source_block_tail_critical_seconds must be greater than 0."
  }
}

variable "worker_cpu_critical_ratio" {
  description = "Critical threshold for OPW worker CPU, as a fraction of the worker's own cgroup allocation (pipelines.cpu_usage_seconds_total over pipelines.cpu_max_cores). Set above the HPA's targetCPUUtilizationPercentage so the monitor fires only once autoscaling has failed to relieve the load."
  type        = number
  default     = 0.85
  nullable    = false
  validation {
    condition     = var.worker_cpu_critical_ratio > 0 && var.worker_cpu_critical_ratio <= 1
    error_message = "worker_cpu_critical_ratio must be greater than 0 and at most 1."
  }
}
