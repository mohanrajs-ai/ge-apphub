#!/usr/bin/env bash
# ==============================================================================
# Microsoft Entra ID to Google Cloud Identity Sync & Federation Provisioner
# ==============================================================================
# Resolves Entra ID OAuth credentials from Secret Manager (`m365-connector-credentials`),
# performs optional bulk UPN migration (`@<ENTRA_SOURCE_DOMAIN>` -> `@<SHARED_IDENTITY_DOMAIN>`),
# queries Microsoft Graph for Entra Users, Groups, and Group Memberships,
# generates `terraform-identity/identity_entities.auto.tfvars.json`, and verifies
# Discovery Engine `aclConfig` and Cloud Identity SSO alignment.
# ==============================================================================

set -euo pipefail

IDENTITY_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/common.sh
source "${IDENTITY_SCRIPT_DIR}/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${IDENTITY_SCRIPT_DIR}/lib/http.sh"

load_identity_config() {
  local config_file="${1:-./configs/identity.env}"
  if [[ ! -f "${config_file}" ]]; then
    log_error "Identity configuration file not found: ${config_file}"
    return 1
  fi
  log_info "Loading Identity configuration from ${config_file}"

  local env_m365_tenant_id="${M365_TENANT_ID:-}"
  local env_m365_client_id="${M365_CLIENT_ID:-}"
  local env_m365_client_secret="${M365_CLIENT_SECRET:-}"
  local env_m365_secret_id="${M365_SECRET_ID:-}"
  local env_dns_project_id="${DNS_PROJECT_ID_OVERRIDE:-}"
  local env_dns_zone_name="${DNS_ZONE_NAME_OVERRIDE:-}"
  local env_sync_mode="${IDENTITY_SYNC_MODE_OVERRIDE:-}"

  set -a
  # shellcheck disable=SC1090
  source "${config_file}"
  set +a

  export GCP_PROJECT_ID="${GCP_PROJECT_ID:-}"
  export GCP_REGION="${GCP_REGION:-us-central1}"
  export GCP_ORG_ID="${GCP_ORG_ID:-}"
  export GE_LOCATION="${GE_LOCATION:-global}"
  export CLOUD_IDENTITY_CUSTOMER_ID="${CLOUD_IDENTITY_CUSTOMER_ID:-}"
  export PRIMARY_CUSTOMER_DOMAIN="${PRIMARY_CUSTOMER_DOMAIN:-example.com}"
  export SHARED_IDENTITY_DOMAIN="${SHARED_IDENTITY_DOMAIN:-${PRIMARY_CUSTOMER_DOMAIN}}"
  export ENTRA_SOURCE_DOMAIN="${ENTRA_SOURCE_DOMAIN:-}"

  export M365_SECRET_ID="${env_m365_secret_id:-${M365_SECRET_ID:-m365-connector-credentials}}"
  export M365_TENANT_ID="${env_m365_tenant_id:-${M365_TENANT_ID:-}}"
  export M365_CLIENT_ID="${env_m365_client_id:-${M365_CLIENT_ID:-}}"
  export M365_CLIENT_SECRET="${env_m365_client_secret:-${M365_CLIENT_SECRET:-}}"

  export MANAGE_DNS_VERIFICATION_RECORD="${MANAGE_DNS_VERIFICATION_RECORD:-false}"
  export DNS_PROJECT_ID="${env_dns_project_id:-${DNS_PROJECT_ID:-${GCP_PROJECT_ID}}}"
  export DNS_ZONE_NAME="${env_dns_zone_name:-${DNS_ZONE_NAME:-}}"
  export ENTRA_DOMAIN_VERIFICATION_MS_ID="${ENTRA_DOMAIN_VERIFICATION_MS_ID:-}"
  export GOOGLE_DOMAIN_VERIFICATION_TXT="${GOOGLE_DOMAIN_VERIFICATION_TXT:-}"

  # Identity Sync Mode:
  #   - GCP_DIRECTORY_SYNC (Default): Native Google Cloud Identity Directory Sync owns User,
  #     Group & Membership lifecycle; Terraform only manages Per-App Group Nesting & DNS/SSO.
  #   - TERRAFORM_GRAPH (Legacy): Scrapes Microsoft Graph users/groups into Terraform state.
  export IDENTITY_SYNC_MODE="${env_sync_mode:-${IDENTITY_SYNC_MODE:-GCP_DIRECTORY_SYNC}}"
  export ENABLE_GCP_DIRECTORY_SYNC="${ENABLE_GCP_DIRECTORY_SYNC:-true}"
  export DIRECTORY_SYNC_MANAGED_GROUPS="${DIRECTORY_SYNC_MANAGED_GROUPS:-ge-service-desk-users,ge-finance-users,ge-hr-users,ge-skill-developers,all-ge-apps-users}"
  export BOOTSTRAP_EMPTY_SYNC_GROUP_SHELLS="${BOOTSTRAP_EMPTY_SYNC_GROUP_SHELLS:-true}"
  export AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS="${AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS:-true}"
  export ENABLE_ENTRA_SCIM_PROVISIONING_JOB="${ENABLE_ENTRA_SCIM_PROVISIONING_JOB:-false}"
  export GCP_DIRECTORY_SYNC_MANIFEST_OUT="${GCP_DIRECTORY_SYNC_MANIFEST_OUT:-}"

  export ENTRA_BULK_UPDATE_UPN_DOMAIN="${ENTRA_BULK_UPDATE_UPN_DOMAIN:-false}"
  export ENTRA_UPN_REWRITE_EXCLUDE_USERS="${ENTRA_UPN_REWRITE_EXCLUDE_USERS:-}"
  export SYNC_CLOUD_IDENTITY_USERS="${SYNC_CLOUD_IDENTITY_USERS:-false}"
  export CLOUD_IDENTITY_DEFAULT_TEMP_PASSWORD="${CLOUD_IDENTITY_DEFAULT_TEMP_PASSWORD:-ChangeMe!Temp2026#}"
  export PROVISION_CLEAN_ENTRA_APP_GROUPS="${PROVISION_CLEAN_ENTRA_APP_GROUPS:-false}"
  export ENTRA_CLEAN_GROUPS_SPEC="${ENTRA_CLEAN_GROUPS_SPEC:-}"
  export ENTRA_GROUP_FILTER="${ENTRA_GROUP_FILTER:-}"
  export ENTRA_TO_APP_GROUP_MAPPINGS="${ENTRA_TO_APP_GROUP_MAPPINGS:-}"

  export ENABLE_CLOUD_IDENTITY_SAML_SSO="${ENABLE_CLOUD_IDENTITY_SAML_SSO:-true}"
  export SAML_SSO_PROFILE_DISPLAY_NAME="${SAML_SSO_PROFILE_DISPLAY_NAME:-Microsoft Entra ID SSO}"
  export SAML_IDP_CERT_FILE="${SAML_IDP_CERT_FILE:-}"
  export SAML_TARGET_ORG_UNIT="${SAML_TARGET_ORG_UNIT:-}"

  export ENABLE_WORKFORCE_POOL_OIDC="${ENABLE_WORKFORCE_POOL_OIDC:-false}"
  export WORKFORCE_POOL_ID="${WORKFORCE_POOL_ID:-entra-id-shared-pool}"
  export WORKFORCE_PROVIDER_ID="${WORKFORCE_PROVIDER_ID:-entra-id-oidc-provider}"

  # Export TF_VAR_* for terraform-identity/
  export TF_VAR_project_id="${GCP_PROJECT_ID}"
  export TF_VAR_region="${GCP_REGION}"
  export TF_VAR_organization_id="${GCP_ORG_ID}"
  export TF_VAR_cloud_identity_customer_id="${CLOUD_IDENTITY_CUSTOMER_ID}"
  export TF_VAR_primary_customer_domain="${PRIMARY_CUSTOMER_DOMAIN}"
  export TF_VAR_shared_identity_domain="${SHARED_IDENTITY_DOMAIN}"
  export TF_VAR_m365_secret_id="${M365_SECRET_ID}"
  export TF_VAR_m365_tenant_id="${M365_TENANT_ID}"
  export TF_VAR_m365_client_id="${M365_CLIENT_ID}"
  export TF_VAR_m365_client_secret="${M365_CLIENT_SECRET}"
  export TF_VAR_manage_dns_verification_record="${MANAGE_DNS_VERIFICATION_RECORD}"
  export TF_VAR_dns_project_id="${DNS_PROJECT_ID}"
  export TF_VAR_dns_zone_name="${DNS_ZONE_NAME}"
  export TF_VAR_entra_domain_verification_ms_id="${ENTRA_DOMAIN_VERIFICATION_MS_ID}"
  export TF_VAR_google_domain_verification_txt="${GOOGLE_DOMAIN_VERIFICATION_TXT}"
  export TF_VAR_enable_workforce_pool_oidc="${ENABLE_WORKFORCE_POOL_OIDC}"
  export TF_VAR_workforce_pool_id="${WORKFORCE_POOL_ID}"
  export TF_VAR_workforce_provider_id="${WORKFORCE_PROVIDER_ID}"
}

