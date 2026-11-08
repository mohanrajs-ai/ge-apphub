# ==============================================================================
# Reusable Terraform Module: Microsoft Entra ID Bootstrap (Step 0A Automation)
# ==============================================================================
# Automates:
#   1. Entra OAuth 2.0 App Registration (<customer>-ge-m365-connector)
#      with Redirect URI https://vertexaisearch.cloud.google.com/oauth-redirect
#   2. All Microsoft Graph Application & Delegated permissions + SharePoint
#      Online Delegated permissions
#   3. Tenant-wide Admin Consent (azuread_app_role_assignment +
#      azuread_service_principal_delegated_permission_grant)
#   4. Client Secret rotation -> Direct write into Google Cloud Secret Manager
#   5. Entra SAML 2.0 Gallery App ("Google Cloud / G Suite Connector by Microsoft")
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 2.47.0"
    }
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0.0"
    }
  }
}

variable "gcp_project_id" {
  type        = string
  description = "Target Google Cloud Project ID where Secret Manager stores M365 credentials."
}

variable "customer_name" {
  type        = string
  default     = "cymbal"
  description = "Short customer slug used for naming Entra applications."
}

variable "customer_domain" {
  type        = string
  default     = "cymbal.com"
  description = "Primary verified corporate domain in Microsoft Entra ID & Cloud Identity."
}

variable "m365_secret_id" {
  type        = string
  default     = "cymbal-m365-connector-credentials"
  description = "Google Cloud Secret Manager secret ID for storing {tenant_id, client_id, client_secret}."
}

variable "saml_sp_entity_id" {
  type        = string
  default     = ""
  description = "Optional Cloud Identity Inbound SAML Profile Entity ID (https://accounts.google.com/samlrp/<profile_id>)."
}

variable "saml_sp_acs_url" {
  type        = string
  default     = ""
  description = "Optional Cloud Identity Inbound SAML Profile ACS URL (https://accounts.google.com/samlrp/<profile_id>/acs)."
}

data "azuread_client_config" "current" {}

# Look up Microsoft Graph & Office 365 SharePoint Online well-known Service Principals
data "azuread_application_published_app_ids" "well_known" {}

data "azuread_service_principal" "msgraph" {
  client_id = data.azuread_application_published_app_ids.well_known.result["MicrosoftGraph"]
}

data "azuread_service_principal" "sharepoint" {
  client_id = data.azuread_application_published_app_ids.well_known.result["Office365SharePointOnline"]
}

locals {
  # Microsoft Graph Application Permissions (App Roles)
  msgraph_app_roles = [
    "User.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All",
    "Sites.Read.All",
    "Files.Read.All",
    "Mail.Read",
  ]

  # Microsoft Graph Delegated Permissions (OAuth2 Permission Scopes)
  msgraph_delegated_scopes = [
    "openid",
    "profile",
    "offline_access",
    "User.Read",
    "Mail.ReadWrite",
    "Mail.ReadWrite.Shared",
    "Mail.Send",
    "Mail.Send.Shared",
    "Calendars.ReadWrite",
    "Contacts.ReadWrite",
    "Files.ReadWrite.All",
    "Sites.ReadWrite.All",
    "Chat.Read",
    "Chat.ReadWrite",
    "ChannelMessage.Read.All",
    "ChannelMessage.Send",
    "Team.ReadBasic.All",
    "Channel.ReadBasic.All",
    "Channel.Create",
  ]

  # SharePoint Online Delegated Permissions
  sharepoint_delegated_scopes = [
    "AllSites.Write",
    "MyFiles.Read",
  ]
}

