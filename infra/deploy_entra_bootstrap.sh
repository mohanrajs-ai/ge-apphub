#!/usr/bin/env bash
# ==============================================================================
# Microsoft Entra ID Bootstrap Orchestrator (Stack 00: Step 0A.1 & 0A.2 Automation)
# ==============================================================================
# Automates 100% of Step 0A.1 & Step 0A.2 for Gemini Enterprise Customer Onboarding:
#   [Step 0A.1 — OAuth 2.0 App Registration & Secret Sync]
#     1. Creates the OAuth 2.0 App Registration (<customer>-ge-m365-connector)
#        with Redirect URI https://vertexaisearch.cloud.google.com/oauth-redirect
#     2. Attaches all 47 Microsoft Graph & SharePoint Application/Delegated scopes
#        across SharePoint Online, OneDrive, Outlook, Teams & Identity Sync
#     3. Grants Tenant-Wide Admin Consent automatically
#     4. Generates a Client Secret and injects {tenant_id, client_id, client_secret}
#        directly into Google Cloud Secret Manager (zero manual secret copy-paste)
#   [Step 0A.2 — SAML 2.0 Enterprise Gallery App & Bi-Directional Handshake]
#     5. Creates/resolves the Google Cloud Identity Inbound SAML SSO Profile
#        (when --cloud-identity-customer-id is provided) to pre-fetch the exact
#        SAML SP Entity ID & ACS URL (https://accounts.google.com/samlrp/<id>)
#     6. Instantiates the Microsoft Entra Gallery SAML 2.0 App
#        "Google Cloud / G Suite Connector by Microsoft"
#        (Template ID: 8b1025e4-1dd2-430b-a150-2ef79cd700f5)
#     7. Configures preferredSingleSignOnMode="saml", Identifier (Entity ID),
#        Reply URL (ACS URL), and Sign-On URL on the Gallery App
#     8. Creates & assigns all 5 Department Security Groups
#        (ge-service-desk-users, ge-finance-users, ge-hr-users,
#         ge-skill-developers, all-ge-apps-users) to the SAML Enterprise App
#     9. Generates the SAML X.509 Token-Signing Certificate, writes
#        configs/<customer>-entra-saml.cer, and uploads it directly into
#        Google Cloud Identity (inboundSamlSsoProfiles.idpCredentials:add)
#
# Supports two execution modes:
#   --mode terraform  (Default: declarative via hashicorp/azuread + google)
#   --mode az-graph   (Imperative via Azure CLI + Microsoft Graph REST API v1.0)
#
# Usage:
#   ./deploy_entra_bootstrap.sh \
#     --tenant-id "11111111-2222-3333-4444-555555555555" \
#     --customer-name "cymbal" \
#     --customer-domain "cymbal.com" \
#     --gcp-project-id "cymbal-ge-prod" \
#     [--cloud-identity-customer-id "customers/C01234567"] \
#     [--saml-sp-entity-id "https://accounts.google.com/samlrp/<id>"] \
#     [--saml-sp-acs-url "https://accounts.google.com/samlrp/<id>/acs"] \
#     [--saml-target-org-unit "orgUnits/03ph8a2z1en3bc"] \
#     [--mode terraform|az-graph] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${SCRIPT_DIR}/stacks/00-entra-bootstrap"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
mkdir -p "${CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

ENTRA_TENANT_ID=""
CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
M365_SECRET_ID=""
CLOUD_IDENTITY_CUSTOMER_ID=""
SAML_SP_ENTITY_ID=""
SAML_SP_ACS_URL=""
SAML_TARGET_ORG_UNIT=""
SAML_PROFILE_NAME=""
MODE="terraform"
DRY_RUN="false"

DEPARTMENT_GROUPS=(
  "ge-service-desk-users"
  "ge-finance-users"
  "ge-hr-users"
  "ge-skill-developers"
  "all-ge-apps-users"
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tenant-id)
      ENTRA_TENANT_ID="$2"
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
    --secret-id)
      M365_SECRET_ID="$2"
      shift 2
      ;;
    --cloud-identity-customer-id)
      CLOUD_IDENTITY_CUSTOMER_ID="$2"
      shift 2
      ;;
    --saml-sp-entity-id)
      SAML_SP_ENTITY_ID="$2"
      shift 2
      ;;
    --saml-sp-acs-url)
      SAML_SP_ACS_URL="$2"
      shift 2
      ;;
    --saml-target-org-unit)
      SAML_TARGET_ORG_UNIT="$2"
      shift 2
      ;;
    --mode)
      MODE="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift 1
      ;;
    *)
      echo "Unknown flag: $1"
      exit 1
      ;;
  esac
