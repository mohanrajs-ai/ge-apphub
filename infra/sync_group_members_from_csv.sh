#!/usr/bin/env bash
# ==============================================================================
# CSV-Driven Group Membership & Gemini Enterprise License Synchronizer
# ==============================================================================
# Reads a declarative CSV file (`group_email,user_email,role,sync_entra,assign_ge_license`)
# and idempotently synchronizes memberships across:
#   1. Microsoft Entra ID Security Groups (Microsoft Graph API)
#   2. Google Cloud Identity Groups (Cloud Identity Groups API v1)
#   3. Gemini Enterprise UserStore Licenses (Discovery Engine API v1alpha)
#
# Usage:
#   ./sync_group_members_from_csv.sh \
#     --csv ./configs/cymbal-group-memberships.csv \
#     --config ./configs/cymbal-identity.env
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="${SCRIPT_DIR}"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${SCRIPT_DIR}/scripts/lib/http.sh"
# shellcheck source=scripts/configure_identity.sh
source "${SCRIPT_DIR}/scripts/configure_identity.sh"

CSV_FILE="${GROUP_MEMBERSHIPS_CSV:-}"
CONFIG_FILE="${SCRIPT_DIR}/configs/cymbal-identity.env"
SKIP_ENTRA_SYNC="false"
SKIP_LICENSE_ASSIGN="false"

usage() {
  cat <<EOF
Usage: ./sync_group_members_from_csv.sh [OPTIONS]

Options:
  --csv <path>            Path to group memberships CSV file (required or via GROUP_MEMBERSHIPS_CSV)
  --config <path>         Path to Identity .env configuration file (default: ./configs/cymbal-identity.env)
  --skip-entra            Skip Microsoft Entra ID group membership sync (Cloud Identity + GE License only)
  --skip-license          Skip Gemini Enterprise UserStore license assignment
  --dry-run               Print API operations without mutating remote state
  -h, --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --csv)
      CSV_FILE="$2"
      shift 2
      ;;
    --config)
      CONFIG_FILE="$2"
      shift 2
      ;;
    --skip-entra)
      SKIP_ENTRA_SYNC="true"
      shift
      ;;
    --skip-license)
      SKIP_LICENSE_ASSIGN="true"
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
      log_error "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ -f "${CONFIG_FILE}" ]]; then
  load_identity_config "${CONFIG_FILE}"
fi

if [[ -z "${CSV_FILE}" ]]; then
  if [[ -n "${GROUP_MEMBERSHIPS_CSV:-}" && -f "${GROUP_MEMBERSHIPS_CSV}" ]]; then
    CSV_FILE="${GROUP_MEMBERSHIPS_CSV}"
  elif [[ -f "${SCRIPT_DIR}/configs/cymbal-group-memberships.csv" ]]; then
    CSV_FILE="${SCRIPT_DIR}/configs/cymbal-group-memberships.csv"
  elif [[ -f "${SCRIPT_DIR}/configs/group_memberships.csv" ]]; then
    CSV_FILE="${SCRIPT_DIR}/configs/group_memberships.csv"
  fi
fi

if [[ -z "${CSV_FILE}" || ! -f "${CSV_FILE}" ]]; then
  log_error "Group memberships CSV file not found: '${CSV_FILE:-<unspecified>}'"
  exit 1
fi

# Auto-resolve CLOUD_IDENTITY_CUSTOMER_ID if not set
if [[ -z "${CLOUD_IDENTITY_CUSTOMER_ID:-}" && "${DRY_RUN:-false}" != "true" ]]; then
  org_line="$(gcloud organizations list --format="value(name,owner.directoryCustomerId)" 2>/dev/null | head -n 1 || true)"
  if [[ -n "${org_line}" ]]; then
    disc_cust="$(echo "${org_line}" | awk '{print $2}')"
    if [[ -n "${disc_cust}" ]]; then
      export CLOUD_IDENTITY_CUSTOMER_ID="customers/${disc_cust#customers/}"
    fi
  fi
