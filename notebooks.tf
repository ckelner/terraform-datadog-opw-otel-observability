# Keep separate module blocks to avoid instance cycles.

module "notebook_assessing_impact" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/assessing-impact.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url          = local.app_url
    op_dashboard_url = local.op_dashboard_url
  }
}

module "notebook_otelcol_refusing_data" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/otelcol-refusing-data.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url                       = local.app_url
    byoc_exporter                 = var.byoc_exporter_filter
    collector_group               = coalesce(var.collector_group_by_tag, "exporter")
    memory_limiter_metric         = var.memory_limiter_refused_metric
    notebook_assessing_impact_url = module.notebook_assessing_impact.url
    optional_monitor_otelcol_data = local.monitor_search_links["otelcol_refusing_data"]
  }
}

module "notebook_opw_request_admission_shedding" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/opw-request-admission-shedding.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url                         = local.app_url
    notebook_assessing_impact_url   = module.notebook_assessing_impact.url
    optional_monitor_admission_shed = local.monitor_search_links["opw_request_admission_shedding"]
  }
}

module "notebook_opw_source_buffer_saturated" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/opw-source-buffer-saturated.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url                        = local.app_url
    notebook_assessing_impact_url  = module.notebook_assessing_impact.url
    optional_monitor_source_buffer = local.monitor_search_links["opw_source_buffer_saturated"]
  }
}

module "notebook_opw_backpressure_triage" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/opw-backpressure-triage.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url                                     = local.app_url
    op_dashboard_url                            = local.op_dashboard_url
    collector_group                             = coalesce(var.collector_group_by_tag, "exporter")
    byoc_exporter                               = var.byoc_exporter_filter
    notebook_assessing_impact_url               = module.notebook_assessing_impact.url
    notebook_otelcol_refusing_data_url          = module.notebook_otelcol_refusing_data.url
    notebook_opw_source_buffer_saturated_url    = module.notebook_opw_source_buffer_saturated.url
    notebook_opw_request_admission_shedding_url = module.notebook_opw_request_admission_shedding.url
    optional_monitor_backpressure               = local.monitor_search_links["opw_backpressure_triage"]
  }
}

module "notebook_start_here" {
  source        = "./modules/notebook"
  template_path = "${path.module}/assets/notebooks/start-here.yaml.tftpl"
  app_url       = local.app_url
  links = {
    app_url                                     = local.app_url
    op_dashboard_url                            = local.op_dashboard_url
    notebook_assessing_impact_url               = module.notebook_assessing_impact.url
    notebook_opw_backpressure_triage_url        = module.notebook_opw_backpressure_triage.url
    notebook_opw_source_buffer_saturated_url    = module.notebook_opw_source_buffer_saturated.url
    notebook_opw_request_admission_shedding_url = module.notebook_opw_request_admission_shedding.url
    notebook_otelcol_refusing_data_url          = module.notebook_otelcol_refusing_data.url
  }
}

locals {
  notebook_ids = {
    "notebook.assessing-impact"               = module.notebook_assessing_impact.id
    "notebook.opw-backpressure-triage"        = module.notebook_opw_backpressure_triage.id
    "notebook.opw-request-admission-shedding" = module.notebook_opw_request_admission_shedding.id
    "notebook.opw-source-buffer-saturated"    = module.notebook_opw_source_buffer_saturated.id
    "notebook.otelcol-refusing-data"          = module.notebook_otelcol_refusing_data.id
    "notebook.start-here"                     = module.notebook_start_here.id
  }
}
