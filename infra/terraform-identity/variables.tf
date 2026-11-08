# Input Variables for Microsoft Entra ID to Google Cloud Identity Sync & Federation

variable "project_id" {
  description = "Google Cloud Project ID hosting Secret Manager and Gemini Enterprise"
  type        = string
}

variable "region" {
  description = "Default Google Cloud region for provider operations"
  type        = string
  default     = "us-central1"
}

variable "organization_id" {
  description = "Google Cloud Organization ID (e.g., 123456789012)"
  type        = string
  default     = ""
}

variable "cloud_identity_customer_id" {
  description = "Google Cloud Identity Customer ID (e.g., customers/C0xxxxxxx)"
  type        = string
}

variable "primary_customer_domain" {
  description = "Primary domain of the Google Cloud Identity account (e.g., example.com)"
  type        = string
  default     = "example.com"
}

variable "shared_identity_domain" {
  description = "Shared verified custom domain across Microsoft Entra ID and Google Cloud Identity (e.g., example.com)"
  type        = string
  default     = "example.com"
}

variable "m365_secret_id" {
  description = "Google Cloud Secret Manager Secret ID storing JSON {tenant_id, client_id, client_secret}"
  type        = string
  default     = "m365-connector-credentials"
}

variable "m365_tenant_id" {
  description = "Fallback Microsoft Entra ID Tenant ID if not overridden by Secret Manager JSON"
  type        = string
  default     = ""
}

variable "m365_client_id" {
  description = "Fallback Microsoft Entra ID Application (client) ID if not overridden by Secret Manager JSON"
  type        = string
  default     = ""
}

variable "m365_client_secret" {
  description = "Fallback Microsoft Entra ID client secret if not overridden by Secret Manager JSON"
  type        = string
  default     = ""
  sensitive   = true
}

variable "manage_dns_verification_record" {
  description = "Whether Terraform should manage the root TXT record on shared_identity_domain in Cloud DNS for Entra + Google verification"
  type        = bool
  default     = false
}

variable "dns_project_id" {
  description = "Google Cloud Project ID hosting the Cloud DNS managed zone for shared_identity_domain (optional)"
  type        = string
  default     = ""
}

variable "dns_zone_name" {
  description = "Cloud DNS Managed Zone name for shared_identity_domain (optional)"
  type        = string
  default     = ""
}

variable "entra_domain_verification_ms_id" {
  description = "Microsoft Entra ID DNS TXT verification value (e.g., MS=msXXXXXXXX)"
  type        = string
  default     = ""
}

variable "google_domain_verification_txt" {
  description = "Google Cloud Identity secondary domain verification TXT token (e.g., google-site-verification=...)"
  type        = string
  default     = ""
}

variable "synced_groups" {
  description = "Map of Microsoft Entra ID groups to synchronize into Google Cloud Identity"
  type = map(object({
    group_email  = string
    display_name = string
    description  = optional(string, "Synchronized from Microsoft Entra ID")
    members      = optional(list(string), [])
  }))
  default = {}
}

variable "app_group_mappings" {
  description = "List of mappings nesting synced Entra groups or users into Gemini Enterprise Per-App Cloud Identity groups"
  type = list(object({
    app_group_email = string
    member_email    = string
  }))
  default = []
}

variable "enable_workforce_pool_oidc" {
  description = "Optional: Whether to also provision a Workforce Identity Federation OIDC Pool & Provider using the same Secret Manager credentials"
  type        = bool
  default     = false
}

variable "workforce_pool_id" {
  description = "Workforce Identity Pool ID when enable_workforce_pool_oidc is true"
  type        = string
  default     = "entra-id-shared-pool"
}

variable "workforce_provider_id" {
  description = "Workforce Identity Pool Provider ID when enable_workforce_pool_oidc is true"
  type        = string
  default     = "entra-id-oidc-provider"
}
