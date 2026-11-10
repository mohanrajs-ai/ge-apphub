# ServiceNow Discovery Engine Data Connector & BAP Write Actions

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

resource "google_secret_manager_secret" "servicenow_credentials" {
  project   = var.project_id
  secret_id = var.servicenow_secret_id

  replication {
    auto {}
  }

  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "servicenow_credentials_initial" {
  secret = google_secret_manager_secret.servicenow_credentials.id
  secret_data = jsonencode({
    instance_uri  = var.servicenow_instance_uri
    client_id     = var.servicenow_client_id
    client_secret = var.servicenow_client_secret
    refresh_token = var.servicenow_refresh_token
    username      = var.servicenow_username
    password      = var.servicenow_password
  })

  lifecycle {
    ignore_changes = [secret_data]
  }
}

data "google_secret_manager_secret_version" "servicenow_credentials_latest" {
  project    = var.project_id
  secret     = google_secret_manager_secret.servicenow_credentials.secret_id
  version    = "latest"
  depends_on = [google_secret_manager_secret_version.servicenow_credentials_initial]
}

locals {
  sn_secret_json          = jsondecode(data.google_secret_manager_secret_version.servicenow_credentials_latest.secret_data)
  effective_instance_uri  = var.servicenow_instance_uri != "" ? var.servicenow_instance_uri : try(local.sn_secret_json.instance_uri, "")
  effective_client_id     = var.servicenow_client_id != "" ? var.servicenow_client_id : try(local.sn_secret_json.client_id, "")
  effective_client_secret = var.servicenow_client_secret != "" ? var.servicenow_client_secret : try(local.sn_secret_json.client_secret, "")
  effective_refresh_token = var.servicenow_refresh_token != "" ? var.servicenow_refresh_token : try(local.sn_secret_json.refresh_token, "")
  effective_username      = var.servicenow_username != "" ? var.servicenow_username : try(local.sn_secret_json.username, "")
  effective_password      = var.servicenow_password != "" ? var.servicenow_password : try(local.sn_secret_json.password, "")

  servicenow_entity_list = [
    for e in split(",", var.servicenow_entities) : trimspace(e)
    if trimspace(e) != ""
  ]

  servicenow_action_list = [
    for a in split(",", var.servicenow_enabled_actions) : trimspace(a)
    if trimspace(a) != ""
  ]

  servicenow_supports_actions = var.enable_servicenow_actions == "true"
}

resource "google_discovery_engine_data_connector" "servicenow" {
  project                   = var.project_id
  location                  = var.location
  collection_id             = var.servicenow_collection_id
  collection_display_name   = replace(var.servicenow_collection_display_name, "&", "and")
  data_source               = "servicenow"
  connector_modes           = local.servicenow_supports_actions ? distinct([var.servicenow_connector_mode, "ACTIONS"]) : [var.servicenow_connector_mode]
  refresh_interval          = var.servicenow_refresh_interval
  auto_run_disabled         = var.servicenow_connector_mode == "FEDERATED"
  incremental_sync_disabled = var.servicenow_connector_mode == "FEDERATED"

  json_params = jsonencode({
    instance_uri  = local.effective_instance_uri
    client_id     = local.effective_client_id
    client_secret = local.effective_client_secret
    user_account  = local.effective_username
    password      = local.effective_password
  })

  dynamic "entities" {
    for_each = local.servicenow_entity_list
    content {
      entity_name = entities.value
    }
  }

  dynamic "destination_configs" {
    for_each = local.servicenow_supports_actions ? [1] : []
    content {
      key = "host_url"
      destinations {
        host = local.effective_instance_uri
      }
    }
  }

  dynamic "action_config" {
    for_each = local.servicenow_supports_actions ? [1] : []
    content {
      create_bap_connection = true
      action_params = merge(
        {
          instance_uri  = local.effective_instance_uri
          client_id     = local.effective_client_id
          client_secret = local.effective_client_secret
          auth_uri      = "${local.effective_instance_uri}/oauth_auth.do"
          token_uri     = "${local.effective_instance_uri}/oauth_token.do"
        },
        local.effective_refresh_token != "" ? { refresh_token = local.effective_refresh_token } : {}
      )
    }
  }

  dynamic "bap_config" {
    for_each = local.servicenow_supports_actions && length(local.servicenow_action_list) > 0 ? [1] : []
    content {
      supported_connector_modes = ["ACTIONS"]
      enabled_actions           = local.servicenow_action_list
    }
  }

  lifecycle {
    ignore_changes = [tag, static_ip_enabled, entities, json_params, action_config, destination_configs, auto_run_disabled, incremental_sync_disabled]
  }

  depends_on = [
    google_project_service.discoveryengine,
    data.google_secret_manager_secret_version.servicenow_credentials_latest,
  ]
}
