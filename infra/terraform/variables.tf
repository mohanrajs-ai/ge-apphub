# Input Variables for Gemini Enterprise App Deployment Automation
# Automatically populated via TF_VAR_* exports from config.env by scripts/lib/common.sh

variable "project_id" {
  description = "Target Google Cloud Project ID where Gemini Enterprise will be deployed."
  type        = string
}

variable "region" {
  description = "Default Google Cloud region for regional resources (e.g., us-central1)."
  type        = string
  default     = "us-central1"
}

variable "location" {
  description = "Discovery Engine multi-region location (global, us, or eu)."
  type        = string
  default     = "global"

  validation {
    condition     = contains(["global", "us", "eu"], var.location)
    error_message = "location must be one of: global, us, eu."
  }
}

variable "collection_id" {
  description = "Discovery Engine collection identifier."
  type        = string
  default     = "default_collection"
}

variable "app_id" {
  description = "Unique identifier for the Gemini Enterprise App / Search Engine."
  type        = string
}

variable "app_display_name" {
  description = "Display name for the Gemini Enterprise App."
  type        = string
}

variable "company_name" {
  description = "Company / organization name used for grounding the Gemini Enterprise assistant."
  type        = string
  default     = "Enterprise Organization"
}

variable "solution_type" {
  description = "Solution type for the engine (SOLUTION_TYPE_SEARCH or SOLUTION_TYPE_CHAT)."
  type        = string
  default     = "SOLUTION_TYPE_SEARCH"
}

variable "app_type" {
  description = "Application type for Gemini Enterprise (APP_TYPE_INTRANET or APP_TYPE_UNSPECIFIED)."
  type        = string
  default     = "APP_TYPE_INTRANET"
}

variable "search_tier" {
  description = "Search tier for the Gemini Enterprise engine (SEARCH_TIER_STANDARD or SEARCH_TIER_ENTERPRISE)."
  type        = string
  default     = "SEARCH_TIER_ENTERPRISE"
}

variable "enable_llm_addon" {
  description = "Whether to enable SEARCH_ADD_ON_LLM on the Gemini Enterprise engine."
  type        = string
  default     = "true"
}

variable "industry_vertical" {
  description = "Industry vertical for the Discovery Engine Data Store and App (GENERIC, MEDIA, HEALTHCARE_FHIR)."
  type        = string
  default     = "GENERIC"
}

variable "data_store_id" {
  description = "Optional unique identifier for the per-app Discovery Engine Data Store (empty when per-app knowledge sources are disabled)."
  type        = string
  default     = ""
}

variable "data_store_display_name" {
  description = "Human-readable display name for the Discovery Engine Data Store."
  type        = string
  default     = ""
}

variable "data_store_content_config" {
  description = "Content configuration for the Data Store (CONTENT_REQUIRED, NO_CONTENT, PUBLIC_WEBSITE)."
  type        = string
  default     = "CONTENT_REQUIRED"
}

variable "backing_storage_type" {
  description = "Backing storage resource to provision (GCS, BIGQUERY, or NONE)."
  type        = string
  default     = "GCS"
}

variable "gcs_bucket_name" {
  description = "GCS bucket name to provision when backing_storage_type is GCS."
  type        = string
  default     = ""
}

variable "bq_dataset_id" {
  description = "BigQuery dataset ID to provision when backing_storage_type is BIGQUERY."
  type        = string
  default     = "gemini_enterprise_data"
}

variable "iam_viewer_members" {
  description = "Comma-separated IAM principals to grant Discovery Engine Viewer access."
  type        = string
  default     = ""
}

variable "customer_domain" {
  description = "Customer Google Workspace / Cloud Identity domain used for per-app group email derivation."
  type        = string
  default     = "example.com"
}

variable "cloud_identity_customer_id" {
  description = "Cloud Identity customer resource ID (e.g., customers/C01234567) for provisioning per-app groups."
  type        = string
  default     = ""
}

variable "app_access_group" {
  description = "Dedicated Cloud Identity group email that grants exclusive access to the Gemini Enterprise App."
  type        = string
  default     = ""
}

variable "app_group_members" {
  description = "Comma-separated user email addresses to add as members of the app's dedicated access group."
  type        = string
  default     = ""
}

variable "common_connector_data_store_ids" {
  description = "Comma-separated entity Data Store IDs from common enterprise connectors (e.g., M365) to attach to every Gemini Enterprise App."
  type        = string
  default     = ""
}
