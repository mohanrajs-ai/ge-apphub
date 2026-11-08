#!/usr/bin/env bash
# ==============================================================================
# Universal ADK Skill Orchestrator Multi-App Publisher & Pinner
# ==============================================================================
# Publishes, shares (scope=ALL_USERS), and pins (defaultPinned=true) a single
# Vertex AI ReasoningEngine (`universal-skill-orchestrator`) across one or more
# Gemini Enterprise Apps (`cymbal-service-desk-app`, `cymbal-dev-sandbox-app`,
# `cymbal-finance-app`, `cymbal-hr-app`, etc.).
#
# Usage:
#   # Share to Service Desk App only:
#   ./publish_universal_agent.sh \
#     --gcp-project-id cymbal-app-514110 \
#     --app-ids cymbal-service-desk-app
#
#   # Share to ALL Cymbal Departmental Apps:
#   ./publish_universal_agent.sh \
#     --gcp-project-id cymbal-app-514110 \
#     --all-apps
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export PROJECT_ROOT="${SCRIPT_DIR}"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${SCRIPT_DIR}/scripts/lib/http.sh"

GCP_PROJECT_ID="${GCP_PROJECT_ID:-cymbal-app-514110}"
GCP_REGION="${GCP_REGION:-us-central1}"
GE_LOCATION="${GE_LOCATION:-global}"
APP_IDS_CSV=""
ALL_APPS="false"
REASONING_ENGINE=""
AGENT_ID="universal-skill-orchestrator"
AGENT_DISPLAY_NAME="Enterprise Skill Orchestrator"
AGENT_DESCRIPTION="Universal ADK Skill Orchestrator that dynamically loads governed Parent Skills and chains reusable Sub-Skills across M365 SharePoint, OneDrive, Outlook, and Teams."
DEFAULT_PINNED="true"
WAIT_FOR_DEPLOY="true"

usage() {
  cat <<EOF
Usage: ./publish_universal_agent.sh [OPTIONS]

Options:
  --gcp-project-id <id>       GCP Project ID hosting the Gemini Enterprise Apps (default: cymbal-app-514110)
  --region <region>           Vertex AI ReasoningEngine region (default: us-central1)
  --location <loc>            Discovery Engine location (default: global)
  --app-ids <id1,id2>         Comma-separated Gemini Enterprise Engine IDs (e.g. cymbal-service-desk-app)
  --all-apps                  Publish and share to all Gemini Enterprise Apps in the project
  --reasoning-engine <res>    Full Vertex AI ReasoningEngine resource name (auto-detected if omitted)
  --agent-id <id>             Agent ID in Discovery Engine (default: universal-skill-orchestrator)
  --display-name <name>       Display name in Gemini Enterprise UI
  --no-wait                   Do not wait for pending ReasoningEngine build operation
  --dry-run                   Print API calls without mutating state
  -h, --help                  Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gcp-project-id)
      GCP_PROJECT_ID="$2"
      shift 2
      ;;
    --region)
      GCP_REGION="$2"
      shift 2
      ;;
    --location)
      GE_LOCATION="$2"
      shift 2
      ;;
    --app-ids|--app-id)
      APP_IDS_CSV="$2"
      shift 2
      ;;
    --all-apps)
      ALL_APPS="true"
      shift
      ;;
    --reasoning-engine)
      REASONING_ENGINE="$2"
      shift 2
      ;;
    --agent-id)
      AGENT_ID="$2"
      shift 2
      ;;
    --display-name)
      AGENT_DISPLAY_NAME="$2"
      shift 2
      ;;
    --no-wait)
      WAIT_FOR_DEPLOY="false"
      shift
      ;;
    --dry-run)
      export DRY_RUN="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log_error "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

export GCP_PROJECT_ID GCP_REGION GE_LOCATION
METADATA_FILE="${REPO_ROOT}/agents/universal_skill_orchestrator/deployment_metadata.json"

