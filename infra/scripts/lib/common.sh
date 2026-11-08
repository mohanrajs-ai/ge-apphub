#!/usr/bin/env bash
# Shared logging, banner, and configuration loader functions.

set -euo pipefail

# Default log file path if init_logging has not been called yet
LOG_FILE="${LOG_FILE:-}"

init_logging() {
  local log_dir="${1:-${PROJECT_ROOT:-.}/logs}"
  mkdir -p "${log_dir}"
  local ts
  ts="$(date +"%Y%m%d-%H%M%S")"
  LOG_FILE="${log_dir}/deploy-${ts}.log"
  touch "${LOG_FILE}"
  export LOG_FILE
}

_write_log() {
  local msg="$1"
  if [[ -n "${LOG_FILE:-}" && -f "${LOG_FILE}" ]]; then
    printf '%s %s\n' "$(date +"%Y-%m-%dT%H:%M:%S%z")" "${msg}" >> "${LOG_FILE}"
  fi
}

log_phase() {
  local phase="$1"
  local title="$2"
  local line="============================================================"
  local banner="[${phase}] ${title}"
  printf '\n%s\n%s\n%s\n' "${line}" "${banner}" "${line}"
  _write_log "${banner}"
}

log_info() {
  local msg="[INFO] $*"
  printf '%s\n' "${msg}"
  _write_log "${msg}"
}

log_ok() {
  local msg="[OK] $*"
  printf '%s\n' "${msg}"
  _write_log "${msg}"
}

log_warn() {
  local msg="[WARN] $*"
  printf '%s\n' "${msg}"
  _write_log "${msg}"
}

log_error() {
  local msg="[ERROR] $*"
  printf '%s\n' "${msg}" >&2
  _write_log "${msg}"
}