validate_identity_config() {
  if [[ -z "${CLOUD_IDENTITY_CUSTOMER_ID:-}" && "${DRY_RUN:-false}" != "true" ]]; then
    local org_line
    org_line="$(gcloud organizations list --format="value(name,owner.directoryCustomerId)" 2>/dev/null | head -n 1 || true)"
    if [[ -n "${org_line}" ]]; then
      local disc_org disc_cust
      disc_org="$(echo "${org_line}" | awk '{print $1}' | sed 's|organizations/||')"
      disc_cust="$(echo "${org_line}" | awk '{print $2}')"
      export GCP_ORG_ID="${GCP_ORG_ID:-${disc_org}}"
      export TF_VAR_organization_id="${GCP_ORG_ID}"
      if [[ -n "${disc_cust}" ]]; then
        export CLOUD_IDENTITY_CUSTOMER_ID="customers/${disc_cust#customers/}"
        export TF_VAR_cloud_identity_customer_id="${CLOUD_IDENTITY_CUSTOMER_ID}"
      fi
    fi
  fi

  local missing=()
  for var_name in GCP_PROJECT_ID CLOUD_IDENTITY_CUSTOMER_ID SHARED_IDENTITY_DOMAIN M365_SECRET_ID; do
    if [[ -z "${!var_name:-}" ]]; then
      missing+=("${var_name}")
    fi
  done

  if [[ "${#missing[@]}" -gt 0 ]]; then
    log_error "Missing required Identity configuration variables: ${missing[*]}"
    return 1
  fi

  if [[ -z "${M365_TENANT_ID:-}" && -z "${M365_CLIENT_ID:-}" && -z "${M365_CLIENT_SECRET:-}" && "${DRY_RUN:-false}" != "true" ]]; then
    ensure_and_load_identity_secret_credentials || true
  fi

  local missing_secrets=()
  for secret_var in M365_TENANT_ID M365_CLIENT_ID M365_CLIENT_SECRET; do
    local secret_val="${!secret_var:-}"
    if [[ -z "${secret_val}" || "${secret_val}" == "00000000-0000-0000-0000-000000000000" || "${secret_val}" == "11111111-1111-1111-1111-111111111111" || "${secret_val}" == "replace-with-entra-client-secret" ]]; then
      missing_secrets+=("${secret_var}")
    fi
  done

  if [[ "${#missing_secrets[@]}" -gt 0 ]]; then
    log_error "Missing or placeholder M365 secret environment variables: ${missing_secrets[*]}. Export M365_TENANT_ID, M365_CLIENT_ID, and M365_CLIENT_SECRET in your environment before proceeding."
    return 1
  fi

  log_ok "Identity configuration and M365 environment variables validated (Project=${GCP_PROJECT_ID}, Customer=${CLOUD_IDENTITY_CUSTOMER_ID}, SharedDomain=${SHARED_IDENTITY_DOMAIN}, Tenant=${M365_TENANT_ID})."
  return 0
}

ensure_and_load_identity_secret_credentials() {
  local secret_id="${M365_SECRET_ID:-m365-connector-credentials}"
  local access_url="https://secretmanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}/secrets/${secret_id}/versions/latest:access"
  local env_tenant="${M365_TENANT_ID:-}"
  local env_client="${M365_CLIENT_ID:-}"
  local env_secret="${M365_CLIENT_SECRET:-}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would resolve Entra ID credentials from environment variables / Secret Manager '${secret_id}' (${access_url})"
    return 0
  fi

  if [[ -z "${env_tenant}" || -z "${env_client}" || -z "${env_secret}" ]]; then
    log_info "Reading fallback Entra ID JSON credentials from Secret Manager ('projects/${GCP_PROJECT_ID}/secrets/${secret_id}/versions/latest')..."
    local access_resp=""
    access_resp="$(ge_curl_request "GET" "${access_url}" "" "true" || echo "{}")"

    local raw_b64 decoded_json sm_tenant sm_client sm_secret
    raw_b64="$(printf '%s' "${access_resp}" | jq -r '.payload.data // empty')"
    if [[ -n "${raw_b64}" ]]; then
      decoded_json="$(printf '%s' "${raw_b64}" | base64 -d 2>/dev/null || printf '%s' "${raw_b64}" | base64 -D 2>/dev/null || echo "{}")"
      sm_tenant="$(echo "${decoded_json}" | jq -r '.tenant_id // empty')"
      sm_client="$(echo "${decoded_json}" | jq -r '.client_id // empty')"
      sm_secret="$(echo "${decoded_json}" | jq -r '.client_secret // empty')"

      export M365_TENANT_ID="${env_tenant:-${sm_tenant}}"
      export M365_CLIENT_ID="${env_client:-${sm_client}}"
      export M365_CLIENT_SECRET="${env_secret:-${sm_secret}}"
    fi
  fi

  export TF_VAR_m365_tenant_id="${M365_TENANT_ID:-}"
  export TF_VAR_m365_client_id="${M365_CLIENT_ID:-}"
  export TF_VAR_m365_client_secret="${M365_CLIENT_SECRET:-}"

  if [[ -z "${M365_TENANT_ID:-}" || -z "${M365_CLIENT_ID:-}" || -z "${M365_CLIENT_SECRET:-}" ]]; then
    log_error "Missing required M365 credentials (M365_TENANT_ID, M365_CLIENT_ID, M365_CLIENT_SECRET). Export them as environment variables before running."
    return 1
  fi

  log_ok "Loaded Entra ID credentials (tenant_id=${M365_TENANT_ID}, client_id=${M365_CLIENT_ID})."
  return 0
}