# 1. Resolve ReasoningEngine resource name (and optionally wait for pending operation)
if [[ -z "${REASONING_ENGINE}" && -f "${METADATA_FILE}" ]]; then
  remote_id="$(jq -r '.remote_agent_runtime_id // .remote_agent_engine_id // empty' "${METADATA_FILE}" 2>/dev/null || true)"
  pending_op="$(jq -r '.pending_operation.operation_name // empty' "${METADATA_FILE}" 2>/dev/null || true)"
  if [[ -n "${remote_id}" && "${remote_id}" != "None" ]]; then
    REASONING_ENGINE="${remote_id}"
  elif [[ -n "${pending_op}" && "${pending_op}" != "None" ]]; then
    REASONING_ENGINE="${pending_op%/operations/*}"
    if [[ "${WAIT_FOR_DEPLOY}" == "true" && "${DRY_RUN:-false}" != "true" ]]; then
      log_info "Checking ReasoningEngine deployment operation '${pending_op}'..."
      for attempt in {1..36}; do
        op_json="$(ge_curl_request "GET" "https://${GCP_REGION}-aiplatform.googleapis.com/v1beta1/${pending_op}" "" "true" || echo '{}')"
        op_done="$(jq -r '.done // false' <<<"${op_json}" 2>/dev/null || echo "false")"
        if [[ "${op_done}" == "true" ]]; then
          op_err="$(jq -r '.error.message // empty' <<<"${op_json}" 2>/dev/null || true)"
          if [[ -n "${op_err}" ]]; then
            log_error "ReasoningEngine build failed: ${op_err}"
            exit 1
          fi
          log_ok "ReasoningEngine '${REASONING_ENGINE}' deployment operation is complete."
          break
        fi
        log_info "ReasoningEngine '${REASONING_ENGINE}' is still building (attempt ${attempt}/36); waiting 10s..."
        sleep 10
      done
    fi
  fi
fi

if [[ -z "${REASONING_ENGINE}" && "${DRY_RUN:-false}" != "true" ]]; then
  re_list="$(ge_curl_request "GET" "https://${GCP_REGION}-aiplatform.googleapis.com/v1beta1/projects/${GCP_PROJECT_ID}/locations/${GCP_REGION}/reasoningEngines" "" "true" || echo '{}')"
  REASONING_ENGINE="$(jq -r '.reasoningEngines[0].name // empty' <<<"${re_list}" 2>/dev/null || true)"
fi

if [[ -z "${REASONING_ENGINE}" ]]; then
  REASONING_ENGINE="projects/${GCP_PROJECT_ID}/locations/${GCP_REGION}/reasoningEngines/universal-skill-orchestrator"
fi

# 2. Resolve target Gemini Enterprise App IDs
base_v1alpha="$(ge_api_base_url "${GE_LOCATION}" "v1alpha")"
col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/default_collection"

if [[ "${ALL_APPS}" == "true" || -z "${APP_IDS_CSV}" ]]; then
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    APP_IDS_CSV="${APP_IDS_CSV:-cymbal-service-desk-app,cymbal-dev-sandbox-app,cymbal-finance-app,cymbal-hr-app}"
  else
    eng_list="$(ge_curl_request "GET" "${base_v1alpha}/${col_parent}/engines" "" "true" || echo '{}')"
    APP_IDS_CSV="$(jq -r '[.engines[]?.name | split("/")[-1]] | join(",")' <<<"${eng_list}" 2>/dev/null || true)"
  fi
fi

if [[ -z "${APP_IDS_CSV}" ]]; then
  log_error "No target Gemini Enterprise Apps found in project '${GCP_PROJECT_ID}'."
  exit 1
fi

log_phase "PUBLISH-UNIVERSAL-AGENT" "Sharing & Pinning '${AGENT_DISPLAY_NAME}' (${REASONING_ENGINE}) -> [${APP_IDS_CSV}]"

if [[ "${DRY_RUN:-false}" != "true" ]]; then
  proj_num="$(gcloud projects describe "${GCP_PROJECT_ID}" --format="value(projectNumber)" 2>/dev/null || true)"
  if [[ -n "${proj_num}" ]]; then
    log_info "Ensuring Discovery Engine Service Agent ('service-${proj_num}@gcp-sa-discoveryengine.iam.gserviceaccount.com') has roles/aiplatform.user on '${GCP_PROJECT_ID}'..."
    gcloud projects add-iam-policy-binding "${GCP_PROJECT_ID}" \
      --member="serviceAccount:service-${proj_num}@gcp-sa-discoveryengine.iam.gserviceaccount.com" \
      --role="roles/aiplatform.user" \
      --condition=None \
      --quiet >/dev/null 2>&1 || true
  fi
