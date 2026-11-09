#!/usr/bin/env bash
# ==============================================================================
# Google Cloud Identity Directory Sync Orchestrator (deploy_gcp_directory_sync.sh)
# ==============================================================================
# Automates GCP Directory Sync configuration, readiness validation, Day-0 group
# shell reconciliation, Per-App Cloud Identity group mapping generation, and
# Gemini Enterprise UserStore license synchronization directly from
# Directory-Synced Cloud Identity groups (zero ad-hoc CSV or Terraform user state).
#
# Key Responsibilities:
#   1. Resolves Entra ID OAuth 2.0 credentials from GCP Secret Manager
#      (`projects/<project>/secrets/<customer>-m365-connector-credentials`)
#   2. Validates Microsoft Graph Application permissions required by
#      Google Cloud Identity Directory Sync:
#        - User.Read.All
#        - Group.Read.All
#        - GroupMember.Read.All
#        - Directory.Read.All
#        - AdministrativeUnit.Read.All
#   3. Generates the declarative GCP Directory Sync Connector Specification
#      (`configs/<customer>-gcp-directory-sync.json`) and optionally activates
#      the Microsoft Entra Outbound SCIM 2.0 Provisioning Job
#      (`--enable-entra-scim-job`)
#   4. Reconciles Directory-Synced Cloud Identity groups (`ge-service-desk-users`,
#      `ge-finance-users`, `ge-hr-users`, `ge-skill-developers`, `all-ge-apps-users`)
#      and generates `terraform-identity/identity_entities.auto.tfvars.json`
#      with `synced_groups: {}` so GCP Directory Sync owns User & Group
#      lifecycle while Terraform only manages Per-App Group Nesting & DNS/SSO
#   5. Synchronizes Gemini Enterprise UserStore licenses (`batchUpdateUserLicenses`)
#      directly from the live memberships of Directory-Synced Cloud Identity groups
#
# Usage:
#   ./deploy_gcp_directory_sync.sh \
#     --config ./configs/cymbal-identity.env \
#     [--manifest-out ./configs/cymbal-gcp-directory-sync.json] \
#     [--enable-entra-scim-job] \
#     [--skip-licenses] \
#     [--verify-only] \
#     [--dry-run]
# ==============================================================================

set -euo pipefail

DEPLOY_DIR_SYNC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="${DEPLOY_DIR_SYNC_ROOT}"

# shellcheck source=scripts/lib/common.sh
source "${DEPLOY_DIR_SYNC_ROOT}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${DEPLOY_DIR_SYNC_ROOT}/scripts/lib/http.sh"
# shellcheck source=scripts/preflight.sh
source "${DEPLOY_DIR_SYNC_ROOT}/scripts/preflight.sh"
# shellcheck source=scripts/configure_identity.sh
source "${DEPLOY_DIR_SYNC_ROOT}/scripts/configure_identity.sh"

print_directory_sync_usage() {
  cat <<'EOF'
Usage: ./deploy_gcp_directory_sync.sh [OPTIONS]

Automated configurator & verifier for Google Cloud Identity Directory Sync with Microsoft Entra ID.

Options:
  --config <path>            Path to Identity configuration file (default: ./configs/identity.env)
  --manifest-out <path>      Output path for GCP Directory Sync JSON specification
  --enable-entra-scim-job    Also configure & start Microsoft Entra SCIM 2.0 Synchronization Job
  --skip-licenses            Skip automatic Gemini Enterprise UserStore license sync from synced groups
  --verify-only              Only verify Directory Sync readiness, synced groups, and SAML/ACL state
  --dry-run                  Preview all Directory Sync operations without mutating remote state
  --help, -h                 Show this help message and exit
EOF
}

deploy_gcp_directory_sync_main() {
  local config_file="${DEPLOY_DIR_SYNC_ROOT}/configs/identity.env"
  export DRY_RUN="false"
  export IDENTITY_SYNC_MODE_OVERRIDE="GCP_DIRECTORY_SYNC"
  local manifest_override=""
  local enable_scim_override=""
  local skip_licenses="false"
  local mode="full"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        config_file="$2"
        shift 2
        ;;
      --manifest-out)
        manifest_override="$2"
        shift 2
        ;;
      --enable-entra-scim-job)
        enable_scim_override="true"
        shift
        ;;
      --skip-licenses)
        skip_licenses="true"
        shift
        ;;
      --verify-only)
        mode="verify-only"
        shift
        ;;
      --dry-run)
        export DRY_RUN="true"
        shift
        ;;
      --help|-h)
        print_directory_sync_usage
        return 0
        ;;
      *)
        log_error "Unknown option: $1"
        print_directory_sync_usage
        return 1
        ;;
    esac
  done

  init_logging "${DEPLOY_DIR_SYNC_ROOT}/logs"
  load_identity_config "${config_file}"

  if [[ -n "${manifest_override}" ]]; then
    export GCP_DIRECTORY_SYNC_MANIFEST_OUT="${manifest_override}"
  elif [[ -z "${GCP_DIRECTORY_SYNC_MANIFEST_OUT:-}" ]]; then
    local base_cfg
    base_cfg="$(basename "${config_file}" .env)"
    base_cfg="${base_cfg%-identity}"
    export GCP_DIRECTORY_SYNC_MANIFEST_OUT="${DEPLOY_DIR_SYNC_ROOT}/configs/${base_cfg}-gcp-directory-sync.json"
  fi

  if [[ -n "${enable_scim_override}" ]]; then
    export ENABLE_ENTRA_SCIM_PROVISIONING_JOB="${enable_scim_override}"
  fi
  if [[ "${skip_licenses}" == "true" ]]; then
    export AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS="false"
  fi

  log_phase "PRE-FLIGHT" "Validating CLI dependencies, GCP Directory Sync config, and authentication"
  check_cli_dependencies
  validate_identity_config
  check_gcloud_auth
  ensure_and_load_identity_secret_credentials
  fetch_microsoft_graph_access_token

  if [[ "${mode}" == "verify-only" ]]; then
    configure_gcp_directory_sync_connector
    run_identity_verification_and_summary
    return 0
  fi

  bulk_update_entra_upn_domain
  provision_clean_entra_app_groups
  configure_gcp_directory_sync_connector
  reconcile_directory_synced_groups
  sync_ge_licenses_from_directory_sync
  run_identity_verification_and_summary

  log_ok "Google Cloud Identity Directory Sync configuration & group reconciliation completed."
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_gcp_directory_sync_main "$@"
fi
