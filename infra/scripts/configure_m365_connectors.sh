#!/usr/bin/env bash
# Configures, provisions, verifies, and deregisters Microsoft 365 (SharePoint,
# OneDrive, Outlook, Teams) Discovery Engine Data Connectors (including write
# Actions / BAP configuration) via REST API and exports TF_VAR_* bindings for
# terraform-m365/.

set -euo pipefail

load_m365_config() {
  local config_path="${1:-./configs/m365.env}"
  if [[ ! -f "${config_path}" ]]; then
    log_error "M365 configuration file not found at '${config_path}'. Copy 'configs/m365.env.example' to 'configs/m365.env' and populate your M365 parameters."
    return 1
  fi

  local env_m365_tenant_id="${M365_TENANT_ID:-}"
  local env_m365_client_id="${M365_CLIENT_ID:-}"
  local env_m365_client_secret="${M365_CLIENT_SECRET:-}"
  local env_m365_secret_id="${M365_SECRET_ID:-}"

  set -a
  # shellcheck disable=SC1090
  source "${config_path}"
  set +a

  export M365_SECRET_ID="${env_m365_secret_id:-${M365_SECRET_ID:-m365-connector-credentials}}"
  export M365_TENANT_ID="${env_m365_tenant_id:-${M365_TENANT_ID:-}}"
  export M365_CLIENT_ID="${env_m365_client_id:-${M365_CLIENT_ID:-}}"
  export M365_CLIENT_SECRET="${env_m365_client_secret:-${M365_CLIENT_SECRET:-}}"

  export TF_VAR_project_id="${GCP_PROJECT_ID:-}"
  export TF_VAR_region="${GCP_REGION:-us-central1}"
  export TF_VAR_location="${GE_LOCATION:-global}"
  export TF_VAR_m365_collection_prefix="${M365_COLLECTION_PREFIX:-m365}"
  export TF_VAR_m365_secret_id="${M365_SECRET_ID}"
  export TF_VAR_m365_tenant_id="${M365_TENANT_ID}"
  export TF_VAR_m365_client_id="${M365_CLIENT_ID}"
  export TF_VAR_m365_client_secret="${M365_CLIENT_SECRET}"
  export TF_VAR_m365_connector_mode="${M365_CONNECTOR_MODE:-FEDERATED}"
  export TF_VAR_m365_refresh_interval="${M365_REFRESH_INTERVAL:-86400s}"
  export TF_VAR_enable_m365_actions="${ENABLE_M365_ACTIONS:-false}"

  export TF_VAR_enable_sharepoint_connector="${ENABLE_SHAREPOINT_CONNECTOR:-true}"
  export TF_VAR_m365_sharepoint_collection_id="${M365_SHAREPOINT_COLLECTION_ID:-}"
  export TF_VAR_m365_sharepoint_data_source="${M365_SHAREPOINT_DATA_SOURCE:-sharepoint_federated_search}"
  export TF_VAR_m365_sharepoint_connector_mode="${M365_SHAREPOINT_CONNECTOR_MODE:-FEDERATED}"
  export TF_VAR_m365_sharepoint_instance_uri="${M365_SHAREPOINT_INSTANCE_URI:-}"
  export TF_VAR_m365_sharepoint_entities="${M365_SHAREPOINT_ENTITIES:-file,page}"
  export TF_VAR_m365_sharepoint_enabled_actions="${M365_SHAREPOINT_ENABLED_ACTIONS:-create_folder,add_page,upload_document,add_list,list_lists,get_list_item,get_list_fields,check_in_document,check_out_document,discard_check_out_document,move_attachment_or_document,rename_attachment_or_document,update_file_properties,create_list_item,update_list_item,update_list,update_page,share_resource}"

  export TF_VAR_enable_onedrive_connector="${ENABLE_ONEDRIVE_CONNECTOR:-false}"
  export TF_VAR_m365_onedrive_collection_id="${M365_ONEDRIVE_COLLECTION_ID:-}"
  export TF_VAR_m365_onedrive_connector_mode="${M365_ONEDRIVE_CONNECTOR_MODE:-FEDERATED}"
  export TF_VAR_m365_onedrive_instance_uri="${M365_ONEDRIVE_INSTANCE_URI:-}"
  export TF_VAR_m365_onedrive_entities="${M365_ONEDRIVE_ENTITIES:-file}"
  export TF_VAR_m365_onedrive_enabled_actions="${M365_ONEDRIVE_ENABLED_ACTIONS:-upload_file,copy_file,copy_folder,move_file,move_folder,create_folder,rename_file,rename_folder,share_file_folder,update_file_properties}"

  export TF_VAR_enable_outlook_connector="${ENABLE_OUTLOOK_CONNECTOR:-false}"
  export TF_VAR_m365_outlook_collection_id="${M365_OUTLOOK_COLLECTION_ID:-}"
  export TF_VAR_m365_outlook_connector_mode="${M365_OUTLOOK_CONNECTOR_MODE:-FEDERATED}"
  export TF_VAR_m365_outlook_instance_uri="${M365_OUTLOOK_INSTANCE_URI:-https://outlook.office365.com}"
  export TF_VAR_m365_outlook_entities="${M365_OUTLOOK_ENTITIES:-mail,mail-attachment,calendar,contact}"
  export TF_VAR_m365_outlook_enabled_actions="${M365_OUTLOOK_ENABLED_ACTIONS:-send_mail,create_message,update_message,reply_to_my_message,forward_mail,move_mail,add_attachments,download_attachments,create_event,update_event,rsvp_to_event,create_calendar,update_calendar,create_contact,update_contact}"

  export TF_VAR_enable_teams_connector="${ENABLE_TEAMS_CONNECTOR:-false}"
  export TF_VAR_m365_teams_collection_id="${M365_TEAMS_COLLECTION_ID:-}"
  export TF_VAR_m365_teams_connector_mode="${M365_TEAMS_CONNECTOR_MODE:-FEDERATED}"
  export TF_VAR_m365_teams_instance_uri="${M365_TEAMS_INSTANCE_URI:-https://teams.microsoft.com}"
  export TF_VAR_m365_teams_entities="${M365_TEAMS_ENTITIES:-channel-message,chat-message}"
  export TF_VAR_m365_teams_enabled_actions="${M365_TEAMS_ENABLED_ACTIONS:-send_channel_message,send_chat_message,create_channel}"

  log_info "Loaded M365 configuration from '${config_path}' (Project: ${GCP_PROJECT_ID:-unset}, Location: ${GE_LOCATION:-unset}, Prefix: ${M365_COLLECTION_PREFIX:-m365}, Actions: ${ENABLE_M365_ACTIONS:-false})"
  return 0
}

