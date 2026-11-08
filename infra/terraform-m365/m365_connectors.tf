# Microsoft 365 (SharePoint, OneDrive, Outlook, Teams) Discovery Engine Data Connectors

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service" "discoveryengine" {
  project            = var.project_id
  service            = "discoveryengine.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "secretmanager" {
  project            = var.project_id
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = false
}

resource "google_secret_manager_secret" "m365_credentials" {
  project   = var.project_id
  secret_id = var.m365_secret_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "m365_credentials_initial" {
  secret = google_secret_manager_secret.m365_credentials.id
  secret_data = jsonencode({
    tenant_id     = var.m365_tenant_id
    client_id     = var.m365_client_id
    client_secret = var.m365_client_secret
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "google_secret_manager_secret_version" "m365_credentials_latest" {
  project    = var.project_id
  secret     = google_secret_manager_secret.m365_credentials.secret_id
  version    = "latest"
  depends_on = [google_secret_manager_secret_version.m365_credentials_initial]
}

locals {
  m365_secret_json             = jsondecode(data.google_secret_manager_secret_version.m365_credentials_latest.secret_data)
  effective_m365_tenant_id     = var.m365_tenant_id != "" ? var.m365_tenant_id : try(local.m365_secret_json.tenant_id, "")
  effective_m365_client_id     = var.m365_client_id != "" ? var.m365_client_id : try(local.m365_secret_json.client_id, "")
  effective_m365_client_secret = var.m365_client_secret != "" ? var.m365_client_secret : try(local.m365_secret_json.client_secret, "")

  sharepoint_entity_list = [
    for e in split(",", var.m365_sharepoint_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  onedrive_entity_list = [
    for e in split(",", var.m365_onedrive_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  outlook_entity_list = [
    for e in split(",", var.m365_outlook_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  teams_entity_list = [
    for e in split(",", var.m365_teams_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  sharepoint_action_list = [
    for a in split(",", var.m365_sharepoint_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  onedrive_action_list = [
    for a in split(",", var.m365_onedrive_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  outlook_action_list = [
    for a in split(",", var.m365_outlook_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  teams_action_list = [
    for a in split(",", var.m365_teams_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  effective_onedrive_uri = var.m365_onedrive_instance_uri != "" ? var.m365_onedrive_instance_uri : var.m365_sharepoint_instance_uri

  sharepoint_collection_id = var.m365_sharepoint_collection_id != "" ? var.m365_sharepoint_collection_id : "${var.m365_collection_prefix}-sp"
  onedrive_collection_id   = var.m365_onedrive_collection_id != "" ? var.m365_onedrive_collection_id : "${var.m365_collection_prefix}-od"
  outlook_collection_id    = var.m365_outlook_collection_id != "" ? var.m365_outlook_collection_id : "${var.m365_collection_prefix}-ol"
  teams_collection_id      = var.m365_teams_collection_id != "" ? var.m365_teams_collection_id : "${var.m365_collection_prefix}-teams"

  # sharepoint_federated_search only supports FEDERATED mode; standard sharepoint supports ACTIONS
  sharepoint_supports_actions = var.enable_m365_actions == "true" && var.m365_sharepoint_data_source == "sharepoint"
  onedrive_supports_actions   = var.enable_m365_actions == "true"
  outlook_supports_actions    = var.enable_m365_actions == "true"
  teams_supports_actions      = var.enable_m365_actions == "true"
}

# 1. Microsoft SharePoint Online Data Connector
resource "google_discovery_engine_data_connector" "sharepoint" {
  count = var.enable_sharepoint_connector == "true" ? 1 : 0

  project                   = var.project_id
  location                  = var.location
  collection_id             = local.sharepoint_collection_id
  collection_display_name   = "M365 SharePoint Online (${var.m365_collection_prefix})"
  data_source               = var.m365_sharepoint_data_source
  connector_modes           = local.sharepoint_supports_actions ? distinct([var.m365_sharepoint_connector_mode, "ACTIONS"]) : [var.m365_sharepoint_connector_mode]
  refresh_interval          = var.m365_refresh_interval
  auto_run_disabled         = var.m365_sharepoint_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.m365_sharepoint_connector_mode == "FEDERATED"

  json_params = jsonencode({
    tenant_id     = local.effective_m365_tenant_id
    client_id     = local.effective_m365_client_id
    client_secret = local.effective_m365_client_secret
    instance_uri  = var.m365_sharepoint_instance_uri
  })

  dynamic "entities" {
    for_each = local.sharepoint_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "destination_configs" {
    for_each = local.sharepoint_supports_actions ? [1] : []
    content {
      key = "url"
      destinations {
        host = var.m365_sharepoint_instance_uri
      }
    }
  }

  dynamic "action_config" {
    for_each = local.sharepoint_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = {
        auth_type         = "OAUTH"
        azure_environment = "GLOBAL"
        tenant_id         = local.effective_m365_tenant_id
        client_id         = local.effective_m365_client_id
        client_secret     = local.effective_m365_client_secret
        instance_uri      = var.m365_sharepoint_instance_uri
      }
    }
  }

  dynamic "bap_config" {
    for_each = local.sharepoint_supports_actions ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.sharepoint_action_list
    }
  }

  lifecycle {
    ignore_changes = [tag, static_ip_enabled, entities, json_params, action_config, destination_configs, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [google_project_service.discoveryengine]
}

# 2. Microsoft OneDrive Data Connector
resource "google_discovery_engine_data_connector" "onedrive" {
  count = var.enable_onedrive_connector == "true" ? 1 : 0

  project                   = var.project_id
  location                  = var.location
  collection_id             = local.onedrive_collection_id
  collection_display_name   = "M365 OneDrive (${var.m365_collection_prefix})"
  data_source               = "onedrive"
  connector_modes           = local.onedrive_supports_actions ? distinct([var.m365_onedrive_connector_mode, "ACTIONS"]) : [var.m365_onedrive_connector_mode]
  refresh_interval          = var.m365_refresh_interval
  auto_run_disabled         = var.m365_onedrive_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.m365_onedrive_connector_mode == "FEDERATED"

  json_params = jsonencode({
    tenant_id     = local.effective_m365_tenant_id
    client_id     = local.effective_m365_client_id
    client_secret = local.effective_m365_client_secret
    instance_uri  = local.effective_onedrive_uri
  })

  dynamic "entities" {
    for_each = local.onedrive_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "destination_configs" {
    for_each = local.onedrive_supports_actions ? [1] : []
    content {
      key = "url"
      destinations {
        host = local.effective_onedrive_uri
      }
    }
  }

  dynamic "action_config" {
    for_each = local.onedrive_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = {
        auth_key              = "OAuth"
        auth_type             = "OAUTH"
        tenant_id             = local.effective_m365_tenant_id
        client_id             = local.effective_m365_client_id
        client_secret         = local.effective_m365_client_secret
        o365_environment_type = "com"
        azure_tenant          = local.effective_m365_tenant_id
        azure_environment     = "GLOBAL"
      }
    }
  }

  dynamic "bap_config" {
    for_each = local.onedrive_supports_actions ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.onedrive_action_list
    }
  }

  lifecycle {
    ignore_changes = [tag, static_ip_enabled, entities, json_params, action_config, destination_configs, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [google_project_service.discoveryengine]
}

# 3. Microsoft Outlook Data Connector
resource "google_discovery_engine_data_connector" "outlook" {
  count = var.enable_outlook_connector == "true" ? 1 : 0

  project                   = var.project_id
  location                  = var.location
  collection_id             = local.outlook_collection_id
  collection_display_name   = "M365 Outlook (${var.m365_collection_prefix})"
  data_source               = "outlook"
  connector_modes           = local.outlook_supports_actions ? distinct([var.m365_outlook_connector_mode, "ACTIONS"]) : [var.m365_outlook_connector_mode]
  refresh_interval          = var.m365_refresh_interval
  auto_run_disabled         = var.m365_outlook_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.m365_outlook_connector_mode == "FEDERATED"

  json_params = jsonencode({
    instance_id = local.effective_m365_tenant_id
    client_id   = local.effective_m365_client_id
  })

  dynamic "entities" {
    for_each = local.outlook_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "action_config" {
    for_each = local.outlook_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = {
        auth_key              = "OAuth"
        auth_type             = "OAUTH"
        instance_id           = local.effective_m365_tenant_id
        client_id             = local.effective_m365_client_id
        client_secret         = local.effective_m365_client_secret
        o365_environment_type = "com"
        azure_tenant          = local.effective_m365_tenant_id
        azure_environment     = "GLOBAL"
      }
    }
  }

  dynamic "bap_config" {
    for_each = local.outlook_supports_actions ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.outlook_action_list
    }
  }

  lifecycle {
    ignore_changes = [tag, static_ip_enabled, entities, json_params, action_config, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [google_project_service.discoveryengine]
}

# 4. Microsoft Teams Data Connector
resource "google_discovery_engine_data_connector" "teams" {
  count = var.enable_teams_connector == "true" ? 1 : 0

  project                   = var.project_id
  location                  = var.location
  collection_id             = local.teams_collection_id
  collection_display_name   = "M365 Microsoft Teams (${var.m365_collection_prefix})"
  data_source               = "teams"
  connector_modes           = local.teams_supports_actions ? distinct([var.m365_teams_connector_mode, "ACTIONS"]) : [var.m365_teams_connector_mode]
  refresh_interval          = var.m365_refresh_interval
  auto_run_disabled         = var.m365_teams_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.m365_teams_connector_mode == "FEDERATED"

  json_params = jsonencode({
    instance_id   = local.effective_m365_tenant_id
    client_id     = local.effective_m365_client_id
    client_secret = local.effective_m365_client_secret
    domain_url    = var.m365_teams_instance_uri
  })

  dynamic "entities" {
    for_each = local.teams_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "action_config" {
    for_each = local.teams_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = {
        auth_key           = "OAuth"
        auth_type          = "OAUTH"
        instance_id        = local.effective_m365_tenant_id
        client_id          = local.effective_m365_client_id
        client_secret      = local.effective_m365_client_secret
        azure_tenant       = local.effective_m365_tenant_id
        include_all_groups = "true"
        include_all_users  = "true"
      }
    }
  }

  dynamic "bap_config" {
    for_each = local.teams_supports_actions ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.teams_action_list
    }
  }

  lifecycle {
    ignore_changes = [tag, static_ip_enabled, entities, json_params, action_config, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [google_project_service.discoveryengine]
}