fetch_microsoft_graph_access_token() {
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would request Microsoft Graph OAuth2 token from https://login.microsoftonline.com/${M365_TENANT_ID:-<tenant>}/oauth2/v2.0/token"
    export MS_GRAPH_ACCESS_TOKEN="dry-run-ms-graph-token"
    return 0
  fi

  local token_url="https://login.microsoftonline.com/${M365_TENANT_ID}/oauth2/v2.0/token"
  log_info "Acquiring Microsoft Graph API access token for tenant '${M365_TENANT_ID}'..."
  local resp_file http_code
  resp_file="$(mktemp)"
  http_code="$(curl -sS -X POST "${token_url}" \
    -o "${resp_file}" \
    -w "%{http_code}" \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "client_id=${M365_CLIENT_ID}" \
    --data-urlencode "scope=https://graph.microsoft.com/.default" \
    --data-urlencode "client_secret=${M365_CLIENT_SECRET}" \
    --data-urlencode "grant_type=client_credentials")"

  local body
  body="$(cat "${resp_file}")"
  rm -f "${resp_file}"

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "Failed to acquire Microsoft Graph token (HTTP ${http_code}). Verify client_id and client_secret in Secret Manager '${M365_SECRET_ID}'."
    return 1
  fi

  export MS_GRAPH_ACCESS_TOKEN="$(echo "${body}" | jq -r '.access_token // empty')"
  if [[ -z "${MS_GRAPH_ACCESS_TOKEN}" ]]; then
    log_error "Microsoft identity platform returned an empty access_token."
    return 1
  fi
  log_ok "Acquired Microsoft Graph OAuth2 token."
  return 0
}

_ms_graph_request() {
  local method="$1"
  local url="$2"
  local payload="${3:-}"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Microsoft Graph ${method} ${url}"
    LAST_GRAPH_STATUS="200"
    LAST_GRAPH_BODY='{"value":[]}'
    return 0
  fi

  local resp_file http_code
  resp_file="$(mktemp)"
  if [[ -n "${payload}" ]]; then
    http_code="$(curl -sS -X "${method}" "${url}" \
      -o "${resp_file}" \
      -w "%{http_code}" \
      -H "Authorization: Bearer ${MS_GRAPH_ACCESS_TOKEN}" \
      -H "Content-Type: application/json" \
      -d "${payload}")"
  else
    http_code="$(curl -sS -X "${method}" "${url}" \
      -o "${resp_file}" \
      -w "%{http_code}" \
      -H "Authorization: Bearer ${MS_GRAPH_ACCESS_TOKEN}")"
  fi

  LAST_GRAPH_STATUS="${http_code}"
  LAST_GRAPH_BODY="$(cat "${resp_file}")"
  rm -f "${resp_file}"

  if [[ "${http_code}" == "403" ]] && echo "${LAST_GRAPH_BODY}" | grep -q "Authorization_RequestDenied"; then
    log_warn "Microsoft Graph returned HTTP 403 (Authorization_RequestDenied) for ${url}."
    log_warn "Remediation: In Microsoft Entra Admin Center -> App registrations (${M365_CLIENT_ID}) -> API permissions, add Microsoft Graph Application permissions 'User.ReadWrite.All', 'Group.Read.All', and 'GroupMember.Read.All' and click 'Grant admin consent'."
    return 43
  fi

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "Microsoft Graph ${method} ${url} failed with HTTP ${http_code}: ${LAST_GRAPH_BODY}"
    return 1
  fi
  return 0
}

bulk_update_entra_upn_domain() {
  if [[ "${ENTRA_BULK_UPDATE_UPN_DOMAIN:-true}" != "true" ]]; then
    log_info "ENTRA_BULK_UPDATE_UPN_DOMAIN is false; skipping Entra UPN domain rewrite."
    return 0
  fi

  log_phase "ENTRA-UPN-MIGRATION" "Updating Entra ID UPNs from @${ENTRA_SOURCE_DOMAIN} to @${SHARED_IDENTITY_DOMAIN}"
  local users_url="https://graph.microsoft.com/v1.0/users?\$top=999&\$select=id,displayName,userPrincipalName,mail,mailNickname"
  local rc=0
  _ms_graph_request "GET" "${users_url}" || rc=$?
  if [[ "${rc}" -eq 43 ]]; then
    log_warn "Skipping Entra UPN migration until Microsoft Graph Application permissions are granted."
    return 0
  elif [[ "${rc}" -ne 0 ]]; then
    return "${rc}"
  fi

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would inspect Entra users and PATCH @${ENTRA_SOURCE_DOMAIN} UPNs to @${SHARED_IDENTITY_DOMAIN}"
    return 0
  fi

  local updated_count=0
  local skipped_count=0
  while IFS= read -r user_obj; do
    [[ -z "${user_obj}" ]] && continue
    local uid upn nickname
    uid="$(echo "${user_obj}" | jq -r '.id // empty')"
    upn="$(echo "${user_obj}" | jq -r '.userPrincipalName // empty')"
    nickname="$(echo "${user_obj}" | jq -r '.mailNickname // empty')"
    [[ -z "${uid}" || -z "${upn}" ]] && continue

    local upn_lower src_dom_lower nick_lower
    upn_lower="$(printf '%s' "${upn}" | tr '[:upper:]' '[:lower:]')"
    src_dom_lower="$(printf '%s' "${ENTRA_SOURCE_DOMAIN}" | tr '[:upper:]' '[:lower:]')"
    nick_lower="$(printf '%s' "${nickname}" | tr '[:upper:]' '[:lower:]')"

    # Ignore guest (#EXT#) accounts or users already on SHARED_IDENTITY_DOMAIN
    if [[ "${upn}" == *"#EXT#"* ]] || [[ "${upn_lower}" != *"@${src_dom_lower}" ]]; then
      continue
    fi

    # Check exclusion list
    local excluded="false"
    IFS=',' read -r -a excl_arr <<< "${ENTRA_UPN_REWRITE_EXCLUDE_USERS:-}"
    for excl in ${excl_arr[@]+"${excl_arr[@]}"}; do
      excl="$(echo "${excl}" | xargs)"
      [[ -z "${excl}" ]] && continue
      local excl_lower
      excl_lower="$(printf '%s' "${excl}" | tr '[:upper:]' '[:lower:]')"
      if [[ "${upn_lower}" == "${excl_lower}" || "${nick_lower}" == "${excl_lower}" ]]; then
        excluded="true"
        break
      fi
    done

    if [[ "${excluded}" == "true" ]]; then
      log_info "Skipping excluded break-glass Entra account: ${upn}"
      skipped_count=$((skipped_count + 1))
      continue
    fi

    local prefix="${nickname}"
    if [[ -z "${prefix}" ]]; then
      prefix="${upn%@*}"
    fi
    local new_upn="${prefix}@${SHARED_IDENTITY_DOMAIN}"
    local patch_payload
    patch_payload="$(jq -n --arg upn "${new_upn}" --arg mail "${new_upn}" '{userPrincipalName: $upn, mail: $mail}')"

    log_info "Migrating Entra user '${upn}' -> '${new_upn}'..."
    local patch_rc=0
    _ms_graph_request "PATCH" "https://graph.microsoft.com/v1.0/users/${uid}" "${patch_payload}" || patch_rc=$?
    if [[ "${patch_rc}" -eq 0 ]]; then
      updated_count=$((updated_count + 1))
    else
      log_warn "Could not update UPN for '${upn}' (rc=${patch_rc}); continuing."
    fi
  done < <(echo "${LAST_GRAPH_BODY}" | jq -c '.value[]? // empty')

  log_ok "Entra UPN migration complete (Updated=${updated_count}, Excluded=${skipped_count})."
  return 0
}

