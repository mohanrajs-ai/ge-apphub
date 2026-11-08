#!/usr/bin/env bash
# ==============================================================================
# Master End-to-End Customer Onboarding Orchestrator (onboard_customer.sh)
# ==============================================================================
# Chains all 7 onboarding phases for any enterprise customer (e.g., Cymbal):
#   - Phase 0C: GCP APIs & Remote Terraform State Bucket (gs://<customer>-ge-tfstate)
#   - Phase 0B: Google Admin & Cloud Identity Bootstrap (deploy_google_admin_bootstrap.sh)
#   - Phase 0A: Microsoft Entra ID OAuth + 47 M365 Scopes + SAML Gallery App (deploy_entra_bootstrap.sh)
#   - Phase 1 : Entra -> Cloud Identity 1:1 Group Sync & SAML Handshake (deploy_identity.sh)
#   - Phase 2 : Shared M365 Connectors — SharePoint, OneDrive, Outlook, Teams (deploy_m365.sh)
#   - Phase 3 : Departmental Gemini Enterprise Apps — Dev, Service Desk, Finance, HR (deploy.sh)
#   - Phase 4 : Universal ADK Skill Orchestrator Deploy & Pin (agents-cli deploy & publish)
#
# Usage:
#   ./onboard_customer.sh \
#     --customer-name "cymbal" \
#     --customer-domain "cymbal.com" \
#     --gcp-project-id "cymbal-ge-prod" \
#     --entra-tenant-id "11111111-2222-3333-4444-555555555555" \
#     [--dns-project-id "cymbal-dns-project"] \
#     [--dns-zone-name "cymbal-com-zone"] \
#     [--entra-mode terraform|az-graph] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
mkdir -p "${CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

CUSTOMER_NAME="cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
GCP_REGION="us-central1"
ENTRA_TENANT_ID=""
DNS_PROJECT_ID=""
DNS_ZONE_NAME=""
MEMBERS_CSV=""
ENTRA_MODE="terraform"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
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
    --entra-tenant-id|--tenant-id)
      ENTRA_TENANT_ID="$2"
      shift 2
      ;;
    --dns-project-id)
      DNS_PROJECT_ID="$2"
      shift 2
      ;;
    --dns-zone-name)
      DNS_ZONE_NAME="$2"
      shift 2
      ;;
    --members-csv)
      MEMBERS_CSV="$2"
      shift 2
      ;;
    --entra-mode)
      ENTRA_MODE="$2"
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
  echo "ERROR: --entra-tenant-id <UUID> is required."
  exit 1
fi

if [[ -z "${DNS_PROJECT_ID}" ]]; then
  DNS_PROJECT_ID="${GCP_PROJECT_ID}"
fi

TF_STATE_BUCKET="${CUSTOMER_NAME}-ge-tfstate"
M365_SECRET_ID="${CUSTOMER_NAME}-m365-connector-credentials"
DRY_RUN_FLAG=()
if [[ "${DRY_RUN}" == "true" ]]; then
  DRY_RUN_FLAG=(--dry-run)
fi

echo "=================================================================="
echo " Master End-to-End Customer Onboarding: ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})"
echo "------------------------------------------------------------------"
echo " App GCP Project : ${GCP_PROJECT_ID}"
echo " DNS GCP Project : ${DNS_PROJECT_ID}"
echo "=================================================================="

