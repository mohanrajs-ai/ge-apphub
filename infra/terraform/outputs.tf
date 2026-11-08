# Outputs exported for downstream curl REST API scripts and verification

output "project_id" {
  description = "Target Google Cloud Project ID."
  value       = data.google_project.current.project_id
}

output "project_number" {
  description = "Target Google Cloud Project Number."
  value       = data.google_project.current.number
}

output "collection_id" {
  description = "Discovery Engine Collection ID."
  value       = var.collection_id
}

output "data_store_id" {
  description = "Provisioned Discovery Engine Data Store ID (empty when per-app knowledge sources are disabled)."
  value       = var.data_store_id != "" ? google_discovery_engine_data_store.main[0].data_store_id : ""
}

output "engine_id" {
  description = "Provisioned Gemini Enterprise Search Engine ID."
  value       = google_discovery_engine_search_engine.main.engine_id
}

output "app_access_group" {
  description = "Dedicated Cloud Identity group email granting exclusive access to this Gemini Enterprise App."
  value       = local.resolved_app_access_group
}
