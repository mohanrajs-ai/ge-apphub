#!/usr/bin/env bash
# ==============================================================================
# Microsoft 365 (M365) Data Connectors — Master Deployment Entrypoint
# ==============================================================================
# Standalone orchestrator to provision and configure M365 Data Connectors
# (SharePoint Online, OneDrive, Outlook, Microsoft Teams) in Google Cloud
# Discovery Engine / Gemini Enterprise using `terraform-m365/` and/or `curl`.
# ==============================================================================

set -euo pipefail

DEPLOY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="${DEPLOY_ROOT}"

# shellcheck source=scripts/lib/common.sh
source "${DEPLOY_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${DEPLOY_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/preflight.sh
source "${DEPLOY_ROOT}/scripts/preflight.sh"
# shellcheck source=scripts/configure_ge_app.sh
source "${DEPLOY_ROOT}/scripts/configure_ge_app.sh"
# shellcheck source=scripts/configure_m365_connectors.sh
source "${DEPLOY_ROOT}/scripts/configure_m365_connectors.sh"

print_m365_usage() {
  cat <<'EOF'
Usage: ./deploy_m365.sh [OPTIONS]

Master executable orchestrator for Microsoft 365 (M365) Data Connectors.

Options:
  --config <path>      Path to M365 configuration file (default: ./configs/m365.env)
  --dry-run            Validate config, run 'terraform plan', and print curl commands without mutating state
  --terraform-only     Execute only Pre-Flight and Terraform (terraform-m365/) provisioning phases
  --curl-only          Execute only Pre-Flight, curl setUpDataConnector REST API, and Verification phases
  --verify-only        Execute only Pre-Flight and Post-Deployment Verification phases
  --destroy            Destroy Terraform-managed M365 connectors and clean up curl-managed collections
  --help, -h           Show this help message and exit
EOF
}

run_m365_preflight_checks() {
  log_phase "PRE-FLIGHT" "Validating CLI dependencies, M365 configuration, and GCP authentication"
  check_cli_dependencies
  validate_m365_config
  check_gcloud_auth
  log_ok "All M365 pre-flight checks passed."
}

import_existing_m365_resources() {
  local tf_dir="$1"
  if [[ "${DRY_RUN:-false}" == "true" || -z "${GCP_PROJECT_ID:-}" ]]; then
    return 0
  fi

  log_info "Reconciling existing Secret Manager & M365 Data Connector resources into Terraform state..."
  local state_list
  state_list="$(terraform -chdir="${tf_dir}" state list 2>/dev/null || true)"

  local secret_id="${M365_SECRET_ID:-m365-connector-credentials}"
  local sm_base="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}"

  if ! grep -qF "google_secret_manager_secret.m365_credentials" <<<"${state_list}"; then
    local sec_resp sec_name
    sec_resp="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}" "" "true" || echo '{}')"
    sec_name="$(jq -r '.name // empty' <<<"${sec_resp}" 2>/dev/null || true)"
    if [[ -n "${sec_name}" ]]; then
      log_info "Importing existing Secret Manager secret '${secret_id}' -> google_secret_manager_secret.m365_credentials"
      terraform -chdir="${tf_dir}" import -input=false "google_secret_manager_secret.m365_credentials" "projects/${GCP_PROJECT_ID}/secrets/${secret_id}" >/dev/null 2>&1 || true
    fi
  fi

  if ! grep -qF "google_secret_manager_secret_version.m365_credentials_initial" <<<"${state_list}"; then
    local ver_meta ver_name
    ver_meta="$(ge_curl_request "GET" "${sm_base}/secrets/${secret_id}/versions/latest" "" "true" || echo '{}')"
    ver_name="$(jq -r '.name // empty' <<<"${ver_meta}" 2>/dev/null || true)"
    if [[ -n "${ver_name}" ]]; then
      log_info "Importing existing Secret Manager secret version '${ver_name}' -> google_secret_manager_secret_version.m365_credentials_initial"
      terraform -chdir="${tf_dir}" import -input=false "google_secret_manager_secret_version.m365_credentials_initial" "${ver_name}" >/dev/null 2>&1 || true
    fi
  fi

  local base_v1alpha loc_parent
  base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
  loc_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"

  local conn_specs=(
    "sharepoint:sp:${ENABLE_SHAREPOINT_CONNECTOR:-true}"
    "onedrive:od:${ENABLE_ONEDRIVE_CONNECTOR:-false}"
    "outlook:ol:${ENABLE_OUTLOOK_CONNECTOR:-false}"
    "teams:teams:${ENABLE_TEAMS_CONNECTOR:-false}"
  )
  for spec in "${conn_specs[@]}"; do
    IFS=":" read -r tf_res sfx enabled <<< "${spec}"
    [[ "${enabled}" != "true" ]] && continue
    local tf_addr="google_discovery_engine_data_connector.${tf_res}[0]"
    if ! grep -qF "${tf_addr}" <<<"${state_list}"; then
      local col_id conn_resp conn_name
      col_id="$(_resolve_m365_col_id "${sfx}")"
      conn_resp="$(ge_curl_request "GET" "${base_v1alpha}/${loc_parent}/collections/${col_id}/dataConnector" "" "true" || echo '{}')"
      conn_name="$(jq -r '.name // empty' <<<"${conn_resp}" 2>/dev/null || true)"
      if [[ -n "${conn_name}" ]]; then
        log_info "Importing existing M365 connector '${col_id}' -> ${tf_addr}"
        terraform -chdir="${tf_dir}" import -input=false "${tf_addr}" "${loc_parent}/collections/${col_id}/dataConnector" >/dev/null 2>&1 || true
      fi
    fi
  done
}