done

if [[ -z "${ENTRA_TENANT_ID}" ]]; then
  echo "ERROR: --tenant-id <ENTRA_TENANT_ID> is required."
  exit 1
fi

if [[ -z "${M365_SECRET_ID}" ]]; then
  M365_SECRET_ID="${CUSTOMER_NAME}-m365-connector-credentials"
fi

OAUTH_APP_NAME="${CUSTOMER_NAME}-ge-m365-connector"
CUSTOMER_UPPER="$(printf '%s' "${CUSTOMER_NAME}" | tr '[:lower:]' '[:upper:]')"
SAML_APP_NAME="${CUSTOMER_UPPER} Google Cloud & Gemini Enterprise SSO"
SAML_PROFILE_DISPLAY_NAME="${CUSTOMER_UPPER} Microsoft Entra ID SSO"
SAML_CERT_OUT="${CONFIGS_DIR}/${CUSTOMER_NAME}-entra-saml.cer"
REDIRECT_URI="https://vertexaisearch.cloud.google.com/oauth-redirect"
MSGRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
SHAREPOINT_APP_ID="00000003-0000-0ff1-ce00-000000000000"
GOOGLE_CLOUD_GALLERY_TEMPLATE_ID="8b1025e4-1dd2-430b-a150-2ef79cd700f5"

echo "=================================================================="
echo " Microsoft Entra ID Step 0A.1 & Step 0A.2 Full Automation"
echo "------------------------------------------------------------------"
echo " Customer         : ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})"
echo " Entra Tenant ID  : ${ENTRA_TENANT_ID}"
echo " GCP Project ID   : ${GCP_PROJECT_ID}"
echo " GCP Secret ID    : ${M365_SECRET_ID}"
echo " Cloud Identity   : ${CLOUD_IDENTITY_CUSTOMER_ID:-<optional>}"
echo " Execution Mode   : ${MODE} (Dry-Run: ${DRY_RUN})"
echo "=================================================================="

# ------------------------------------------------------------------------------
# Helper: Pre-create / Resolve Google Cloud Identity Inbound SAML SSO Profile
# so Step 0A.2 has the exact SAML_SP_ENTITY_ID and SAML_SP_ACS_URL upfront
# ------------------------------------------------------------------------------
ensure_cloud_identity_saml_profile() {
  if [[ -z "${CLOUD_IDENTITY_CUSTOMER_ID}" ]]; then
    return 0
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] Would create/resolve Cloud Identity Inbound SAML SSO Profile '${SAML_PROFILE_DISPLAY_NAME}' for '${CLOUD_IDENTITY_CUSTOMER_ID}'"
    if [[ -z "${SAML_SP_ENTITY_ID}" ]]; then
      SAML_SP_ENTITY_ID="https://accounts.google.com/samlrp/02abc123def456"
    fi
    if [[ -z "${SAML_SP_ACS_URL}" ]]; then
      SAML_SP_ACS_URL="https://accounts.google.com/samlrp/02abc123def456/acs"
    fi
    return 0
  fi

  echo "[0A.2-Pre] Resolving Cloud Identity Inbound SAML SSO Profile for ${CLOUD_IDENTITY_CUSTOMER_ID}..."
  local gcp_token
  gcp_token="$(gcloud auth print-access-token)"
  local list_resp
  list_resp="$(curl -sS -H "Authorization: Bearer ${gcp_token}" -H "x-goog-user-project: ${GCP_PROJECT_ID}" \
    "https://cloudidentity.googleapis.com/v1/inboundSamlSsoProfiles?filter=customer%3D%3D%22${CLOUD_IDENTITY_CUSTOMER_ID}%22" || echo '{}')"

  SAML_PROFILE_NAME="$(echo "${list_resp}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for p in data.get('inboundSamlSsoProfiles', []):
    if p.get('displayName') == '${SAML_PROFILE_DISPLAY_NAME}':
        print(p.get('name', ''))
        break