# 1. OAuth 2.0 App Registration for M365 Connectors & Graph Group Sync
resource "azuread_application" "m365_connector" {
  display_name     = "${var.customer_name}-ge-m365-connector"
  sign_in_audience = "AzureADMyOrg"

  web {
    redirect_uris = [
      "https://vertexaisearch.cloud.google.com/oauth-redirect",
    ]
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.msgraph.client_id

    dynamic "resource_access" {
      for_each = local.msgraph_app_roles
      content {
        id   = data.azuread_service_principal.msgraph.app_role_ids[resource_access.value]
        type = "Role"
      }
    }

    dynamic "resource_access" {
      for_each = local.msgraph_delegated_scopes
      content {
        id   = data.azuread_service_principal.msgraph.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }

  required_resource_access {
    resource_app_id = data.azuread_service_principal.sharepoint.client_id

    dynamic "resource_access" {
      for_each = local.sharepoint_delegated_scopes
      content {
        id   = data.azuread_service_principal.sharepoint.oauth2_permission_scope_ids[resource_access.value]
        type = "Scope"
      }
    }
  }
}

resource "azuread_service_principal" "m365_connector" {
  client_id                    = azuread_application.m365_connector.client_id
  app_role_assignment_required = false
}

resource "azuread_application_password" "m365_connector_secret" {
  application_id = azuread_application.m365_connector.id
  display_name   = "Gemini Enterprise M365 Connector & Graph Sync"
}

# 2. Automated Tenant-Wide Admin Consent (Application + Delegated Permissions)
resource "azuread_app_role_assignment" "msgraph_admin_consent" {
  for_each            = toset(local.msgraph_app_roles)
  app_role_id         = data.azuread_service_principal.msgraph.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.m365_connector.object_id
  resource_object_id  = data.azuread_service_principal.msgraph.object_id
}

resource "azuread_service_principal_delegated_permission_grant" "msgraph_delegated_consent" {
  service_principal_object_id          = azuread_service_principal.m365_connector.object_id
  resource_service_principal_object_id = data.azuread_service_principal.msgraph.object_id
  claim_values                         = local.msgraph_delegated_scopes
}

resource "azuread_service_principal_delegated_permission_grant" "sharepoint_delegated_consent" {
  service_principal_object_id          = azuread_service_principal.m365_connector.object_id
  resource_service_principal_object_id = data.azuread_service_principal.sharepoint.object_id
  claim_values                         = local.sharepoint_delegated_scopes
}

# 3. Direct Sync of {tenant_id, client_id, client_secret} into GCP Secret Manager
resource "google_secret_manager_secret" "m365_credentials" {
  project   = var.gcp_project_id
  secret_id = var.m365_secret_id
  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "m365_credentials_version" {
  secret = google_secret_manager_secret.m365_credentials.id
  secret_data = jsonencode({
    tenant_id     = data.azuread_client_config.current.tenant_id
    client_id     = azuread_application.m365_connector.client_id
    client_secret = azuread_application_password.m365_connector_secret.value
  })
}

# 4. SAML 2.0 Gallery App ("Google Cloud / G Suite Connector by Microsoft")
resource "azuread_application_from_template" "google_cloud_saml" {
  display_name = "${upper(var.customer_name)} Google Cloud & Gemini Enterprise SSO"
  template_id  = "8b1025e4-1dd2-430b-a150-2ef79cd700f5"
}

data "azuread_service_principal" "google_cloud_saml" {
  object_id = azuread_application_from_template.google_cloud_saml.service_principal_object_id
}

resource "azuread_service_principal_token_signing_certificate" "saml_cert" {
  service_principal_id = data.azuread_service_principal.google_cloud_saml.id
  display_name         = "CN=${var.customer_name} Google Cloud SAML Signing"
}

output "entra_tenant_id" {
  value       = data.azuread_client_config.current.tenant_id
  description = "Microsoft Entra ID Tenant UUID."
}

output "entra_m365_client_id" {
  value       = azuread_application.m365_connector.client_id
  description = "OAuth 2.0 Client ID for Gemini Enterprise M365 Connectors."
}

output "gcp_secret_manager_resource" {
  value       = google_secret_manager_secret.m365_credentials.name
  description = "Secret Manager secret populated with Entra OAuth credentials."
}

output "saml_idp_certificate_pem" {
  value       = azuread_service_principal_token_signing_certificate.saml_cert.value
  sensitive   = true
  description = "Base64 X.509 SAML signing certificate for Cloud Identity Inbound SAML Profile."
}
