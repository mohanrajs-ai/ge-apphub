#!/usr/bin/env bash
# Pre-flight validation for CLI dependencies, gcloud authentication, and customer configuration.

set -euo pipefail

check_cli_dependencies() {
  local tools=("$@")
  if [[ "${#tools[@]}" -eq 0 ]]; then
    tools=("gcloud" "curl" "jq")
    if [[ "${SKIP_TERRAFORM:-false}" != "true" ]]; then
      tools+=("terraform")
    fi
  fi

  local missing=0
  for tool in "${tools[@]}"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      log_error "Required CLI tool '${tool}' is not installed or not in PATH."
      missing=1
    else
      log_info "Verified CLI dependency: ${tool}"
    fi
  done

  if [[ "${missing}" -ne 0 ]]; then
    log_error "Remediation: Install the missing CLI tools above or run inside Google Cloud Shell."
    return 1
  fi
  return 0
}

validate_required_config() {
  local required_vars=("GCP_PROJECT_ID" "GCP_REGION" "GE_LOCATION" "GE_APP_ID" "GE_APP_DISPLAY_NAME")
  if [[ "${GE_CREATE_PER_APP_DATA_STORE:-false}" == "true" ]]; then
    required_vars+=("GE_DATA_STORE_ID" "GE_DATA_STORE_DISPLAY_NAME")
  fi

  for var_name in "${required_vars[@]}"; do
    local val="${!var_name:-}"
    if [[ -z "${val}" ]]; then
      log_error "Required configuration variable '${var_name}' is empty or unset."
      return 1
    fi
  done

  case "${GE_LOCATION}" in
    global|us|eu)
      log_info "Validated GE_LOCATION='${GE_LOCATION}'"
      ;;
    *)
      log_error "Invalid GE_LOCATION='${GE_LOCATION}'. Allowed values: global, us, eu."
      return 1
      ;;
  esac

  return 0
}

check_gcloud_auth() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping live gcloud token retrieval check."
    return 0
  fi

  local token
  if ! token="$(gcloud auth application-default print-access-token --quiet 2>/dev/null || gcloud auth print-access-token --quiet 2>/dev/null)" || [[ -z "${token}" ]]; then
    log_error "Failed to obtain an active OAuth2 access token from gcloud."
    log_error "Remediation: Run 'gcloud auth login' and 'gcloud config set project ${GCP_PROJECT_ID:-<PROJECT_ID>}'."
    return 1
  fi

  log_ok "Active gcloud authentication verified."
  return 0
}

run_preflight_checks() {
  log_phase "PRE-FLIGHT" "Validating CLI dependencies, configuration, and GCP authentication"
  check_cli_dependencies
  validate_required_config
  check_gcloud_auth
  log_ok "All pre-flight checks passed."
  return 0
}
