#!/usr/bin/env bash
# ==============================================================================
# Template-Driven Gemini Enterprise App Generator & Provisioner
# ==============================================================================
# Renders a new departmental Gemini Enterprise App configuration from
# `configs/templates/ge-app-master.template.env` with all 16 enterprise
# capabilities pre-configured:
#   1. App Core Configuration (Engine Tier, Add-Ons, Industry Vertical)
#   2. Identity Configuration for App (GSUITE/WIF ACLs, Per-App Group & IAM)
#   3. Associate Connectors (9 M365 SharePoint/OneDrive/Outlook/Teams Stores)
#   4. Admin-Configured Connector Display Names (Friendly UI Labels)
#   5. Autocomplete Configuration (Prefix Matching, People & Recent Search)
#   6. Feedback Configuration (Thumbs Up/Down + Detailed Comments)
#   7. User Event Collection Configuration (365-Day Retention & Personalization)
#   8. Logo & UI Branding (Custom Company/App Logo & Favicon)
#   9. LLM System Instructions (Department-Specific Grounding Persona)
#  10. Google Web Search Grounding (WEB_GROUNDING_TYPE_GOOGLE_SEARCH)
#  11. Model Armor (Prompt/Response Templates & FAIL_CLOSED Enforcement)
#  12. Enterprise Knowledge Catalog (Taxonomy & Auto-Classification)
#  13. Chat History Retention (Configurable Retention Days & Session TTL)
#  14. Private Knowledge Graph (PKG Entity Extraction & People/Topic Graph)
#  15. Full Feature Management (Agent Gallery, NotebookLM, Deep Research,
#      No-Code Agent Builder, Prompt Gallery, Model Selector, Actions, Audio)
#  16. Observability Options (Audit Logs, Query/Response Logs, Latency Metrics,
#      BigQuery Analytics Export & Cloud Logging Sink)
#
# Usage:
#   ./create_app_from_template.sh \
#     --app-id "cymbal-finance-app" \
#     --app-display-name "Cymbal Finance & Accounting Assistant" \
#     --customer-name "cymbal" \
#     --customer-company-name "Cymbal" \
#     --customer-domain "cymbal.com" \
#     --gcp-project-id "cymbal-ge-prod" \
#     --access-group "ge-finance-users@cymbal.com" \
#     [--system-instruction "You are the Cymbal Finance Assistant..."] \
#     [--logo-uri "https://storage.googleapis.com/cymbal-ge-prod-assets/cymbal-logo.png"] \
#     [--chat-retention-days 90] \
#     [--render-only] \
#     [--dry-run]
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/configs/templates/ge-app-master.template.env"
CONFIGS_DIR="${SCRIPT_DIR}/configs"
mkdir -p "${CONFIGS_DIR}"

export CLOUDSDK_METRICS_ENVIRONMENT="geapphub"

