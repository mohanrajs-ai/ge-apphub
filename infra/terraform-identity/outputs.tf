# Outputs for Microsoft Entra ID to Google Cloud Identity Sync & Federation

output "m365_secret_version_name" {
  description = "Secret Manager secret version resource name used for Entra ID credentials"
  value       = data.google_secret_manager_secret_version.m365_credentials_latest.name
}

output "entra_tenant_id" {
  description = "Resolved Microsoft Entra ID Tenant ID from Secret Manager"
  value       = nonsensitive(local.effective_m365_tenant_id)
}

output "entra_client_id" {
  description = "Resolved Microsoft Entra ID Application (Client) ID from Secret Manager"
  value       = nonsensitive(local.effective_m365_client_id)
}

output "shared_identity_domain" {
  description = "Shared custom identity domain across Entra ID and Cloud Identity"
  value       = var.shared_identity_domain
}

output "synced_cloud_identity_groups" {
  description = "Map of synchronized Cloud Identity groups (key => resource name and email)"
  value = {
    for k, g in google_cloud_identity_group.synced_entra_groups : k => {
      id           = g.id
      group_email  = g.group_key[0].id
      display_name = g.display_name
    }
  }
}

output "synced_group_membership_count" {
  description = "Total number of user memberships synchronized into Cloud Identity groups"
  value       = length(google_cloud_identity_group_membership.synced_group_members)
}

output "app_group_nested_membership_count" {
  description = "Total number of Entra groups/users nested into Gemini Enterprise Per-App groups"
  value       = length(google_cloud_identity_group_membership.app_group_nested_members)
}

output "workforce_pool_provider_redirect_uri" {
  description = "Entra ID Web Redirect URI if Workforce Identity Pool OIDC provider is enabled"
  value       = var.enable_workforce_pool_oidc ? "https://auth.cloud.google/signin-callback/locations/global/workforcePools/${var.workforce_pool_id}/providers/${var.workforce_provider_id}" : ""
}