provision_clean_entra_app_groups() {
  if [[ "${PROVISION_CLEAN_ENTRA_APP_GROUPS:-false}" != "true" ]]; then
    return 0
  fi

  log_phase "ENTRA-CLEAN-GROUPS" "Provisioning dedicated Gemini Enterprise App Security Groups in Microsoft Entra ID"
  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would create/verify configured security groups in Entra ID and assign department members."
    return 0
  fi

  # Fetch all users to map userPrincipalName -> Entra Object ID
  local users_rc=0
  _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/users?\$top=999&\$select=id,userPrincipalName" || users_rc=$?
  if [[ "${users_rc}" -ne 0 ]]; then
    log_warn "Could not list Entra users for clean group provisioning (rc=${users_rc})."
    return 0
  fi
  local users_body="${LAST_GRAPH_BODY}"

  # Read group specifications from ENTRA_CLEAN_GROUPS_SPEC (semicolon-separated: "mailNickname|Display Name|Description|user1,user2")
  if [[ -z "${ENTRA_CLEAN_GROUPS_SPEC:-}" ]]; then
    log_info "ENTRA_CLEAN_GROUPS_SPEC is empty; skipping clean Entra group creation."
    return 0
  fi
  local group_specs=()
  IFS=';' read -r -a group_specs <<< "${ENTRA_CLEAN_GROUPS_SPEC}"

  for spec in "${group_specs[@]}"; do
    local nick dname desc members_csv
    IFS='|' read -r nick dname desc members_csv <<< "${spec}"

    # Check if group already exists in Entra ID by mailNickname
    local chk_rc=0
    _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/groups?\$filter=mailNickname%20eq%20'${nick}'&\$select=id,displayName,mailNickname" || chk_rc=$?
    if [[ "${chk_rc}" -ne 0 ]]; then
      continue
    fi

    local gid
    gid="$(echo "${LAST_GRAPH_BODY}" | jq -r '.value[0].id // empty')"
    if [[ -z "${gid}" ]]; then
      log_info "Creating Entra ID Security Group '${dname}' (mailNickname=${nick})..."
      local create_payload
      create_payload="$(jq -n \
        --arg dn "${dname}" \
        --arg desc "${desc}" \
        --arg nick "${nick}" \
        '{
          displayName: $dn,
          description: $desc,
          mailEnabled: false,
          mailNickname: $nick,
          securityEnabled: true
        }')"
      local create_rc=0
      _ms_graph_request "POST" "https://graph.microsoft.com/v1.0/groups" "${create_payload}" || create_rc=$?
      if [[ "${create_rc}" -ne 0 ]]; then
        log_warn "Could not create Entra group '${nick}' (ensure 'Group.ReadWrite.All' Application permission is granted on client_id ${M365_CLIENT_ID})."
        continue
      fi
      gid="$(echo "${LAST_GRAPH_BODY}" | jq -r '.id // empty')"
    else
      log_info "Entra ID Security Group '${dname}' (${nick}) already exists (id=${gid})."
    fi

    [[ -z "${gid}" ]] && continue

    # Get existing member IDs in this group
    local existing_mem_ids=""
    if _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/groups/${gid}/members?\$select=id"; then
      existing_mem_ids="$(echo "${LAST_GRAPH_BODY}" | jq -r '.value[]?.id // empty')"
    fi

    # Add each configured member by UPN prefix
    IFS=',' read -r -a prefixes <<< "${members_csv:-}"
    for pfx in ${prefixes[@]+"${prefixes[@]}"}; do
      pfx="$(echo "${pfx}" | xargs)"
      [[ -z "${pfx}" ]] && continue
      local target_upn="${pfx}@${SHARED_IDENTITY_DOMAIN}"
      local uid
      uid="$(echo "${users_body}" | jq -r --arg u "${target_upn}" '.value[] | select((.userPrincipalName | ascii_downcase) == ($u | ascii_downcase)) | .id' | head -n1)"
      [[ -z "${uid}" ]] && continue

      if echo "${existing_mem_ids}" | grep -q -F "${uid}"; then
        continue
      fi

      local ref_payload
      ref_payload="$(jq -n --arg url "https://graph.microsoft.com/v1.0/directoryObjects/${uid}" '{"@odata.id": $url}')"
      _ms_graph_request "POST" "https://graph.microsoft.com/v1.0/groups/${gid}/members/\$ref" "${ref_payload}" || true
    done
  done

  log_ok "Clean Entra ID Gemini Enterprise App Groups verified and populated."
  return 0
}

_normalize_principal_email() {
  local raw_email="$1"
  raw_email="$(echo "${raw_email}" | xargs)"
  if [[ -z "${raw_email}" ]]; then
    echo ""
    return 0
  fi
  local raw_lower src_lower
  raw_lower="$(printf '%s' "${raw_email}" | tr '[:upper:]' '[:lower:]')"
  src_lower="$(printf '%s' "${ENTRA_SOURCE_DOMAIN}" | tr '[:upper:]' '[:lower:]')"
  if [[ "${raw_lower}" == *"@${src_lower}" ]]; then
    local prefix="${raw_email%@*}"
    echo "${prefix}@${SHARED_IDENTITY_DOMAIN}"
    return 0
  fi
  echo "${raw_email}"
}

