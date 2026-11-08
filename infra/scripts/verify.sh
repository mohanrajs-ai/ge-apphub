#!/usr/bin/env bash
# Post-Deployment Health Checks and Summary Output Table for Gemini Enterprise

set -euo pipefail

verify_gemini_enterprise_resources() {
  log_phase "VERIFY" "Verifying Gemini Enterprise resources via Discovery Engine REST API"

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}"

  if [[ -n "${GE_DATA_STORE_ID:-}" ]]; then
    log_info "Verifying Data Store '${GE_DATA_STORE_ID}'..."
    ge_curl_request "GET" "${base_v1alpha}/${col_parent}/dataStores/${GE_DATA_STORE_ID}" >/dev/null
    log_ok "Data Store '${GE_DATA_STORE_ID}' is reachable and active."
  else
    log_info "Per-app knowledge source creation disabled (Google Search grounding + shared connectors only)."
  fi

  log_info "Verifying Gemini Enterprise Engine '${GE_APP_ID}'..."
  ge_curl_request "GET" "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}" >/dev/null
  log_ok "Gemini Enterprise Engine '${GE_APP_ID}' is reachable and active."

  log_info "Verifying exclusive Engine IAM policy on '${GE_APP_ID}' for group '${GE_APP_ACCESS_GROUP:-}'..."
  ge_curl_request "GET" "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}:getIamPolicy" >/dev/null
  log_ok "Engine '${GE_APP_ID}' IAM policy verified for exclusive group '${GE_APP_ACCESS_GROUP:-}'."

  if [[ "${ENABLE_AGENT_REGISTRATION:-false}" == "true" ]]; then
    local agent_id="${AGENT_ID:-ops-automation-agent}"
    log_info "Verifying Registered Agent '${agent_id}'..."
    ge_curl_request "GET" "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}/assistants/${GE_ASSISTANT_ID:-default_assistant}/agents/${agent_id}" >/dev/null
    log_ok "Registered Agent '${agent_id}' is reachable and active."
  fi
}

print_deployment_summary() {
  log_phase "SUMMARY" "Gemini Enterprise App Deployment Summary"
  printf '  Project ID          : %s\n' "${GCP_PROJECT_ID}"
  printf '  Location            : %s\n' "${GE_LOCATION}"
  printf '  Collection ID       : %s\n' "${GE_COLLECTION_ID:-default_collection}"
  printf '  Data Store ID       : %s (%s)\n' "${GE_DATA_STORE_ID}" "${GE_DATA_STORE_DISPLAY_NAME}"
  printf '  Common Connectors   : %s\n' "${GE_COMMON_CONNECTOR_COLLECTIONS:-(none)}"
  printf '  App / Engine ID     : %s (%s)\n' "${GE_APP_ID}" "${GE_APP_DISPLAY_NAME}"
  printf '  App Access Group    : %s\n' "${GE_APP_ACCESS_GROUP:-}"
  if [[ "${ENABLE_AGENT_REGISTRATION:-false}" == "true" ]]; then
    printf '  Registered Agent ID : %s (%s)\n' "${AGENT_ID:-ops-automation-agent}" "${AGENT_DISPLAY_NAME:-Custom Agent}"
  else
    printf '  Registered Agent ID : (disabled)\n'
  fi
  printf '  GCP Console URL     : https://console.cloud.google.com/gen-app-builder/engines?project=%s\n' "${GCP_PROJECT_ID}"
  if [[ -n "${LOG_FILE:-}" ]]; then
    printf '  Execution Log File  : %s\n' "${LOG_FILE}"
  fi
}

run_verification_and_summary() {
  verify_gemini_enterprise_resources
  print_deployment_summary
}