GE_APP_ID=""
GE_APP_DISPLAY_NAME=""
CUSTOMER_NAME="cymbal"
CUSTOMER_COMPANY_NAME="Cymbal"
CUSTOMER_DOMAIN="cymbal.com"
GCP_PROJECT_ID="cymbal-ge-prod"
GCP_REGION="us-central1"
GE_LOCATION="global"
TF_STATE_BUCKET=""
CLOUD_IDENTITY_CUSTOMER_ID=""
GE_APP_ACCESS_GROUP=""
GE_ASSISTANT_SYSTEM_INSTRUCTION=""
LOGO_URI=""
CHAT_RETENTION_DAYS="90"
ENABLE_WEB_GROUNDING="true"
ENABLE_MODEL_ARMOR="true"
ENABLE_KNOWLEDGE_CATALOG="true"
ENABLE_PKG="true"
ALLOW_AGENT_SHARING="false"
ENABLE_SKILLS="true"
SKILL_SHARING_POLICY="ADMIN_APPROVAL_REQUIRED"
SKILL_APPROVER_GROUP=""
ENABLE_PROJECTS="true"
RENDER_ONLY="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-id)
      GE_APP_ID="$2"
      shift 2
      ;;
    --app-display-name|--display-name)
      GE_APP_DISPLAY_NAME="$2"
      shift 2
      ;;
    --customer-name)
      CUSTOMER_NAME="$2"
      shift 2
      ;;
    --customer-company-name|--company-name)
      CUSTOMER_COMPANY_NAME="$2"
      shift 2
      ;;
    --customer-domain|--domain)
      CUSTOMER_DOMAIN="$2"
      shift 2
      ;;
    --gcp-project-id|--project-id)
      GCP_PROJECT_ID="$2"
      shift 2
      ;;
    --gcp-region|--region)
      GCP_REGION="$2"
      shift 2
      ;;
    --ge-location|--location)
      GE_LOCATION="$2"
      shift 2
      ;;
    --tf-state-bucket)
      TF_STATE_BUCKET="$2"
      shift 2
      ;;
    --cloud-identity-customer-id)
      CLOUD_IDENTITY_CUSTOMER_ID="$2"
      shift 2
      ;;
    --access-group)
      GE_APP_ACCESS_GROUP="$2"
      shift 2
      ;;
    --system-instruction)
      GE_ASSISTANT_SYSTEM_INSTRUCTION="$2"
      shift 2
      ;;
    --logo-uri)
      LOGO_URI="$2"
      shift 2
      ;;
    --chat-retention-days)
      CHAT_RETENTION_DAYS="$2"
      shift 2
      ;;
    --enable-web-grounding)
      ENABLE_WEB_GROUNDING="$2"
      shift 2
      ;;
    --enable-model-armor)
      ENABLE_MODEL_ARMOR="$2"
      shift 2
      ;;
    --enable-knowledge-catalog)
      ENABLE_KNOWLEDGE_CATALOG="$2"
      shift 2
      ;;
    --enable-pkg)
      ENABLE_PKG="$2"
      shift 2
      ;;
    --allow-agent-sharing)
      ALLOW_AGENT_SHARING="$2"
      shift 2
      ;;
    --enable-skills)
      ENABLE_SKILLS="$2"
      shift 2
      ;;
    --skill-sharing-policy)
      SKILL_SHARING_POLICY="$2"
      shift 2
      ;;
    --skill-approver-group)
      SKILL_APPROVER_GROUP="$2"
      shift 2
      ;;
    --enable-projects)
      ENABLE_PROJECTS="$2"
      shift 2
      ;;
    --render-only)
      RENDER_ONLY="true"
      shift 1
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

if [[ -z "${GE_APP_ID}" ]]; then
  echo "ERROR: --app-id <GE_APP_ID> is required."
  exit 1
fi

if [[ -z "${GE_APP_DISPLAY_NAME}" ]]; then
  GE_APP_DISPLAY_NAME="${CUSTOMER_COMPANY_NAME} ${GE_APP_ID}"
fi
if [[ -z "${TF_STATE_BUCKET}" ]]; then
  TF_STATE_BUCKET="${CUSTOMER_NAME}-ge-tfstate"
fi
if [[ -z "${GE_APP_ACCESS_GROUP}" ]]; then
  GE_APP_ACCESS_GROUP="${GE_APP_ID}-users@${CUSTOMER_DOMAIN}"
fi
if [[ -z "${GE_ASSISTANT_SYSTEM_INSTRUCTION}" ]]; then
  GE_ASSISTANT_SYSTEM_INSTRUCTION="You are the official ${GE_APP_DISPLAY_NAME} for ${CUSTOMER_COMPANY_NAME} (${CUSTOMER_DOMAIN}). Always ground your answers in verified ${CUSTOMER_COMPANY_NAME} SharePoint, OneDrive, Outlook, Microsoft Teams, and Enterprise Knowledge data stores while strictly honoring user ACLs and Model Armor safety policies."
fi

if [[ -z "${SKILL_APPROVER_GROUP}" ]]; then
  SKILL_APPROVER_GROUP="ge-platform-admins@${CUSTOMER_DOMAIN}"
fi

OUTPUT_ENV_FILE="${CONFIGS_DIR}/${GE_APP_ID}.env"
WORKSPACE_KEY="app-${GE_LOCATION}-${GE_APP_ID}"