fi
export CLOUD_IDENTITY_CUSTOMER_ID="${CLOUD_IDENTITY_CUSTOMER_ID:-customers/my_customer}"
if [[ "${CLOUD_IDENTITY_CUSTOMER_ID}" != customers/* ]]; then
  export CLOUD_IDENTITY_CUSTOMER_ID="customers/${CLOUD_IDENTITY_CUSTOMER_ID}"
fi

log_phase "CSV-GROUP-SYNC" "Synchronizing Group Memberships & GE Licenses from ${CSV_FILE}"

# 1. Optional Entra ID Preparation
ENTRA_READY="false"
ENTRA_USERS_JSON='{"value":[]}'
ENTRA_GROUPS_JSON='{"value":[]}'
if [[ "${SKIP_ENTRA_SYNC}" != "true" ]]; then
  if ensure_and_load_identity_secret_credentials 2>/dev/null && fetch_microsoft_graph_access_token 2>/dev/null; then
    ENTRA_READY="true"
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
      if _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/users?\$top=999&\$select=id,userPrincipalName,mail"; then
        ENTRA_USERS_JSON="${LAST_GRAPH_BODY}"
      fi
      if _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/groups?\$top=999&\$select=id,displayName,mailNickname,mail"; then
        ENTRA_GROUPS_JSON="${LAST_GRAPH_BODY}"
      fi
    fi
  else
    log_warn "Entra ID credentials not available; proceeding with Google Cloud Identity & GE License sync only."
  fi
fi

# 2. Fetch existing Cloud Identity groups under customer
CI_GROUPS_JSON='{}'
if [[ "${DRY_RUN:-false}" != "true" ]]; then
  CI_GROUPS_JSON="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"
fi

resolve_or_create_ci_group() {
  local group_email="$1"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    printf 'groups/dry-run-%s' "${group_email%@*}"
    return 0
  fi

  local gname lookup_resp
  gname="$(jq -r --arg em "${group_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' <<<"${CI_GROUPS_JSON}" 2>/dev/null | head -n 1 || true)"
  if [[ -z "${gname}" ]]; then
    lookup_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups:lookup?groupKey.id=${group_email}" "" "true" || echo '{}')"
    gname="$(jq -r '.name // empty' <<<"${lookup_resp}" 2>/dev/null || true)"
  fi
  if [[ -z "${gname}" ]]; then
    log_info "Creating Cloud Identity group '${group_email}' under '${CLOUD_IDENTITY_CUSTOMER_ID}'..." >&2
    local create_payload create_resp
    create_payload="$(jq -n \
      --arg parent "${CLOUD_IDENTITY_CUSTOMER_ID}" \
      --arg email "${group_email}" \
      --arg dn "${group_email%@*}" \
      '{
        parent: $parent,
        groupKey: {id: $email},
        displayName: $dn,
        description: ("Managed via CSV Group Sync (" + $email + ")"),
        labels: {
          "cloudidentity.googleapis.com/groups.discussion_forum": "",
          "cloudidentity.googleapis.com/groups.security": ""
        }
      }')"
    create_resp="$(ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/groups?initialGroupConfig=EMPTY" "${create_payload}" "true" || echo '{}')"
    gname="$(jq -r '.response.name // .name // empty' <<<"${create_resp}" 2>/dev/null || true)"
    if [[ "${gname}" != groups/* ]]; then
      lookup_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups:lookup?groupKey.id=${group_email}" "" "true" || echo '{}')"
      gname="$(jq -r '.name // empty' <<<"${lookup_resp}" 2>/dev/null || true)"
    fi
  fi
  printf '%s' "${gname}"
}

LICENSE_USERS_JSON="[]"
CI_ADDED=0
CI_SKIPPED=0
ENTRA_ADDED=0

while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
  line="$(printf '%s' "${raw_line}" | sed 's/\r$//' | xargs)"
  [[ -z "${line}" || "${line}" == \#* ]] && continue
  # Skip header line
  if [[ "$(printf '%s' "${line}" | tr '[:upper:]' '[:lower:]')" == group_email,* ]]; then
    continue
  fi

  IFS=',' read -r raw_group raw_user raw_role raw_sync_entra raw_assign_lic _ <<< "${line}"
  group_email="$(printf '%s' "${raw_group:-}" | xargs | tr '[:upper:]' '[:lower:]')"
  user_email="$(printf '%s' "${raw_user:-}" | xargs | tr '[:upper:]' '[:lower:]')"
  role="$(printf '%s' "${raw_role:-MEMBER}" | xargs | tr '[:lower:]' '[:upper:]')"
  sync_entra="$(printf '%s' "${raw_sync_entra:-true}" | xargs | tr '[:upper:]' '[:lower:]')"
  assign_lic="$(printf '%s' "${raw_assign_lic:-true}" | xargs | tr '[:upper:]' '[:lower:]')"

  [[ -z "${group_email}" || -z "${user_email}" ]] && continue
  [[ -z "${role}" ]] && role="MEMBER"

  if [[ "${group_email}" != *"@"* ]]; then
    group_email="${group_email}@${SHARED_IDENTITY_DOMAIN}"
  fi
  if [[ "${user_email}" != *"@"* ]]; then
    user_email="${user_email}@${SHARED_IDENTITY_DOMAIN}"
  fi

  # 2a. Sync to Microsoft Entra ID Security Group if enabled
  if [[ "${ENTRA_READY}" == "true" && "${sync_entra}" == "true" ]]; then
    group_nick="${group_email%@*}"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] Would add '${user_email}' to Entra ID group '${group_nick}'"
      ENTRA_ADDED=$((ENTRA_ADDED + 1))
    else
      entra_gid="$(jq -r --arg nick "${group_nick}" --arg em "${group_email}" '.value[]? | select(((.mailNickname // "" | ascii_downcase) == ($nick | ascii_downcase)) or ((.mail // "" | ascii_downcase) == ($em | ascii_downcase))) | .id' <<<"${ENTRA_GROUPS_JSON}" 2>/dev/null | head -n 1 || true)"
      entra_uid="$(jq -r --arg u "${user_email}" '.value[]? | select(((.userPrincipalName // "" | ascii_downcase) == ($u | ascii_downcase)) or ((.mail // "" | ascii_downcase) == ($u | ascii_downcase))) | .id' <<<"${ENTRA_USERS_JSON}" 2>/dev/null | head -n 1 || true)"
      if [[ -n "${entra_gid}" && -n "${entra_uid}" ]]; then
        ref_payload="$(jq -n --arg url "https://graph.microsoft.com/v1.0/directoryObjects/${entra_uid}" '{"@odata.id": $url}')"
        # POST $ref returns 204 on add or 400 if object references already exist; ignore 400 duplicate
        curl -sS -o /dev/null -X POST "https://graph.microsoft.com/v1.0/groups/${entra_gid}/members/\$ref" \
          -H "Authorization: Bearer ${MS_GRAPH_ACCESS_TOKEN}" \
          -H "Content-Type: application/json" \
          -d "${ref_payload}" || true
        ENTRA_ADDED=$((ENTRA_ADDED + 1))
      fi
    fi
  fi

  # 2b. Sync to Google Cloud Identity Group
  ci_group_name="$(resolve_or_create_ci_group "${group_email}")"
  if [[ -n "${ci_group_name}" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] Would add '${user_email}' (${role}) to Cloud Identity group '${group_email}' (${ci_group_name})"
      CI_ADDED=$((CI_ADDED + 1))
    else
      mems_json="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${ci_group_name}/memberships" "" "true" || echo '{}')"
      existing_mem="$(jq -r --arg u "${user_email}" '.memberships[]? | select((.preferredMemberKey.id | ascii_downcase) == ($u | ascii_downcase)) | .name' <<<"${mems_json}" 2>/dev/null | head -n 1 || true)"
      if [[ -z "${existing_mem}" ]]; then
        log_info "Adding '${user_email}' (${role}) -> Cloud Identity group '${group_email}' (${ci_group_name})..."
        roles_json='[{"name":"MEMBER"}]'
        if [[ "${role}" == "OWNER" ]]; then
          roles_json='[{"name":"MEMBER"},{"name":"OWNER"}]'
        elif [[ "${role}" == "MANAGER" ]]; then
          roles_json='[{"name":"MEMBER"},{"name":"MANAGER"}]'
        fi
        mem_payload="$(jq -n --arg email "${user_email}" --argjson roles "${roles_json}" '{preferredMemberKey: {id: $email}, roles: $roles}')"
        if ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/${ci_group_name}/memberships" "${mem_payload}" "true" >/dev/null; then
          CI_ADDED=$((CI_ADDED + 1))
        else
          log_warn "Could not add '${user_email}' to '${group_email}' (ensure user exists in Cloud Identity)."
        fi
      else
        CI_SKIPPED=$((CI_SKIPPED + 1))
      fi
    fi
  fi

  # 2c. Queue user for Gemini Enterprise License Assignment
  if [[ "${assign_lic}" == "true" ]]; then
    LICENSE_USERS_JSON="$(jq -c --arg u "${user_email}" '. + [$u] | unique' <<<"${LICENSE_USERS_JSON}")"
  fi
done < "${CSV_FILE}"

log_ok "Group Membership Sync Complete (CloudIdentity Added=${CI_ADDED}, AlreadyMember=${CI_SKIPPED}, Entra Checked/Added=${ENTRA_ADDED})."

# 3. Assign Gemini Enterprise Licenses in UserStore
if [[ "${SKIP_LICENSE_ASSIGN}" != "true" && -n "${GCP_PROJECT_ID:-}" ]]; then
  lic_user_count="$(jq 'length' <<<"${LICENSE_USERS_JSON}")"
  if [[ "${lic_user_count}" -gt 0 ]]; then
    base_v1alpha="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")"
    parent="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}"
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] Would assign Gemini Enterprise licenses to ${lic_user_count} user(s) in '${GCP_PROJECT_ID}'"
    else
      lc_list="$(ge_curl_request "GET" "${base_v1alpha}/${parent}/licenseConfigs" "" "true" || echo '{}')"
      active_lc="$(jq -r '.licenseConfigs[]? | select(.state == "ACTIVE") | .name' <<<"${lc_list}" 2>/dev/null | head -n 1 || true)"
      if [[ -n "${active_lc}" ]]; then
        log_info "Assigning Gemini Enterprise license ('${active_lc}') to ${lic_user_count} user(s) from CSV..."
        batch_payload="$(jq -n --arg lc "${active_lc}" --argjson users "${LICENSE_USERS_JSON}" '{
          inlineSource: {
            userLicenses: [
              $users[] | {
                userPrincipal: .,
                licenseAssignmentState: "ASSIGNED",
                licenseConfig: $lc
              }
            ],
            updateMask: "licenseAssignmentState,licenseConfig"
          }
        }')"
        ge_curl_request "POST" "${base_v1alpha}/${parent}/userStores/default_user_store:batchUpdateUserLicenses" "${batch_payload}" "true" >/dev/null || true
        log_ok "Assigned Gemini Enterprise licenses to ${lic_user_count} user(s) in '${GCP_PROJECT_ID}'."
      else
        log_warn "No ACTIVE LicenseConfig found in '${GCP_PROJECT_ID}'; skipping user license assignment."
      fi
    fi
  fi
fi
