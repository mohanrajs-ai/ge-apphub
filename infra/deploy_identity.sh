#!/usr/bin/env bash
# ==============================================================================
# Microsoft Entra ID to Google Cloud Identity Sync — Master Entrypoint
# ==============================================================================
# Standalone orchestrator that reads Entra ID OAuth credentials from Google
# Cloud Secret Manager (`m365-connector-credentials`), optionally migrates legacy UPNs to
# the shared domain (`SHARED_IDENTITY_DOMAIN`), syncs Entra Users, Groups,
# and Group Memberships into Google Cloud Identity via `terraform-identity/`,
# and aligns Gemini Enterprise Per-App access groups.
# ==============================================================================

set -euo pipefail

DEPLOY_IDENTITY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="${DEPLOY_IDENTITY_ROOT}"

# shellcheck source=scripts/lib/common.sh
source "${DEPLOY_IDENTITY_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${DEPLOY_IDENTITY_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/preflight.sh
source "${DEPLOY_IDENTITY_ROOT}/scripts/preflight.sh"
# shellcheck source=scripts/configure_identity.sh
source "${DEPLOY_IDENTITY_ROOT}/scripts/configure_identity.sh"

print_identity_usage() {
  cat <<'EOF'
Usage: ./deploy_identity.sh [OPTIONS]

Master executable orchestrator for Microsoft Entra ID to Google Cloud Identity Sync & SSO.

Options:
  --config <path>          Path to Identity configuration file (default: ./configs/identity.env)
  --dns-project-id <id>    Override Cloud DNS GCP project ID (when DNS lives in a separate project from the App project)
  --dns-zone-name <zone>   Override Cloud DNS managed zone name for shared_identity_domain
  --dry-run                Validate config, preview Graph sync, and run 'terraform plan' without mutating state
  --sync-only              Execute only Pre-Flight and Microsoft Graph discovery / UPN migration phases
  --terraform-only         Execute only Pre-Flight and Terraform (terraform-identity/) provisioning phases
  --verify-only            Execute only Pre-Flight and Post-Deployment Verification phases
  --destroy                Destroy Terraform-managed synced Cloud Identity group resources
  --help, -h               Show this help message and exit
EOF
}

run_identity_preflight_checks() {
  log_phase "PRE-FLIGHT" "Validating CLI dependencies, Identity configuration, and GCP authentication"
  check_cli_dependencies
  validate_identity_config
  check_gcloud_auth
  log_ok "All Identity pre-flight checks passed."
}

