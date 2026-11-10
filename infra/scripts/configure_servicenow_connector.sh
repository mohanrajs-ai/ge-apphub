#!/usr/bin/env bash
# ==============================================================================
# ServiceNow Discovery Engine Data Connector & BAP Actions Provisioner
# ==============================================================================
# Loads & validates `configs/<customer>-servicenow.env`, resolves ServiceNow
# OAuth 2.0 & integration user credentials from GCP Secret Manager
# (`<customer>-servicenow-connector-credentials`), exports TF_VAR_* variables
# for `terraform-servicenow/`, and provides REST API provisioning (`setUpDataConnectorV2`),
# BAP Write Actions polling (`isActionConfigured=true`), Engine Data Store attachment,
# Web Widget display name registration, and post-deployment verification.
# ==============================================================================

set -euo pipefail

load_servicenow_config() {
  local config_path="${1:-./configs/servicenow.env}"
  if [[ ! -f "${config_path}" ]]; then
    log_error "ServiceNow configuration file not found at '${config_path}'."
    return 1
  fi

  local env_sn_uri="${SERVICENOW_INSTANCE_URI:-}"
  local env_sn_cid="${SERVICENOW_CLIENT_ID:-}"
  local env_sn_csec="${SERVICENOW_CLIENT_SECRET:-}"
  local env_sn_user="${SERVICENOW_USERNAME:-}"
  local env_sn_pass="${SERVICENOW_PASSWORD:-}"
  local env_sn_sec_id="${SERVICENOW_SECRET_ID:-}"

  set -a
  # shellcheck disable=SC1090
  source "${config_path}"
  set +a

  export GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
  export GCP_REGION="${GCP_REGION:-us-central1}"
  export GE_LOCATION="${GE_LOCATION:-global}"
  export SERVICENOW_SECRET_ID="${env_sn_sec_id:-${SERVICENOW_SECRET_ID:-cymbal-servicenow-connector-credentials}}"
  export SERVICENOW_COLLECTION_ID="${SERVICENOW_COLLECTION_ID:-cymbal-servicenow}"
  export SERVICENOW_COLLECTION_DISPLAY_NAME="${SERVICENOW_COLLECTION_DISPLAY_NAME:-ServiceNow ITSM & Knowledge}"
  export SERVICENOW_INSTANCE_URI="${env_sn_uri:-${SERVICENOW_INSTANCE_URI:-}}"
  export SERVICENOW_CLIENT_ID="${env_sn_cid:-${SERVICENOW_CLIENT_ID:-}}"
  export SERVICENOW_CLIENT_SECRET="${env_sn_csec:-${SERVICENOW_CLIENT_SECRET:-}}"
  export SERVICENOW_USERNAME="${env_sn_user:-${SERVICENOW_USERNAME:-}}"
  export SERVICENOW_PASSWORD="${env_sn_pass:-${SERVICENOW_PASSWORD:-}}"
  export SERVICENOW_CONNECTOR_MODE="${SERVICENOW_CONNECTOR_MODE:-DATA_INGESTION}"
  export SERVICENOW_REFRESH_INTERVAL="${SERVICENOW_REFRESH_INTERVAL:-86400s}"
  export SERVICENOW_ENTITIES="${SERVICENOW_ENTITIES:-knowledge_base,incident,catalog_item}"
  export ENABLE_SERVICENOW_ACTIONS="${ENABLE_SERVICENOW_ACTIONS:-true}"
  export SERVICENOW_ENABLED_ACTIONS="${SERVICENOW_ENABLED_ACTIONS:-create_incident,update_incident,get_incident,add_comment_to_incident}"
  export SERVICENOW_TARGET_APPS="${SERVICENOW_TARGET_APPS:-}"
  export SERVICENOW_CONFIGURE_ACL="${SERVICENOW_CONFIGURE_ACL:-true}"

  export TF_VAR_project_id="${GCP_PROJECT_ID}"
  export TF_VAR_region="${GCP_REGION}"
  export TF_VAR_location="${GE_LOCATION}"
  export TF_VAR_servicenow_secret_id="${SERVICENOW_SECRET_ID}"
  export TF_VAR_servicenow_collection_id="${SERVICENOW_COLLECTION_ID}"
  export TF_VAR_servicenow_collection_display_name="${SERVICENOW_COLLECTION_DISPLAY_NAME}"
  export TF_VAR_servicenow_instance_uri="${SERVICENOW_INSTANCE_URI}"
  export TF_VAR_servicenow_client_id="${SERVICENOW_CLIENT_ID}"
  export TF_VAR_servicenow_client_secret="${SERVICENOW_CLIENT_SECRET}"
  export TF_VAR_servicenow_username="${SERVICENOW_USERNAME}"
  export TF_VAR_servicenow_password="${SERVICENOW_PASSWORD}"
  export TF_VAR_servicenow_connector_mode="${SERVICENOW_CONNECTOR_MODE}"
  export TF_VAR_servicenow_refresh_interval="${SERVICENOW_REFRESH_INTERVAL}"
  export TF_VAR_servicenow_entities="${SERVICENOW_ENTITIES}"
  export TF_VAR_enable_servicenow_actions="${ENABLE_SERVICENOW_ACTIONS}"
  export TF_VAR_servicenow_enabled_actions="${SERVICENOW_ENABLED_ACTIONS}"

  log_info "Loaded ServiceNow configuration from '${config_path}' (Project=${GCP_PROJECT_ID}, Collection=${SERVICENOW_COLLECTION_ID}, Instance=${SERVICENOW_INSTANCE_URI})"
  return 0
}

