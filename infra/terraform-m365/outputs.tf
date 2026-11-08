# Outputs exported from Microsoft 365 Data Connector Terraform deployment

output "project_id" {
  description = "Target Google Cloud Project ID."
  value       = data.google_project.current.project_id
}

output "m365_secret_name" {
  description = "Full resource name of the Secret Manager secret storing M365 Entra ID credentials JSON."
  value       = google_secret_manager_secret.m365_credentials.name
}

output "sharepoint_connector_name" {
  description = "Full resource name of the provisioned SharePoint Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.sharepoint[0].name, "")
}

output "sharepoint_collection_id" {
  description = "Collection ID for the SharePoint Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.sharepoint[0].collection_id, "")
}

output "onedrive_connector_name" {
  description = "Full resource name of the provisioned OneDrive Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.onedrive[0].name, "")
}

output "onedrive_collection_id" {
  description = "Collection ID for the OneDrive Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.onedrive[0].collection_id, "")
}

output "outlook_connector_name" {
  description = "Full resource name of the provisioned Outlook Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.outlook[0].name, "")
}

output "outlook_collection_id" {
  description = "Collection ID for the Outlook Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.outlook[0].collection_id, "")
}

output "teams_connector_name" {
  description = "Full resource name of the provisioned Microsoft Teams Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.teams[0].name, "")
}

output "teams_collection_id" {
  description = "Collection ID for the Microsoft Teams Data Connector (if enabled)."
  value       = try(google_discovery_engine_data_connector.teams[0].collection_id, "")
}
