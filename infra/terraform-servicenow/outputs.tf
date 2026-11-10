output "servicenow_connector_name" {
  description = "Full resource name of the ServiceNow Discovery Engine Data Connector."
  value       = google_discovery_engine_data_connector.servicenow.name
}

output "servicenow_collection_id" {
  description = "Collection ID hosting the ServiceNow entity data stores."
  value       = google_discovery_engine_data_connector.servicenow.collection_id
}

output "servicenow_secret_id" {
  description = "Secret Manager secret ID storing ServiceNow credentials."
  value       = google_secret_manager_secret.servicenow_credentials.secret_id
}