fi

IFS=',' read -r -a TARGET_APPS <<< "${APP_IDS_CSV}"
for raw_app in "${TARGET_APPS[@]}"; do
  app_id="$(printf '%s' "${raw_app}" | xargs)"
  [[ -z "${app_id}" ]] && continue

  assistant_parent="${col_parent}/engines/${app_id}/assistants/default_assistant"
  agent_url="${base_v1alpha}/${assistant_parent}/agents/${AGENT_ID}"
  agents_col_url="${base_v1alpha}/${assistant_parent}/agents"

  log_info "Registering & sharing '${AGENT_DISPLAY_NAME}' on Engine '${app_id}'..."

  agent_payload="$(jq -n \
    --arg dn "${AGENT_DISPLAY_NAME}" \
    --arg desc "${AGENT_DESCRIPTION}" \
    --arg re "${REASONING_ENGINE}" \
    --argjson pinned "${DEFAULT_PINNED}" \
    '{
      displayName: $dn,
      description: $desc,
      state: "ENABLED",
      defaultPinned: $pinned,
      sharingConfig: {
        scope: "ALL_USERS"
      },
      starterPrompts: [
        {text: "Run /daily-morning-summary (m365-calendar-briefing + m365-outlook-triage + m365-teams-incident-swarm)"},
        {text: "Run /service-desk-major-incident-bridge (m365-teams-incident-swarm + sharepoint-policy-lookup + m365-onedrive-artifact-finder + m365-outlook-triage)"},
        {text: "Run /customer-escalation-resolver (m365-outlook-triage + sharepoint-policy-lookup)"},
        {text: "List all M365 composite skills and atomic sub-skills in the Skill Registry"}
      ],
      adkAgentDefinition: {
        toolSettings: {
          toolDescription: $desc
        },
        provisionedReasoningEngine: {
          reasoningEngine: $re
        }
      }
    }')"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would upsert ADK Agent '${AGENT_ID}' on '${app_id}' with reasoningEngine='${REASONING_ENGINE}', sharingConfig.scope='ALL_USERS', defaultPinned=true"
    continue
  fi

  # Check if an agent with AGENT_ID or displayName already exists on this Engine
  existing_agents="$(ge_curl_request "GET" "${agents_col_url}" "" "true" || echo '{}')"
  existing_name="$(jq -r --arg aid "${AGENT_ID}" --arg dn "${AGENT_DISPLAY_NAME}" '
    .agents[]? | select((.name | endswith("/" + $aid)) or (.displayName == $dn)) | .name
  ' <<<"${existing_agents}" 2>/dev/null | head -n 1 || true)"

  if [[ -n "${existing_name}" ]]; then
    log_info "Updating existing Agent '${existing_name}' on '${app_id}'..."
    ge_curl_request "PATCH" "${base_v1alpha}/${existing_name}?updateMask=displayName,description,adkAgentDefinition,sharingConfig" "${agent_payload}" "true" >/dev/null || true
    log_ok "Updated & shared Universal Agent ('${existing_name}') on '${app_id}'."
  else
    create_resp="$(ge_curl_request "POST" "${agents_col_url}?agentId=${AGENT_ID}" "${agent_payload}" "true" || echo '{}')"
    created_name="$(jq -r '.name // empty' <<<"${create_resp}" 2>/dev/null || true)"
    if [[ -z "${created_name}" ]]; then
      # Retry without ?agentId= if server generates numeric agent IDs
      create_resp="$(ge_curl_request "POST" "${agents_col_url}" "${agent_payload}" "true" || echo '{}')"
      created_name="$(jq -r '.name // empty' <<<"${create_resp}" 2>/dev/null || true)"
    fi
    if [[ -n "${created_name}" ]]; then
      log_ok "Published & shared Universal Agent ('${created_name}') on '${app_id}' (scope=ALL_USERS)."
    else
      log_warn "Could not verify agent creation response on '${app_id}': ${create_resp}"
    fi
  fi
done

log_ok "Universal ADK Skill Orchestrator published and shared across: ${APP_IDS_CSV}"