# ------------------------------------------------------------------------------
# Phase 0C: GCP APIs & Remote Terraform State Bucket
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 0C] Preparing GCP Project (${GCP_PROJECT_ID}) & State Bucket (gs://${TF_STATE_BUCKET})..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Would enable Cloud Resource Manager, Service Usage, Discovery Engine, Cloud Identity, Admin SDK, Secret Manager, Vertex AI & Agent Registry APIs on '${GCP_PROJECT_ID}'"
  if [[ "${DNS_PROJECT_ID}" != "${GCP_PROJECT_ID}" || -n "${DNS_ZONE_NAME}" ]]; then
    echo "[DRY-RUN] Would enable Cloud DNS API (dns.googleapis.com) on DNS project '${DNS_PROJECT_ID}'"
  fi
  echo "[DRY-RUN] Would create versioned GCS bucket gs://${TF_STATE_BUCKET}"
else
  gcloud services enable \
    cloudresourcemanager.googleapis.com \
    serviceusage.googleapis.com \
    discoveryengine.googleapis.com \
    cloudidentity.googleapis.com \
    admin.googleapis.com \
    siteverification.googleapis.com \
    secretmanager.googleapis.com \
    aiplatform.googleapis.com \
    agentregistry.googleapis.com \
    iam.googleapis.com \
    iamcredentials.googleapis.com \
    sts.googleapis.com \
    storage.googleapis.com \
    bigquery.googleapis.com \
    --project="${GCP_PROJECT_ID}"

  if [[ "${DNS_PROJECT_ID}" != "${GCP_PROJECT_ID}" || -n "${DNS_ZONE_NAME}" ]]; then
    echo ">>> [Phase 0C] Enabling Cloud DNS & Resource Manager APIs on DNS Project (${DNS_PROJECT_ID})..."
    gcloud services enable \
      cloudresourcemanager.googleapis.com \
      serviceusage.googleapis.com \
      dns.googleapis.com \
      --project="${DNS_PROJECT_ID}"
  fi

  gcloud storage buckets describe "gs://${TF_STATE_BUCKET}" --project="${GCP_PROJECT_ID}" >/dev/null 2>&1 || \
    gcloud storage buckets create "gs://${TF_STATE_BUCKET}" \
      --project="${GCP_PROJECT_ID}" \
      --location="${GCP_REGION}" \
      --uniform-bucket-level-access
  gcloud storage buckets update "gs://${TF_STATE_BUCKET}" --versioning
fi

# ------------------------------------------------------------------------------
# Phase 0B: Google Admin Console & Cloud Identity Bootstrap
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 0B] Running Google Admin & Cloud Identity Bootstrap..."
"${SCRIPT_DIR}/deploy_google_admin_bootstrap.sh" \
  --customer-name "${CUSTOMER_NAME}" \
  --customer-domain "${CUSTOMER_DOMAIN}" \
  --gcp-project-id "${GCP_PROJECT_ID}" \
  --entra-tenant-id "${ENTRA_TENANT_ID}" \
  --dns-project-id "${DNS_PROJECT_ID}" \
  --dns-zone-name "${DNS_ZONE_NAME}" \
  --tf-state-bucket "${TF_STATE_BUCKET}" \
  ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}

# ------------------------------------------------------------------------------
# Phase 0A: Microsoft Entra ID Bootstrap (Step 0A.1 OAuth + Step 0A.2 SAML)
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 0A] Running Microsoft Entra ID OAuth & SAML Gallery Bootstrap..."
"${SCRIPT_DIR}/deploy_entra_bootstrap.sh" \
  --tenant-id "${ENTRA_TENANT_ID}" \
  --customer-name "${CUSTOMER_NAME}" \
  --customer-domain "${CUSTOMER_DOMAIN}" \
  --gcp-project-id "${GCP_PROJECT_ID}" \
  --secret-id "${M365_SECRET_ID}" \
  --mode "${ENTRA_MODE}" \
  ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}

# ------------------------------------------------------------------------------
# Phase 1: Entra -> Cloud Identity Sync & Bi-Directional SAML Handshake
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 1] Running Stack 01: Entra -> Cloud Identity Group Sync & SAML Handshake..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Would run: TF_WORKSPACE_OVERRIDE=id-${CUSTOMER_NAME}-com ./deploy_identity.sh --config configs/${CUSTOMER_NAME}-identity.env --dns-project-id ${DNS_PROJECT_ID}"
else
  TF_WORKSPACE_OVERRIDE="id-${CUSTOMER_NAME}-com" "${SCRIPT_DIR}/deploy_identity.sh" \
    --config "${CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env" \
    --dns-project-id "${DNS_PROJECT_ID}"
