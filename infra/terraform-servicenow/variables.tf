# Variables for the ServiceNow Discovery Engine Data Connector

variable "project_id" {
  description = "Google Cloud Project ID hosting Discovery Engine and Secret Manager."
  type        = string
}

variable "region" {
  description = "Default Google Cloud region."
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Discovery Engine multi-region location (global, us, eu)."
  type        = string
  default     = "global"
}

variable "servicenow_secret_id" {
  description = "Secret Manager secret ID storing ServiceNow JSON credentials ({instance_uri, client_id, client_secret, username, password})."
  type        = string
  default     = "cymbal-servicenow-connector-credentials"
}

variable "servicenow_collection_id" {
  description = "Discovery Engine Collection ID for the ServiceNow connector."
  type        = string
  default     = "cymbal-sn"
}

variable "servicenow_collection_display_name" {
  description = "Display name for the ServiceNow connector collection."
  type        = string
  default     = "ServiceNow ITSM and Knowledge"
}

variable "servicenow_instance_uri" {
  description = "ServiceNow instance base URL (e.g. https://dev123456.service-now.com)."
  type        = string
  default     = ""
}

variable "servicenow_client_id" {
  description = "ServiceNow OAuth 2.0 Client ID."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_client_secret" {
  description = "ServiceNow OAuth 2.0 Client Secret."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_username" {
  description = "ServiceNow integration username (e.g. cymbal_ge_connector)."
  type        = string
  default     = ""
}

variable "servicenow_password" {
  description = "ServiceNow integration user password."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_refresh_token" {
  description = "ServiceNow OAuth 2.0 Refresh Token (minted via /oauth_token.do)."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_connector_mode" {
  description = "Primary connector mode for ServiceNow (DATA_INGESTION or FEDERATED)."
  type        = string
  default     = "DATA_INGESTION"
}

variable "servicenow_refresh_interval" {
  description = "Sync refresh interval for ServiceNow ingestion."
  type        = string
  default     = "86400s"
}

variable "servicenow_entities" {
  description = "Comma-separated ServiceNow entities to sync (knowledge_base,incident,catalog)."
  type        = string
  default     = "knowledge_base,incident,catalog"
}

variable "enable_servicenow_actions" {
  description = "Whether to enable ServiceNow BAP Write Actions (create_incident, update_incident, etc.)."
  type        = string
  default     = "true"
}

variable "servicenow_enabled_actions" {
  description = "Comma-separated list of ServiceNow BAP actions to enable."
  type        = string
  default     = "create_incident"
}