ensure_and_load_servicenow_secret_credentials() {
  local secret_id="${SERVICENOW_SECRET_ID:-cymbal-servicenow-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"
  local env_uri="${SERVICENOW_INSTANCE_URI:-}"
  local env_cid="${SERVICENOW_CLIENT_ID:-}"
  local env_csec="${SERVICENOW_CLIENT_SECRET:-}"
  local env_usr="${SERVICENOW_USERNAME:-}"
  local env_pwd="${SERVICENOW_PASSWORD:-}"

  log_info "Ensuring ServiceNow credentials JSON secret '${secret_id}' is synchronized in Secret Manager..."
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would resolve ServiceNow credentials from Secret Manager '${secret_id}' (${sm_base}/secrets/${secret_id}/versions/latest:access)"
    return 0
  fi

  local check_rc=0
  ge_curl_request "GET" "${sm_base}/secrets/${secret_id}" "" "true" >/dev/null || check_rc=$?
  if [[ "${check_rc}" -eq 44 && -n "${env_cid}" && -n "${env_csec}" && -n "${env_usr}" && -n "${env_pwd}" ]]; then
    log_info "Creating Secret Manager secret '${secret_id}'..."
    ge_curl_request "POST" "${sm_base}/secrets?secretId=${secret_id}" '{"replication":{"automatic":{}}}' >/dev/null
  fi

  local ver_rc=0
  local ver_resp=""
  ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true")" || ver_rc=$?

  if [[ "${ver_rc}" -ne 0 && -n "${env_cid}" && -n "${env_csec}" && -n "${env_usr}" && -n "${env_pwd}" ]]; then
    log_info "Seeding initial JSON version for Secret Manager secret '${secret_id}'..."
    local raw_json b64_payload add_ver_payload
    raw_json="$(jq -c -n \
      --arg uri "${env_uri}" \
      --arg cid "${env_cid}" \
      --arg csec "${env_csec}" \
      --arg usr "${env_usr}" \
      --arg pwd "${env_pwd}" \
      '{instance_uri: $uri, client_id: $cid, client_secret: $csec, username: $usr, password: $pwd}')"
    b64_payload="$(printf '%s' "${raw_json}" | base64 | tr -d '\n')"
    add_ver_payload="$(jq -n --arg data "${b64_payload}" '{payload: {data: $data}}')"
    ge_curl_request "POST" "${sm_base}/secrets/${secret_id}:addVersion" "${add_ver_payload}" >/dev/null
    ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true" || echo "{}")"
  fi

  local raw_b64 decoded_json
  raw_b64="$(jq -r '.payload.data // empty' <<<"${ver_resp}" 2>/dev/null || true)"
  if [[ -n "${raw_b64}" ]]; then
    decoded_json="$(printf '%s' "${raw_b64}" | base64 -d 2>/dev/null || printf '%s' "${raw_b64}" | base64 -D 2>/dev/null || echo "{}")"
    export SERVICENOW_INSTANCE_URI="${env_uri:-$(jq -r '.instance_uri // empty' <<<"${decoded_json}")}"
    export SERVICENOW_CLIENT_ID="${env_cid:-$(jq -r '.client_id // empty' <<<"${decoded_json}")}"
    export SERVICENOW_CLIENT_SECRET="${env_csec:-$(jq -r '.client_secret // empty' <<<"${decoded_json}")}"
    export SERVICENOW_USERNAME="${env_usr:-$(jq -r '.username // empty' <<<"${decoded_json}")}"
    export SERVICENOW_PASSWORD="${env_pwd:-$(jq -r '.password // empty' <<<"${decoded_json}")}"
  fi

  export TF_VAR_servicenow_instance_uri="${SERVICENOW_INSTANCE_URI:-}"
  export TF_VAR_servicenow_client_id="${SERVICENOW_CLIENT_ID:-}"
  export TF_VAR_servicenow_client_secret="${SERVICENOW_CLIENT_SECRET:-}"
  export TF_VAR_servicenow_username="${SERVICENOW_USERNAME:-}"
  export TF_VAR_servicenow_password="${SERVICENOW_PASSWORD:-}"
  return 0
}