echo "=================================================================="
echo " Gemini Enterprise 16-Point App Template Generator"
echo "------------------------------------------------------------------"
echo " App ID            : ${GE_APP_ID} (${GE_APP_DISPLAY_NAME})"
echo " Customer          : ${CUSTOMER_COMPANY_NAME} (${CUSTOMER_DOMAIN})"
echo " GCP Project       : ${GCP_PROJECT_ID} (${GE_LOCATION})"
echo " Isolated Workspace: ${WORKSPACE_KEY}"
echo " Access Group      : ${GE_APP_ACCESS_GROUP}"
echo " Agent Sharing     : ${ALLOW_AGENT_SHARING} (Disabled by default)"
echo " Skills & Approval : ${ENABLE_SKILLS} (${SKILL_SHARING_POLICY} via ${SKILL_APPROVER_GROUP})"
echo " Projects          : ${ENABLE_PROJECTS}"
echo " Output Config     : ${OUTPUT_ENV_FILE}"
echo "=================================================================="

python3 - "${TEMPLATE_FILE}" "${OUTPUT_ENV_FILE}" \
  "${GCP_PROJECT_ID}" "${GCP_REGION}" "${GE_LOCATION}" "${TF_STATE_BUCKET}" \
  "${GE_APP_ID}" "${GE_APP_DISPLAY_NAME}" "${CUSTOMER_NAME}" "${CUSTOMER_COMPANY_NAME}" \
  "${CUSTOMER_DOMAIN}" "${CLOUD_IDENTITY_CUSTOMER_ID}" "${GE_APP_ACCESS_GROUP}" \
  "${GE_ASSISTANT_SYSTEM_INSTRUCTION}" "${LOGO_URI}" "${CHAT_RETENTION_DAYS}" \
  "${ENABLE_WEB_GROUNDING}" "${ENABLE_MODEL_ARMOR}" "${ENABLE_KNOWLEDGE_CATALOG}" "${ENABLE_PKG}" \
  "${ALLOW_AGENT_SHARING}" "${ENABLE_SKILLS}" "${SKILL_SHARING_POLICY}" "${SKILL_APPROVER_GROUP}" "${ENABLE_PROJECTS}" <<'PYEOF'
import sys

(
    _,
    tmpl_path,
    out_path,
    project_id,
    region,
    location,
    tf_bucket,
    app_id,
    app_display_name,
    customer_name,
    company_name,
    domain,
    ci_customer_id,
    access_group,
    sys_instruction,
    logo_uri,
    retention_days,
    enable_web,
    enable_ma,
    enable_kc,
    enable_pkg,
    allow_agent_sharing,
    enable_skills,
    skill_sharing_policy,
    skill_approver_group,
    enable_projects,
) = sys.argv

with open(tmpl_path, "r", encoding="utf-8") as f:
    content = f.read()

replacements = {
    "{{GCP_PROJECT_ID}}": project_id,
    "{{GCP_REGION}}": region,
    "{{GE_LOCATION}}": location,
    "{{TF_STATE_BUCKET}}": tf_bucket,
    "{{GE_APP_ID}}": app_id,
    "{{GE_APP_DISPLAY_NAME}}": app_display_name,
    "{{CUSTOMER_NAME}}": customer_name,
    "{{CUSTOMER_COMPANY_NAME}}": company_name,
    "{{CUSTOMER_DOMAIN}}": domain,
    "{{CLOUD_IDENTITY_CUSTOMER_ID}}": ci_customer_id,
    "{{GE_APP_ACCESS_GROUP}}": access_group,
    "{{GE_ASSISTANT_SYSTEM_INSTRUCTION}}": sys_instruction,
}

for k, v in replacements.items():
    content = content.replace(k, v)

if logo_uri:
    content = content.replace(
        f'GE_APP_LOGO_URI="https://storage.googleapis.com/{project_id}-assets/{customer_name}-logo.png"',
        f'GE_APP_LOGO_URI="{logo_uri}"',
    )

content = content.replace('GE_CHAT_HISTORY_RETENTION_DAYS="90"', f'GE_CHAT_HISTORY_RETENTION_DAYS="{retention_days}"')
content = content.replace('GE_ENABLE_WEB_SEARCH_GROUNDING="true"', f'GE_ENABLE_WEB_SEARCH_GROUNDING="{enable_web}"')
content = content.replace('GE_ENABLE_MODEL_ARMOR="true"', f'GE_ENABLE_MODEL_ARMOR="{enable_ma}"')
content = content.replace('GE_ENABLE_KNOWLEDGE_CATALOG="true"', f'GE_ENABLE_KNOWLEDGE_CATALOG="{enable_kc}"')
content = content.replace('GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH="true"', f'GE_ENABLE_PRIVATE_KNOWLEDGE_GRAPH="{enable_pkg}"')

