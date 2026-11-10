variable "project_id" {
  description = "Google Cloud Project ID hosting Gemini Enterprise and Secret Manager."
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

  validation {
    condition     = contains(["global", "us", "eu"], var.location)
    error_message = "location must be one of: global, us, eu."
  }
}

variable "servicenow_secret_id" {
  description = "Secret Manager secret ID storing ServiceNow JSON credentials ({instance_uri, client_id, client_secret, username, password})."
  type        = string
  default     = "cymbal-servicenow-connector-credentials"
}

variable "servicenow_collection_id" {
  description = "Discovery Engine Collection ID for the ServiceNow connector."
  type        = string
  default     = "cymbal-servicenow"
}

variable "servicenow_collection_display_name" {
  description = "Display name for the ServiceNow Discovery Engine collection."
  type        = string
  default     = "ServiceNow ITSM & Knowledge (cymbal)"
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
  description = "ServiceNow integration username."
  type        = string
  default     = ""
}

variable "servicenow_password" {
  description = "ServiceNow integration user password."
  type        = string
  default     = ""
  sensitive   = true
}

variable "servicenow_connector_mode" {
  description = "Primary ServiceNow connector mode (DATA_INGESTION or FEDERATED)."
  type        = string
  default     = "DATA_INGESTION"

  validation {
    condition     = contains(["DATA_INGESTION", "FEDERATED", "FEDERATED_AND_EUA", "EUA", "ACTIONS"], var.servicenow_connector_mode)
    error_message = "servicenow_connector_mode must be one of: DATA_INGESTION, FEDERATED, FEDERATED_AND_EUA, EUA, ACTIONS."
  }
}

variable "servicenow_refresh_interval" {
  description = "Refresh interval for ServiceNow data synchronization."
  type        = string
  default     = "86400s"
}

variable "servicenow_entities" {
  description = "Comma-separated list of ServiceNow entities to index (knowledge_base,incident,catalog_item)."
  type        = string
  default     = "knowledge_base,incident,catalog_item"
}

variable "enable_servicenow_actions" {
  description = "Whether to enable ServiceNow BAP Write Actions (create_incident, update_incident, etc.)."
  type        = string
  default     = "true"
}