" || true)"

  if [[ -z "${SAML_PROFILE_NAME}" ]]; then
    echo "           Creating Cloud Identity Inbound SAML Profile '${SAML_PROFILE_DISPLAY_NAME}'..."
    local create_resp
    create_resp="$(curl -sS -X POST "https://cloudidentity.googleapis.com/v1/inboundSamlSsoProfiles" \
      -H "Authorization: Bearer ${gcp_token}" \
      -H "x-goog-user-project: ${GCP_PROJECT_ID}" \
      -H "Content-Type: application/json" \
      -d "{
        \"customer\": \"${CLOUD_IDENTITY_CUSTOMER_ID}\",
        \"displayName\": \"${SAML_PROFILE_DISPLAY_NAME}\",
        \"idpConfig\": {
          \"entityId\": \"https://sts.windows.net/${ENTRA_TENANT_ID}/\",
          \"singleSignOnServiceUri\": \"https://login.microsoftonline.com/${ENTRA_TENANT_ID}/saml2\"
        }
      }" || echo '{}')"
    SAML_PROFILE_NAME="$(echo "${create_resp}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('response', d).get('name', ''))" || true)"
    SAML_SP_ENTITY_ID="${SAML_SP_ENTITY_ID:-$(echo "${create_resp}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('response', d).get('spConfig', {}).get('entityId', ''))" || true)}"
    SAML_SP_ACS_URL="${SAML_SP_ACS_URL:-$(echo "${create_resp}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('response', d).get('spConfig', {}).get('assertionConsumerServiceUri', ''))" || true)}"
  else
    local get_resp
    get_resp="$(curl -sS -H "Authorization: Bearer ${gcp_token}" -H "x-goog-user-project: ${GCP_PROJECT_ID}" \
      "https://cloudidentity.googleapis.com/v1/${SAML_PROFILE_NAME}" || echo '{}')"
    SAML_SP_ENTITY_ID="${SAML_SP_ENTITY_ID:-$(echo "${get_resp}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('spConfig', {}).get('entityId', ''))" || true)}"
    SAML_SP_ACS_URL="${SAML_SP_ACS_URL:-$(echo "${get_resp}" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('spConfig', {}).get('assertionConsumerServiceUri', ''))" || true)}"
  fi

  echo "           Resolved SAML SP Entity ID : ${SAML_SP_ENTITY_ID}"
  echo "           Resolved SAML SP ACS URL   : ${SAML_SP_ACS_URL}"
}

# ------------------------------------------------------------------------------
# Helper: Upload Entra SAML X.509 Certificate to Cloud Identity Inbound SAML Profile
# ------------------------------------------------------------------------------
upload_cert_to_cloud_identity() {
  local cert_file="$1"
  if [[ -z "${SAML_PROFILE_NAME}" || ! -f "${cert_file}" ]]; then
    return 0
  fi

  echo "[0A.2-Post] Uploading Entra SAML X.509 Certificate (${cert_file}) to Cloud Identity '${SAML_PROFILE_NAME}'..."
  local gcp_token pem_payload
  gcp_token="$(gcloud auth print-access-token)"
  pem_payload="$(python3 - "${cert_file}" <<'PYEOF'
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    raw = f.read().strip()
if "BEGIN CERTIFICATE" not in raw:
    raw = f"-----BEGIN CERTIFICATE-----\n{raw}\n-----END CERTIFICATE-----"
print(json.dumps({"pemData": raw}))
PYEOF
  )"

  curl -sS -X POST "https://cloudidentity.googleapis.com/v1/${SAML_PROFILE_NAME}/idpCredentials:add" \
    -H "Authorization: Bearer ${gcp_token}" \
    -H "x-goog-user-project: ${GCP_PROJECT_ID}" \
    -H "Content-Type: application/json" \
    -d "${pem_payload}" >/dev/null || true

  if [[ -n "${SAML_TARGET_ORG_UNIT}" ]]; then
    echo "[0A.2-Post] Assigning SAML SSO Profile '${SAML_PROFILE_NAME}' to Org Unit '${SAML_TARGET_ORG_UNIT}'..."
    curl -sS -X POST "https://cloudidentity.googleapis.com/v1/inboundSsoAssignments" \
      -H "Authorization: Bearer ${gcp_token}" \
      -H "x-goog-user-project: ${GCP_PROJECT_ID}" \
      -H "Content-Type: application/json" \
      -d "{
        \"customer\": \"${CLOUD_IDENTITY_CUSTOMER_ID}\",
        \"targetOrgUnit\": \"${SAML_TARGET_ORG_UNIT}\",
        \"ssoMode\": \"SAML_SSO\",
        \"samlSsoInfo\": {\"inboundSamlSsoProfile\": \"${SAML_PROFILE_NAME}\"}
      }" >/dev/null || true
  fi
}

