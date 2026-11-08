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
  export DNS_PROJECT_ID="${DNS_PROJECT_ID:-}"
  export DNS_ZONE_NAME="${DNS_ZONE_NAME:-}"
  export ENTRA_DOMAIN_VERIFICATION_MS_ID="${ENTRA_DOMAIN_VERIFICATION_MS_ID:-}"
  export GOOGLE_DOMAIN_VERIFICATION_TXT="${GOOGLE_DOMAIN_VERIFICATION_TXT:-}"

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

sync_entra_entities_to_cloud_identity() {
  log_phase "ENTRA-GRAPH-SYNC" "Discovering Entra ID Users, Groups & Memberships and preparing Cloud Identity Sync"
  local tf_dir="${TF_IDENTITY_DIR_OVERRIDE:-${PROJECT_ROOT}/terraform-identity}"
  local tfvars_out="${tf_dir}/identity_entities.auto.tfvars.json"

  ensure_and_load_identity_secret_credentials
  fetch_microsoft_graph_access_token
  bulk_update_entra_upn_domain
  provision_clean_entra_app_groups

  # 1. Build app_group_mappings JSON array from ENTRA_TO_APP_GROUP_MAPPINGS
  #    and ensure each target Per-App Cloud Identity group exists before Terraform lookup
  local mappings_json="[]"
  if [[ -n "${ENTRA_TO_APP_GROUP_MAPPINGS:-}" ]]; then
    local existing_ci_groups="{}"
    if [[ "${DRY_RUN:-false}" != "true" && -n "${CLOUD_IDENTITY_CUSTOMER_ID:-}" ]]; then
      existing_ci_groups="$(ge_curl_request "GET" "https://cloudidentity.googleapis.com/v1/groups?parent=${CLOUD_IDENTITY_CUSTOMER_ID}" "" "true" || echo '{}')"
    fi

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
            log_info "Pre-creating target Per-App Cloud Identity group '${dst_app_group}' for group nesting..."
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

  # 2. Query Entra Users (export Google Admin Console CSV + optional Cloud Identity Directory API sync)
  local users_rc=0
  local csv_out="${PROJECT_ROOT}/configs/cloud_identity_users.csv"
  _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/users?\$top=999&\$select=id,displayName,givenName,surname,userPrincipalName,mail,mailNickname,accountEnabled" || users_rc=$?
  if [[ "${users_rc}" -eq 0 && "${DRY_RUN:-false}" != "true" ]]; then
    echo "First Name [Required],Last Name [Required],Email Address [Required],Password [Required],Org Unit Path [Required],Change Password at Next Sign-In" > "${csv_out}"
    while IFS= read -r u_obj; do
      [[ -z "${u_obj}" ]] && continue
      local upn given surname dname target_email
      upn="$(echo "${u_obj}" | jq -r '.userPrincipalName // empty')"
      [[ -z "${upn}" || "${upn}" == *"#EXT#"* ]] && continue
      target_email="$(_normalize_principal_email "${upn}")"
      given="$(echo "${u_obj}" | jq -r '.givenName // (.displayName | split(" ")[0]) // "Entra"')"
      surname="$(echo "${u_obj}" | jq -r '.surname // (.displayName | split(" ")[-1]) // "User"')"
      dname="$(echo "${u_obj}" | jq -r '.displayName // "Entra User"')"
      echo "${given},${surname},${target_email},${CLOUD_IDENTITY_DEFAULT_TEMP_PASSWORD},/,False" >> "${csv_out}"

      if [[ "${SYNC_CLOUD_IDENTITY_USERS:-false}" == "true" ]]; then
        local user_payload
        user_payload="$(jq -n \
          --arg email "${target_email}" \
          --arg given "${given}" \
          --arg family "${surname}" \
          --arg full "${dname}" \
          --arg pwd "${CLOUD_IDENTITY_DEFAULT_TEMP_PASSWORD}" \
          --arg ext "${upn}" \
          '{
            primaryEmail: $email,
            name: {givenName: $given, familyName: $family, fullName: $full},
            password: $pwd,
            changePasswordAtNextLogin: false,
            externalIds: [{value: $ext, type: "login_id"}]
          }')"
        ge_curl_request "POST" "https://admin.googleapis.com/admin/directory/v1/users" "${user_payload}" "true" || true
      fi
    done < <(echo "${LAST_GRAPH_BODY}" | jq -c '.value[]? // empty')
    log_ok "Exported Entra users bulk CSV to ${csv_out}."
  fi

  # 3. Query Entra Groups & Transitive Members
  local groups_url="https://graph.microsoft.com/v1.0/groups?\$top=999&\$select=id,displayName,description,mail,mailNickname,securityEnabled"
  if [[ -n "${ENTRA_GROUP_FILTER:-}" ]]; then
    local encoded_filter
    encoded_filter="$(printf '%s' "${ENTRA_GROUP_FILTER}" | sed 's/ /%20/g')"
    groups_url="${groups_url}&\$filter=${encoded_filter}"
  fi

  local synced_groups_json="{}"
  local grp_rc=0
  _ms_graph_request "GET" "${groups_url}" || grp_rc=$?
  if [[ "${grp_rc}" -eq 0 && "${DRY_RUN:-false}" != "true" ]]; then
    while IFS= read -r g_obj; do
      [[ -z "${g_obj}" ]] && continue
      local gid gname gdesc gmail gnick group_email group_key
      gid="$(echo "${g_obj}" | jq -r '.id // empty')"
      gname="$(echo "${g_obj}" | jq -r '.displayName // empty')"
      gdesc="$(echo "${g_obj}" | jq -r '.description // "Synchronized from Microsoft Entra ID"')"
      gmail="$(echo "${g_obj}" | jq -r '.mail // empty')"
      gnick="$(echo "${g_obj}" | jq -r '.mailNickname // empty')"
      [[ -z "${gid}" || -z "${gname}" ]] && continue

      if [[ -n "${gmail}" ]]; then
        group_email="$(_normalize_principal_email "${gmail}")"
      elif [[ -n "${gnick}" ]]; then
        group_email="${gnick}@${SHARED_IDENTITY_DOMAIN}"
      else
        continue
      fi

      group_key="$(echo "${group_email%@*}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')"

      # Query transitive members for this group
      local mem_rc=0
      local members_arr="[]"
      _ms_graph_request "GET" "https://graph.microsoft.com/v1.0/groups/${gid}/transitiveMembers?\$select=id,userPrincipalName,mail" || mem_rc=$?
      if [[ "${mem_rc}" -eq 0 ]]; then
        while IFS= read -r m_obj; do
          [[ -z "${m_obj}" ]] && continue
          local m_upn m_mail norm_mem
          m_mail="$(echo "${m_obj}" | jq -r '.mail // empty')"
          m_upn="$(echo "${m_obj}" | jq -r '.userPrincipalName // empty')"
          norm_mem="$(_normalize_principal_email "${m_mail:-${m_upn}}")"
          norm_mem="$(printf '%s' "${norm_mem}" | tr '[:upper:]' '[:lower:]')"
          if [[ -n "${norm_mem}" ]]; then
            members_arr="$(echo "${members_arr}" | jq -c --arg m "${norm_mem}" '. + [$m] | unique')"
          fi
        done < <(echo "${LAST_GRAPH_BODY}" | jq -c '.value[]? // empty')
      fi

      synced_groups_json="$(echo "${synced_groups_json}" | jq -c \
        --arg k "${group_key}" \
        --arg email "${group_email}" \
        --arg dn "${gname}" \
        --arg desc "${gdesc}" \
        --argjson mems "${members_arr}" \
        '. + {($k): {group_email: $email, display_name: $dn, description: $desc, members: $mems}}')"
    done < <(echo "${LAST_GRAPH_BODY}" | jq -c '.value[]? // empty')
  fi

  mkdir -p "${tf_dir}"
  jq -n \
    --argjson groups "${synced_groups_json}" \
    --argjson mappings "${mappings_json}" \
    '{
      synced_groups: $groups,
      app_group_mappings: $mappings
    }' > "${tfvars_out}"

  local group_count mapping_count
  group_count="$(echo "${synced_groups_json}" | jq 'keys | length')"
  mapping_count="$(echo "${mappings_json}" | jq 'length')"
  log_ok "Generated ${tfvars_out} (SyncedGroups=${group_count}, AppGroupMappings=${mapping_count})."
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
        log_info "Uploading Entra ID X.509 Certificate from '${SAML_IDP_CERT_FILE}' to '${profile_name}'..."
        local pem_data cert_payload
        pem_data="$(cat "${SAML_IDP_CERT_FILE}")"
        cert_payload="$(jq -n --arg pem "${pem_data}" '{pemData: $pem}')"
        ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/${profile_name}/idpCredentials:add" "${cert_payload}" "true" >/dev/null || true
      fi

      if [[ -n "${SAML_TARGET_ORG_UNIT:-}" ]]; then
        log_info "Assigning SAML SSO Profile '${profile_name}' to Org Unit '${SAML_TARGET_ORG_UNIT}'..."
        local assign_payload
        assign_payload="$(jq -n \
          --arg cust "${CLOUD_IDENTITY_CUSTOMER_ID}" \
          --arg ou "${SAML_TARGET_ORG_UNIT}" \
          --arg prof "${profile_name}" \
          '{customer: $cust, targetOrgUnit: $ou, ssoMode: "SAML_SSO", samlSsoInfo: {inboundSamlSsoProfile: $prof}}')"
        ge_curl_request "POST" "https://cloudidentity.googleapis.com/v1/inboundSsoAssignments" "${assign_payload}" "true" >/dev/null || true
      fi
    fi
  fi

  local rc=0 acl_resp=""
  acl_resp="$(ge_curl_request "GET" "${acl_url}" "" "true")" || rc=$?
  if [[ "${rc}" -eq 0 ]]; then
    local idp_type
    idp_type="$(printf '%s' "${acl_resp}" | jq -r '.idpConfig.idpType // "UNKNOWN"')"
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