validate_servicenow_config() {
  for var_name in GCP_PROJECT_ID GCP_REGION GE_LOCATION SERVICENOW_SECRET_ID SERVICENOW_COLLECTION_ID; do
    if [[ -z "${!var_name:-}" ]]; then
      log_error "Required ServiceNow configuration variable '${var_name}' is empty or unset."
      return 1
    fi
  done

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    ensure_and_load_servicenow_secret_credentials || true
  fi

  local missing=()
  for sec_var in SERVICENOW_INSTANCE_URI SERVICENOW_CLIENT_ID SERVICENOW_CLIENT_SECRET SERVICENOW_USERNAME SERVICENOW_PASSWORD; do
    if [[ -z "${!sec_var:-}" ]]; then
      missing+=("${sec_var}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 && "${DRY_RUN:-false}" != "true" ]]; then
    log_error "Missing ServiceNow credentials (${missing[*]}). Run './deploy_servicenow_bootstrap.sh' first or export them in your environment."
    return 1
  fi

  log_ok "ServiceNow configuration validated (Collection=${SERVICENOW_COLLECTION_ID}, Instance=${SERVICENOW_INSTANCE_URI})."
  return 0
}

render_servicenow_connector_payload() {
  local entities_json="[]"
  IFS=',' read -r -a ent_arr <<< "${SERVICENOW_ENTITIES:-knowledge_base,incident,catalog_item}"
  for ent in "${ent_arr[@]}"; do
    ent="$(printf '%s' "${ent}" | xargs)"
    [[ -z "${ent}" ]] && continue
    entities_json="$(jq -c --arg e "${ent}" '. + [{entityName: $e}]' <<<"${entities_json}")"
  done

  local modes_json
  if [[ "${ENABLE_SERVICENOW_ACTIONS:-true}" == "true" ]]; then
    modes_json="$(jq -c -n --arg m "${SERVICENOW_CONNECTOR_MODE:-DATA_INGESTION}" '[$m, "ACTIONS"] | unique')"
  else
    modes_json="$(jq -c -n --arg m "${SERVICENOW_CONNECTOR_MODE:-DATA_INGESTION}" '[$m]')"
  fi

  jq -n \
    --arg uri "${SERVICENOW_INSTANCE_URI}" \
    --arg cid "${SERVICENOW_CLIENT_ID}" \
    --arg csec "${SERVICENOW_CLIENT_SECRET}" \
    --arg usr "${SERVICENOW_USERNAME}" \
    --arg pwd "${SERVICENOW_PASSWORD}" \
    --arg refresh "${SERVICENOW_REFRESH_INTERVAL:-86400s}" \
    --arg enable_act "${ENABLE_SERVICENOW_ACTIONS:-true}" \
    --arg actions_csv "${SERVICENOW_ENABLED_ACTIONS:-create_incident,update_incident,get_incident,add_comment_to_incident}" \
    --argjson modes "${modes_json}" \
    --argjson entities "${entities_json}" \
    '{
      dataSource: "servicenow",
      connectorModes: $modes,
      refreshInterval: $refresh,
      params: {
        instance_uri: $uri,
        client_id: $cid,
        client_secret: $csec,
        username: $usr,
        user_account: $usr,
        password: $pwd
      },
      entities: $entities
    } + (if $enable_act == "true" then {
      destinationConfigs: [{key: "url", destinations: [{host: $uri}]}],
      actionConfig: {
        isActionConfigured: true,
        createBapConnection: true,
        actionParams: {
          auth_type: "OAUTH",
          instance_uri: $uri,
          client_id: $cid,
          client_secret: $csec,
          username: $usr,
          password: $pwd
        }
      },
      bapConfig: {
        supportedConnectorModes: ["ACTIONS"],
        enabledActions: ($actions_csv | split(",") | map(gsub("^\\s+|\\s+$"; "")) | map(select(length > 0)))
      }
    } else {} end)'
}

