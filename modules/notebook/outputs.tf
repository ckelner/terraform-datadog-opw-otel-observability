output "id" { value = restapi_object.this.id }
output "url" { value = "${var.app_url}/notebook/${restapi_object.this.id}" }
output "document" {
  description = "Rendered input document; server-generated IDs and timestamps are excluded."
  value       = local.document
}