import_existing_cloud_identity_resources() {
  local tf_dir="$1"
  local tfvars_file="${tf_dir}/identity_entities.auto.tfvars.json"
  if [[ "${DRY_RUN:-false}" == "true" || ! -f "${tfvars_file}" || -z "${CLOUD_IDENTITY_CUSTOMER_ID:-}" ]]; then
    return 0
  fi

  log_info "Reconciling existing Cloud Identity groups & memberships into Terraform state..."
  local state_list existing_groups_json
  state_list="$(terraform -chdir="${tf_dir}" state list 2>/dev/null || true)"
  existing_groups_json="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"

  local group_keys
  group_keys="$(jq -r '.synced_groups | keys[]?' "${tfvars_file}" 2>/dev/null || true)"
  for gkey in ${group_keys}; do
    local gemail gname_res
    gemail="$(jq -r --arg k "${gkey}" '.synced_groups[$k].group_email // empty' "${tfvars_file}")"
    [[ -z "${gemail}" ]] && continue
    gname_res="$(echo "${existing_groups_json}" | jq -r --arg em "${gemail}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' 2>/dev/null | head -n 1 || true)"
    [[ -z "${gname_res}" ]] && continue

    local tf_grp_addr="google_cloud_identity_group.synced_entra_groups[\"${gkey}\"]"
    if ! grep -qF "${tf_grp_addr}" <<<"${state_list}"; then
      log_info "Importing existing Cloud Identity group '${gemail}' (${gname_res}) -> ${tf_grp_addr}"
      terraform -chdir="${tf_dir}" import -input=false "${tf_grp_addr}" "${gname_res}" >/dev/null 2>&1 || true
    fi

    # Also import any existing memberships for this group
    local mem_resp
    mem_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${gname_res}/memberships" "" "true" || echo '{}')"
    local cfg_members
    cfg_members="$(jq -r --arg k "${gkey}" '.synced_groups[$k].members[]?' "${tfvars_file}" 2>/dev/null || true)"
    for mem_email in ${cfg_members}; do
      local mem_lower mem_res_name tf_mem_addr
      mem_lower="$(printf '%s' "${mem_email}" | tr '[:upper:]' '[:lower:]')"
      tf_mem_addr="google_cloud_identity_group_membership.synced_group_members[\"${gkey}::${mem_lower}\"]"
      if ! grep -qF "${tf_mem_addr}" <<<"${state_list}"; then
        mem_res_name="$(echo "${mem_resp}" | jq -r --arg m "${mem_lower}" '.memberships[]? | select((.preferredMemberKey.id | ascii_downcase) == $m) | .name' 2>/dev/null | head -n 1 || true)"
        if [[ -n "${mem_res_name}" ]]; then
          log_info "Importing existing group membership '${mem_lower}' (${mem_res_name}) -> ${tf_mem_addr}"
          terraform -chdir="${tf_dir}" import -input=false "${tf_mem_addr}" "${mem_res_name}" >/dev/null 2>&1 || true
        fi
      fi
    done
  done

  # Also import existing nested app_group_mappings memberships if already present
  local map_count
  map_count="$(jq -r '.app_group_mappings | length' "${tfvars_file}" 2>/dev/null || echo "0")"
  if [[ "${map_count}" -gt 0 ]]; then
    existing_groups_json="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"
    local idx=0
    while [[ "${idx}" -lt "${map_count}" ]]; do
      local app_grp mem_grp app_grp_res
      app_grp="$(jq -r ".app_group_mappings[${idx}].app_group_email // empty" "${tfvars_file}" | tr '[:upper:]' '[:lower:]')"
      mem_grp="$(jq -r ".app_group_mappings[${idx}].member_email // empty" "${tfvars_file}" | tr '[:upper:]' '[:lower:]')"
      idx=$((idx + 1))
      [[ -z "${app_grp}" || -z "${mem_grp}" ]] && continue
      local tf_nest_addr="google_cloud_identity_group_membership.app_group_nested_members[\"${app_grp}::${mem_grp}\"]"
      if ! grep -qF "${tf_nest_addr}" <<<"${state_list}"; then
        app_grp_res="$(echo "${existing_groups_json}" | jq -r --arg em "${app_grp}" '.groups[]? | select((.groupKey.id | ascii_downcase) == $em) | .name' 2>/dev/null | head -n 1 || true)"
        if [[ -n "${app_grp_res}" ]]; then
          local app_mem_resp nest_res_name
          app_mem_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${app_grp_res}/memberships" "" "true" || echo '{}')"
          nest_res_name="$(echo "${app_mem_resp}" | jq -r --arg m "${mem_grp}" '.memberships[]? | select((.preferredMemberKey.id | ascii_downcase) == $m) | .name' 2>/dev/null | head -n 1 || true)"
          if [[ -n "${nest_res_name}" ]]; then
            log_info "Importing existing nested membership '${mem_grp}' -> '${app_grp}' (${nest_res_name})"
            terraform -chdir="${tf_dir}" import -input=false "${tf_nest_addr}" "${nest_res_name}" >/dev/null 2>&1 || true
          fi
        fi
      fi
    done
  fi
  # Also import existing Cloud DNS domain verification TXT record if managed in DNS_PROJECT_ID
  if [[ "${MANAGE_DNS_VERIFICATION_RECORD:-false}" == "true" && -n "${DNS_PROJECT_ID:-}" && -n "${DNS_ZONE_NAME:-}" && -n "${SHARED_IDENTITY_DOMAIN:-}" ]]; then
    local tf_dns_addr='google_dns_record_set.domain_verification_txt[0]'
    if ! grep -qF "${tf_dns_addr}" <<<"${state_list}"; then
      local fqdn="${SHARED_IDENTITY_DOMAIN%.}."
      if gcloud dns record-sets describe "${fqdn}" --type=TXT --zone="${DNS_ZONE_NAME}" --project="${DNS_PROJECT_ID}" --quiet >/dev/null 2>&1; then
        log_info "Importing existing Cloud DNS TXT record '${fqdn}' from project '${DNS_PROJECT_ID}' (zone '${DNS_ZONE_NAME}') -> ${tf_dns_addr}"
        terraform -chdir="${tf_dir}" import -input=false "${tf_dns_addr}" "projects/${DNS_PROJECT_ID}/managedZones/${DNS_ZONE_NAME}/rrsets/${fqdn}/TXT" >/dev/null 2>&1 || true
      fi
    fi
  fi
}