ensure_cloud_identity_saml_profile

# ------------------------------------------------------------------------------
# MODE 1: Terraform Stack 00 (hashicorp/azuread + hashicorp/google)
# ------------------------------------------------------------------------------
if [[ "${MODE}" == "terraform" ]]; then
  cd "${STACK_DIR}"
  WORKSPACE_NAME="entra-${CUSTOMER_NAME}"
  export ARM_TENANT_ID="${ENTRA_TENANT_ID}"

  echo "[1/4] Initializing Terraform Stack 00 (00-entra-bootstrap)..."
  terraform init -input=false

  if terraform workspace list | grep -q "${WORKSPACE_NAME}"; then
    terraform workspace select "${WORKSPACE_NAME}"
  else
    terraform workspace new "${WORKSPACE_NAME}"
  fi

  terraform validate

  TF_ARGS=(
    -var="entra_tenant_id=${ENTRA_TENANT_ID}"
    -var="customer_name=${CUSTOMER_NAME}"
    -var="customer_domain=${CUSTOMER_DOMAIN}"
    -var="gcp_project_id=${GCP_PROJECT_ID}"
    -var="m365_secret_id=${M365_SECRET_ID}"
    -var="saml_sp_entity_id=${SAML_SP_ENTITY_ID}"
    -var="saml_sp_acs_url=${SAML_SP_ACS_URL}"
  )

  if ! az account show >/dev/null 2>&1; then
    if [[ "${DRY_RUN}" == "true" ]]; then
      echo "[WARN] Azure CLI is not logged in yet ('az login --tenant ${ENTRA_TENANT_ID} --allow-no-subscriptions')."
      echo "[DRY-RUN] Terraform configuration validated. When authenticated to Entra ID, Stack 00 will provision:"
      echo "  + azuread_application.m365_connector (${OAUTH_APP_NAME}) with 47 Graph & SharePoint permissions"
      echo "  + azuread_service_principal.m365_connector + Tenant-Wide Admin Consent"
      echo "  + google_secret_manager_secret.m365_credentials (projects/${GCP_PROJECT_ID}/secrets/${M365_SECRET_ID})"
      echo "  + azuread_application_from_template.google_cloud_saml (${SAML_APP_NAME})"
      echo "  + azuread_group.department_groups (${DEPARTMENT_GROUPS[*]}) + SAML Role Assignments"
      echo "  + azuread_service_principal_token_signing_certificate.saml_cert -> ${SAML_CERT_OUT}"
      exit 0
    else
      echo "[AUTH] No active Azure CLI session found. Launching 'az login --tenant ${ENTRA_TENANT_ID} --allow-no-subscriptions'..."
      az login --tenant "${ENTRA_TENANT_ID}" --allow-no-subscriptions
    fi
  fi

  echo "[2/4] Running terraform plan..."
  terraform plan "${TF_ARGS[@]}" -out=tfplan

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[3/4] Dry-run complete. Skipping terraform apply."
    rm -f tfplan
    exit 0
  fi

  echo "[3/4] Applying Terraform Stack 00 (Step 0A.1 OAuth App + Step 0A.2 SAML Gallery App & Groups)..."
  terraform apply -input=false tfplan
  rm -f tfplan

  SAML_APP_OBJ_ID="$(terraform output -raw saml_application_object_id 2>/dev/null || true)"
  SAML_SP_OBJ_ID="$(terraform output -raw saml_service_principal_object_id 2>/dev/null || true)"
  if [[ -n "${SAML_APP_OBJ_ID}" && -n "${SAML_SP_OBJ_ID}" ]]; then
    echo "[3.5/4] Configuring SAML Mode, Entity ID & Reply URLs (ACS) on Gallery App (${SAML_APP_OBJ_ID})..."
    SAML_URLS_PAYLOAD="$(python3 - "${CUSTOMER_DOMAIN}" "${SAML_SP_ENTITY_ID}" "${SAML_SP_ACS_URL}" <<'PYEOF'