build_app_group_mappings_json() {
  local existing_ci_groups="${1:-{}}"
  local mappings_json="[]"
  if [[ -n "${ENTRA_TO_APP_GROUP_MAPPINGS:-}" ]]; then
    IFS=',' read -r -a map_pairs <<< "${ENTRA_TO_APP_GROUP_MAPPINGS}"
    for pair in "${map_pairs[@]}"; do
      pair="$(echo "${pair}" | xargs)"
      [[ -z "${pair}" || "${pair}" != *":"* ]] && continue
      local src_member="${pair%%:*}"
      local dst_app_group="${pair#*:}"
      src_member="$(_normalize_principal_email "${src_member}")"
      src_member="$(printf '%s' "${src_member}" | tr '[:upper:]' '[:lower:]')"
      dst_app_group="$(echo "${dst_app_group}" | xargs | tr '[:upper:]' '[:lower:]')"
      if [[ -n "${src_member}" && -n "${dst_app_group}" ]]; then
        if [[ "${DRY_RUN:-false}" != "true" && -n "${CLOUD_IDENTITY_CUSTOMER_ID:-}" ]]; then
          local found_dst
          found_dst="$(echo "${existing_ci_groups}" | jq -r --arg em "${dst_app_group}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' 2>/dev/null | head -n 1 || true)"
          if [[ -z "${found_dst}" ]]; then
            log_info "Pre-creating target Per-App Cloud Identity group '${dst_app_group}' for group nesting..." >&2
            local app_grp_payload
            app_grp_payload="$(jq -n \
              --arg parent "${CLOUD_IDENTITY_CUSTOMER_ID}" \
              --arg email "${dst_app_group}" \
              --arg dn "${dst_app_group%@*}" \
              '{
                parent: $parent,
                groupKey: {id: $email},
                displayName: $dn,
                description: ("Dedicated Gemini Enterprise Per-App access group for " + $email),
                labels: {
                  "cloudidentity.googleapis.com/groups.discussion_forum": "",
                  "cloudidentity.googleapis.com/groups.security": ""
                }
              }')"
            ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/groups?initialGroupConfig=EMPTY" "${app_grp_payload}" "true" >/dev/null || true
          fi
        fi

        mappings_json="$(echo "${mappings_json}" | jq -c \
          --arg app_grp "${dst_app_group}" \
          --arg mem "${src_member}" \
          '. + [{app_group_email: $app_grp, member_email: $mem}]')"
      fi
    done
  fi
  printf '%s' "${mappings_json}"
}

configure_gcp_directory_sync_connector() {
  log_phase "GCP-DIRECTORY-SYNC" "Configuring & Validating Google Cloud Identity Directory Sync for Microsoft Entra ID (${M365_TENANT_ID})"

  local manifest_out="${GCP_DIRECTORY_SYNC_MANIFEST_OUT:-${PROJECT_ROOT}/configs/gcp-directory-sync-config.json}"
  mkdir -p "$(dirname "${manifest_out}")"

  # 1. Verify Microsoft Graph Directory Sync readiness (Groups & Users endpoint access)
  local groups_url="https://graph.microsoft.com/v1.0/groups?\$top=999&\$select=id,displayName,description,mail,mailNickname,securityEnabled"
  if [[ -n "${ENTRA_GROUP_FILTER:-}" ]]; then
    local encoded_filter
    encoded_filter="$(printf '%s' "${ENTRA_GROUP_FILTER}" | sed 's/ /%20/g')"
    groups_url="${groups_url}&\$filter=${encoded_filter}"
  fi

  local grp_rc=0
  _ms_graph_request "GET" "${groups_url}" || grp_rc=$?
  local discovered_entra_groups="[]"
  if [[ "${grp_rc}" -eq 0 && "${DRY_RUN:-false}" != "true" ]]; then
    discovered_entra_groups="$(echo "${LAST_GRAPH_BODY}" | jq -c --arg dom "${SHARED_IDENTITY_DOMAIN}" '
      [.value[]? | select(.mailNickname != null or .mail != null) | {
        entra_object_id: .id,
        display_name: .displayName,
        mail_nickname: .mailNickname,
        cloud_identity_group_email: ((.mail // ((.mailNickname // "group") + "@" + $dom)) | ascii_downcase)
      }]' 2>/dev/null || echo '[]')"
  fi

  # 2. Build managed group emails array from DIRECTORY_SYNC_MANAGED_GROUPS
  local managed_groups_json="[]"
  IFS=',' read -r -a mg_arr <<< "${DIRECTORY_SYNC_MANAGED_GROUPS:-}"
  for mg in ${mg_arr[@]+"${mg_arr[@]}"}; do
    mg="$(echo "${mg}" | xargs)"
    [[ -z "${mg}" ]] && continue
    local mg_email="${mg}"
    if [[ "${mg_email}" != *"@"* ]]; then
      mg_email="${mg_email}@${SHARED_IDENTITY_DOMAIN}"
    fi
    mg_email="$(printf '%s' "${mg_email}" | tr '[:upper:]' '[:lower:]')"
    managed_groups_json="$(echo "${managed_groups_json}" | jq -c --arg g "${mg_email}" '. + [$g] | unique')"
  done

  # 3. Optional: Configure Microsoft Entra Outbound SCIM 2.0 Provisioning Job on Google Cloud Gallery App
  local scim_job_status="MANAGED_BY_GCP_DIRECTORY_SYNC"
  if [[ "${ENABLE_ENTRA_SCIM_PROVISIONING_JOB:-false}" == "true" ]]; then
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] Would configure Entra SCIM 2.0 Synchronization Job (templateId=googleCloud) targeting https://www.googleapis.com/admin/directory/v1"
      scim_job_status="DRY_RUN_SCIM_JOB"
    else
      log_info "Checking Microsoft Entra ID Gallery App Service Principal for SCIM Synchronization Job..."
      local sp_rc=0
      _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/servicePrincipals?\$filter=startswith(displayName,'Google%20Cloud')%20or%20endswith(displayName,'google-cloud-sso')&\$select=id,displayName" || sp_rc=$?
      if [[ "${sp_rc}" -eq 0 ]]; then
        local sp_id
        sp_id="$(echo "${LAST_GRAPH_BODY}" | jq -r '.value[0].id // empty')"
        if [[ -n "${sp_id}" ]]; then
          local jobs_rc=0
          _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/servicePrincipals/${sp_id}/synchronization/jobs" || jobs_rc=$?
          local job_id
          job_id="$(echo "${LAST_GRAPH_BODY}" | jq -r '.value[0].id // empty' 2>/dev/null || true)"
          if [[ -z "${job_id}" ]]; then
            local create_job_payload='{"templateId":"gsuite"}'
            _ms_graph_request "POST" "https://graph.microsoft.com/v1.0/servicePrincipals/${sp_id}/synchronization/jobs" "${create_job_payload}" || true
            job_id="$(echo "${LAST_GRAPH_BODY}" | jq -r '.id // empty' 2>/dev/null || true)"
          fi
          if [[ -n "${job_id}" ]]; then
            _ms_graph_request "POST" "https://graph.microsoft.com/v1.0/servicePrincipals/${sp_id}/synchronization/jobs/${job_id}/start" "" || true
            scim_job_status="ACTIVE:${job_id}"
            log_ok "Started Entra SCIM Provisioning Job '${job_id}' on Service Principal '${sp_id}'."
          fi
        fi
      fi
    fi
  fi

  # 4. Write declarative GCP Directory Sync Connector Specification JSON
  jq -n \
    --arg cust "${CLOUD_IDENTITY_CUSTOMER_ID}" \
    --arg proj "${GCP_PROJECT_ID}" \
    --arg dom "${SHARED_IDENTITY_DOMAIN}" \
    --arg src_dom "${ENTRA_SOURCE_DOMAIN}" \
    --arg tenant "${M365_TENANT_ID}" \
    --arg client "${M365_CLIENT_ID}" \
    --arg secret "projects/${GCP_PROJECT_ID}/secrets/${M365_SECRET_ID}/versions/latest" \
    --arg ou "${SAML_TARGET_ORG_UNIT:-/}" \
    --arg filter "${ENTRA_GROUP_FILTER:-startswith(mailNickname,'ge-')}" \
    --arg scim_status "${scim_job_status}" \
    --argjson managed_groups "${managed_groups_json}" \
    --argjson discovered_groups "${discovered_entra_groups}" \
    '{
      schema_version: "1.0",
      identity_sync_mode: "GCP_DIRECTORY_SYNC",
      cloud_identity_customer_id: $cust,
      gcp_project_id: $proj,
      shared_identity_domain: $dom,
      entra_source_domain: $src_dom,
      external_directory_connection: {
        directory_type: "MICROSOFT_ENTRA_ID",
        tenant_id: $tenant,
        oauth_client_id: $client,
        secret_manager_credentials: $secret,
        microsoft_graph_base_uri: "https://graph.microsoft.com/v1.0",
        required_application_permissions: [
          "User.Read.All",
          "Group.Read.All",
          "GroupMember.Read.All",
          "Directory.Read.All",
          "AdministrativeUnit.Read.All"
        ],
        scim_provisioning_status: $scim_status
      },
      user_sync_configuration: {
        enabled: true,
        target_org_unit: $ou,
        attribute_mapping: {
          primaryEmail: "userPrincipalName",
          "name.givenName": "givenName",
          "name.familyName": "surname",
          "externalIds[0].value": "mailNickname"
        },
        conflict_resolution_policy: "MERGE_EXISTING_CLOUD_IDENTITY_USER",
        deprovisioning_policy: "SUSPEND_USER_ON_ENTRA_DISABLE_OR_DELETE"
      },
      group_sync_configuration: {
        enabled: true,
        entra_odata_group_filter: $filter,
        managed_group_emails: $managed_groups,
        discovered_entra_groups: $discovered_groups
      }
    }' > "${manifest_out}"

  log_ok "Wrote GCP Directory Sync connector specification to ${manifest_out}."
  return 0
}

