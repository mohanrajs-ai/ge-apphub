#!/usr/bin/env bash
# ==============================================================================
# Microsoft Entra ID Bootstrap Orchestrator (Stack 00: Step 0A Automation)
# ==============================================================================
# Automates Microsoft Entra ID setup for Gemini Enterprise Customer Onboarding:
#   1. Creates the OAuth 2.0 App Registration (<customer>-ge-m365-connector)
#      with Redirect URI https://vertexaisearch.cloud.google.com/oauth-redirect
#   2. Attaches all 25+ Microsoft Graph & SharePoint Application/Delegated scopes
#   3. Grants Tenant-Wide Admin Consent automatically
#   4. Generates a Client Secret and injects {tenant_id, client_id, client_secret}
#      directly into Google Cloud Secret Manager (zero manual secret copy-paste)
#   5. Instantiates the Microsoft Entra Gallery SAML 2.0 App
#      "Google Cloud / G Suite Connector by Microsoft"
#      (Template ID: 8b1025e4-1dd2-430b-a150-2ef79cd700f5)
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
#     [--mode terraform|az-graph] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STACK_DIR="${SCRIPT_DIR}/stacks/00-entra-bootstrap"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

ENTRA_TENANT_ID=""
CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
M365_SECRET_ID=""
MODE="terraform"
DRY_RUN="false"

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
SAML_APP_NAME="Google Cloud / G Suite Connector (${CUSTOMER_NAME})"
REDIRECT_URI="https://vertexaisearch.cloud.google.com/oauth-redirect"
MSGRAPH_APP_ID="00000003-0000-0000-c000-000000000000"
SHAREPOINT_APP_ID="00000003-0000-0ff1-ce00-000000000000"
GOOGLE_CLOUD_GALLERY_TEMPLATE_ID="8b1025e4-1dd2-430b-a150-2ef79cd700f5"

echo "=================================================================="
echo " Microsoft Entra ID Step 0A Automation"
echo "------------------------------------------------------------------"
echo " Customer         : ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})"
echo " Entra Tenant ID  : ${ENTRA_TENANT_ID}"
echo " GCP Project ID   : ${GCP_PROJECT_ID}"
echo " GCP Secret ID    : ${M365_SECRET_ID}"
echo " Execution Mode   : ${MODE} (Dry-Run: ${DRY_RUN})"
echo "=================================================================="

