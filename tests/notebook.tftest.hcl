mock_provider "restapi" {}

run "yaml_preserves_text_and_cell_attributes" {
  command = apply
  module {
    source = "./modules/notebook"
  }
  variables {
    template_path = "tests/fixtures/notebook.yaml.tftpl"
    app_url       = "https://app.datadoghq.com"
    links = {
      label   = "日本語 \"quoted\" \\path"
      details = "First line\ncells: []\n  Last \"line\" \\path $${literal}"
    }
  }
  assert {
    condition = output.document == {
      data = {
        type = "notebooks"
        attributes = {
          name               = "Notebook 日本語 \"quoted\" \\path"
          status             = "published"
          time               = { live_span = "1h" }
          metadata           = { is_template = false, take_snapshots = false, type = "runbook" }
          template_variables = [{ name = "cluster_name", prefix = "cluster_name", default = "*" }]
          cells = [
            {
              type = "notebook_cells"
              attributes = {
                definition = {
                  type = "markdown"
                  text = "# Procedure\n\nFirst line\ncells: []\n  Last \"line\" \\path $${literal}\n\n```sh\necho \"$${shell}\"\n```\nLiteral %%{if}, {{value}}, $cluster_name, and C:\\logs."
                }
              }
            },
            {
              type = "notebook_cells"
              attributes = {
                definition = {
                  type     = "timeseries"
                  title    = "Graph 日本語 \"quoted\" \\path"
                  requests = [{ q = "sum:metric{$cluster_name}", display_type = "line" }]
                }
                graph_size = "m"
                time       = { live_span = "4h" }
              }
            },
            {
              type       = "notebook_cells"
              attributes = { definition = { type = "markdown", text = "Last paragraph.\n" } }
            },
          ]
        }
      }
    }
    error_message = "YAML must preserve cell order, attributes, literal template syntax, and all text while substituting links safely."
  }
}