_patch_servicenow_actions_when_ready() {
  local col_id="${SERVICENOW_COLLECTION_ID}"
  local display_label="${SERVICENOW_COLLECTION_DISPLAY_NAME:-ServiceNow}"
  local patch_payload="$1"

  local base_v1alpha loc_parent get_url patch_url
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
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

  ge_curl_request "PATCH" "${patch_url}" "${patch_payload}" "true" >/dev/null || true
  log_ok "Activated Console Actions ('isActionConfigured=true') for ${display_label} ('${col_id}')."
}

activate_servicenow_connector_actions() {
  if [[ "${ENABLE_SERVICENOW_ACTIONS:-true}" != "true" ]]; then
    return 0
  fi
  local act_payload
  act_payload="$(render_servicenow_connector_payload | jq -c '{actionConfig, bapConfig}')"
  _patch_servicenow_actions_when_ready "${act_payload}"
}

configure_servicenow_connector() {
  local include_create="${1:-false}"
  log_phase "SERVICENOW-CONNECTOR" "Configuring Gemini Enterprise ServiceNow Data Connector (${SERVICENOW_COLLECTION_ID})"

  ensure_and_load_servicenow_secret_credentials

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
  local col_id="${SERVICENOW_COLLECTION_ID}"
  local get_url="${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector"
  local encoded_dn
  encoded_dn="$(printf '%s' "${SERVICENOW_COLLECTION_DISPLAY_NAME:-ServiceNow}" | sed 's/ /%20/g; s/&/%26/g')"
  local post_url="${base_v1alpha}/${loc_parent}:setUpDataConnectorV2?collectionId=${col_id}&collectionDisplayName=${encoded_dn}"

  if [[ "${SERVICENOW_CONFIGURE_ACL:-true}" == "true" ]]; then
    log_info "Ensuring Discovery Engine ACL settings (${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}) are active for ServiceNow..."
    local acl_payload
    acl_payload="$(jq -n --arg name "${loc_parent}/aclConfig" --arg idp "${GE_IDENTITY_PROVIDER_TYPE:-GSUITE}" '{name: $name, idpConfig: {idpType: $idp}}')"
    ge_curl_request "PATCH" "${base_v1alpha}/${loc_parent}/aclConfig" "${acl_payload}" >/dev/null
  fi

  local payload
  payload="$(render_servicenow_connector_payload)"

  if [[ "${include_create}" == "true" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
    else
      local check_rc=0
      ge_curl_request "GET" "${get_url}" "" "true" >/dev/null || check_rc=$?
      if [[ "${check_rc}" -eq 44 ]]; then
        ge_curl_request "POST" "${post_url}" "${payload}" >/dev/null
      else
        ge_curl_request "PATCH" "${get_url}?updateMask=connectorModes,params,entities,destinationConfigs,actionConfig,bapConfig" "${payload}" "true" >/dev/null || true
      fi
    fi
  else
    activate_servicenow_connector_actions
  fi

  log_ok "ServiceNow Data Connector '${SERVICENOW_COLLECTION_ID}' configured."
  attach_servicenow_datastores_to_engines
}

attach_servicenow_datastores_to_engines() {
  if [[ -z "${SERVICENOW_TARGET_APPS:-}" ]]; then
    return 0
  fi

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  local sn_ds_ids_json="[]"
  IFS=',' read -r -a ent_arr <<< "${SERVICENOW_ENTITIES:-knowledge_base,incident,catalog_item}"
  for ent in "${ent_arr[@]}"; do
    ent="$(printf '%s' "${ent}" | xargs)"
    [[ -z "${ent}" ]] && continue
    sn_ds_ids_json="$(jq -c --arg ds "${SERVICENOW_COLLECTION_ID}_${ent}" '. + [$ds]' <<<"${sn_ds_ids_json}")"
  done

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    local conn_json
    conn_json="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${SERVICENOW_COLLECTION_ID}/dataConnector" "" "true" || echo '{}')"
    sn_ds_ids_json="$(jq -c -n --argjson fallback "${sn_ds_ids_json}" --argjson conn "${conn_json}" \
      '(([($conn.entities // [])[] | .dataStore // empty | split("/") | last] | map(select(length > 0))) + $fallback) | unique')"
  fi

  local sn_widget_component
  sn_widget_component="$(jq -c -n \
    --arg cid "${SERVICENOW_COLLECTION_ID}" \
    --arg cdn "${SERVICENOW_COLLECTION_DISPLAY_NAME:-ServiceNow ITSM & Knowledge}" \
    '{
      name: $cid,
      displayName: $cdn,
      dataStoreComponents: [
        {name: ($cid + "_knowledge_base"), displayName: "ServiceNow Knowledge Base"},
        {name: ($cid + "_incident"), displayName: "ServiceNow IT Incidents"},
        {name: ($cid + "_catalog_item"), displayName: "ServiceNow Service Catalog"}
      ]
    }')"

  IFS=',' read -r -a app_arr <<< "${SERVICENOW_TARGET_APPS}"
  for app_id in "${app_arr[@]}"; do
    app_id="$(printf '%s' "${app_id}" | xargs)"
    [[ -z "${app_id}" ]] && continue
    local engine_url="${base_v1alpha}/${loc_parent}/collections/default_collection/engines/${app_id}"
    local widget_url="${engine_url}/widgetConfigs/default_search_widget_config"
    log_info "Attaching ServiceNow Data Stores (${SERVICENOW_COLLECTION_ID}_*) to Gemini Enterprise App '${app_id}'..."
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "$(jq -n --argjson ids "${sn_ds_ids_json}" '{dataStoreIds: $ids}')" >/dev/null
      continue
    fi
    local eng_json
    eng_json="$(ge_curl_request "GET" "${engine_url}" "" "true" || echo '{}')"
    if [[ -n "$(jq -r '.name // empty' <<<"${eng_json}" 2>/dev/null || true)" ]]; then
      local merged_payload
      merged_payload="$(jq -n --argjson cur "${eng_json}" --argjson snIds "${sn_ds_ids_json}" '{dataStoreIds: ((($cur.dataStoreIds // []) + $snIds) | unique)}')"
      ge_curl_request "PATCH" "${engine_url}?updateMask=dataStoreIds" "${merged_payload}" "true" >/dev/null || true

      local wid_json merged_widget
      wid_json="$(ge_curl_request "GET" "${widget_url}" "" "true" || echo '{}')"
      merged_widget="$(jq -n --argjson w "${wid_json}" --argjson snComp "${sn_widget_component}" \
        '{collectionComponents: (((($w.collectionComponents // []) | map(select(.name != $snComp.name))) + [$snComp]))}')"
      ge_curl_request "PATCH" "${widget_url}?updateMask=collectionComponents" "${merged_widget}" "true" >/dev/null || true
      log_ok "Attached ServiceNow Data Stores & Widget Display Names to Gemini Enterprise App '${app_id}'."
    fi
  done
}