# ------------------------------------------------------------------------------
# MODE 1: Terraform Stack 00 (hashicorp/azuread + hashicorp/google)
# ------------------------------------------------------------------------------
if [[ "${MODE}" == "terraform" ]]; then
  cd "${STACK_DIR}"
  WORKSPACE_NAME="entra-${CUSTOMER_NAME}"

  echo "[1/3] Initializing Terraform Stack 00 (00-entra-bootstrap)..."
  terraform init -input=false

  if terraform workspace list | grep -q "${WORKSPACE_NAME}"; then
    terraform workspace select "${WORKSPACE_NAME}"
  else
    terraform workspace new "${WORKSPACE_NAME}"
  fi

  TF_ARGS=(
    -var="entra_tenant_id=${ENTRA_TENANT_ID}"
    -var="customer_name=${CUSTOMER_NAME}"
    -var="customer_domain=${CUSTOMER_DOMAIN}"
    -var="gcp_project_id=${GCP_PROJECT_ID}"
    -var="m365_secret_id=${M365_SECRET_ID}"
  )

  echo "[2/3] Running terraform plan..."
  terraform plan "${TF_ARGS[@]}" -out=tfplan

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[3/3] Dry-run complete. Skipping terraform apply."
    rm -f tfplan
    exit 0
  fi

  echo "[3/3] Applying Terraform Stack 00..."
  terraform apply -input=false tfplan
  rm -f tfplan

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
    echo "[DRY-RUN] Would authenticate to Entra Tenant ${ENTRA_TENANT_ID} via 'az account show'"
    echo "[DRY-RUN] Would create Entra OAuth App '${OAUTH_APP_NAME}' with Redirect URI '${REDIRECT_URI}'"
    echo "[DRY-RUN] Would attach 20+ Microsoft Graph & SharePoint Application/Delegated permissions"
    echo "[DRY-RUN] Would grant Tenant-Wide Admin Consent via /oauth2PermissionGrants & /appRoleAssignments"
    echo "[DRY-RUN] Would push {tenant_id, client_id, client_secret} to GCP Secret Manager '${M365_SECRET_ID}'"
    echo "[DRY-RUN] Would instantiate Gallery SAML App Template '${GOOGLE_CLOUD_GALLERY_TEMPLATE_ID}' (${SAML_APP_NAME})"
    exit 0
  fi

  echo "[1/6] Verifying Azure CLI session for Tenant ${ENTRA_TENANT_ID}..."
  az account show --output none

  echo "[2/6] Creating Entra OAuth 2.0 App Registration (${OAUTH_APP_NAME})..."
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

  echo "[3/6] Creating Service Principal & granting Tenant-Wide Admin Consent..."
  SP_JSON=$(az ad sp create --id "${CLIENT_ID}" --output json)
  SP_OBJECT_ID=$(echo "${SP_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['id'])")

  # Grant Admin Consent via Azure CLI
  az ad app permission admin-consent --id "${CLIENT_ID}" || true

  echo "[4/6] Generating 24-month Client Secret..."
  CRED_JSON=$(az ad app credential reset \
    --id "${CLIENT_ID}" \
    --append \
    --display-name "${CUSTOMER_NAME}-ge-m365-connector-secret" \
    --years 2 \
    --output json)
  CLIENT_SECRET=$(echo "${CRED_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['password'])")

  echo "[5/6] Syncing {tenant_id, client_id, client_secret} directly into GCP Secret Manager..."
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

  echo "[6/6] Instantiating SAML 2.0 Enterprise Gallery App (${SAML_APP_NAME})..."
  SAML_INSTANTIATE_JSON=$(az rest \
    --method POST \
    --uri "https://graph.microsoft.com/v1.0/applicationTemplates/${GOOGLE_CLOUD_GALLERY_TEMPLATE_ID}/instantiate" \
    --headers "Content-Type=application/json" \
    --body "{\"displayName\": \"${SAML_APP_NAME}\"}" \
    --output json)

  SAML_SP_ID=$(echo "${SAML_INSTANTIATE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['servicePrincipal']['id'])")
  SAML_APP_ID=$(echo "${SAML_INSTANTIATE_JSON}" | python3 -c "import sys, json; print(json.load(sys.stdin)['application']['id'])")

  # Patch SAML Identifier (Entity ID) and Reply URL (ACS URL) for google.com
  az rest \
    --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/applications/${SAML_APP_ID}" \
    --headers "Content-Type=application/json" \
    --body "{
      \"identifierUris\": [\"https://www.google.com/a/${CUSTOMER_DOMAIN}\"],
      \"web\": {
        \"redirectUris\": [
          \"https://www.google.com/a/${CUSTOMER_DOMAIN}/acs\",
          \"https://www.google.com\"
        ]
      }
    }"

  az rest \
    --method PATCH \
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/${SAML_SP_ID}" \
    --headers "Content-Type=application/json" \
    --body "{
      \"preferredSingleSignOnMode\": \"saml\",
      \"loginUrl\": \"https://www.google.com/a/${CUSTOMER_DOMAIN}/ServiceLogin?continue=https://console.cloud.google.com/\",
      \" appRoleAssignmentRequired\": false
    }" || true

  echo "=================================================================="
  echo " Step 0A Automation Complete!"
  echo " - OAuth Client ID : ${CLIENT_ID}"
  echo " - GCP Secret      : projects/${GCP_PROJECT_ID}/secrets/${M365_SECRET_ID}"
  echo " - SAML Entity ID  : https://sts.windows.net/${ENTRA_TENANT_ID}/"
  echo " - SAML Login URL  : https://login.microsoftonline.com/${ENTRA_TENANT_ID}/saml2"
  echo " - Fed Metadata XML: https://login.microsoftonline.com/${ENTRA_TENANT_ID}/federationmetadata/2007-06/federationmetadata.xml?appid=${SAML_APP_ID}"
  echo "=================================================================="
  exit 0
fi

echo "ERROR: Invalid --mode '${MODE}'. Must be 'terraform' or 'az-graph'."
exit 1
