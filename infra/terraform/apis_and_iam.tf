# Google Cloud API Enablement and Per-App Cloud Identity Group Provisioning

data "google_project" "current" {
  project_id = var.project_id
}

locals {
  required_apis = toset([
    "discoveryengine.googleapis.com",
    "aiplatform.googleapis.com",
    "storage.googleapis.com",
    "bigquery.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "cloudidentity.googleapis.com"
  ])

  resolved_app_access_group = trimspace(var.app_access_group) != "" ? trimspace(var.app_access_group) : "${var.app_id}-users@${var.customer_domain}"

  group_member_emails = [
    for m in split(",", var.app_group_members) : trimspace(m)
    if trimspace(m) != ""
  ]
}

resource "google_project_service" "main" {
  for_each = local.required_apis

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}

# Dedicated Cloud Identity group per Gemini Enterprise App (when cloud_identity_customer_id is set)
resource "google_cloud_identity_group" "app_group" {
  count                = trimspace(var.cloud_identity_customer_id) != "" ? 1 : 0
  display_name         = "${var.app_display_name} Users"
  description          = "Dedicated access control group for Gemini Enterprise App ${var.app_id}"
  initial_group_config = "EMPTY"
  parent               = trimspace(var.cloud_identity_customer_id)

  group_key {
    id = local.resolved_app_access_group
  }

  labels = {
    "cloudidentity.googleapis.com/groups.discussion_forum" = ""
  }

  lifecycle {
    ignore_changes = [display_name, description, labels, initial_group_config]
  }

  depends_on = [google_project_service.main]
}

# Membership bindings for the app's dedicated Cloud Identity group
resource "google_cloud_identity_group_membership" "app_group_members" {
  for_each = trimspace(var.cloud_identity_customer_id) != "" ? toset(local.group_member_emails) : toset([])
  group    = google_cloud_identity_group.app_group[0].id

  preferred_member_key {
    id = each.value
  }

  roles {
    name = "MEMBER"
  }
}

# Least-privilege Custom Role for Connector OAuth (widgetBuildAuthorizationUrl & acquireAndStoreRefreshToken)
resource "google_project_iam_custom_role" "connector_auth_user" {
  project     = var.project_id
  role_id     = "geConnectorAuthUser"
  title       = "Gemini Enterprise Connector OAuth User"
  description = "Least-privilege location and dataConnector OAuth permissions without granting cross-app Engine access."
  stage       = "GA"

  permissions = [
    "discoveryengine.authorizations.storeUserAuthorization",
    "discoveryengine.collections.get",
    "discoveryengine.dataConnectors.acquireAccessToken",
    "discoveryengine.dataConnectors.acquireAndStoreRefreshToken",
    "discoveryengine.dataConnectors.buildActionInvocation",
    "discoveryengine.dataConnectors.checkRefreshToken",
    "discoveryengine.dataConnectors.executeAction",
    "discoveryengine.dataConnectors.queryAvailableActions",
    "discoveryengine.dataStores.get",
    "discoveryengine.locations.buildAuthorizationUrl",
    "discoveryengine.locations.completeExternalIdentities",
    "discoveryengine.locations.fetchAgentCards",
    "discoveryengine.locations.listConnectorSources",
    "discoveryengine.users.get",
    "discoveryengine.users.update",
  ]

  depends_on = [google_project_service.main]
}

resource "google_project_iam_member" "app_group_connector_auth" {
  count   = trimspace(var.cloud_identity_customer_id) != "" ? 1 : 0
  project = var.project_id
  role    = google_project_iam_custom_role.connector_auth_user.name
  member  = "group:${google_cloud_identity_group.app_group[0].group_key[0].id}"
}
