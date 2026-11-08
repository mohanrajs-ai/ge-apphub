#!/usr/bin/env bash
# Registers and deregisters ADK / custom Agents with Gemini Enterprise via REST API (curl).

set -euo pipefail

render_agent_payload() {
  jq -n \
    --arg displayName "${AGENT_DISPLAY_NAME:-Custom Enterprise Agent}" \
    --arg description "${AGENT_DESCRIPTION:-Enterprise custom agent}" \
    --arg reasoningEngine "${AGENT_REASONING_ENGINE:-}" \
    '{displayName: $displayName, description: $description, adkAgentDefinition: {toolSettings: {toolDescription: $description}, provisionedReasoningEngine: {reasoningEngine: $reasoningEngine}}}'
}

register_gemini_enterprise_agents() {
  if [[ "${ENABLE_AGENT_REGISTRATION:-false}" != "true" ]]; then
    log_info "ENABLE_AGENT_REGISTRATION is '${ENABLE_AGENT_REGISTRATION:-false}'; skipping Agent registration."
    return 0
  fi

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local assistant_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}/engines/${GE_APP_ID}/assistants/${GE_ASSISTANT_ID:-default_assistant}"
  local agent_id="${AGENT_ID:-ops-automation-agent}"

  log_info "Registering Agent '${agent_id}' (${AGENT_DISPLAY_NAME}) into Gemini Enterprise Assistant..."
  local payload
  payload="$(render_agent_payload)"

  ge_upsert_resource \
    "${base_v1alpha}/${assistant_parent}/agents/${agent_id}" \
    "${base_v1alpha}/${assistant_parent}/agents?agentId=${agent_id}" \
    "${base_v1alpha}/${assistant_parent}/agents/${agent_id}?updateMask=displayName,description,adkAgentDefinition" \
    "${payload}" >/dev/null

  log_ok "Agent '${agent_id}' registered with Gemini Enterprise Engine '${GE_APP_ID}'."
}

deregister_gemini_enterprise_agents() {
  if [[ "${ENABLE_AGENT_REGISTRATION:-false}" != "true" ]]; then
    log_info "ENABLE_AGENT_REGISTRATION is false; skipping Agent deregistration."
    return 0
  fi

  local base_v1alpha
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
  local agent_url="${base_v1alpha}/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/${GE_COLLECTION_ID:-default_collection}/engines/${GE_APP_ID}/assistants/${GE_ASSISTANT_ID:-default_assistant}/agents/${AGENT_ID:-ops-automation-agent}"

  log_info "Deregistering Agent '${AGENT_ID:-ops-automation-agent}' via DELETE..."
  ge_curl_request "DELETE" "${agent_url}" "" "true" >/dev/null || true
  log_ok "Agent '${AGENT_ID:-ops-automation-agent}' deregistered."
}