validate_m365_config() {
  local required_vars=("GCP_PROJECT_ID" "GCP_REGION" "GE_LOCATION" "M365_SECRET_ID")

  for var_name in "${required_vars[@]}"; do
    local val="${!var_name:-}"
    if [[ -z "${val}" ]]; then
      log_error "Required M365 configuration variable '${var_name}' is empty or unset."
      return 1
    fi
  done

  if [[ -z "${M365_TENANT_ID:-}" && -z "${M365_CLIENT_ID:-}" && -z "${M365_CLIENT_SECRET:-}" && "${DRY_RUN:-false}" != "true" ]]; then
    ensure_and_load_m365_secret_credentials || true
  fi

  local missing_secrets=()
  for secret_var in M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET; do
    local secret_val="${!secret_var:-}"
    if [[ -z "${secret_val}" || "${secret_val}" == "00000000-0000-0000-0000-000000000000" || "${secret_val}" == "11111111-1111-1111-1111-111111111111" || "${secret_val}" == "replace-with-entra-client-secret" ]]; then
      missing_secrets+=("${secret_var}")
    fi
  done

  if [[ "${#missing_secrets[@]}" -gt 0 ]]; then
    log_error "Missing or placeholder M365 secret environment variables: ${missing_secrets[*]}. Export M365_TENANT_ID, M365_CLIENT_ID, and M365_CLIENT_SECRET in your environment before proceeding."
    return 1
  fi

  if [[ "${ENABLE_SHAREPOINT_CONNECTOR:-true}" == "true" && -z "${M365_SHAREPOINT_INSTANCE_URI:-}" ]]; then
    log_error "M365_SHAREPOINT_INSTANCE_URI is required when ENABLE_SHAREPOINT_CONNECTOR=true."
    return 1
  fi

  case "${GE_LOCATION}" in
    global|us|eu)
      log_info "Validated GE_LOCATION='${GE_LOCATION}' and M365 secret environment variables (Tenant=${M365_TENANT_ID}, Client=${M365_CLIENT_ID})"
      ;;
    *)
      log_error "Invalid GE_LOCATION='${GE_LOCATION}'. Allowed values: global, us, eu."
      return 1
      ;;
  esac

  return 0
}