run_identity_terraform_phase() {
  local action="${1:-apply}"
  local tf_dir="${TF_IDENTITY_DIR_OVERRIDE:-${DEPLOY_IDENTITY_ROOT}/terraform-identity}"
  local workspace="${TF_WORKSPACE_OVERRIDE:-identity-sync}"
  log_phase "TERRAFORM-IDENTITY" "Executing Terraform workflow (${action}) in ${tf_dir}"

  if [[ "${DRY_RUN:-false}" != "true" ]]; then
    export GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth application-default print-access-token --quiet 2>/dev/null || gcloud auth print-access-token --quiet)"
    gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com --project="${GCP_PROJECT_ID}" --quiet >/dev/null 2>&1 || true
    if [[ "${MANAGE_DNS_VERIFICATION_RECORD:-false}" == "true" && -n "${DNS_PROJECT_ID:-}" && "${DNS_PROJECT_ID}" != "${GCP_PROJECT_ID}" ]]; then
      gcloud services enable cloudresourcemanager.googleapis.com serviceusage.googleapis.com dns.googleapis.com --project="${DNS_PROJECT_ID}" --quiet >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${TF_STATE_BUCKET:-}" ]]; then
    log_info "Configuring remote GCS backend (bucket=${TF_STATE_BUCKET}, prefix=${TF_STATE_PREFIX:-gemini-enterprise/identity-sync})..."
    cat > "${tf_dir}/backend_override.tf" <<EOF
terraform {
  backend "gcs" {
    bucket = "${TF_STATE_BUCKET}"
    prefix = "${TF_STATE_PREFIX:-gemini-enterprise/identity-sync}"
  }
}
EOF
  else
    rm -f "${tf_dir}/backend_override.tf"
  fi

  log_info "Initializing Terraform in ${tf_dir}..."
  terraform -chdir="${tf_dir}" init -input=false >/dev/null
  log_info "Selecting Terraform workspace '${workspace}'..."
  terraform -chdir="${tf_dir}" workspace select -or-create "${workspace}" >/dev/null
  log_info "Validating Terraform Identity configuration..."
  terraform -chdir="${tf_dir}" validate >/dev/null

  if [[ "${action}" != "destroy" ]]; then
    import_existing_cloud_identity_resources "${tf_dir}"
  fi

  if [[ "${action}" == "destroy" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] terraform -chdir='${tf_dir}' plan -destroy"
    else
      log_info "Destroying Terraform-managed Cloud Identity resources..."
      terraform -chdir="${tf_dir}" destroy -auto-approve -input=false >/dev/null
    fi
    rm -f "${tf_dir}/backend_override.tf"
    log_ok "Terraform Identity destroy phase complete."
    return 0
  fi

  log_info "Generating Terraform Identity execution plan..."
  terraform -chdir="${tf_dir}" plan -out=tfplan -input=false >/dev/null

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Skipping 'terraform apply' (plan saved to ${tf_dir}/tfplan)."
  else
    log_info "Applying Terraform Identity plan..."
    terraform -chdir="${tf_dir}" apply -auto-approve -input=false tfplan >/dev/null
  fi

  rm -f "${tf_dir}/backend_override.tf"
  log_ok "Terraform Identity phase complete."
}

deploy_identity_main() {
  local config_file="${DEPLOY_IDENTITY_ROOT}/configs/identity.env"
  export DRY_RUN="false"
  export SKIP_TERRAFORM="false"
  export DNS_PROJECT_ID_OVERRIDE=""
  export DNS_ZONE_NAME_OVERRIDE=""
  local mode="full"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --dns-project-id)
        export DNS_PROJECT_ID_OVERRIDE="$2"
        shift 2
        ;;
      --dns-zone-name)
        export DNS_ZONE_NAME_OVERRIDE="$2"
        shift 2
        ;;
      --dry-run)
        export DRY_RUN="true"
        shift
        ;;
      --sync-only)
        mode="sync-only"
        export SKIP_TERRAFORM="true"
        shift
        ;;
      --terraform-only)
        mode="terraform-only"
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
        print_identity_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_identity_usage
        return 1
        ;;
    esac
  done

  init_logging "${DEPLOY_IDENTITY_ROOT}/logs"
  load_identity_config "${config_file}"
  run_identity_preflight_checks

  case "${mode}" in
    sync-only)
      sync_entra_entities_to_cloud_identity
      run_identity_verification_and_summary
      ;;
    terraform-only)
      ensure_and_load_identity_secret_credentials
      run_identity_terraform_phase "apply"
      ;;
    verify-only)
      run_identity_verification_and_summary
      ;;
    destroy)
      ensure_and_load_identity_secret_credentials
      run_identity_terraform_phase "destroy"
      ;;
    full)
      sync_entra_entities_to_cloud_identity
      run_identity_terraform_phase "apply"
      run_identity_verification_and_summary
      ;;
  esac

  log_ok "Microsoft Entra ID to Cloud Identity workflow ('${mode}') completed successfully."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_identity_main "$@"
fi