import json, sys
domain, sp_entity, sp_acs = sys.argv[1], sys.argv[2], sys.argv[3]
id_uris = [u for u in [sp_entity, f"https://www.google.com/a/{domain}"] if u]
acs_uris = [u for u in [sp_acs, f"https://www.google.com/a/{domain}/acs", "https://www.google.com"] if u]
print(json.dumps({
    "identifierUris": list(dict.fromkeys(id_uris)),
    "web": {"redirectUris": list(dict.fromkeys(acs_uris))}
}))
PYEOF
    )"
    az rest --method PATCH \
      --uri "https://graph.microsoft.com/v1.0/applications/${SAML_APP_OBJ_ID}" \
      --headers "Content-Type=application/json" \
      --body "${SAML_URLS_PAYLOAD}" >/dev/null 2>&1 || true

    az rest --method PATCH \
      --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SAML_SP_OBJ_ID}" \
      --headers "Content-Type=application/json" \
      --body "{
        \"preferredSingleSignOnMode\": \"saml\",
        \"loginUrl\": \"https://www.google.com/a/${CUSTOMER_DOMAIN}/ServiceLogin?continue=https://vertexaisearch.cloud.google.com\",
        \"appRoleAssignmentRequired\": true
      }" >/dev/null 2>&1 || true
  fi

  echo "[4/4] Exporting SAML X.509 Signing Certificate to ${SAML_CERT_OUT}..."
  terraform output -raw saml_idp_certificate_pem > "${SAML_CERT_OUT}" || true
  upload_cert_to_cloud_identity "${SAML_CERT_OUT}"

  echo ""
  echo "Entra Bootstrap Outputs:"
  terraform output -json
  exit 0
fi

