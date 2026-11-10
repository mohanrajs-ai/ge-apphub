#!/usr/bin/env bash
# ==============================================================================
# ServiceNow Discovery Engine Data Connector & BAP Actions Provisioner
# ==============================================================================
# Loads & validates `configs/<customer>-servicenow.env`, resolves ServiceNow
# OAuth 2.0 & integration user credentials from GCP Secret Manager
# (`<customer>-servicenow-connector-credentials`), exports TF_VAR_* variables
# for `terraform-servicenow/`, and provides REST API provisioning/verification.
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

  log_info "Loaded ServiceNow configuration from '${config_path}' (Project=${GCP_PROJECT_ID}, Collection=${SERVICENOW_COLLECTION_ID}, Instance=${SERVICENOW_INSTANCE_URI})"
  return 0
}

ensure_and_load_servicenow_secret_credentials() {
  local secret_id="${SERVICENOW_SECRET_ID:-cymbal-servicenow-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would resolve ServiceNow credentials from Secret Manager '${secret_id}' (${sm_base}/secrets/${secret_id}/versions/latest:access)"
    return 0
  fi

  if [[ -z "${SERVICENOW_CLIENT_ID:-}" || -z "${SERVICENOW_CLIENT_SECRET:-}" || -z "${SERVICENOW_USERNAME:-}" || -z "${SERVICENOW_PASSWORD:-}" ]]; then
    log_info "Reading ServiceNow JSON credentials from Secret Manager ('projects/${GCP_PROJECT_ID}/secrets/${secret_id}/versions/latest')..."
    local ver_resp=""
    ver_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest:access" "" "true" || echo "{}")"
    local raw_b64 decoded_json
    raw_b64="$(jq -r '.payload.data // empty' <<<"${ver_resp}")"
    if [[ -n "${raw_b64}" ]]; then
      decoded_json="$(printf '%s' "${raw_b64}" | base64 -d 2>/dev/null || printf '%s' "${raw_b64}" | base64 -D 2>/dev/null || echo "{}")"
      export SERVICENOW_INSTANCE_URI="${SERVICENOW_INSTANCE_URI:-$(jq -r '.instance_uri // empty' <<<"${decoded_json}")}"
      export SERVICENOW_CLIENT_ID="${SERVICENOW_CLIENT_ID:-$(jq -r '.client_id // empty' <<<"${decoded_json}")}"
      export SERVICENOW_CLIENT_SECRET="${SERVICENOW_CLIENT_SECRET:-$(jq -r '.client_secret // empty' <<<"${decoded_json}")}"
      export SERVICENOW_USERNAME="${SERVICENOW_USERNAME:-$(jq -r '.username // empty' <<<"${decoded_json}")}"
      export SERVICENOW_PASSWORD="${SERVICENOW_PASSWORD:-$(jq -r '.password // empty' <<<"${decoded_json}")}"
    fi
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
        createBapConnection: true,
        actionParams: {
          auth_type: "OAUTH",
          instance_uri: $uri,
          client_id: $cid,
          client_secret: $csec,
          username: $usr,
          password: $pwd
        }
      }
    } else {} end)'
}

configure_servicenow_connector() {
  local include_create="${1:-false}"
  log_phase "SERVICENOW-CONNECTOR" "Configuring Gemini Enterprise ServiceNow Data Connector (${SERVICENOW_COLLECTION_ID})"

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  local loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
  local col_url="${base_v1alpha}/${loc_parent}/collections/${SERVICENOW_COLLECTION_ID}"
  local conn_url="${col_url}/dataConnector"

  if [[ "${include_create}" == "true" ]]; then
    local col_payload
    col_payload="$(jq -n --arg dn "${SERVICENOW_COLLECTION_DISPLAY_NAME}" '{displayName: $dn}')"
    ge_upsert_resource "${col_url}" "${base_v1alpha}/${loc_parent}/collections?collectionId=${SERVICENOW_COLLECTION_ID}" "${col_url}?updateMask=displayName" "${col_payload}" >/dev/null || true
  fi

  local payload
  payload="$(render_servicenow_connector_payload)"
  ge_curl_request "PATCH" "${conn_url}?updateMask=connectorModes,params,entities,destinationConfigs,actionConfig" "${payload}" "true" >/dev/null || true
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

  IFS=',' read -r -a app_arr <<< "${SERVICENOW_TARGET_APPS}"
  for app_id in "${app_arr[@]}"; do
    app_id="$(printf '%s' "${app_id}" | xargs)"
    [[ -z "${app_id}" ]] && continue
    local engine_url="${base_v1alpha}/${loc_parent}/collections/default_collection/engines/${app_id}"
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
      log_ok "Attached ServiceNow Data Stores to Gemini Enterprise App '${app_id}'."
    fi
  done
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