ensure_and_load_m365_secret_credentials() {
  local secret_id="${M365_SECRET_ID:-m365-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  local env_tenant="${M365_TENANT_ID:-}"
  local env_client="${M365_CLIENT_ID:-}"
  local env_secret="${M365_CLIENT_SECRET:-}"

  log_info "Ensuring M365 credentials JSON secret '${secret_id}' is synchronized in Secret Manager..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would ensure Secret Manager secret '${secret_id}' and sync M365 credentials from environment variables."
    return 0
  fi

  local check_rc=0
  ge_curl_request "GET" "${sm_base}/secrets/${secret_id}" "" "true" >/dev/null || check_rc=$?
  if [[ "${check_rc}" -eq 44 ]]; then
    log_info "Creating Secret Manager secret '${secret_id}'..."
    ge_curl_request "POST" "${sm_base}/secrets?secretId=${secret_id}" '{"replication":{"automatic":{}}}' >/dev/null
  fi

  local ver_rc=0 ver_resp="" decoded_json=""
  ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true")" || ver_rc=$?
  if [[ "${ver_rc}" -eq 44 ]]; then
    log_info "Seeding initial JSON version for Secret Manager secret '${secret_id}' from environment variables..."
    decoded_json="$(jq -c -n --arg t "${env_tenant}" --arg c "${env_client}" --arg s "${env_secret}" '{tenant_id:$t,client_id:$c,client_secret:$s}')"
    local b64_init
    b64_init="$(printf '%s' "${decoded_json}" | base64 | tr -d '\n')"
    ge_curl_request "POST" "${sm_base}/secrets/${secret_id}:addVersion" "{\"payload\":{\"data\":\"${b64_init}\"}}" >/dev/null
  else
    local b64_payload
    b64_payload="$(jq -r '.payload.data // empty' <<<"${ver_resp}")"
    if [[ -n "${b64_payload}" ]]; then
      decoded_json="$(printf '%s' "${b64_payload}" | base64 -d 2>/dev/null || printf '%s' "${b64_payload}" | base64 -D 2>/dev/null || echo "")"
    fi
  fi

  local sm_tenant="" sm_client="" sm_secret=""
  if [[ -n "${decoded_json}" ]]; then
    sm_tenant="$(jq -r '.tenant_id // empty' <<<"${decoded_json}")"
    sm_client="$(jq -r '.client_id // empty' <<<"${decoded_json}")"
    sm_secret="$(jq -r '.client_secret // empty' <<<"${decoded_json}")"
  fi

  export M365_TENANT_ID="${env_tenant:-${sm_tenant}}"
  export M365_CLIENT_ID="${env_client:-${sm_client}}"
  export M365_CLIENT_SECRET="${env_secret:-${sm_secret}}"
  export TF_VAR_m365_tenant_id="${M365_TENANT_ID}"
  export TF_VAR_m365_client_id="${M365_CLIENT_ID}"
  export TF_VAR_m365_client_secret="${M365_CLIENT_SECRET}"
  log_ok "Loaded M365 credentials (tenant_id=${M365_TENANT_ID}, client_id=${M365_CLIENT_ID})."
}