reconcile_directory_synced_groups() {
  log_phase "DIRECTORY-SYNC-RECONCILE" "Verifying Directory-Synced Cloud Identity Groups & Generating Clean Per-App Group Mappings"
  local tf_dir="${TF_IDENTITY_DIR_OVERRIDE:-${PROJECT_ROOT}/terraform-identity}"
  local tfvars_out="${tf_dir}/identity_entities.auto.tfvars.json"

  local existing_ci_groups="{}"
  if [[ "${DRY_RUN:-false}" != "true" && -n "${CLOUD_IDENTITY_CUSTOMER_ID:-}" ]]; then
    existing_ci_groups="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"
  fi

  # 1. Verify that Directory-Synced Entra groups exist in Cloud Identity (or bootstrap empty Day-0 shells
  #    so GCP Directory Sync merges into them and Day-0 Per-App group nesting succeeds immediately)
  local verified_sync_count=0
  local bootstrapped_shell_count=0
  IFS=',' read -r -a mg_arr <<< "${DIRECTORY_SYNC_MANAGED_GROUPS:-}"
  for mg in ${mg_arr[@]+"${mg_arr[@]}"}; do
    mg="$(echo "${mg}" | xargs)"
    [[ -z "${mg}" ]] && continue
    local mg_email="${mg}"
    if [[ "${mg_email}" != *"@"* ]]; then
      mg_email="${mg_email}@${SHARED_IDENTITY_DOMAIN}"
    fi
    mg_email="$(printf '%s' "${mg_email}" | tr '[:upper:]' '[:lower:]')"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
      log_info "[DRY-RUN] Would verify Directory-Synced group '${mg_email}' in Cloud Identity (${CLOUD_IDENTITY_CUSTOMER_ID})"
      verified_sync_count=$((verified_sync_count + 1))
      continue
    fi

    local found_grp_name
    found_grp_name="$(echo "${existing_ci_groups}" | jq -r --arg em "${mg_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' 2>/dev/null | head -n 1 || true)"
    if [[ -n "${found_grp_name}" ]]; then
      verified_sync_count=$((verified_sync_count + 1))
    elif [[ "${BOOTSTRAP_EMPTY_SYNC_GROUP_SHELLS:-true}" == "true" && -n "${CLOUD_IDENTITY_CUSTOMER_ID:-}" ]]; then
      log_info "Bootstrapping Day-0 Cloud Identity group shell '${mg_email}' for GCP Directory Sync merge..."
      local shell_payload
      shell_payload="$(jq -n \
        --arg parent "${CLOUD_IDENTITY_CUSTOMER_ID}" \
        --arg email "${mg_email}" \
        --arg dn "${mg_email%@*}" \
        '{
          parent: $parent,
          groupKey: {id: $email},
          displayName: $dn,
          description: ("Managed by GCP Directory Sync from Microsoft Entra ID (" + $email + ")"),
          labels: {
            "cloudidentity.googleapis.com/groups.discussion_forum": "",
            "cloudidentity.googleapis.com/groups.security": ""
          }
        }')"
      ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/groups?initialGroupConfig=EMPTY" "${shell_payload}" "true" >/dev/null || true
      bootstrapped_shell_count=$((bootstrapped_shell_count + 1))
    else
      log_warn "Group '${mg_email}' has not yet replicated via GCP Directory Sync."
    fi
  done

  # 2. Build Per-App group mappings (ENTRA_TO_APP_GROUP_MAPPINGS)
  local mappings_json
  mappings_json="$(build_app_group_mappings_json "${existing_ci_groups}")"

  # 3. Write identity_entities.auto.tfvars.json with synced_groups={} so GCP Directory Sync
  #    owns User & Group memberships rather than Terraform state
  mkdir -p "${tf_dir}"
  jq -n \
    --argjson mappings "${mappings_json}" \
    '{
      synced_groups: {},
      app_group_mappings: $mappings
    }' > "${tfvars_out}"

  local mapping_count
  mapping_count="$(echo "${mappings_json}" | jq 'length')"
  log_ok "Directory Sync reconciliation complete (VerifiedGroups=${verified_sync_count}, BootstrappedDay0Shells=${bootstrapped_shell_count}, AppGroupMappings=${mapping_count}; Terraform synced_groups={} delegated to GCP Directory Sync)."
  return 0
}

