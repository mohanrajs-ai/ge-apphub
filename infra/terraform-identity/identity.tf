# Microsoft Entra ID to Google Cloud Identity Entity Synchronization & Federation
# Reads Entra ID OAuth credentials from Secret Manager (m365-connector-credentials)
# and declaratively provisions Cloud DNS verification records, synced Cloud Identity
# security groups, group memberships, and Gemini Enterprise per-app group mappings.

resource "google_project_service" "identity_apis" {
  for_each = toset([
    "secretmanager.googleapis.com",
    "cloudidentity.googleapis.com",
    "admin.googleapis.com",
    "siteverification.googleapis.com",
  ])

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

resource "google_project_service" "dns_project_api" {
  count              = var.manage_dns_verification_record ? 1 : 0
  project            = trimspace(var.dns_project_id) != "" ? trimspace(var.dns_project_id) : var.project_id
  service            = "dns.googleapis.com"
  disable_on_destroy = false
}

data "google_secret_manager_secret_version" "m365_credentials_latest" {
  project    = var.project_id
  secret     = var.m365_secret_id
  version    = "latest"
  depends_on = [google_project_service.identity_apis]
}

locals {
  m365_secret_json             = jsondecode(data.google_secret_manager_secret_version.m365_credentials_latest.secret_data)
  effective_m365_tenant_id     = var.m365_tenant_id != "" ? var.m365_tenant_id : try(local.m365_secret_json.tenant_id, "")
  effective_m365_client_id     = var.m365_client_id != "" ? var.m365_client_id : try(local.m365_secret_json.client_id, "")
  effective_m365_client_secret = var.m365_client_secret != "" ? var.m365_client_secret : try(local.m365_secret_json.client_secret, "")

  dns_txt_records = compact([
    trimspace(var.entra_domain_verification_ms_id) != "" ? "\"${trimspace(var.entra_domain_verification_ms_id)}\"" : "",
    trimspace(var.google_domain_verification_txt) != "" ? "\"${trimspace(var.google_domain_verification_txt)}\"" : ""
  ])

  # Flatten synced group memberships into a deterministic map keyed by "<group_key>::<member_email>"
  synced_group_memberships = merge([
    for group_key, group_cfg in var.synced_groups : {
      for member_email in distinct(group_cfg.members) :
      "${group_key}::${lower(trimspace(member_email))}" => {
        group_key    = group_key
        member_email = trimspace(member_email)
      }
      if trimspace(member_email) != ""
    }
  ]...)

  # Distinct target Gemini Enterprise Per-App group emails to look up
  distinct_target_app_groups = toset([
    for m in var.app_group_mappings : trimspace(m.app_group_email)
    if trimspace(m.app_group_email) != ""
  ])

  # Deterministic map of Per-App group -> nested Entra group/user memberships
  app_group_membership_map = {
    for m in var.app_group_mappings :
    "${lower(trimspace(m.app_group_email))}::${lower(trimspace(m.member_email))}" => {
      app_group_email = trimspace(m.app_group_email)
      member_email    = trimspace(m.member_email)
    }
    if trimspace(m.app_group_email) != "" && trimspace(m.member_email) != ""
  }
}

# Optional: Manage shared domain TXT verification records in Cloud DNS (var.dns_project_id / var.dns_zone_name)
resource "google_dns_record_set" "domain_verification_txt" {
  count        = var.manage_dns_verification_record ? 1 : 0
  project      = trimspace(var.dns_project_id) != "" ? trimspace(var.dns_project_id) : var.project_id
  managed_zone = var.dns_zone_name
  name         = "${trimsuffix(var.shared_identity_domain, ".")}."
  type         = "TXT"
  ttl          = 60
  rrdatas      = local.dns_txt_records
  depends_on   = [google_project_service.dns_project_api]
}

# Provision synchronized Microsoft Entra ID Security/M365 Groups in Google Cloud Identity
resource "google_cloud_identity_group" "synced_entra_groups" {
  for_each             = var.synced_groups
  display_name         = each.value.display_name
  description          = each.value.description
  initial_group_config = "EMPTY"
  parent               = trimspace(var.cloud_identity_customer_id)

  group_key {
    id = trimspace(each.value.group_email)
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
    "cloudidentity.googleapis.com/groups.security"         = ""
  }

  depends_on = [google_project_service.identity_apis]
}

# Synchronize Entra ID user memberships into each synced Cloud Identity group
resource "google_cloud_identity_group_membership" "synced_group_members" {
  for_each = local.synced_group_memberships
  group    = google_cloud_identity_group.synced_entra_groups[each.value.group_key].id

  preferred_member_key {
    id = each.value.member_email
  }

  roles {
    name = "MEMBER"
  }
}

# Look up existing Gemini Enterprise Per-App Cloud Identity groups (<app-id>-users@<primary_customer_domain>)
data "google_cloud_identity_group_lookup" "target_app_groups" {
  for_each = local.distinct_target_app_groups

  group_key {
    id = each.value
  }

  depends_on = [google_project_service.identity_apis]
}

# Nest synced Entra groups (or mapped users) into Gemini Enterprise Per-App Cloud Identity groups
resource "google_cloud_identity_group_membership" "app_group_nested_members" {
  for_each = local.app_group_membership_map
  group    = data.google_cloud_identity_group_lookup.target_app_groups[each.value.app_group_email].name

  preferred_member_key {
    id = each.value.member_email
  }

  roles {
    name = "MEMBER"
  }

  depends_on = [google_cloud_identity_group.synced_entra_groups]
}

# Optional: Workforce Identity Federation OIDC Pool & Provider using the same Secret Manager credentials
resource "google_iam_workforce_pool" "entra_oidc" {
  count             = var.enable_workforce_pool_oidc && trimspace(var.organization_id) != "" ? 1 : 0
  workforce_pool_id = var.workforce_pool_id
  parent            = "organizations/${trimspace(var.organization_id)}"
  location          = "global"
  display_name      = "Microsoft Entra ID Shared Domain Pool"
  description       = "Workforce Identity Pool federated with Microsoft Entra ID (${var.shared_identity_domain})"
  session_duration  = "3600s"
}

resource "google_iam_workforce_pool_provider" "entra_oidc" {
  count             = var.enable_workforce_pool_oidc && trimspace(var.organization_id) != "" ? 1 : 0
  workforce_pool_id = google_iam_workforce_pool.entra_oidc[0].workforce_pool_id
  location          = google_iam_workforce_pool.entra_oidc[0].location
  provider_id       = var.workforce_provider_id
  display_name      = "Microsoft Entra ID OIDC Provider"
  description       = "OIDC provider backed by Secret Manager secret ${var.m365_secret_id}"

  attribute_mapping = {
    "google.subject"      = "assertion.sub"
    "google.display_name" = "assertion.preferred_username"
    "google.groups"       = "assertion.groups"
  }

  oidc {
    issuer_uri = "https://login.microsoftonline.com/${local.effective_m365_tenant_id}/v2.0"
    client_id  = local.effective_m365_client_id

    client_secret {
      value {
        plain_text = local.effective_m365_client_secret
      }
    }

    web_sso_config {
      response_type             = "CODE"
      assertion_claims_behavior = "MERGE_USER_INFO_OVER_ID_TOKEN_CLAIMS"
    }
  }

  extra_attributes_oauth2_client {
    attributes_type = "AZURE_AD_GROUPS_MAIL"
    issuer_uri      = "https://login.microsoftonline.com/${local.effective_m365_tenant_id}/v2.0"
    client_id       = local.effective_m365_client_id

    client_secret {
      value {
        plain_text = local.effective_m365_client_secret
      }
    }
  }
}