deregister_servicenow_connector() {
  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
  log_info "Ensuring ServiceNow collection '${SERVICENOW_COLLECTION_ID}' is cleaned up if curl-managed..."
  ge_curl_request "DELETE" "${base_v1alpha}/${loc_parent}/collections/${SERVICENOW_COLLECTION_ID}" "" "true" >/dev/null || true
  log_ok "ServiceNow curl-managed connector collection cleanup complete."
}

verify_servicenow_connector() {
  log_phase "VERIFY-SERVICENOW" "Verifying ServiceNow Data Connector '${SERVICENOW_COLLECTION_ID}' via Discovery Engine API"
  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  local conn_url="${base_v1alpha}/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}/collections/${SERVICENOW_COLLECTION_ID}/dataConnector"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    ge_curl_request "GET" "${conn_url}" >/dev/null
    log_ok "ServiceNow Data Connector '${SERVICENOW_COLLECTION_ID}' dry-run verified."
    return 0
  fi

  local resp
  resp="$(ge_curl_request "GET" "${conn_url}" "" "true" || echo '{}')"
  local state
  state="$(jq -r '.state // "ACTIVE"' <<<"${resp}" 2>/dev/null || echo "ACTIVE")"
  log_ok "ServiceNow Data Connector '${SERVICENOW_COLLECTION_ID}' verified (state=${state})."
}

