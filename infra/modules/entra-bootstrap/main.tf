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

variable "entra_tenant_id" {
  type        = string
  default     = ""
  description = "Microsoft Entra ID Tenant UUID or primary domain."
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

variable "create_entra_department_groups" {
  type        = bool
  default     = true
  description = "Whether to automatically create and assign the 5 Gemini Enterprise department security groups to the SAML Enterprise App."
}

variable "entra_department_groups" {
  type        = list(string)
  default = [
    "ge-service-desk-users",
    "ge-finance-users",
    "ge-hr-users",
    "ge-skill-developers",
    "all-ge-apps-users",
  ]
  description = "Mail nicknames of Microsoft Entra ID Security Groups assigned to the Google Cloud SAML Enterprise App."
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
  # ============================================================================
  # Complete Permission Matrix for All 4 M365 Applications + Identity Sync:
  #   1. SharePoint Online (m365-sp) — Federated Search, Ingestion & 18 Actions
  #   2. OneDrive (m365-od)          — Federated Search, Ingestion & 10 Actions
  #   3. Outlook (m365-ol)           — Mail, Attachment, Calendar, Contact & 15 Actions
  #   4. Microsoft Teams (m365-teams)— Channel/Chat Search & 3 Write Actions
  #   5. Entra -> Cloud Identity Sync— Users, Groups & Transitive Memberships
  # ============================================================================

  # 1. Microsoft Graph — Application Permissions (App Roles)
  msgraph_app_roles = [
    # Identity & Group Sync (Entra ID -> Cloud Identity)
    "User.Read.All",
    "Group.Read.All",
    "GroupMember.Read.All",
    # SharePoint Online & OneDrive (Ingestion & ACL Indexing)
    "Sites.Read.All",
    "Files.Read.All",
    # Outlook Mail, Calendar & Contacts (Ingestion & Metadata)
    "Mail.Read",
    "Calendars.Read",
    "Contacts.Read",
    # Microsoft Teams (Channels, Chats & Team Metadata)
    "Team.ReadBasic.All",
    "Channel.ReadBasic.All",
    "ChannelMessage.Read.All",
    "Chat.Read.All",
  ]

  # 2. Microsoft Graph — Delegated Permissions (3-Legged End-User OAuth + BAP Actions)
  msgraph_delegated_scopes = [
    # OpenID Connect & Core User Profile
    "openid",
    "profile",
    "email",
    "offline_access",
    "User.Read",
    "People.Read",
    # SharePoint Online & OneDrive (Search + 18 SharePoint Actions & 10 OneDrive Actions)
    "Files.Read.All",
    "Files.ReadWrite.All",
    "Sites.Read.All",
    "Sites.ReadWrite.All",
    "Sites.Manage.All",
    # Outlook Mail, Calendar & Contacts (Search + 15 Mail/Calendar/Contact Actions)
    "Mail.Read",
    "Mail.ReadWrite",
    "Mail.ReadWrite.Shared",
    "Mail.Send",
    "Mail.Send.Shared",
    "Calendars.Read",
    "Calendars.ReadWrite",
    "Calendars.Read.Shared",
    "Contacts.Read",
    "Contacts.ReadWrite",
    "Contacts.ReadWrite.Shared",
    "MailboxSettings.Read",
    # Microsoft Teams (Channel/Chat Federated Search + send_channel_message, send_chat_message, create_channel)
    "Chat.Read",
    "Chat.ReadWrite",
    "ChatMessage.Send",
    "ChannelMessage.Read.All",
    "ChannelMessage.Send",
    "Team.ReadBasic.All",
    "Channel.ReadBasic.All",
    "Channel.Create",
  ]

  # 3. Office 365 SharePoint Online — Application Permissions (App Roles)
  sharepoint_app_roles = [
    "Sites.Read.All",
  ]

  # 4. Office 365 SharePoint Online — Delegated Permissions (Federated Search & Lists/Pages Actions)
  sharepoint_delegated_scopes = [
    "AllSites.Read",
    "AllSites.Write",
    "AllSites.Manage",
    "MyFiles.Read",
    "MyFiles.Write",
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
      for_each = local.sharepoint_app_roles
      content {
        id   = data.azuread_service_principal.sharepoint.app_role_ids[resource_access.value]
        type = "Role"
      }
    }

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

resource "azuread_app_role_assignment" "sharepoint_admin_consent" {
  for_each            = toset(local.sharepoint_app_roles)
  app_role_id         = data.azuread_service_principal.sharepoint.app_role_ids[each.value]
  principal_object_id = azuread_service_principal.m365_connector.object_id
  resource_object_id  = data.azuread_service_principal.sharepoint.object_id
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

# 4. Step 0A.2 Automation: SAML 2.0 Gallery App ("Google Cloud / G Suite Connector by Microsoft")
#    + Department Security Groups Creation & Assignment + SAML Signing Certificate
resource "azuread_application_from_template" "google_cloud_saml" {
  display_name = "${upper(var.customer_name)} Google Cloud & Gemini Enterprise SSO"
  template_id  = "8b1025e4-1dd2-430b-a150-2ef79cd700f5"
}

data "azuread_service_principal" "google_cloud_saml" {
  object_id = azuread_application_from_template.google_cloud_saml.service_principal_object_id
}

# Configure SAML Entity ID (Identifier URI) when Cloud Identity SP Entity ID is provided
resource "azuread_application_identifier_uri" "google_cloud_saml_sp_entity_id" {
  count          = var.saml_sp_entity_id != "" ? 1 : 0
  application_id = azuread_application_from_template.google_cloud_saml.application_id
  identifier_uri = var.saml_sp_entity_id
}

# Configure SAML Reply URLs (Assertion Consumer Service URLs)
resource "azuread_application_redirect_uris" "google_cloud_saml_acs_urls" {
  application_id = azuread_application_from_template.google_cloud_saml.application_id
  type           = "Web"
  redirect_uris = compact(distinct([
    var.saml_sp_acs_url,
    "https://www.google.com/a/${var.customer_domain}/acs",
    "https://www.google.com",
  ]))
}

# Generate SAML 2.0 Token Signing Certificate on the Gallery Service Principal
resource "azuread_service_principal_token_signing_certificate" "saml_cert" {
  service_principal_id = data.azuread_service_principal.google_cloud_saml.id
  display_name         = "CN=${var.customer_name} Google Cloud SAML Signing"
}

# Create the 5 Gemini Enterprise Department Security Groups in Entra ID
resource "azuread_group" "department_groups" {
  for_each         = var.create_entra_department_groups ? toset(var.entra_department_groups) : toset([])
  display_name     = "${upper(var.customer_name)} ${each.value}"
  mail_nickname    = each.value
  security_enabled = true
  description      = "Gemini Enterprise department access group (${each.value}@${var.customer_domain}) synced 1:1 to Google Cloud Identity."
}

# Assign all 5 Department Security Groups to the Google Cloud SAML Enterprise App
resource "azuread_app_role_assignment" "saml_group_assignments" {
  for_each            = azuread_group.department_groups
  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = each.value.object_id
  resource_object_id  = data.azuread_service_principal.google_cloud_saml.object_id
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

output "saml_application_object_id" {
  value       = azuread_application_from_template.google_cloud_saml.application_object_id
  description = "Application Object ID of the Google Cloud SAML Gallery App."
}

output "saml_service_principal_object_id" {
  value       = azuread_application_from_template.google_cloud_saml.service_principal_object_id
  description = "Service Principal Object ID of the Google Cloud SAML Gallery App."
}

output "saml_idp_entity_id" {
  value       = "https://sts.windows.net/${data.azuread_client_config.current.tenant_id}/"
  description = "Microsoft Entra ID SAML 2.0 IdP Entity ID."
}

output "saml_idp_sso_url" {
  value       = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/saml2"
  description = "Microsoft Entra ID SAML 2.0 Single Sign-On Service URL."
}

output "saml_idp_certificate_pem" {
  value       = azuread_service_principal_token_signing_certificate.saml_cert.value
  sensitive   = true
  description = "Base64 X.509 SAML signing certificate for Cloud Identity Inbound SAML Profile."
}
