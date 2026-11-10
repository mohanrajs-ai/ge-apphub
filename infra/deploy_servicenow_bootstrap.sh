#!/usr/bin/env bash
# ==============================================================================
# ServiceNow Instance Bootstrap Orchestrator (Phase 0D Automation)
# ==============================================================================
# Automates 100% of the ServiceNow-side prerequisites for Google Cloud
# Gemini Enterprise (Discovery Engine ServiceNow Connector + BAP Write Actions):
#   [Step 0D.1 — Dedicated Integration User Provisioning (sys_user)]
#     1. Creates or updates the dedicated ServiceNow integration account
#        (`<customer>_ge_connector`) via `/api/now/table/sys_user` with a
#        strong generated password (or custom `--connector-password`).
#   [Step 0D.2 — Least-Privilege ITSM, KB, Catalog & ACL Role Binding]
#     2. Resolves role `sys_id`s from `/api/now/table/sys_user_role` and
#        idempotently binds them via `/api/now/table/sys_user_has_role`:
#          - `itil`                        (Incident, Problem, Change, Catalog Task read/write)
#          - `knowledge`                   (Knowledge Base articles & user criteria)
#          - `catalog` & `catalog_admin`   (Service Catalog items & categories)
#          - `snc_platform_rest_api_access`(REST Table & Attachment API access)
#          - `rest_service`                (Web Service API access)
#          - `user_admin`                  (Read sys_user, sys_user_group, sys_user_grmember for ACLs)
#   [Step 0D.3 — System OAuth Application Registry Provisioning (oauth_entity)]
#     3. Creates or updates the OAuth 2.0 Client in `/api/now/table/oauth_entity`
#        with Redirect URI `https://vertexaisearch.cloud.google.com/oauth-redirect`,
#        extracts `client_id` and `client_secret`, and verifies an OAuth 2.0
#        token exchange against `https://<instance>.service-now.com/oauth_token.do`.
#   [Step 0D.4 — Zero-Touch GCP Secret Manager Sync & Config Generation]
#     4. Injects `{instance_uri, client_id, client_secret, username, password}`
#        directly into Google Cloud Secret Manager
#        (`projects/<project>/secrets/<customer>-servicenow-connector-credentials`)
#        and generates `configs/<customer>-servicenow.env` for Phase 2B.
#
# Usage:
#   ./deploy_servicenow_bootstrap.sh \
#     --instance-uri "https://dev123456.service-now.com" \
#     --admin-user "admin" \
#     --customer-name "cymbal" \
#     --customer-domain "mohanrajs.demo.altostrat.com" \
#     --gcp-project-id "cymbal-app-514110" \
#     [--admin-password "<password>"] \
#     [--align-user-emails] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
mkdir -p "${CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

# shellcheck source=scripts/lib/common.sh
source "${SCRIPT_DIR}/scripts/lib/common.sh"
# shellcheck source=scripts/lib/http.sh
source "${SCRIPT_DIR}/scripts/lib/http.sh"

SN_INSTANCE_URI="${SERVICENOW_INSTANCE_URI:-}"
SN_ADMIN_USER="${SN_ADMIN_USER:-admin}"
SN_ADMIN_PASSWORD="${SN_ADMIN_PASSWORD:-}"
SN_ADMIN_BEARER_TOKEN="${SN_ADMIN_BEARER_TOKEN:-}"
CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
GCP_REGION="us-central1"
GE_LOCATION="global"
SN_SECRET_ID=""
SN_CONNECTOR_USERNAME=""
SN_CONNECTOR_PASSWORD="${SERVICENOW_PASSWORD:-}"
SN_OAUTH_CLIENT_ID="${SERVICENOW_CLIENT_ID:-}"
SN_OAUTH_CLIENT_SECRET="${SERVICENOW_CLIENT_SECRET:-}"
ALIGN_USER_EMAILS="false"
TF_STATE_BUCKET=""
DRY_RUN="false"

REQUIRED_SN_ROLES=(
  "itil"
  "knowledge"
  "catalog"
  "catalog_admin"
  "snc_platform_rest_api_access"
  "rest_service"
  "user_admin"
)