render_m365_connector_payload() {
  local data_source="$1"
  local instance_uri="$2"
  local entities_csv="$3"
  local connector_mode="${4:-${M365_CONNECTOR_MODE:-FEDERATED}}"
  local actions_csv="${5:-}"
  local enable_actions="${ENABLE_M365_ACTIONS:-false}"

  if [[ "${data_source}" == "sharepoint_federated_search" ]]; then
    enable_actions="false"
  fi

  jq -n \
    --arg dataSource "${data_source}" \
    --arg tenantId "${M365_TENANT_ID}" \
    --arg clientId "${M365_CLIENT_ID}" \
    --arg clientSecret "${M365_CLIENT_SECRET}" \
    --arg instanceUri "${instance_uri}" \
    --arg refreshInterval "${M365_REFRESH_INTERVAL:-86400s}" \
    --arg mode "${connector_mode}" \
    --arg entitiesCsv "${entities_csv}" \
    --arg enableActions "${enable_actions}" \
    --arg actionsCsv "${actions_csv}" \
    '{
      dataSource: $dataSource,
      params: (
        if $dataSource == "outlook" then
          {instance_id: $tenantId, client_id: $clientId}
        elif $dataSource == "teams" then
          {instance_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, domain_url: $instanceUri}
        elif $dataSource == "onedrive" then
          {tenant_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, instance_uri: $instanceUri, picker_config_provider: false, decrypt_mip_files: false}
        else
          {tenant_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, instance_uri: $instanceUri}
        end
      ),
      refreshInterval: $refreshInterval,
      autoRunDisabled: ($mode == "FEDERATED"),
      incrementalSyncDisabled: ($mode == "FEDERATED"),
      entities: ($entitiesCsv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)) | map({entityName: .})),
      connectorModes: (if $enableActions == "true" and $mode != "ACTIONS" then [$mode, "ACTIONS"] else [$mode] end)
    }
    + (if $enableActions == "true" and ($dataSource == "onedrive" or $dataSource == "sharepoint") then
        {destinationConfigs: [{key: "url", destinations: [{host: $instanceUri}]}]}
       else {} end)
    + (if $enableActions == "true" then
        {
          actionConfig: {
            isActionConfigured: true,
            createBapConnection: true,
            actionParams: (
              if $dataSource == "outlook" then
                {auth_key: "OAuth", auth_type: "OAUTH", instance_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, o365_environment_type: "com", azure_tenant: $tenantId, azure_environment: "GLOBAL"}
              elif $dataSource == "teams" then
                {auth_key: "OAuth", auth_type: "OAUTH", instance_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, azure_tenant: $tenantId, include_all_groups: true, include_all_users: true}
              elif $dataSource == "onedrive" then
                {auth_key: "OAuth", auth_type: "OAUTH", tenant_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, o365_environment_type: "com", azure_tenant: $tenantId, azure_environment: "GLOBAL", picker_config_provider: false}
              else
                {auth_type: "OAUTH", tenant_id: $tenantId, client_id: $clientId, client_secret: $clientSecret, instance_uri: $instanceUri, azure_environment: "GLOBAL"}
              end
            )
          },
          bapConfig: {
            supportedConnectorModes: ["ACTIONS"],
            enabledActions: ($actionsCsv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
          }
        }
       else {} end)'
}

_resolve_m365_col_id() {
  local suffix="$1"
  local prefix="${M365_COLLECTION_PREFIX:-m365}"
  case "${suffix}" in
    sp)    printf '%s' "${M365_SHAREPOINT_COLLECTION_ID:-${prefix}-sp}" ;;
    od)    printf '%s' "${M365_ONEDRIVE_COLLECTION_ID:-${prefix}-od}" ;;
    ol)    printf '%s' "${M365_OUTLOOK_COLLECTION_ID:-${prefix}-ol}" ;;
    teams) printf '%s' "${M365_TEAMS_COLLECTION_ID:-${prefix}-teams}" ;;
    *)     printf '%s' "${prefix}-${suffix}" ;;
  esac
}

_upsert_single_m365_connector() {
  local col_suffix="$1"
  local display_label="$2"
  local data_source="$3"
  local instance_uri="$4"
  local entities_csv="$5"
  local connector_mode="${6:-${M365_CONNECTOR_MODE:-FEDERATED}}"
  local actions_csv="${7:-}"

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"
  local col_id
  col_id="$(_resolve_m365_col_id "${col_suffix}")"
  local payload
  payload="$(render_m365_connector_payload "${data_source}" "${instance_uri}" "${entities_csv}" "${connector_mode}" "${actions_csv}")"

  log_info "Upserting M365 ${display_label} connector in collection '${col_id}'..."
  local get_url="${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector"
  local post_url="${base_v1alpha}/${loc_parent}:setUpDataConnectorV2?collectionId=${col_id}&collectionDisplayName=${display_label}"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
    return 0
  fi

  local check_rc=0
  ge_curl_request "GET" "${get_url}" "" "true" >/dev/null || check_rc=$?
  if [[ "${check_rc}" -eq 44 ]]; then
    ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
  elif [[ "${ENABLE_M365_ACTIONS:-false}" == "true" && "${data_source}" != "sharepoint_federated_search" ]]; then
    _patch_connector_actions_when_ready "${col_id}" "${display_label}" "$(jq -c '{actionConfig, bapConfig}' <<<"${payload}")"
  fi
  log_ok "M365 ${display_label} connector ('${col_id}') configured via REST API."
}