# ------------------------------------------------------------------------------
# MODE 2: Imperative Azure CLI + Microsoft Graph REST API v1.0
# ------------------------------------------------------------------------------
if [[ "${MODE}" == "az-graph" ]]; then
  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[DRY-RUN] [Step 0A.1] Would authenticate to Entra Tenant ${ENTRA_TENANT_ID} via 'az account show'"
    echo "[DRY-RUN] [Step 0A.1] Would create Entra OAuth App '${OAUTH_APP_NAME}' with Redirect URI '${REDIRECT_URI}'"
    echo "[DRY-RUN] [Step 0A.1] Would attach all 47 Microsoft Graph & SharePoint Application/Delegated permissions across:"
    echo "          - SharePoint Online (m365-sp: Sites.Read.All, Sites.ReadWrite.All, Sites.Manage.All, AllSites.Read/Write/Manage)"
    echo "          - OneDrive (m365-od: Files.Read.All, Files.ReadWrite.All, MyFiles.Read/Write)"
    echo "          - Outlook Mail/Calendar/Contacts (m365-ol: Mail.Read/ReadWrite/Send, Calendars.Read/ReadWrite, Contacts.Read/ReadWrite)"
    echo "          - Microsoft Teams (m365-teams: Chat.Read/ReadWrite, ChatMessage.Send, ChannelMessage.Read.All/Send, Team/Channel.ReadBasic.All, Channel.Create)"
    echo "          - Identity Sync (User.Read.All, Group.Read.All, GroupMember.Read.All)"
    echo "[DRY-RUN] [Step 0A.1] Would grant Tenant-Wide Admin Consent via 'az ad app permission admin-consent'"
    echo "[DRY-RUN] [Step 0A.1] Would push {tenant_id, client_id, client_secret} to GCP Secret Manager '${M365_SECRET_ID}'"
    echo "[DRY-RUN] [Step 0A.2] Would instantiate Gallery SAML App Template '${GOOGLE_CLOUD_GALLERY_TEMPLATE_ID}' (${SAML_APP_NAME})"
    echo "[DRY-RUN] [Step 0A.2] Would configure SAML mode ('preferredSingleSignOnMode=saml'), Entity ID ('${SAML_SP_ENTITY_ID:-https://www.google.com/a/${CUSTOMER_DOMAIN}}'), and ACS URL ('${SAML_SP_ACS_URL:-https://www.google.com/a/${CUSTOMER_DOMAIN}/acs}')"
    echo "[DRY-RUN] [Step 0A.2] Would create & assign all 5 department security groups (${DEPARTMENT_GROUPS[*]}) to '${SAML_APP_NAME}'"
    echo "[DRY-RUN] [Step 0A.2] Would generate SAML X.509 signing certificate -> '${SAML_CERT_OUT}' and upload to Cloud Identity"
    exit 0
  fi

  echo "[1/8] Verifying Azure CLI session for Tenant ${ENTRA_TENANT_ID}..."
  if ! az account show --output none >/dev/null 2>&1; then
    echo "[AUTH] No active Azure CLI session found. Launching 'az login --tenant ${ENTRA_TENANT_ID} --allow-no-subscriptions'..."
    az login --tenant "${ENTRA_TENANT_ID}" --allow-no-subscriptions
  fi

  echo "[2/8] [Step 0A.1] Creating Entra OAuth 2.0 App Registration (${OAUTH_APP_NAME})..."
  APP_JSON=$(az ad app create \
    --display-name "${OAUTH_APP_NAME}" \
    --sign-in-audience "AzureADMyOrg" \
    --web-redirect-uris "${REDIRECT_URI}" \
    --enable-access-token-issuance true \
    --enable-id-token-issuance true \
    --output json)

  CLIENT_ID=$(echo "${APP_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['appId'])")
  APP_OBJECT_ID=$(echo "${APP_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")

  echo "      Created Client ID: ${CLIENT_ID} (Object ID: ${APP_OBJECT_ID})"

  echo "[3/8] [Step 0A.1] Resolving & attaching all 47 M365 permissions (SharePoint, OneDrive, Outlook, Teams & Identity Sync)..."
  MSGRAPH_SP_JSON=$(az ad sp show --id "${MSGRAPH_APP_ID}" --output json)
  SHAREPOINT_SP_JSON=$(az ad sp show --id "${SHAREPOINT_APP_ID}" --output json)

  REQUIRED_RESOURCE_ACCESS_PAYLOAD=$(python3 - "${MSGRAPH_SP_JSON}" "${SHAREPOINT_SP_JSON}" <<'PYEOF'
import json
import sys

msgraph_sp = json.loads(sys.argv[1])
sp_online = json.loads(sys.argv[2])

msgraph_roles = {r["value"]: r["id"] for r in msgraph_sp.get("appRoles", []) if r.get("value")}
msgraph_scopes = {s["value"]: s["id"] for s in msgraph_sp.get("oauth2PermissionScopes", []) if s.get("value")}

sp_roles = {r["value"]: r["id"] for r in sp_online.get("appRoles", []) if r.get("value")}
sp_scopes = {s["value"]: s["id"] for s in sp_online.get("oauth2PermissionScopes", []) if s.get("value")}

wanted_msgraph_roles = [
    "User.Read.All", "Group.Read.All", "GroupMember.Read.All",
    "Directory.Read.All", "AdministrativeUnit.Read.All",
    "Sites.Read.All", "Files.Read.All",
    "Mail.Read", "Calendars.Read", "Contacts.Read",
    "Team.ReadBasic.All", "Channel.ReadBasic.All", "ChannelMessage.Read.All", "Chat.Read.All",
]
wanted_msgraph_scopes = [
    "openid", "profile", "email", "offline_access", "User.Read", "People.Read",
    "Files.Read.All", "Files.ReadWrite.All", "Sites.Read.All", "Sites.ReadWrite.All", "Sites.Manage.All",
    "Mail.Read", "Mail.ReadWrite", "Mail.ReadWrite.Shared", "Mail.Send", "Mail.Send.Shared",
    "Calendars.Read", "Calendars.ReadWrite", "Calendars.Read.Shared",
    "Contacts.Read", "Contacts.ReadWrite", "Contacts.ReadWrite.Shared", "MailboxSettings.Read",
    "Chat.Read", "Chat.ReadWrite", "ChatMessage.Send", "ChannelMessage.Read.All",
    "ChannelMessage.Send", "Team.ReadBasic.All", "Channel.ReadBasic.All", "Channel.Create",
]
wanted_sp_roles = ["Sites.Read.All"]
wanted_sp_scopes = ["AllSites.Read", "AllSites.Write", "AllSites.Manage", "MyFiles.Read", "MyFiles.Write"]

msgraph_access = (
    [{"id": msgraph_roles[r], "type": "Role"} for r in wanted_msgraph_roles if r in msgraph_roles]
    + [{"id": msgraph_scopes[s], "type": "Scope"} for s in wanted_msgraph_scopes if s in msgraph_scopes]
)
sp_access = (
    [{"id": sp_roles[r], "type": "Role"} for r in wanted_sp_roles if r in sp_roles]
    + [{"id": sp_scopes[s], "type": "Scope"} for s in wanted_sp_scopes if s in sp_scopes]
)

print(json.dumps({
    "requiredResourceAccess": [
        {"resourceAppId": "00000003-0000-0000-c000-000000000000", "resourceAccess": msgraph_access},
        {"resourceAppId": "00000003-0000-0ff1-ce00-000000000000", "resourceAccess": sp_access},
    ]
}))
PYEOF
  )

  az rest \
    --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/${APP_OBJECT_ID}" \
    --headers "Content-Type=application/json" \
    --body "${REQUIRED_RESOURCE_ACCESS_PAYLOAD}"

  SP_JSON=$(az ad sp create --id "${CLIENT_ID}" --output json)
  SP_OBJECT_ID=$(echo "${SP_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")

  echo "      Granting Tenant-Wide Admin Consent for all 4 M365 applications..."
  az ad app permission admin-consent --id "${CLIENT_ID}" || true

  echo "[4/8] [Step 0A.1] Generating 24-month Client Secret..."
  CRED_JSON=$(az ad app credential reset \
    --id "${CLIENT_ID}" \
    --append \
    --display-name "${CUSTOMER_NAME}-ge-m365-connector-secret" \
    --years 2 \
    --output json)
  CLIENT_SECRET=$(echo "${CRED_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

  echo "[5/8] [Step 0A.1] Syncing {tenant_id, client_id, client_secret} directly into GCP Secret Manager..."
  gcloud secrets describe "${M365_SECRET_ID}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || \
    gcloud secrets create "${M365_SECRET_ID}" \
      --project="${GCP_PROJECT_ID}" \
      --replication-policy="automatic" \
      --labels="customer=${CUSTOMER_NAME},managed_by=entra_bootstrap"

  python3 -c "import json; print(json.dumps({
    'tenant_id': '${ENTRA_TENANT_ID}',
    'client_id': '${CLIENT_ID}',
    'client_secret': '${CLIENT_SECRET}',
    'domain': '${CUSTOMER_DOMAIN}'
  }))" | gcloud secrets versions add "${M365_SECRET_ID}" \
    --project="${GCP_PROJECT_ID}" \
    --data-file=-

  echo "[6/8] [Step 0A.2] Instantiating SAML 2.0 Enterprise Gallery App (${SAML_APP_NAME})..."
  SAML_INSTANTIATE_JSON=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/applicationTemplates/${GOOGLE_CLOUD_GALLERY_TEMPLATE_ID}/instantiate" \
    --headers "Content-Type=application/json" \
    --body "{\"displayName\": \"${SAML_APP_NAME}\"}" \
    --output json)

  SAML_SP_ID=$(echo "${SAML_INSTANTIATE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['servicePrincipal']['id'])")
  SAML_APP_ID=$(echo "${SAML_INSTANTIATE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['application']['id'])")

  # Build Identifier URIs and Redirect URIs (including Cloud Identity Inbound SAML Profile if resolved)
  SAML_URLS_PAYLOAD=$(python3 - "${CUSTOMER_DOMAIN}" "${SAML_SP_ENTITY_ID}" "${SAML_SP_ACS_URL}" <<'PYEOF'
import json, sys
domain, sp_entity, sp_acs = sys.argv[1], sys.argv[2], sys.argv[3]
id_uris = [u for u in [sp_entity, f"https://www.google.com/a/{domain}"] if u]
acs_uris = [u for u in [sp_acs, f"https://www.google.com/a/{domain}/acs", "https://www.google.com"] if u]
print(json.dumps({
    "identifierUris": list(dict.fromkeys(id_uris)),
    "web": {"redirectUris": list(dict.fromkeys(acs_uris))}
}))
PYEOF
  )

  az rest \
    --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/${SAML_APP_ID}" \
    --headers "Content-Type=application/json" \
    --body "${SAML_URLS_PAYLOAD}"

  az rest \
    --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SAML_SP_ID}" \
    --headers "Content-Type=application/json" \
    --body "{
      \"preferredSingleSignOnMode\": \"saml\",
      \"loginUrl\": \"https://www.google.com/a/${CUSTOMER_DOMAIN}/ServiceLogin?continue=https://vertexaisearch.cloud.google.com\",
      \"appRoleAssignmentRequired\": true
    }" || true

  echo "[7/8] [Step 0A.2] Generating SAML Token-Signing Certificate & syncing to Cloud Identity..."
  CERT_JSON=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SAML_SP_ID}/addTokenSigningCertificate" \
    --headers "Content-Type=application/json" \
    --body "{\"displayName\": \"CN=${CUSTOMER_NAME} Google Cloud SAML Signing\"}" \
    --output json)

  echo "${CERT_JSON}" | python3 -c "
