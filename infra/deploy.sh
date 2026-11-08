#!/usr/bin/env bash
# ==============================================================================
# Gemini Enterprise App Deployment Automation — Master Executable Entrypoint
# ==============================================================================
# Provisions and configures Gemini Enterprise applications in a target Google
# Cloud environment using Terraform where supported and authenticated curl REST
# API calls for Discovery Engine / Gemini Enterprise capabilities.
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
# shellcheck source=scripts/register_agents.sh
source "${DEPLOY_ROOT}/scripts/register_agents.sh"
# shellcheck source=scripts/verify.sh
source "${DEPLOY_ROOT}/scripts/verify.sh"

print_usage() {
  cat <<'EOF'
Usage: ./deploy.sh [OPTIONS]

Master executable orchestrator for Gemini Enterprise App Deployment Automation.

Options:
  --config <path>      Path to customer configuration file (default: ./config.env)
  --dry-run            Validate config, run 'terraform plan', and print curl commands without mutating state
  --terraform-only     Execute only Pre-Flight and Terraform provisioning phases
  --curl-only          Execute only Pre-Flight and curl REST API phases (also creates Data Store/Engine via curl if missing)
  --verify-only        Execute only Pre-Flight and Post-Deployment Verification phases
  --destroy            Deregister curl-managed resources and run 'terraform destroy'
  --help, -h           Show this help message and exit
EOF
}

import_existing_ge_app_resources() {
  local tf_dir="$1"
  if [[ "${DRY_RUN:-false}" == "true" || -z "${GCP_PROJECT_ID:-}" ]]; then
    return 0
  fi

  log_info "Reconciling existing Cloud Identity, IAM & Discovery Engine resources into Terraform state..."
  local state_list
  state_list="$(terraform -chdir="${tf_dir}" state list 2>/dev/null || true)"

  # 1. Import project-wide custom role geConnectorAuthUser if it already exists
  if ! grep -qF "google_project_iam_custom_role.connector_auth_user" <<<"${state_list}"; then
    local role_resp role_name
    role_resp="$(ge_curl_request "GET" "https://iam.googleapis.com/v1/projects/${GCP_PROJECT_ID}/roles/geConnectorAuthUser" "" "true" || echo '{}')"
    role_name="$(jq -r '.name // empty' <<<"${role_resp}" 2>/dev/null || true)"
    if [[ -n "${role_name}" ]]; then
      log_info "Importing existing IAM custom role '${role_name}' -> google_project_iam_custom_role.connector_auth_user"
      terraform -chdir="${tf_dir}" import -input=false "google_project_iam_custom_role.connector_auth_user" "${role_name}" >/dev/null 2>&1 || true
    fi
  fi

  # 2. Import per-app Cloud Identity group if it already exists
  if [[ -n "${GE_CLOUD_IDENTITY_CUSTOMER_ID:-}" ]] && ! grep -qF 'google_cloud_identity_group.app_group[0]' <<<"${state_list}"; then
    local grp_email existing_grps grp_res_name
    grp_email="${GE_APP_ACCESS_GROUP:-${GE_APP_ID}-users@${GE_CUSTOMER_DOMAIN:-example.com}}"
    existing_grps="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${GE_CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"
    grp_res_name="$(jq -r --arg em "${grp_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' <<<"${existing_grps}" 2>/dev/null | head -n 1 || true)"
    if [[ -n "${grp_res_name}" ]]; then
      log_info "Importing existing Cloud Identity group '${grp_email}' (${grp_res_name}) -> google_cloud_identity_group.app_group[0]"
      terraform -chdir="${tf_dir}" import -input=false 'google_cloud_identity_group.app_group[0]' "${grp_res_name}" >/dev/null 2>&1 || true
    fi
  fi

  # 3. Import existing Discovery Engine Search Engine if it already exists
  if [[ -n "${GE_APP_ID:-}" ]] && ! grep -qF "google_discovery_engine_search_engine.main" <<<"${state_list}"; then
    local base_v1alpha col_parent eng_resp eng_name
    base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
    col_parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}/collections/${GE_COLLECTION_ID:-default_collection}"
    eng_resp="$(ge_curl_request "GET" "${base_v1alpha}/${col_parent}/engines/${GE_APP_ID}" "" "true" || echo '{}')"
    eng_name="$(jq -r '.name // empty' <<<"${eng_resp}" 2>/dev/null || true)"
    if [[ -n "${eng_name}" ]]; then
      log_info "Importing existing Gemini Enterprise Engine '${GE_APP_ID}' -> google_discovery_engine_search_engine.main"
      terraform -chdir="${tf_dir}" import -input=false "google_discovery_engine_search_engine.main" "${col_parent}/engines/${GE_APP_ID}" >/dev/null 2>&1 || true
    fi
  fi
}