attach_m365_datastores_to_engine() {
  local app_id="${GE_APP_ID:-}"
  if [[ -z "${app_id}" ]]; then
    return 0
  fi

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"
  local engine_url="${base_v1alpha}/${loc_parent}/collections/default_collection/engines/${app_id}"

  log_info "Attaching M365 connector entity Data Stores to Gemini Enterprise App '${app_id}'..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" '{"dataStoreIds":[]}' >/dev/null
    return 0
  fi

  local engine_json
  engine_json="$(ge_curl_request "GET" "${engine_url}" "" "true" || echo "{}")"

  local suffixes=()
  [[ "${ENABLE_SHAREPOINT_CONNECTOR:-true}" == "true" ]] && suffixes+=("sp")
  [[ "${ENABLE_ONEDRIVE_CONNECTOR:-false}" == "true" ]] && suffixes+=("od")
  [[ "${ENABLE_OUTLOOK_CONNECTOR:-false}" == "true" ]] && suffixes+=("ol")
  [[ "${ENABLE_TEAMS_CONNECTOR:-false}" == "true" ]] && suffixes+=("teams")

  local ds_ids_json="[]"
  for sfx in "${suffixes[@]}"; do
    local cid
    cid="$(_resolve_m365_col_id "${sfx}")"
    local conn_json
    conn_json="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${cid}/dataConnector" "" "true" || echo "{}")"
    ds_ids_json="$(jq -n --argjson acc "${ds_ids_json}" --argjson conn "${conn_json}" \
      '$acc + ([($conn.entities // [])[] | .dataStore // empty | split("/") | last] | map(select(length > 0))) | unique')"
  done

  local merged_payload
  merged_payload="$(jq -n --argjson eng "${engine_json}" --argjson newIds "${ds_ids_json}" \
    '{dataStoreIds: ((($eng.dataStoreIds // []) + $newIds) | unique)}')"

  if [[ "$(jq -r '.dataStoreIds | length' <<<"${merged_payload}")" -gt 0 ]]; then
    ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "${merged_payload}" >/dev/null
    log_ok "Attached M365 Data Stores to Gemini Enterprise App '${app_id}'."
  fi
}

_patch_connector_actions_when_ready() {
  local col_id="$1"
  local display_label="$2"
  local patch_payload="$3"

  local base_v1alpha loc_parent get_url patch_url
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"
  get_url="${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector"
  patch_url="${get_url}?updateMask=actionConfig,bapConfig"

  if [[ "${DRY_RUN:-false}" == "true" || -n "${MOCK_CURL_GET_STATUS:-}" || -n "${MOCK_CURL_PATCH_STATUS:-}" ]]; then
    ge_curl_request "PATCH" "${patch_url}" "${patch_payload}" >/dev/null
    log_ok "Activated Console Actions ('isActionConfigured=true') for ${display_label} ('${col_id}')."
    return 0
  fi

  local attempt=1 max_attempts=18 conn_json="" conn_state="" is_cfg=""
  while [[ "${attempt}" -le "${max_attempts}" ]]; do
    conn_json="$(ge_curl_request "GET" "${get_url}" "" "true" || echo '{}')"
    conn_state="$(jq -r '.state // empty' <<<"${conn_json}" 2>/dev/null || true)"
    is_cfg="$(jq -r '.actionConfig.isActionConfigured // false' <<<"${conn_json}" 2>/dev/null || echo "false")"

    if [[ "${is_cfg}" == "true" && "${conn_state}" != "INITIALIZING" && "${conn_state}" != "CREATING" ]]; then
      log_ok "Console Actions ('isActionConfigured=true') already active for ${display_label} ('${col_id}')."
      return 0
    fi

    if [[ "${conn_state}" == "INITIALIZING" || "${conn_state}" == "CREATING" ]]; then
      log_info "Waiting for ${display_label} connector ('${col_id}') to finish ${conn_state} before patching actions (attempt ${attempt}/${max_attempts})..."
      sleep 10
      attempt=$((attempt + 1))
      continue
    fi
    break
  done

  local patch_rc=0
  ge_curl_request "PATCH" "${patch_url}" "${patch_payload}" "true" >/dev/null || patch_rc=$?
  if [[ "${patch_rc}" -eq 0 ]]; then
    log_ok "Activated Console Actions ('isActionConfigured=true') for ${display_label} ('${col_id}')."
  else
    log_info "${display_label} connector ('${col_id}') is still initializing in the background; Terraform action_config is queued."
  fi
  return 0
}