fi

# ------------------------------------------------------------------------------
# Phase 1B: Declarative CSV Group Membership & GE License Sync
# ------------------------------------------------------------------------------
RESOLVED_MEMBERS_CSV="${MEMBERS_CSV:-${CONFIGS_DIR}/${CUSTOMER_NAME}-group-memberships.csv}"
if [[ -f "${RESOLVED_MEMBERS_CSV}" ]]; then
  echo ""
  echo ">>> [Phase 1B] Synchronizing Group Memberships & GE Licenses from ${RESOLVED_MEMBERS_CSV}..."
  "${SCRIPT_DIR}/sync_group_members_from_csv.sh" \
    --csv "${RESOLVED_MEMBERS_CSV}" \
    --config "${CONFIGS_DIR}/${CUSTOMER_NAME}-identity.env" \
    ${DRY_RUN_FLAG[@]+"${DRY_RUN_FLAG[@]}"}
fi

# ------------------------------------------------------------------------------
# Phase 2: Shared M365 Connectors (SharePoint, OneDrive, Outlook, Teams)
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 2] Running Stack 03: Shared M365 Connectors (${CUSTOMER_NAME}-m365-sp/od/ol/teams)..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Would generate configs/${CUSTOMER_NAME}-m365.env and run: TF_WORKSPACE_OVERRIDE=m365-global-${CUSTOMER_NAME}-m365 ./deploy_m365.sh"
else
  SP_TENANT_PREFIX="${CUSTOMER_NAME}"
  if command -v az >/dev/null 2>&1 && az account show >/dev/null 2>&1; then
    INIT_DOM="$(az rest --method GET --uri "https://graph.microsoft.com/v1.0/domains" --query "value[?isInitial].id | [0]" -o tsv 2>/dev/null || true)"
    if [[ -n "${INIT_DOM}" && "${INIT_DOM}" == *.onmicrosoft.com ]]; then
      SP_TENANT_PREFIX="${INIT_DOM%.onmicrosoft.com}"
    fi
  fi
  cat > "${CONFIGS_DIR}/${CUSTOMER_NAME}-m365.env" <<EOF
GCP_PROJECT_ID="${GCP_PROJECT_ID}"
GCP_REGION="${GCP_REGION}"
GE_LOCATION="global"
TF_STATE_BUCKET="${TF_STATE_BUCKET}"
TF_STATE_PREFIX="ge-apphub/03-m365-connectors/m365-global-${CUSTOMER_NAME}-m365"
M365_COLLECTION_PREFIX="${CUSTOMER_NAME}-m365"
M365_SECRET_ID="${M365_SECRET_ID}"
M365_CONNECTOR_MODE="FEDERATED"
ENABLE_M365_ACTIONS="true"
ENABLE_SHAREPOINT_CONNECTOR="true"
M365_SHAREPOINT_COLLECTION_ID="${CUSTOMER_NAME}-m365-sp"
M365_SHAREPOINT_INSTANCE_URI="https://${SP_TENANT_PREFIX}.sharepoint.com"
M365_SHAREPOINT_ENTITIES="file,page"
ENABLE_ONEDRIVE_CONNECTOR="true"
M365_ONEDRIVE_COLLECTION_ID="${CUSTOMER_NAME}-m365-od"
M365_ONEDRIVE_INSTANCE_URI="https://${SP_TENANT_PREFIX}-my.sharepoint.com"
M365_ONEDRIVE_ENTITIES="file"
ENABLE_OUTLOOK_CONNECTOR="true"
M365_OUTLOOK_COLLECTION_ID="${CUSTOMER_NAME}-m365-ol"
M365_OUTLOOK_INSTANCE_URI="https://outlook.office365.com"
M365_OUTLOOK_ENTITIES="mail,mail-attachment,calendar,contact"
ENABLE_TEAMS_CONNECTOR="true"
M365_TEAMS_COLLECTION_ID="${CUSTOMER_NAME}-m365-teams"
M365_TEAMS_INSTANCE_URI="https://teams.microsoft.com"
M365_TEAMS_ENTITIES="channel-message,chat-message"
EOF
  TF_WORKSPACE_OVERRIDE="m365-global-${CUSTOMER_NAME}-m365" "${SCRIPT_DIR}/deploy_m365.sh" \
    --config "${CONFIGS_DIR}/${CUSTOMER_NAME}-m365.env"