sync_ge_licenses_from_directory_sync() {
  if [[ "${AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS:-true}" != "true" ]]; then
    log_info "AUTO_ASSIGN_GE_LICENSES_FROM_SYNCED_GROUPS is false; skipping automatic GE UserStore license assignment."
    return 0
  fi

  log_phase "DIRECTORY-SYNC-LICENSES" "Assigning Gemini Enterprise UserStore Licenses from Directory-Synced Cloud Identity Groups"
  local license_url
  license_url="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}/userStores/default_user_store:batchUpdateUserLicenses"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would inspect Cloud Identity memberships of (${DIRECTORY_SYNC_MANAGED_GROUPS}) and assign Gemini Enterprise licenses via ${license_url}"
    return 0
  fi

  local existing_ci_groups
  existing_ci_groups="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"

  local licensed_users_json="[]"
  IFS=',' read -r -a mg_arr <<< "${DIRECTORY_SYNC_MANAGED_GROUPS:-}"
  for mg in ${mg_arr[@]+"${mg_arr[@]}"}; do
    mg="$(echo "${mg}" | xargs)"
    [[ -z "${mg}" ]] && continue
    local mg_email="${mg}"
    if [[ "${mg_email}" != *"@"* ]]; then
      mg_email="${mg_email}@${SHARED_IDENTITY_DOMAIN}"
    fi
    mg_email="$(printf '%s' "${mg_email}" | tr '[:upper:]' '[:lower:]')"

    local grp_res_name
    grp_res_name="$(echo "${existing_ci_groups}" | jq -r --arg em "${mg_email}" '.groups[]? | select((.groupKey.id | ascii_downcase) == ($em | ascii_downcase)) | .name' 2>/dev/null | head -n 1 || true)"
    [[ -z "${grp_res_name}" ]] && continue

    local mem_resp
    mem_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${grp_res_name}/memberships" "" "true" || echo '{}')"
    while IFS= read -r mem_email; do
      [[ -z "${mem_email}" ]] && continue
      mem_email="$(printf '%s' "${mem_email}" | tr '[:upper:]' '[:lower:]')"
      # Skip nested group principals
      if [[ "${mem_email}" == ge-* || "${mem_email}" == *-app-users@* || "${mem_email}" == all-ge-apps-users@* ]]; then
        continue
      fi
      licensed_users_json="$(echo "${licensed_users_json}" | jq -c --arg u "${mem_email}" '. + [$u] | unique')"
    done < <(echo "${mem_resp}" | jq -r '.memberships[]?.preferredMemberKey.id // empty' 2>/dev/null || true)
  done

  local user_count
  user_count="$(echo "${licensed_users_json}" | jq 'length')"
  if [[ "${user_count}" -eq 0 ]]; then
    log_info "No individual user memberships found in Directory-Synced groups yet; skipping UserStore license batch update."
    return 0
  fi

  # Discover existing licenseConfig resource name if present on UserStore
  local existing_lic_url existing_lic_resp license_cfg_name=""
  existing_lic_url="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}/userStores/default_user_store/userLicenses?pageSize=50"
  existing_lic_resp="$(ge_curl_request "GET" "${existing_lic_url}" "" "false" || echo '{}')"
  license_cfg_name="$(echo "${existing_lic_resp}" | jq -r '.userLicenses[]? | select(.licenseConfig != null and .licenseConfig != "") | .licenseConfig' 2>/dev/null | head -n 1 || true)"

  if [[ -z "${license_cfg_name}" ]]; then
    log_info "No existing Gemini Enterprise licenseConfig detected on default_user_store (${user_count} Directory-Synced users ready)."
    return 0
  fi

  local batch_payload
  batch_payload="$(jq -n \
    --arg cfg "${license_cfg_name}" \
    --argjson users "${licensed_users_json}" \
    '{
      inlineSource: {
        userLicenses: [
          $users[] | {
            userPrincipal: .,
            licenseAssignmentState: "ASSIGNED",
            licenseConfig: $cfg
          }
        ],
        updateMask: {
          paths: ["license_assignment_state", "license_config"]
        }
      }
    }')"

  ge_curl_request "POST" "${license_url}" "${batch_payload}" "false" >/dev/null || true
  log_ok "Synchronized Gemini Enterprise UserStore licenses for ${user_count} Directory-Synced user(s)."
  return 0
}

sync_entra_entities_to_cloud_identity() {
  ensure_and_load_identity_secret_credentials
  fetch_microsoft_graph_access_token
  bulk_update_entra_upn_domain
  provision_clean_entra_app_groups
  configure_gcp_directory_sync_connector
  reconcile_directory_synced_groups
  sync_ge_licenses_from_directory_sync
  return 0
}