feat_agent_sharing = "FEATURE_STATE_ON" if allow_agent_sharing.lower() == "true" else "FEATURE_STATE_OFF"
agent_policy = "SHARING_POLICY_ENABLED" if allow_agent_sharing.lower() == "true" else "SHARING_POLICY_DISABLED"
feat_skills = "FEATURE_STATE_ON" if enable_skills.lower() == "true" else "FEATURE_STATE_OFF"
feat_skill_sharing = "FEATURE_STATE_ON" if skill_sharing_policy != "DISABLED" else "FEATURE_STATE_OFF"
feat_skill_approval = "FEATURE_STATE_ON" if skill_sharing_policy == "ADMIN_APPROVAL_REQUIRED" else "FEATURE_STATE_OFF"
req_admin_approval = "true" if skill_sharing_policy == "ADMIN_APPROVAL_REQUIRED" else "false"
feat_projects = "FEATURE_STATE_ON" if enable_projects.lower() == "true" else "FEATURE_STATE_OFF"

content = content.replace('GE_FEATURE_AGENT_SHARING="FEATURE_STATE_OFF"', f'GE_FEATURE_AGENT_SHARING="{feat_agent_sharing}"')
content = content.replace('GE_ALLOW_AGENT_SHARING="false"', f'GE_ALLOW_AGENT_SHARING="{allow_agent_sharing.lower()}"')
content = content.replace('GE_AGENT_SHARING_POLICY="SHARING_POLICY_DISABLED"', f'GE_AGENT_SHARING_POLICY="{agent_policy}"')
content = content.replace('GE_FEATURE_SKILLS="FEATURE_STATE_ON"', f'GE_FEATURE_SKILLS="{feat_skills}"')
content = content.replace('GE_ENABLE_SKILLS="true"', f'GE_ENABLE_SKILLS="{enable_skills.lower()}"')
content = content.replace('GE_FEATURE_SKILL_SHARING="FEATURE_STATE_ON"', f'GE_FEATURE_SKILL_SHARING="{feat_skill_sharing}"')
content = content.replace('GE_FEATURE_SKILL_SHARING_ADMIN_APPROVAL="FEATURE_STATE_ON"', f'GE_FEATURE_SKILL_SHARING_ADMIN_APPROVAL="{feat_skill_approval}"')
content = content.replace('GE_SKILL_SHARING_APPROVAL_POLICY="ADMIN_APPROVAL_REQUIRED"', f'GE_SKILL_SHARING_APPROVAL_POLICY="{skill_sharing_policy}"')
content = content.replace('GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING="true"', f'GE_REQUIRE_ADMIN_APPROVAL_FOR_SKILL_SHARING="{req_admin_approval}"')
content = content.replace(f'GE_SKILL_APPROVER_GROUP="ge-platform-admins@{domain}"', f'GE_SKILL_APPROVER_GROUP="{skill_approver_group}"')
content = content.replace('GE_FEATURE_PROJECTS="FEATURE_STATE_ON"', f'GE_FEATURE_PROJECTS="{feat_projects}"')
content = content.replace('GE_ENABLE_PROJECTS="true"', f'GE_ENABLE_PROJECTS="{enable_projects.lower()}"')

with open(out_path, "w", encoding="utf-8") as f:
    f.write(content)
PYEOF

echo "[OK] Rendered 16-Point App Configuration -> ${OUTPUT_ENV_FILE}"

if [[ "${RENDER_ONLY}" == "true" ]]; then
  echo "[INFO] --render-only specified. Skipping ./deploy.sh execution."
  exit 0
fi

DEPLOY_ARGS=(--config "${OUTPUT_ENV_FILE}")
if [[ "${DRY_RUN}" == "true" ]]; then
  DEPLOY_ARGS+=(--dry-run)
fi

echo "[INFO] Executing ./deploy.sh in isolated workspace '${WORKSPACE_KEY}'..."
TF_WORKSPACE_OVERRIDE="${WORKSPACE_KEY}" "${SCRIPT_DIR}/deploy.sh" "${DEPLOY_ARGS[@]}"