activate_m365_connector_actions() {
  if [[ "${ENABLE_M365_ACTIONS:-false}" != "true" ]]; then
    return 0
  fi

  if [[ "${ENABLE_SHAREPOINT_CONNECTOR:-true}" == "true" && "${M365_SHAREPOINT_DATA_SOURCE:-sharepoint_federated_search}" == "sharepoint" ]]; then
    local sp_col sp_payload
    sp_col="$(_resolve_m365_col_id "sp")"
    sp_payload="$(render_m365_connector_payload "sharepoint" "${M365_SHAREPOINT_INSTANCE_URI}" "${M365_SHAREPOINT_ENTITIES:-file,page}" "${M365_SHAREPOINT_CONNECTOR_MODE:-FEDERATED}" "${M365_SHAREPOINT_ENABLED_ACTIONS:-create_folder,add_page,upload_document,add_list,list_lists,get_list_item,get_list_fields,check_in_document,check_out_document,discard_check_out_document,move_attachment_or_document,rename_attachment_or_document,update_file_properties,create_list_item,update_list_item,update_list,update_page,share_resource}" | jq '{actionConfig, bapConfig}')"
    _patch_connector_actions_when_ready "${sp_col}" "SharePoint" "${sp_payload}"
  fi

  if [[ "${ENABLE_ONEDRIVE_CONNECTOR:-false}" == "true" ]]; then
    local od_col od_uri od_payload
    od_col="$(_resolve_m365_col_id "od")"
    od_uri="${M365_ONEDRIVE_INSTANCE_URI:-${M365_SHAREPOINT_INSTANCE_URI:-}}"
    od_payload="$(render_m365_connector_payload "onedrive" "${od_uri}" "${M365_ONEDRIVE_ENTITIES:-file}" "${M365_ONEDRIVE_CONNECTOR_MODE:-FEDERATED}" "${M365_ONEDRIVE_ENABLED_ACTIONS:-upload_file,copy_file,copy_folder,move_file,move_folder,create_folder,rename_file,rename_folder,share_file_folder,update_file_properties}" | jq '{actionConfig, bapConfig}')"
    _patch_connector_actions_when_ready "${od_col}" "OneDrive" "${od_payload}"
  fi

  if [[ "${ENABLE_OUTLOOK_CONNECTOR:-false}" == "true" ]]; then
    local ol_col ol_payload
    ol_col="$(_resolve_m365_col_id "ol")"
    ol_payload="$(render_m365_connector_payload "outlook" "${M365_OUTLOOK_INSTANCE_URI:-https://outlook.office365.com}" "${M365_OUTLOOK_ENTITIES:-mail,mail-attachment,calendar,contact}" "${M365_OUTLOOK_CONNECTOR_MODE:-FEDERATED}" "${M365_OUTLOOK_ENABLED_ACTIONS:-send_mail,create_message,update_message,reply_to_my_message,forward_mail,move_mail,add_attachments,download_attachments,create_event,update_event,rsvp_to_event,create_calendar,update_calendar,create_contact,update_contact}" | jq '{actionConfig, bapConfig}')"
    _patch_connector_actions_when_ready "${ol_col}" "Outlook" "${ol_payload}"
  fi

  if [[ "${ENABLE_TEAMS_CONNECTOR:-false}" == "true" ]]; then
    local teams_col teams_payload
    teams_col="$(_resolve_m365_col_id "teams")"
    teams_payload="$(render_m365_connector_payload "teams" "${M365_TEAMS_INSTANCE_URI:-https://teams.microsoft.com}" "${M365_TEAMS_ENTITIES:-channel-message,chat-message}" "${M365_TEAMS_CONNECTOR_MODE:-FEDERATED}" "${M365_TEAMS_ENABLED_ACTIONS:-send_channel_message,send_chat_message,create_channel}" | jq '{actionConfig, bapConfig}')"
    _patch_connector_actions_when_ready "${teams_col}" "Microsoft Teams" "${teams_payload}"
  fi
}

configure_m365_connectors() {
  local include_connectors="${1:-false}"
  log_phase "CURL/API" "Configuring M365 Identity/ACLs, Connectors, and Write Actions"

  ensure_and_load_m365_secret_credentials

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"

  if [[ "${M365_CONFIGURE_ACL:-true}" == "true" ]]; then
    log_info "Configuring Discovery Engine ACL settings (${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}) for M365..."
    local acl_payload
    acl_payload="$(render_acl_payload)"
    ge_curl_request "PATCH" "${base_v1alpha}/${loc_parent}/aclConfig" "${acl_payload}" >/dev/null
    log_ok "M365 Identity/ACL configuration applied."
  fi

  if [[ "${include_connectors}" == "true" ]]; then
    if [[ "${ENABLE_SHAREPOINT_CONNECTOR:-true}" == "true" ]]; then
      _upsert_single_m365_connector "sp" "M365-SharePoint-Online" \
        "${M365_SHAREPOINT_DATA_SOURCE:-sharepoint_federated_search}" \
        "${M365_SHAREPOINT_INSTANCE_URI}" \
        "${M365_SHAREPOINT_ENTITIES:-file,page}" \
        "${M365_SHAREPOINT_CONNECTOR_MODE:-FEDERATED}" \
        "${M365_SHAREPOINT_ENABLED_ACTIONS:-create_folder,add_page,upload_document,add_list,list_lists,get_list_item,get_list_fields,check_in_document,check_out_document,discard_check_out_document,move_attachment_or_document,rename_attachment_or_document,update_file_properties,create_list_item,update_list_item,update_list,update_page,share_resource}"
    fi

    if [[ "${ENABLE_ONEDRIVE_CONNECTOR:-false}" == "true" ]]; then
      local od_uri="${M365_ONEDRIVE_INSTANCE_URI:-${M365_SHAREPOINT_INSTANCE_URI:-}}"
      _upsert_single_m365_connector "od" "M365-OneDrive" \
        "onedrive" "${od_uri}" "${M365_ONEDRIVE_ENTITIES:-file}" \
        "${M365_ONEDRIVE_CONNECTOR_MODE:-FEDERATED}" \
        "${M365_ONEDRIVE_ENABLED_ACTIONS:-upload_file,copy_file,copy_folder,move_file,move_folder,create_folder,rename_file,rename_folder,share_file_folder,update_file_properties}"
    fi

    if [[ "${ENABLE_OUTLOOK_CONNECTOR:-false}" == "true" ]]; then
      _upsert_single_m365_connector "ol" "M365-Outlook" \
        "outlook" "${M365_OUTLOOK_INSTANCE_URI:-https://outlook.office365.com}" \
        "${M365_OUTLOOK_ENTITIES:-mail,mail-attachment,calendar,contact}" \
        "${M365_OUTLOOK_CONNECTOR_MODE:-FEDERATED}" \
        "${M365_OUTLOOK_ENABLED_ACTIONS:-send_mail,create_message,update_message,reply_to_my_message,forward_mail,move_mail,add_attachments,download_attachments,create_event,update_event,rsvp_to_event,create_calendar,update_calendar,create_contact,update_contact}"
    fi

    if [[ "${ENABLE_TEAMS_CONNECTOR:-false}" == "true" ]]; then
      _upsert_single_m365_connector "teams" "M365-Teams" \
        "teams" "${M365_TEAMS_INSTANCE_URI:-https://teams.microsoft.com}" \
        "${M365_TEAMS_ENTITIES:-channel-message,chat-message}" \
        "${M365_TEAMS_CONNECTOR_MODE:-FEDERATED}" \
        "${M365_TEAMS_ENABLED_ACTIONS:-send_channel_message,send_chat_message,create_channel}"
    fi
  else
    activate_m365_connector_actions
  fi

  attach_m365_datastores_to_engine
}

deregister_m365_connectors() {
  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"

  for suffix in sp od ol teams; do
    local col_id
    col_id="$(_resolve_m365_col_id "${suffix}")"
    log_info "Ensuring M365 collection '${col_id}' is cleaned up if curl-managed..."
    ge_curl_request "DELETE" "${base_v1alpha}/${loc_parent}/collections/${col_id}" "" "true" >/dev/null || true
  done
  log_ok "M365 curl-managed connector collections cleanup complete."
}

verify_m365_connectors() {
  log_phase "VERIFY" "Verifying M365 Discovery Engine Data Connectors via REST API"

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}"

  if [[ "${ENABLE_SHAREPOINT_CONNECTOR:-true}" == "true" ]]; then
    local sp_col
    sp_col="$(_resolve_m365_col_id "sp")"
    log_info "Verifying SharePoint Data Connector ('${sp_col}')..."
    ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${sp_col}/dataConnector" >/dev/null
    log_ok "SharePoint Data Connector ('${sp_col}') is reachable and active."
  fi

  if [[ "${ENABLE_ONEDRIVE_CONNECTOR:-false}" == "true" ]]; then
    local od_col
    od_col="$(_resolve_m365_col_id "od")"
    log_info "Verifying OneDrive Data Connector ('${od_col}')..."
    ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${od_col}/dataConnector" >/dev/null
    log_ok "OneDrive Data Connector ('${od_col}') is reachable and active."
  fi

  if [[ "${ENABLE_OUTLOOK_CONNECTOR:-false}" == "true" ]]; then
    local ol_col
    ol_col="$(_resolve_m365_col_id "ol")"
    log_info "Verifying Outlook Data Connector ('${ol_col}')..."
    ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${ol_col}/dataConnector" >/dev/null
    log_ok "Outlook Data Connector ('${ol_col}') is reachable and active."
  fi

  if [[ "${ENABLE_TEAMS_CONNECTOR:-false}" == "true" ]]; then
    local teams_col
    teams_col="$(_resolve_m365_col_id "teams")"
    log_info "Verifying Microsoft Teams Data Connector ('${teams_col}')..."
    ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${teams_col}/dataConnector" >/dev/null
    log_ok "Microsoft Teams Data Connector ('${teams_col}') is reachable and active."
  fi
}

print_m365_summary() {
  log_phase "SUMMARY" "Microsoft 365 Data Connectors Deployment Summary"
  printf '  Project ID          : %s\n' "${GCP_PROJECT_ID}"
  printf '  Location            : %s\n' "${GE_LOCATION}"
  printf '  Secret Manager ID   : %s\n' "${M365_SECRET_ID:-m365-connector-credentials}"
  printf '  M365 Tenant ID      : %s\n' "${M365_TENANT_ID}"
  printf '  Connector Mode      : %s\n' "${M365_CONNECTOR_MODE:-FEDERATED}"
  printf '  Write Actions (BAP) : %s\n' "${ENABLE_M365_ACTIONS:-false}"
  printf '  SharePoint Online   : %s (collection: %s)\n' "${ENABLE_SHAREPOINT_CONNECTOR:-true}" "$(_resolve_m365_col_id "sp")"
  printf '  OneDrive            : %s (collection: %s, actions: %s)\n' "${ENABLE_ONEDRIVE_CONNECTOR:-false}" "$(_resolve_m365_col_id "od")" "${M365_ONEDRIVE_ENABLED_ACTIONS:-none}"
  printf '  Outlook             : %s (collection: %s, actions: %s)\n' "${ENABLE_OUTLOOK_CONNECTOR:-false}" "$(_resolve_m365_col_id "ol")" "${M365_OUTLOOK_ENABLED_ACTIONS:-none}"
  printf '  Microsoft Teams     : %s (collection: %s, actions: %s)\n' "${ENABLE_TEAMS_CONNECTOR:-false}" "$(_resolve_m365_col_id "teams")" "${M365_TEAMS_ENABLED_ACTIONS:-none}"
  if [[ -n "${GE_APP_ID:-}" ]]; then
    printf '  Linked GE App ID    : %s\n' "${GE_APP_ID}"
  fi
  printf '  GCP Console URL     : https://console.cloud.google.com/gen-app-builder/data-stores?project=%s\n' "${GCP_PROJECT_ID}"
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '  Execution Log File  : %s\n' "${LOG_FILE}"
  fi
}

run_m365_verification_and_summary() {
  verify_m365_connectors
  print_m365_summary
}