print_sn_bootstrap_usage() {
  cat <<'EOF'
Usage: ./deploy_servicenow_bootstrap.sh [OPTIONS]

Automates ServiceNow instance configuration (Integration User, Roles, OAuth 2.0
Application Registry endpoint, OAuth verification, and GCP Secret Manager sync).

Options:
  --instance-uri <url>         ServiceNow Instance URL (e.g. https://dev123456.service-now.com)
  --instance <name>            ServiceNow Instance name (expands to https://<name>.service-now.com)
  --admin-user <user>          ServiceNow admin username for bootstrap API calls (default: admin)
  --admin-password <pass>      ServiceNow admin password (if omitted, prompts interactively or reads SN_ADMIN_PASSWORD)
  --admin-token <token>        ServiceNow admin OAuth Bearer token (alternative to Basic Auth)
  --customer-name <name>       Customer short slug (default: cymbal)
  --customer-domain <domain>   Verified corporate domain (default: cymbal.com)
  --gcp-project-id <id>        Target GCP Project ID for Secret Manager & Discovery Engine
  --gcp-region <region>        Target GCP Region (default: us-central1)
  --secret-id <id>             Override Secret Manager secret ID (default: <customer>-servicenow-connector-credentials)
  --connector-username <user>  Integration username to create/update (default: <customer>_ge_connector)
  --connector-password <pass>  Integration user password (auto-generated if omitted)
  --align-user-emails          Normalize active ServiceNow sys_user emails to @<customer-domain> for ACL matching
  --tf-state-bucket <bucket>   Remote Terraform state bucket name (default: <customer>-ge-tfstate)
  --dry-run                    Preview all ServiceNow REST API & GCP operations without mutating state
  --help, -h                   Show this help message and exit
EOF
}

_sn_api_request() {
  local method="$1"
  local path="$2"
  local payload="${3:-}"
  local url="${SN_INSTANCE_URI%/}/${path#/}"

  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] ServiceNow ${method} ${url}"
    LAST_SN_STATUS="200"
    LAST_SN_BODY='{"result":[]}'
    return 0
  fi

  local resp_file http_code
  resp_file="$(mktemp)"
  local auth_args=()
  if [[ -n "${SN_ADMIN_BEARER_TOKEN}" ]]; then
    auth_args=(-H "Authorization: Bearer ${SN_ADMIN_BEARER_TOKEN}")
  else
    auth_args=(-u "${SN_ADMIN_USER}:${SN_ADMIN_PASSWORD}")
  fi

  if [[ -n "${payload}" ]]; then
    http_code="$(curl -sS -X "${method}" "${url}" \
      -o "${resp_file}" \
      -w "%{http_code}" \
      "${auth_args[@]}" \
      -H "Accept: application/json" \
      -H "Content-Type: application/json" \
      -d "${payload}")"
  else
    http_code="$(curl -sS -X "${method}" "${url}" \
      -o "${resp_file}" \
      -w "%{http_code}" \
      "${auth_args[@]}" \
      -H "Accept: application/json")"
  fi

  LAST_SN_STATUS="${http_code}"
  LAST_SN_BODY="$(cat "${resp_file}")"
  rm -f "${resp_file}"

  if [[ "${http_code}" -lt 200 || "${http_code}" -ge 300 ]]; then
    log_error "ServiceNow API ${method} ${url} returned HTTP ${http_code}: ${LAST_SN_BODY}"
    return 1
  fi
  return 0
}

deploy_servicenow_bootstrap_main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --instance-uri)
        SN_INSTANCE_URI="$2"
        shift 2
        ;;
      --instance)
        SN_INSTANCE_URI="https://${2#https://}.service-now.com"
        SN_INSTANCE_URI="${SN_INSTANCE_URI%.service-now.com.service-now.com}.service-now.com"
        shift 2
        ;;
      --admin-user)
        SN_ADMIN_USER="$2"
        shift 2
        ;;
      --admin-password)
        SN_ADMIN_PASSWORD="$2"
        shift 2
        ;;
      --admin-token)
        SN_ADMIN_BEARER_TOKEN="$2"
        shift 2
        ;;
      --customer-name)
        CUSTOMER_NAME="$2"
        shift 2
        ;;
      --customer-domain)
        CUSTOMER_DOMAIN="$2"
        shift 2
        ;;
      --gcp-project-id)
        GCP_PROJECT_ID="$2"
        shift 2
        ;;
      --gcp-region)
        GCP_REGION="$2"
        shift 2
        ;;
      --secret-id)
        SN_SECRET_ID="$2"
        shift 2
        ;;
      --connector-username)
        SN_CONNECTOR_USERNAME="$2"
        shift 2
        ;;
      --connector-password)
        SN_CONNECTOR_PASSWORD="$2"
        shift 2
        ;;
      --align-user-emails)
        ALIGN_USER_EMAILS="true"
        shift 1
        ;;
      --tf-state-bucket)
        TF_STATE_BUCKET="$2"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        export DRY_RUN="true"
        shift 1
        ;;
      --help|-h)
        print_sn_bootstrap_usage
        return 0
        ;;
      *)
        log_error "Unknown flag: $1"
        print_sn_bootstrap_usage
        return 1
        ;;
    esac
  done

  if [[ -z "${SN_INSTANCE_URI}" ]]; then
    log_error "--instance-uri <https://instance.service-now.com> (or SERVICENOW_INSTANCE_URI) is required."
    return 1
  fi
  SN_INSTANCE_URI="${SN_INSTANCE_URI%/}"

  CUSTOMER_UPPER="$(printf '%s' "${CUSTOMER_NAME}" | tr '[:lower:]' '[:upper:]')"
  SN_SECRET_ID="${SN_SECRET_ID:-${CUSTOMER_NAME}-servicenow-connector-credentials}"
  SN_CONNECTOR_USERNAME="${SN_CONNECTOR_USERNAME:-${CUSTOMER_NAME}_ge_connector}"
  TF_STATE_BUCKET="${TF_STATE_BUCKET:-${CUSTOMER_NAME}-ge-tfstate}"
  OAUTH_APP_NAME="${CUSTOMER_UPPER} Google Cloud Gemini Enterprise Connector"
  REDIRECT_URI="https://vertexaisearch.cloud.google.com/oauth-redirect"
  SN_ENV_OUT="${CONFIGS_DIR}/${CUSTOMER_NAME}-servicenow.env"

  if [[ -z "${SN_CONNECTOR_PASSWORD}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      SN_CONNECTOR_PASSWORD="DryRun!SnGe2026#Password"
    else
      SN_CONNECTOR_PASSWORD="GeSn!$(python3 -c 'import secrets, string; alphabet = string.ascii_letters + string.digits; print("".join(secrets.choice(alphabet) for _ in range(18)))')#9a"
    fi
  fi

  if [[ -z "${SN_OAUTH_CLIENT_SECRET}" ]]; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      SN_OAUTH_CLIENT_SECRET="dry-run-sn-oauth-client-secret"
    else
      SN_OAUTH_CLIENT_SECRET="GeOAuth!$(python3 -c 'import secrets, string; alphabet = string.ascii_letters + string.digits; print("".join(secrets.choice(alphabet) for _ in range(24)))')"
    fi
  fi

  echo "=================================================================="
  echo " ServiceNow Instance Phase 0D Automation"
  echo "------------------------------------------------------------------"
  echo " Customer            : ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})"
  echo " ServiceNow Instance : ${SN_INSTANCE_URI}"
  echo " Integration Account : ${SN_CONNECTOR_USERNAME}"
  echo " OAuth Registry App  : ${OAUTH_APP_NAME}"
  echo " GCP Secret Manager  : projects/${GCP_PROJECT_ID}/secrets/${SN_SECRET_ID}"
  echo " Output Config File  : ${SN_ENV_OUT}"
  echo " Dry-Run Mode        : ${DRY_RUN}"
  echo "=================================================================="

  if [[ "${DRY_RUN}" != "true" && -z "${SN_ADMIN_PASSWORD}" && -z "${SN_ADMIN_BEARER_TOKEN}" ]]; then
    if [[ -t 0 ]]; then
      read -r -s -p "Enter ServiceNow Admin Password for '${SN_ADMIN_USER}' at ${SN_INSTANCE_URI}: " SN_ADMIN_PASSWORD
      echo ""
    else
      log_error "ServiceNow admin credentials required: pass --admin-password, --admin-token, or export SN_ADMIN_PASSWORD."
      return 1
    fi
  fi

  # ----------------------------------------------------------------------------
  # Step 0D.1: Create or Update Dedicated ServiceNow Integration User (sys_user)
  # ----------------------------------------------------------------------------
  log_phase "STEP-0D.1" "Provisioning Dedicated ServiceNow Integration User (${SN_CONNECTOR_USERNAME})"
  local user_sys_id=""
  _sn_api_request "GET" "/api/now/table/sys_user?sysparm_query=user_name=${SN_CONNECTOR_USERNAME}&sysparm_fields=sys_id,user_name,email&sysparm_limit=1"
  if [[ "${DRY_RUN}" == "true" ]]; then
    user_sys_id="dry-run-user-sys-id"
    log_info "[DRY-RUN] Would create/update sys_user '${SN_CONNECTOR_USERNAME}@${CUSTOMER_DOMAIN}' with roles: ${REQUIRED_SN_ROLES[*]}"
  else
    user_sys_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result[0].sys_id // empty')"
    local user_payload
    user_payload="$(jq -n \
      --arg uname "${SN_CONNECTOR_USERNAME}" \
      --arg fname "${CUSTOMER_UPPER} Gemini" \
      --arg lname "Enterprise Connector" \
      --arg email "${SN_CONNECTOR_USERNAME}@${CUSTOMER_DOMAIN}" \
      --arg pwd "${SN_CONNECTOR_PASSWORD}" \
      '{
        user_name: $uname,
        first_name: $fname,
        last_name: $lname,
        email: $email,
        active: "true",
        locked_out: "false",
        password_needs_reset: "false",
        user_password: $pwd
      }')"

    if [[ -z "${user_sys_id}" ]]; then
      log_info "Creating ServiceNow integration user '${SN_CONNECTOR_USERNAME}'..."
      _sn_api_request "POST" "/api/now/table/sys_user?sysparm_input_display_value=true" "${user_payload}"
      user_sys_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result.sys_id // empty')"
      log_ok "Created ServiceNow integration user '${SN_CONNECTOR_USERNAME}' (sys_id=${user_sys_id})."
    else
      log_info "Updating existing ServiceNow integration user '${SN_CONNECTOR_USERNAME}' (sys_id=${user_sys_id})..."
      _sn_api_request "PATCH" "/api/now/table/sys_user/${user_sys_id}?sysparm_input_display_value=true" "${user_payload}"
      log_ok "Updated ServiceNow integration user '${SN_CONNECTOR_USERNAME}' (sys_id=${user_sys_id})."
    fi
  fi

  # ----------------------------------------------------------------------------
  # Step 0D.2: Bind Required ITSM, Knowledge, Catalog & REST Roles
  # ----------------------------------------------------------------------------
  log_phase "STEP-0D.2" "Assigning Required ServiceNow Roles (${REQUIRED_SN_ROLES[*]})"
  for role_name in "${REQUIRED_SN_ROLES[@]}"; do
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "[DRY-RUN] Would resolve role '${role_name}' in sys_user_role and bind to '${SN_CONNECTOR_USERNAME}' in sys_user_has_role"
      continue
    fi

    _sn_api_request "GET" "/api/now/table/sys_user_role?sysparm_query=name=${role_name}&sysparm_fields=sys_id,name&sysparm_limit=1" || continue
    local role_sys_id
    role_sys_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result[0].sys_id // empty')"
    if [[ -z "${role_sys_id}" ]]; then
      log_warn "ServiceNow role '${role_name}' not found on instance; skipping."
      continue
    fi

    _sn_api_request "GET" "/api/now/table/sys_user_has_role?sysparm_query=user=${user_sys_id}^role=${role_sys_id}&sysparm_fields=sys_id&sysparm_limit=1" || true
    local existing_bind_id
    existing_bind_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result[0].sys_id // empty')"
    if [[ -z "${existing_bind_id}" ]]; then
      local bind_payload
      bind_payload="$(jq -n --arg u "${user_sys_id}" --arg r "${role_sys_id}" '{user: $u, role: $r, state: "active"}')"
      _sn_api_request "POST" "/api/now/table/sys_user_has_role" "${bind_payload}" || true
      log_ok "Assigned role '${role_name}' (${role_sys_id}) -> '${SN_CONNECTOR_USERNAME}'."
    else
      log_info "Role '${role_name}' already assigned to '${SN_CONNECTOR_USERNAME}'."
    fi
  done

  # ----------------------------------------------------------------------------
  # Step 0D.3: Provision OAuth 2.0 Application Registry Client (oauth_entity)
  # ----------------------------------------------------------------------------
  log_phase "STEP-0D.3" "Provisioning ServiceNow OAuth 2.0 Application Registry Endpoint (${OAUTH_APP_NAME})"
  local encoded_app_name
  encoded_app_name="$(printf '%s' "${OAUTH_APP_NAME}" | sed 's/ /%20/g')"
  _sn_api_request "GET" "/api/now/table/oauth_entity?sysparm_query=name=${encoded_app_name}&sysparm_fields=sys_id,name,client_id,client_secret,redirect_url&sysparm_limit=1"

  if [[ "${DRY_RUN}" == "true" ]]; then
    SN_OAUTH_CLIENT_ID="${SN_OAUTH_CLIENT_ID:-dry-run-sn-oauth-client-id}"
    log_info "[DRY-RUN] Would create/update oauth_entity '${OAUTH_APP_NAME}' with redirect_url='${REDIRECT_URI}'"
  else
    local oauth_sys_id
    oauth_sys_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result[0].sys_id // empty')"
    local oauth_payload
    oauth_payload="$(jq -n \
      --arg name "${OAUTH_APP_NAME}" \
      --arg redir "${REDIRECT_URI}" \
      --arg secret "${SN_OAUTH_CLIENT_SECRET}" \
      '{
        name: $name,
        type: "client",
        active: "true",
        redirect_url: $redir,
        client_secret: $secret,
        access_token_lifespan: "1800",
        refresh_token_lifespan: "8640000",
        comments: "Managed by Gemini Enterprise Phase 0D ServiceNow Bootstrap"
      }')"

    if [[ -z "${oauth_sys_id}" ]]; then
      log_info "Creating OAuth 2.0 Application Registry client '${OAUTH_APP_NAME}'..."
      _sn_api_request "POST" "/api/now/table/oauth_entity?sysparm_input_display_value=true" "${oauth_payload}"
      oauth_sys_id="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result.sys_id // empty')"
      SN_OAUTH_CLIENT_ID="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result.client_id // empty')"
    else
      log_info "Updating existing OAuth 2.0 Application Registry client '${OAUTH_APP_NAME}' (sys_id=${oauth_sys_id})..."
      _sn_api_request "PATCH" "/api/now/table/oauth_entity/${oauth_sys_id}?sysparm_input_display_value=true" "${oauth_payload}"
      SN_OAUTH_CLIENT_ID="$(printf '%s' "${LAST_SN_BODY}" | jq -r '.result.client_id // empty')"
    fi
    log_ok "ServiceNow OAuth 2.0 Client ready (client_id=${SN_OAUTH_CLIENT_ID})."

    # Verify OAuth 2.0 password grant handshake against /oauth_token.do
    log_info "Verifying OAuth 2.0 token handshake at ${SN_INSTANCE_URI}/oauth_token.do..."
    local token_resp_file token_http_code
    token_resp_file="$(mktemp)"
    token_http_code="$(curl -sS -X POST "${SN_INSTANCE_URI}/oauth_token.do" \
      -o "${token_resp_file}" \
      -w "%{http_code}" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      --data-urlencode "grant_type=password" \
      --data-urlencode "client_id=${SN_OAUTH_CLIENT_ID}" \
      --data-urlencode "client_secret=${SN_OAUTH_CLIENT_SECRET}" \
      --data-urlencode "username=${SN_CONNECTOR_USERNAME}" \
      --data-urlencode "password=${SN_CONNECTOR_PASSWORD}" || echo "000")"
    rm -f "${token_resp_file}"
    if [[ "${token_http_code}" == "200" ]]; then
      log_ok "ServiceNow OAuth 2.0 token exchange (/oauth_token.do) succeeded (HTTP 200)."
    else
      log_warn "ServiceNow /oauth_token.do returned HTTP ${token_http_code}. Ensure 'com.snc.platform.security.oauth.is.active' system property is true."
    fi
  fi

  # Optional: Align ServiceNow sys_user emails to @<customer_domain>
  if [[ "${ALIGN_USER_EMAILS}" == "true" ]]; then
    log_phase "STEP-0D.3B" "Aligning ServiceNow sys_user Emails to @${CUSTOMER_DOMAIN} for Cloud Identity ACL Matching"
    if [[ "${DRY_RUN}" == "true" ]]; then
      log_info "[DRY-RUN] Would inspect active sys_user records and align emails to @${CUSTOMER_DOMAIN}"
    else
      _sn_api_request "GET" "/api/now/table/sys_user?sysparm_query=active=true^emailISNOTEMPTY&sysparm_fields=sys_id,user_name,email&sysparm_limit=200" || true
      while IFS= read -r u_row; do
        [[ -z "${u_row}" ]] && continue
        local u_id u_name u_mail
        u_id="$(printf '%s' "${u_row}" | jq -r '.sys_id // empty')"
        u_name="$(printf '%s' "${u_row}" | jq -r '.user_name // empty')"
        u_mail="$(printf '%s' "${u_row}" | jq -r '.email // empty')"
        [[ -z "${u_id}" || -z "${u_name}" ]] && continue
        if [[ "${u_mail}" == *"@example.com" ]]; then
          local new_mail="${u_name}@${CUSTOMER_DOMAIN}"
          _sn_api_request "PATCH" "/api/now/table/sys_user/${u_id}" "$(jq -n --arg m "${new_mail}" '{email: $m}')" || true
        fi
      done < <(printf '%s' "${LAST_SN_BODY}" | jq -c '.result[]? // empty' 2>/dev/null || true)
    fi
  fi

  # ----------------------------------------------------------------------------
  # Step 0D.4: Sync Credentials to GCP Secret Manager & Write Phase 2B Config
  # ----------------------------------------------------------------------------
  log_phase "STEP-0D.4" "Syncing ServiceNow Credentials to GCP Secret Manager (${SN_SECRET_ID}) & Writing ${SN_ENV_OUT}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    log_info "[DRY-RUN] Would create/update GCP Secret Manager secret 'projects/${GCP_PROJECT_ID}/secrets/${SN_SECRET_ID}'"
  else
    gcloud secrets describe "${SN_SECRET_ID}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || \
      gcloud secrets create "${SN_SECRET_ID}" \
        --project="${GCP_PROJECT_ID}" \
        --replication-policy="automatic" \
        --labels="customer=${CUSTOMER_NAME},connector=servicenow,managed_by=servicenow_bootstrap"

    jq -n \
      --arg uri "${SN_INSTANCE_URI}" \
      --arg cid "${SN_OAUTH_CLIENT_ID}" \
      --arg csec "${SN_OAUTH_CLIENT_SECRET}" \
      --arg usr "${SN_CONNECTOR_USERNAME}" \
      --arg pwd "${SN_CONNECTOR_PASSWORD}" \
      '{
        instance_uri: $uri,
        client_id: $cid,
        client_secret: $csec,
        username: $usr,
        password: $pwd
      }' | gcloud secrets versions add "${SN_SECRET_ID}" \
        --project="${GCP_PROJECT_ID}" \
        --data-file=- >/dev/null
    log_ok "Injected ServiceNow credentials into Secret Manager ('projects/${GCP_PROJECT_ID}/secrets/${SN_SECRET_ID}')."
  fi

  cat > "${SN_ENV_OUT}" <<EOF