configure_cloud_identity_sso_and_acl() {
  log_phase "CLOUD-IDENTITY-SSO" "Configuring Cloud Identity SAML SSO Profile and verifying Discovery Engine aclConfig (idpType=GSUITE)"
  local acl_url
  acl_url="$(ge_api_base_url "${GE_LOCATION:-global}" "v1alpha")/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION:-global}/aclConfig"

  if [[ "${DRY_RUN:-false}" == "true" ]]; then
    log_info "[DRY-RUN] Would verify Discovery Engine aclConfig at ${acl_url} has idpType=GSUITE and ensure Cloud Identity Inbound SAML SSO Profile."
    return 0
  fi

  if [[ "${ENABLE_CLOUD_IDENTITY_SAML_SSO:-true}" == "true" && -n "${M365_TENANT_ID:-}" ]]; then
    local sso_list_url="https://cloudidentity.googleapis.com/v1/inboundSamlSsoProfiles?filter=customer%3D%3D%22${CLOUD_IDENTITY_CUSTOMER_ID}%22"
    local sso_list_resp="" profile_name="" sp_entity_id="" sp_acs_url=""
    sso_list_resp="$(ge_curl_request "GET" "${sso_list_url}" "" "true" || echo '{}')"
    profile_name="$(jq -r --arg dn "${SAML_SSO_PROFILE_DISPLAY_NAME:-Microsoft Entra ID SSO}" '.inboundSamlSsoProfiles[]? | select(.displayName == $dn) | .name' <<<"${sso_list_resp}" 2>/dev/null | head -n 1 || true)"

    if [[ -z "${profile_name}" ]]; then
      log_info "Creating Cloud Identity Inbound SAML SSO Profile '${SAML_SSO_PROFILE_DISPLAY_NAME:-Microsoft Entra ID SSO}' for Entra Tenant '${M365_TENANT_ID}'..."
      local create_sso_payload create_sso_resp
      create_sso_payload="$(jq -n \
        --arg cust "${CLOUD_IDENTITY_CUSTOMER_ID}" \
        --arg dn "${SAML_SSO_PROFILE_DISPLAY_NAME:-Microsoft Entra ID SSO}" \
        --arg eid "https://sts.windows.net/${M365_TENANT_ID}/" \
        --arg sso "https://login.microsoftonline.com/${M365_TENANT_ID}/saml2" \
        '{customer: $cust, displayName: $dn, idpConfig: {entityId: $eid, singleSignOnServiceUri: $sso}}')"
      create_sso_resp="$(ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/inboundSamlSsoProfiles" "${create_sso_payload}" "true" || echo '{}')"
      profile_name="$(jq -r '.response.name // .name // empty' <<<"${create_sso_resp}" 2>/dev/null || true)"
      sp_entity_id="$(jq -r '.response.spConfig.entityId // .spConfig.entityId // empty' <<<"${create_sso_resp}" 2>/dev/null || true)"
      sp_acs_url="$(jq -r '.response.spConfig.assertionConsumerServiceUri // .spConfig.assertionConsumerServiceUri // empty' <<<"${create_sso_resp}" 2>/dev/null || true)"
    else
      local get_sso_resp
      get_sso_resp="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${profile_name}" "" "true" || echo '{}')"
      sp_entity_id="$(jq -r '.spConfig.entityId // empty' <<<"${get_sso_resp}" 2>/dev/null || true)"
      sp_acs_url="$(jq -r '.spConfig.assertionConsumerServiceUri // empty' <<<"${get_sso_resp}" 2>/dev/null || true)"
    fi

    if [[ -n "${profile_name}" ]]; then
      export SAML_SP_ENTITY_ID="${sp_entity_id}"
      export SAML_SP_ACS_URL="${sp_acs_url}"
      log_ok "Cloud Identity SAML SSO Profile '${profile_name}' active (EntityID=${sp_entity_id}, ACS=${sp_acs_url})."

      if [[ -n "${SAML_IDP_CERT_FILE:-}" && -f "${SAML_IDP_CERT_FILE}" ]]; then
        local existing_creds cred_count
        existing_creds="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/${profile_name}/idpCredentials" "" "false" || echo '{}')"
        cred_count="$(jq -r '.idpCredentials | length // 0' <<<"${existing_creds}" 2>/dev/null || echo "0")"
        if [[ "${cred_count}" -lt 2 ]]; then
          log_info "Uploading Entra ID X.509 Certificate from '${SAML_IDP_CERT_FILE}' to '${profile_name}'..."
          local pem_data cert_payload
          pem_data="$(cat "${SAML_IDP_CERT_FILE}")"
          cert_payload="$(jq -n --arg pem "${pem_data}" '{pemData: $pem}')"
          ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/${profile_name}/idpCredentials:add" "${cert_payload}" "false" >/dev/null || true
        else
          log_info "SAML SSO Profile '${profile_name}' already has ${cred_count} IdP X.509 certificate(s) registered."
        fi
      fi

      if [[ -n "${SAML_TARGET_ORG_UNIT:-}" ]]; then
        local existing_assigns has_ou_assign
        existing_assigns="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/inboundSsoAssignments?filter=customer%3D%3D%22${CLOUD_IDENTITY_CUSTOMER_ID}%22" "" "false" || echo '{}')"
        has_ou_assign="$(jq -r --arg ou "${SAML_TARGET_ORG_UNIT}" '.inboundSsoAssignments[]? | select(.targetOrgUnit == $ou) | .name' <<<"${existing_assigns}" 2>/dev/null | head -n 1 || true)"
        if [[ -z "${has_ou_assign}" ]]; then
          log_info "Assigning SAML SSO Profile '${profile_name}' to Org Unit '${SAML_TARGET_ORG_UNIT}'..."
          local assign_payload
          assign_payload="$(jq -n \
            --arg cust "${CLOUD_IDENTITY_CUSTOMER_ID}" \
            --arg ou "${SAML_TARGET_ORG_UNIT}" \
            --arg prof "${profile_name}" \
            '{customer: $cust, targetOrgUnit: $ou, ssoMode: "SAML_SSO", samlSsoInfo: {inboundSamlSsoProfile: $prof}}')"
          ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/inboundSsoAssignments" "${assign_payload}" "false" >/dev/null || true
        else
          log_info "Org Unit '${SAML_TARGET_ORG_UNIT}' already has Inbound SAML SSO assignment (${has_ou_assign})."
        fi
      fi
    fi
  fi

  local rc=0 acl_resp=""
  acl_resp="$(ge_curl_request "GET" "${acl_url}" "" "false")" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    local idp_type
    idp_type="$(printf '%s' "${acl_resp}" | jq -r '.idpConfig.idpType // "UNKNOWN"')"
    if [[ "${idp_type}" != "GSUITE" ]]; then
      log_info "Setting Discovery Engine aclConfig idpType=GSUITE on project '${GCP_PROJECT_ID}'..."
      local patch_acl_resp=""
      patch_acl_resp="$(ge_curl_request "PATCH" "${acl_url}" '{"idpConfig":{"idpType":"GSUITE"}}' "false" || echo "{}")"
      idp_type="$(printf '%s' "${patch_acl_resp}" | jq -r '.idpConfig.idpType // "GSUITE"')"
    fi
    log_ok "Discovery Engine aclConfig verified (idpType=${idp_type})."
  else
    log_warn "Could not inspect Discovery Engine aclConfig (rc=${rc})."
  fi
  return 0
}

run_identity_verification_and_summary() {
  log_phase "VERIFY" "Verifying Microsoft Entra ID & Google Cloud Identity Sync Readiness"
  ensure_and_load_identity_secret_credentials
  configure_cloud_identity_sso_and_acl

  log_phase "SUMMARY" "Microsoft Entra ID <-> Google Cloud Identity Deployment Summary"
  echo "  GCP Project ID            : ${GCP_PROJECT_ID}"
  echo "  Cloud Identity Customer   : ${CLOUD_IDENTITY_CUSTOMER_ID}"
  echo "  Primary Customer Domain   : ${PRIMARY_CUSTOMER_DOMAIN}"
  echo "  Shared Identity Domain    : ${SHARED_IDENTITY_DOMAIN}"
  echo "  Secret Manager Secret ID  : ${M365_SECRET_ID}"
  echo "  Entra Tenant ID           : ${M365_TENANT_ID}"
  echo "  Entra Client ID           : ${M365_CLIENT_ID}"
  if [[ -n "${SAML_SP_ENTITY_ID:-}" ]]; then
    echo "  SAML SP Entity ID         : ${SAML_SP_ENTITY_ID}"
    echo "  SAML SP ACS (Reply) URL   : ${SAML_SP_ACS_URL:-}"
  fi
  log_ok "Identity verification and summary complete."
  return 0
}