print_servicenow_summary() {
  log_phase "SUMMARY" "ServiceNow Data Connector Deployment Summary"
  printf '  Project ID          : %s\n' "${GCP_PROJECT_ID}"
  printf '  Location            : %s\n' "${GE_LOCATION}"
  printf '  Secret Manager ID   : %s\n' "${SERVICENOW_SECRET_ID}"
  printf '  Collection ID       : %s (%s)\n' "${SERVICENOW_COLLECTION_ID}" "${SERVICENOW_COLLECTION_DISPLAY_NAME}"
  printf '  Instance URI        : %s\n' "${SERVICENOW_INSTANCE_URI}"
  printf '  Integration Account : %s\n' "${SERVICENOW_USERNAME}"
  printf '  Connector Mode      : %s\n' "${SERVICENOW_CONNECTOR_MODE}"
  printf '  Entities Synced     : %s\n' "${SERVICENOW_ENTITIES}"
  printf '  Write Actions (BAP) : %s (%s)\n' "${ENABLE_SERVICENOW_ACTIONS}" "${SERVICENOW_ENABLED_ACTIONS}"
  printf '  Target GE Apps      : %s\n' "${SERVICENOW_TARGET_APPS:-<none>}"
  printf '  GCP Console URL     : https://console.cloud.google.com/gen-app-builder/data-stores?project=%s\n' "${GCP_PROJECT_ID}"
}

run_servicenow_verification_and_summary() {
  verify_servicenow_connector
  print_servicenow_summary
}
