terraform {
  required_version = ">= 1.9.0, < 2.0.0"
  required_providers {
    restapi = {
      source  = "Mastercard/restapi"
      version = "~> 3.0.0"
    }
  }
}

variable "template_path" { type = string }
variable "links" { type = map(string) }
variable "app_url" { type = string }

locals {
  # Decode YAML before substituting links so multiline values cannot change its
  # structure. Escape each binding as JSON string content for the rendered JSON.
  template_json = jsonencode(yamldecode(file(var.template_path)))
  json_links = {
    for key, value in var.links : key => substr(jsonencode(value), 1, length(jsonencode(value)) - 2)
  }
  source = jsondecode(templatestring(local.template_json, local.json_links))
  attributes = merge(local.source, {
    cells = [for cell in local.source.cells : {
      type       = "notebook_cells"
      attributes = cell
    }]
  })
  document = { data = { type = "notebooks", attributes = local.attributes } }
}

resource "restapi_object" "this" {
  path                    = "/api/v1/notebooks"
  id_attribute            = "data/id"
  create_method           = "POST"
  read_method             = "GET"
  update_method           = "PUT"
  destroy_method          = "DELETE"
  data                    = jsonencode(local.document)
  ignore_server_additions = true
}