run_m365_terraform_phase() {
  local action="${1:-apply}"
  local tf_dir="${DEPLOY_ROOT}/terraform-m365"
  local workspace="${TF_WORKSPACE_OVERRIDE:-${M365_COLLECTION_PREFIX:-m365}}"
  log_phase "TERRAFORM-M365" "Executing Terraform workflow (${action}) in ${tf_dir}"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token --quiet 2>/dev/null || gcloud auth print-access-token --quiet)"
    gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project="${GCP_PROJECT_ID}" --quiet >/dev/null 2>&1 || true
  fi

  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    log_info "Configuring remote GCS backend (bucket=${TF_STATE_BUCKET}, prefix=${TF_STATE_PREFIX:-gemini-enterprise/m365-connectors})..."
    cat > "${tf_dir}/backend_override.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "${TF_STATE_PREFIX:-gemini-enterprise/m365-connectors}"
  }
}
EOF
  else
    rm -f "${tf_dir}/backend_override.tf"
  fi

  log_info "Initializing Terraform in ${tf_dir}..."
  rm -f "${tf_dir}/.terraform/environment"
  terraform -chdir="${tf_dir}" init -reconfigure -input=false >/dev/null
  log_info "Selecting Terraform workspace '${workspace}'..."
  terraform -chdir="${tf_dir}" workspace select -or-create "${workspace}" >/dev/null
  log_info "Validating Terraform M365 configuration..."
  terraform -chdir="${tf_dir}" validate >/dev/null

  if [[ "${action}" != "destroy" ]]; then
    import_existing_m365_resources "${tf_dir}"
  fi

  if [[ "${action}" == "destroy" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] terraform -chdir='${tf_dir}' plan -destroy"
    else
      log_info "Destroying Terraform-managed M365 connectors..."
      terraform -chdir="${tf_dir}" destroy -auto-approve -input=false >/dev/null
    fi
    rm -f "${tf_dir}/backend_override.tf"
    log_ok "Terraform M365 destroy phase complete."
    return 0
  fi

  log_info "Generating Terraform M365 execution plan..."
  terraform -chdir="${tf_dir}" plan -out=tfplan -input=false >/dev/null

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping 'terraform apply' (plan saved to ${tf_dir}/tfplan)."
  else
    log_info "Applying Terraform M365 plan..."
    terraform -chdir="${tf_dir}" apply -auto-approve -input=false tfplan >/dev/null
  fi

  rm -f "${tf_dir}/backend_override.tf"
  log_ok "Terraform M365 phase complete."
}

deploy_m365_main() {
  local config_file="${DEPLOY_ROOT}/configs/m365.env"
  export DRY_RUN="false"
  export SKIP_TERRAFORM="false"
  local mode="full"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --dry-run)
        export DRY_RUN="true"
        shift
        ;;
      --terraform-only)
        mode="terraform-only"
        shift
        ;;
      --curl-only)
        mode="curl-only"
        export SKIP_TERRAFORM="true"
        shift
        ;;
      --verify-only)
        mode="verify-only"
        export SKIP_TERRAFORM="true"
        shift
        ;;
      --destroy)
        mode="destroy"
        shift
        ;;
      --help|-h)
        print_m365_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_m365_usage
        return 1
        ;;
    esac
  done

  init_logging "${DEPLOY_ROOT}/logs"
  load_m365_config "${config_file}"
  run_m365_preflight_checks

  case "${mode}" in
    terraform-only)
      run_m365_terraform_phase "apply"
      ;;
    curl-only)
      configure_m365_connectors "true"
      run_m365_verification_and_summary
      ;;
    verify-only)
      run_m365_verification_and_summary
      ;;
    destroy)
      deregister_m365_connectors
      run_m365_terraform_phase "destroy"
      ;;
    full)
      run_m365_terraform_phase "apply"
      configure_m365_connectors "false"
      run_m365_verification_and_summary
      ;;
  esac

  log_ok "M365 Data Connectors deployment workflow ('${mode}') completed successfully."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_m365_main "$@"
fi