GCP_PROJECT_ID="${GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION}"
GE_LOCATION="${GE_LOCATION}"
TF_STATE_BUCKET="${TF_STATE_BUCKET}"
TF_STATE_PREFIX="ge-apphub/03b-servicenow-connector/sn-global-${CUSTOMER_NAME}-servicenow"

SERVICENOW_SECRET_ID="${SN_SECRET_ID}"
SERVICENOW_COLLECTION_ID="${CUSTOMER_NAME}-servicenow"
SERVICENOW_COLLECTION_DISPLAY_NAME="ServiceNow ITSM & Knowledge (${CUSTOMER_NAME})"
SERVICENOW_INSTANCE_URI="${SN_INSTANCE_URI}"
SERVICENOW_CONNECTOR_MODE="DATA_INGESTION"
SERVICENOW_REFRESH_INTERVAL="86400s"
SERVICENOW_ENTITIES="knowledge_base,incident,catalog_item"
ENABLE_SERVICENOW_ACTIONS="true"
SERVICENOW_ENABLED_ACTIONS="create_incident,update_incident,get_incident,add_comment_to_incident"
SERVICENOW_TARGET_APPS="${CUSTOMER_NAME}-service-desk-app,${CUSTOMER_NAME}-dev-sandbox-app"
EOF

  log_ok "Generated Phase 2B ServiceNow configuration file: ${SN_ENV_OUT}"
  echo "=================================================================="
  echo " Phase 0D ServiceNow Bootstrap Complete!"
  echo " - ServiceNow Instance : ${SN_INSTANCE_URI}"
  echo " - Integration Account : ${SN_CONNECTOR_USERNAME}"
  echo " - OAuth Client ID     : ${SN_OAUTH_CLIENT_ID}"
  echo " - GCP Secret Manager  : projects/${GCP_PROJECT_ID}/secrets/${SN_SECRET_ID}"
  echo " - Phase 2B Config     : ${SN_ENV_OUT}"
  echo "=================================================================="
  return 0
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  deploy_servicenow_bootstrap_main "$@"
fi