fi

# ------------------------------------------------------------------------------
# Phase 3: Departmental Gemini Enterprise Apps (16-Point Master Template)
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 3] Running Stack 02: Departmental Gemini Enterprise Apps (create_app_from_template.sh)..."
for SPEC in \
  "${CUSTOMER_NAME}-dev-sandbox-app|${CUSTOMER_NAME} AI Skill Dev Sandbox|ge-skill-developers@${CUSTOMER_DOMAIN}" \
  "${CUSTOMER_NAME}-service-desk-app|${CUSTOMER_NAME} Service Desk Assistant|ge-service-desk-users@${CUSTOMER_DOMAIN}" \
  "${CUSTOMER_NAME}-finance-app|${CUSTOMER_NAME} Finance & Accounting Assistant|ge-finance-users@${CUSTOMER_DOMAIN}" \
  "${CUSTOMER_NAME}-hr-app|${CUSTOMER_NAME} People & HR Assistant|ge-hr-users@${CUSTOMER_DOMAIN}"; do
  IFS="|" read -r APP_ID APP_NAME ACCESS_GROUP <<< "${SPEC}"
  WORKSPACE_KEY="app-global-${APP_ID}"
  if [[ "${DRY_RUN}" == "true" ]]; then
    "${SCRIPT_DIR}/create_app_from_template.sh" \
      --app-id "${APP_ID}" \
      --app-display-name "${APP_NAME}" \
      --customer-name "${CUSTOMER_NAME}" \
      --customer-company-name "${CUSTOMER_NAME}" \
      --customer-domain "${CUSTOMER_DOMAIN}" \
      --gcp-project-id "${GCP_PROJECT_ID}" \
      --access-group "${ACCESS_GROUP}" \
      --render-only
    echo "[DRY-RUN] Rendered 16-Point Template configs/${APP_ID}.env and would provision in isolated workspace '${WORKSPACE_KEY}'"
  else
    "${SCRIPT_DIR}/create_app_from_template.sh" \
      --app-id "${APP_ID}" \
      --app-display-name "${APP_NAME}" \
      --customer-name "${CUSTOMER_NAME}" \
      --customer-company-name "${CUSTOMER_NAME}" \
      --customer-domain "${CUSTOMER_DOMAIN}" \
      --gcp-project-id "${GCP_PROJECT_ID}" \
      --access-group "${ACCESS_GROUP}"
  fi
done

# ------------------------------------------------------------------------------
# Phase 4: Universal ADK Skill Orchestrator Deploy & Pin (agents-cli)
# ------------------------------------------------------------------------------
echo ""
echo ">>> [Phase 4] Deploying & Pinning Universal ADK Skill Orchestrator across ${CUSTOMER_NAME} GE Apps..."
if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY-RUN] Would run 'agents-cli deploy --project ${GCP_PROJECT_ID} --region ${GCP_REGION}' in agents/universal_skill_orchestrator"
  echo "[DRY-RUN] Would run 'agents-cli publish gemini-enterprise' and set defaultPinned=true on ${CUSTOMER_NAME}-service-desk-app, ${CUSTOMER_NAME}-finance-app, ${CUSTOMER_NAME}-hr-app"
else
  cd "${REPO_ROOT}/agents/universal_skill_orchestrator"
  agents-cli deploy --project "${GCP_PROJECT_ID}" --region "${GCP_REGION}" --no-wait
fi

echo ""
echo "=================================================================="
echo " End-to-End Onboarding Complete for ${CUSTOMER_NAME} (${CUSTOMER_DOMAIN})!"
echo "=================================================================="