load_config() {
  local config_path="${1:-./config.env}"
  if [[ ! -f "${config_path}" ]]; then
    log_error "Configuration file not found at '${config_path}'. Copy 'config.env.example' to 'config.env' and populate your environment values."
    return 1
  fi

  set -a
  local repo_root="${PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
  if [[ -f "${repo_root}/configs/common_connectors.env" ]]; then
    # shellcheck disable=SC1091
    source "${repo_root}/configs/common_connectors.env"
  elif [[ -f "${repo_root}/configs/common_connectors.env.example" ]]; then
    # shellcheck disable=SC1091
    source "${repo_root}/configs/common_connectors.env.example"
  fi
  # shellcheck disable=SC1090
  source "${config_path}"
  set +a

  export GE_ENABLE_COMMON_CONNECTORS="${GE_ENABLE_COMMON_CONNECTORS:-true}"
  export GE_COMMON_CONNECTOR_COLLECTIONS="${GE_COMMON_CONNECTOR_COLLECTIONS:-}"
  export GE_COMMON_CONNECTOR_DATA_STORE_IDS="${GE_COMMON_CONNECTOR_DATA_STORE_IDS:-}"
  if [[ "${GE_ENABLE_COMMON_CONNECTORS}" == "false" ]]; then
    GE_COMMON_CONNECTOR_COLLECTIONS=""
    GE_COMMON_CONNECTOR_DATA_STORE_IDS=""
  fi

  export GE_CUSTOMER_DOMAIN="${GE_CUSTOMER_DOMAIN:-example.com}"
  export GE_CLOUD_IDENTITY_CUSTOMER_ID="${GE_CLOUD_IDENTITY_CUSTOMER_ID:-}"
  if [[ -z "${GE_APP_ACCESS_GROUP:-}" && -n "${GE_APP_ID:-}" ]]; then
    GE_APP_ACCESS_GROUP="${GE_APP_ID}-users@${GE_CUSTOMER_DOMAIN}"
  fi
  export GE_APP_ACCESS_GROUP="${GE_APP_ACCESS_GROUP:-}"
  export GE_APP_GROUP_MEMBERS="${GE_APP_GROUP_MEMBERS:-}"

  # Enterprise App Feature & Governance Defaults (16-Point Template)
  export GE_CONNECTOR_DISPLAY_NAMES_JSON="${GE_CONNECTOR_DISPLAY_NAMES_JSON:-{}}"
  export GE_ENABLE_AUTOCOMPLETE="${GE_ENABLE_AUTOCOMPLETE:-true}"
  export GE_AUTOCOMPLETE_MATCHING_ORDER="${GE_AUTOCOMPLETE_MATCHING_ORDER:-SUGGESTION_MATCHING_ORDER_PREFIX}"
  export GE_ENABLE_PEOPLE_SUGGESTION="${GE_ENABLE_PEOPLE_SUGGESTION:-true}"
  export GE_ENABLE_RECENT_SEARCH="${GE_ENABLE_RECENT_SEARCH:-true}"
  export GE_ENABLE_FEEDBACK="${GE_ENABLE_FEEDBACK:-true}"
  export GE_FEEDBACK_ALLOW_DETAILED_COMMENT="${GE_FEEDBACK_ALLOW_DETAILED_COMMENT:-true}"
  export GE_FEEDBACK_CAPTURE_THUMBS_UP_DOWN="${GE_FEEDBACK_CAPTURE_THUMBS_UP_DOWN:-true}"
  export GE_ENABLE_USER_EVENT_COLLECTION="${GE_ENABLE_USER_EVENT_COLLECTION:-true}"
  export GE_USER_EVENT_RETENTION_DAYS="${GE_USER_EVENT_RETENTION_DAYS:-365}"
  export GE_ENABLE_SEARCH_PERSONALIZATION="${GE_ENABLE_SEARCH_PERSONALIZATION:-true}"
  export GE_APP_LOGO_URI="${GE_APP_LOGO_URI:-}"
  export GE_APP_FAVICON_URI="${GE_APP_FAVICON_URI:-}"
  export GE_ENABLE_WEB_SEARCH_GROUNDING="${GE_ENABLE_WEB_SEARCH_GROUNDING:-true}"
  export GE_WEB_GROUNDING_TYPE="${GE_WEB_GROUNDING_TYPE:-WEB_GROUNDING_TYPE_GOOGLE_SEARCH}"
  export GE_ENABLE_MODEL_ARMOR="${GE_ENABLE_MODEL_ARMOR:-true}"
  export GE_MODEL_ARMOR_PROMPT_TEMPLATE="${GE_MODEL_ARMOR_PROMPT_TEMPLATE:-}"
  export GE_MODEL_ARMOR_RESPONSE_TEMPLATE="${GE_MODEL_ARMOR_RESPONSE_TEMPLATE:-}"
  export GE_MODEL_ARMOR_FAILURE_MODE="${GE_MODEL_ARMOR_FAILURE_MODE:-FAIL_CLOSED}"
  export GE_ENABLE_KNOWLEDGE_CATALOG="${GE_ENABLE_KNOWLEDGE_CATALOG:-true}"
  export GE_KNOWLEDGE_CATALOG_TAXONOMY="${GE_KNOWLEDGE_CATALOG_TAXONOMY:-enterprise-taxonomy}"
  export GE_CHAT_HISTORY_RETENTION_DAYS="${GE_CHAT_HISTORY_RETENTION_DAYS:-90}"
  export GE_CHAT_SESSION_TTL_SECONDS="${GE_CHAT_SESSION_TTL_SECONDS:-7776000s}"
  export GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH="${GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH:-true}"
  export GE_PKG_ENTITY_EXTRACTION_TYPES="${GE_PKG_ENTITY_EXTRACTION_TYPES:-PERSON,ORGANIZATION,PROJECT,ACRONYM,TOPIC}"
  export GE_FEATURE_AGENT_GALLERY="${GE_FEATURE_AGENT_GALLERY:-FEATURE_STATE_ON}"
  export GE_FEATURE_NO_CODE_AGENT_BUILDER="${GE_FEATURE_NO_CODE_AGENT_BUILDER:-FEATURE_STATE_ON}"
  export GE_FEATURE_AGENT_SHARING="${GE_FEATURE_AGENT_SHARING:-FEATURE_STATE_OFF}"
  export GE_FEATURE_SKILLS="${GE_FEATURE_SKILLS:-FEATURE_STATE_ON}"
  export GE_FEATURE_SKILL_SHARING="${GE_FEATURE_SKILL_SHARING:-FEATURE_STATE_ON}"
  export GE_FEATURE_SKILL_SHARING_ADMIN_APPROVAL="${GE_FEATURE_SKILL_SHARING_ADMIN_APPROVAL:-FEATURE_STATE_ON}"
  export GE_FEATURE_PROJECTS="${GE_FEATURE_PROJECTS:-FEATURE_STATE_ON}"
  export GE_FEATURE_PROMPT_GALLERY="${GE_FEATURE_PROMPT_GALLERY:-FEATURE_STATE_ON}"
  export GE_FEATURE_MODEL_SELECTOR="${GE_FEATURE_MODEL_SELECTOR:-FEATURE_STATE_ON}"
  export GE_FEATURE_NOTEBOOK_LM="${GE_FEATURE_NOTEBOOK_LM:-FEATURE_STATE_ON}"
  export GE_FEATURE_DEEP_RESEARCH="${GE_FEATURE_DEEP_RESEARCH:-FEATURE_STATE_ON}"
  export GE_FEATURE_PEOPLE_SEARCH="${GE_FEATURE_PEOPLE_SEARCH:-FEATURE_STATE_ON}"
  export GE_FEATURE_ACTIONS="${GE_FEATURE_ACTIONS:-FEATURE_STATE_ON}"
  export GE_FEATURE_AUDIO_OVERVIEW="${GE_FEATURE_AUDIO_OVERVIEW:-FEATURE_STATE_ON}"
  export GE_ALLOW_AGENT_SHARING="${GE_ALLOW_AGENT_SHARING:-false}"
  export GE_AGENT_SHARING_POLICY="${GE_AGENT_SHARING_POLICY:-SHARING_POLICY_DISABLED}"
  export GE_ENABLE_SKILLS="${GE_ENABLE_SKILLS:-true}"
  export GE_SKILL_SHARING_APPROVAL_POLICY="${GE_SKILL_SHARING_APPROVAL_POLICY:-ADMIN_APPROVAL_REQUIRED}"
  export GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING="${GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING:-true}"
  export GE_SKILL_APPROVER_GROUP="${GE_SKILL_APPROVER_GROUP:-ge-platform-admins@${GE_CUSTOMER_DOMAIN}}"
  export GE_ENABLE_PROJECTS="${GE_ENABLE_PROJECTS:-true}"
  export GE_ENABLE_OBSERVABILITY="${GE_ENABLE_OBSERVABILITY:-true}"
  export GE_OBSERVABILITY_AUDIT_LOGGING="${GE_OBSERVABILITY_AUDIT_LOGGING:-true}"
  export GE_OBSERVABILITY_QUERY_RESPONSE_LOGGING="${GE_OBSERVABILITY_QUERY_RESPONSE_LOGGING:-true}"
  export GE_OBSERVABILITY_LATENCY_METRICS="${GE_OBSERVABILITY_LATENCY_METRICS:-true}"
  export GE_OBSERVABILITY_BQ_DATASET="${GE_OBSERVABILITY_BQ_DATASET:-ge_observability}"
  export GE_OBSERVABILITY_LOG_SINK_NAME="${GE_OBSERVABILITY_LOG_SINK_NAME:-}"

  # Export standard TF_VAR_* mappings so Terraform uses the exact same single source of truth
  export TF_VAR_project_id="${GCP_PROJECT_ID:-}"
  export TF_VAR_region="${GCP_REGION:-us-central1}"
  export TF_VAR_location="${GE_LOCATION:-global}"
  export TF_VAR_collection_id="${GE_COLLECTION_ID:-default_collection}"
  export TF_VAR_app_id="${GE_APP_ID:-}"
  export TF_VAR_app_display_name="${GE_APP_DISPLAY_NAME:-}"
  export TF_VAR_company_name="${GE_COMPANY_NAME:-}"
  export TF_VAR_solution_type="${GE_SOLUTION_TYPE:-SOLUTION_TYPE_SEARCH}"
  export TF_VAR_app_type="${GE_APP_TYPE:-APP_TYPE_INTRANET}"
  export TF_VAR_search_tier="${GE_SEARCH_TIER:-SEARCH_TIER_ENTERPRISE}"
  export TF_VAR_enable_llm_addon="${GE_ENABLE_LLM_ADDON:-true}"
  export TF_VAR_industry_vertical="${GE_INDUSTRY_VERTICAL:-GENERIC}"
  export TF_VAR_data_store_id="${GE_DATA_STORE_ID:-}"
  export TF_VAR_data_store_display_name="${GE_DATA_STORE_DISPLAY_NAME:-}"
  export TF_VAR_data_store_content_config="${GE_DATA_STORE_CONTENT_CONFIG:-CONTENT_REQUIRED}"
  export TF_VAR_backing_storage_type="${GE_BACKING_STORAGE_TYPE:-GCS}"
  export TF_VAR_gcs_bucket_name="${GE_GCS_BUCKET_NAME:-}"
  export TF_VAR_bq_dataset_id="${GE_BQ_DATASET_ID:-gemini_enterprise_data}"
  export TF_VAR_iam_viewer_members="${GE_IAM_VIEWER_MEMBERS:-}"
  export TF_VAR_customer_domain="${GE_CUSTOMER_DOMAIN}"
  export TF_VAR_cloud_identity_customer_id="${GE_CLOUD_IDENTITY_CUSTOMER_ID}"
  export TF_VAR_app_access_group="${GE_APP_ACCESS_GROUP}"
  export TF_VAR_app_group_members="${GE_APP_GROUP_MEMBERS}"
  export TF_VAR_common_connector_data_store_ids="${GE_COMMON_CONNECTOR_DATA_STORE_IDS}"

  log_info "Loaded configuration from '${config_path}' (Project: ${GCP_PROJECT_ID:-unset}, Location: ${GE_LOCATION:-unset})"
  return 0
}
