terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    datadog = {
      source  = "DataDog/datadog"
      version = "~> 4.21.0"
    }
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0.0"
    }
  }
}

variable "datadog_api_key" {
  type      = string
  sensitive = true
}

variable "datadog_app_key" {
  type      = string
  sensitive = true
}

variable "datadog_site" {
  type    = string
  default = "us5.datadoghq.com"
}

provider "datadog" {
  api_key  = var.datadog_api_key
  app_key  = var.datadog_app_key
  api_url  = "https://api.${var.datadog_site}/"
  validate = true
}

# The Datadog provider has no Notebook resource, so notebooks are created through
# the Notebooks API with a generic REST provider.
provider "restapi" {
  uri                  = "https://api.${var.datadog_site}"
  write_returns_object = true
  headers = {
    "DD-API-KEY"         = var.datadog_api_key
    "DD-APPLICATION-KEY" = var.datadog_app_key
    "Content-Type"       = "application/json"
  }
}

module "opw_otel_observability" {
  source = "../../"

  datadog_site = var.datadog_site

  # Monitors group by pipeline_id and scope by the pipeline_name tag, so individual
  # pipeline IDs are never required. "*" covers every pipeline in the organization.
  pipeline_name_filter = "*"

  # Paging is gated per alerting group on the pipeline_name tag. Substring
  # matching cannot tell prod from pre-prod on its own, so the exclude list
  # carries the negation. Set include = [] for the exclude-only form, which
  # uses one documented construct and fails toward paging rather than silence.
  paging_pipeline_name_include = ["prod", "production", "prd"]
  paging_pipeline_name_exclude = ["pre-prod", "preprod", "non-prod", "nonprod", "pre-prd", "non-prd"]

  # Scopes the exporter-tier Collector monitors to the pipeline shipping to BYOC.
  # Receiver and memory_limiter signals cannot be scoped this way; see README.
  byoc_exporter_filter = "otlphttp/datadog-byoc-logs"

  collector_group_by_tag = "k8s_namespace_name"

  # Collector v0.155.0 and later use otelcol_processor_memory_limiter_refused_log_records.
  memory_limiter_refused_metric = "otelcol_processor_refused_log_records"

  notification_handles = ["@team-observability"]
  paging_handles       = ["@pagerduty-observability"]
  monitor_tags         = ["env:prod"]

  # Monitors are created muted indefinitely so a new deployment cannot page on a
  # threshold that has not been observed against real traffic. Set to false and
  # apply to begin alerting.
  start_monitors_muted = true
}

output "start_here_url" {
  value = module.opw_otel_observability.start_here_url
}

output "monitor_search_url" {
  value = module.opw_otel_observability.monitor_search_url
}