run_terraform_phase() {
  local action="${1:-apply}"
  local tf_dir="${DEPLOY_ROOT}/terraform"
  log_phase "TERRAFORM" "Executing Terraform workflow (${action}) in ${tf_dir}"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"
    gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project="${GCP_PROJECT_ID}" --quiet >/dev/null 2>&1 || true
  fi

  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    log_info "Configuring remote GCS backend (bucket=${TF_STATE_BUCKET}, prefix=${TF_STATE_PREFIX:-gemini-enterprise/state})..."
    cat > "${tf_dir}/backend_override.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "${TF_STATE_PREFIX:-gemini-enterprise/state}"
  }
}
EOF
  else
    rm -f "${tf_dir}/backend_override.tf"
  fi

  local workspace="${TF_WORKSPACE_OVERRIDE:-${GE_APP_ID}}"
  log_info "Initializing Terraform..."
  terraform -chdir="${tf_dir}" init -reconfigure -input=false >/dev/null
  log_info "Selecting Terraform workspace '${workspace}'..."
  terraform -chdir="${tf_dir}" workspace select -or-create "${workspace}" >/dev/null
  log_info "Validating Terraform configuration..."
  terraform -chdir="${tf_dir}" validate >/dev/null

  if [[ "${action}" != "destroy" ]]; then
    import_existing_ge_app_resources "${tf_dir}"
  fi

  if [[ "${action}" == "destroy" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] terraform -chdir='${tf_dir}' plan -destroy"
    else
      log_info "Destroying Terraform-managed resources..."
      terraform -chdir="${tf_dir}" destroy -auto-approve -input=false >/dev/null
    fi
    rm -f "${tf_dir}/backend_override.tf"
    log_ok "Terraform destroy phase complete."
    return 0
  fi

  log_info "Generating Terraform execution plan..."
  terraform -chdir="${tf_dir}" plan -out=tfplan -input=false >/dev/null

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping 'terraform apply' (plan saved to ${tf_dir}/tfplan)."
  else
    log_info "Applying Terraform plan..."
    terraform -chdir="${tf_dir}" apply -auto-approve -input=false tfplan >/dev/null
    local tf_outputs
    tf_outputs="$(terraform -chdir="${tf_dir}" output -json)"
    export GE_APP_ID="$(printf '%s' "${tf_outputs}" | jq -r '.engine_id.value // empty' || printf '%s' "${GE_APP_ID}")"
    export GE_DATA_STORE_ID="$(printf '%s' "${tf_outputs}" | jq -r '.data_store_id.value // empty' || printf '%s' "${GE_DATA_STORE_ID}")"
  fi

  rm -f "${tf_dir}/backend_override.tf"
  log_ok "Terraform phase complete."
}

deploy_main() {
  local config_file="${DEPLOY_ROOT}/config.env"
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
        print_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_usage
        return 1
        ;;
    esac
  done

  init_logging "${DEPLOY_ROOT}/logs"
  load_config "${config_file}"
  run_preflight_checks

  case "${mode}" in
    terraform-only)
      run_terraform_phase "apply"
      ;;
    curl-only)
      configure_gemini_enterprise_app "true"
      register_gemini_enterprise_agents
      run_verification_and_summary
      ;;
    verify-only)
      run_verification_and_summary
      ;;
    destroy)
      deregister_gemini_enterprise_agents
      run_terraform_phase "destroy"
      ;;
    full)
      run_terraform_phase "apply"
      configure_gemini_enterprise_app "false"
      register_gemini_enterprise_agents
      run_verification_and_summary
      ;;
  esac

  log_ok "Gemini Enterprise deployment workflow ('${mode}') completed successfully."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_main "$@"
fi