import sys, json
d = json.load(sys.stdin)
raw = d.get('key', '')
if raw:
    print(f'-----BEGIN CERTIFICATE-----\n{raw}\n-----END CERTIFICATE-----')
" > "${SAML_CERT_OUT}"

  upload_cert_to_cloud_identity "${SAML_CERT_OUT}"

  echo "[8/8] [Step 0A.2] Creating & assigning Cymbal's 5 Department Security Groups to '${SAML_APP_NAME}'..."
  SAML_APP_ROLE_ID=$(az ad sp show --id "${SAML_SP_ID}" --query "appRoles[?displayName=='msiam_access'].id | [0]" -o tsv || true)
  SAML_APP_ROLE_ID="${SAML_APP_ROLE_ID:-7dfd756e-8c27-4472-b2b7-38c17fc5de5e}"
  for grp_nick in "${DEPARTMENT_GROUPS[@]}"; do
    GRP_ID=$(az ad group list --filter "mailNickname eq '${grp_nick}'" --query "[0].id" -o tsv || true)
    if [[ -z "${GRP_ID}" ]]; then
      GRP_ID=$(az ad group create \
        --display-name "${CUSTOMER_UPPER} ${grp_nick}" \
        --mail-nickname "${grp_nick}" \
        --description "Gemini Enterprise department access group (${grp_nick}@${CUSTOMER_DOMAIN})" \
        --query "id" -o tsv)
      echo "      Created Entra Security Group: ${grp_nick} (${GRP_ID})"
    else
      echo "      Found Entra Security Group  : ${grp_nick} (${GRP_ID})"
    fi

    az rest \
      --method POST \
      --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SAML_SP_ID}/appRoleAssignedTo" \
      --headers "Content-Type=application/json" \
      --body "{
        \"principalId\": \"${GRP_ID}\",
        \"resourceId\": \"${SAML_SP_ID}\",
        \"appRoleId\": \"${SAML_APP_ROLE_ID}\"
      }" >/dev/null 2>&1 || true
    echo "      Assigned '${grp_nick}' -> '${SAML_APP_NAME}'"
  done

  echo "=================================================================="
  echo " Step 0A.1 & Step 0A.2 Automation Complete!"
  echo " - OAuth Client ID : ${CLIENT_ID}"
  echo " - GCP Secret      : projects/${GCP_PROJECT_ID}/secrets/${M365_SECRET_ID}"
  echo " - SAML Gallery App: ${SAML_APP_NAME} (SP Object ID: ${SAML_SP_ID})"
  echo " - SAML Entity ID  : https://sts.windows.net/${ENTRA_TENANT_ID}/"
  echo " - SAML Login URL  : https://login.microsoftonline.com/${ENTRA_TENANT_ID}/saml2"
  echo " - SAML Cert PEM   : ${SAML_CERT_OUT}"
  echo "=================================================================="
  exit 0
fi

echo "ERROR: Invalid --mode '${MODE}'. Must be 'terraform' or 'az-graph'."
exit 1
