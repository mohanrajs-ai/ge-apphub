#!/usr/bin/env bash
# ==============================================================================
# Publish & Share M365 Composite Skills & Sub-Skills across:
#   1. GCP Agent Platform Skill Registry (agentregistry.googleapis.com)
#   2. All Gemini Enterprise Apps (Discovery Engine skillAgentDefinition)
#   3. Universal ADK Skill Orchestrator (starterPrompts & registry integration)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

ENV_FILE="${SCRIPT_DIR}/.env"
Target_Engines=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env)
      ENV_FILE="$2"
      shift 2
      ;;
    --apps)
      IFS=',' read -r -a Target_Engines <<< "$2"
      shift 2
      ;;
    -h|--help)
      cat <<EOF
Usage: ./publish_m365_skills.sh [options]

Options:
  --env <path>     Customer .env file (default: infra/.env)
  --apps <csv>     Comma-separated target GE App IDs (auto-discovers all apps if omitted)
EOF
      exit 0
      ;;
    *)
      echo "[ERROR] Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -f "${ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${ENV_FILE}"
  set +a
fi

GCP_PROJECT_ID="${GCP_PROJECT_ID:-cymbal-app-514110}"
GE_LOCATION="${GE_LOCATION:-global}"
CUSTOMER_PRIMARY_DOMAIN="${CUSTOMER_PRIMARY_DOMAIN:-mohanrajs.demo.altostrat.com}"

PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

TOKEN="$("${PYTHON_BIN}" -c '
import google.auth, google.auth.transport.requests
creds, _ = google.auth.default(scopes=["https://www.googleapis.com/auth/cloud-platform"])
creds.refresh(google.auth.transport.requests.Request())
print(creds.token)
')"

PROJECT_NUMBER="$(curl -s -H "Authorization: Bearer ${TOKEN}" "https://cloudresourcemanager.googleapis.com/v1/projects/${GCP_PROJECT_ID}" | jq -r '.projectNumber')"

if [[ "${GE_LOCATION}" == "global" ]]; then
  DE_ENDPOINT="https://discoveryengine.googleapis.com"
else
  DE_ENDPOINT="https://${GE_LOCATION}-discoveryengine.googleapis.com"
fi
AR_ENDPOINT="https://agentregistry.googleapis.com"

# Auto-discover all Gemini Enterprise apps if --apps was not specified
if [[ ${#Target_Engines[@]} -eq 0 ]]; then
  ENGINES_JSON="$(curl -s \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    "${DE_ENDPOINT}/v1alpha/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/collections/default_collection/engines")"
  while IFS= read -r eng_id; do
    [[ -n "${eng_id}" ]] && Target_Engines+=("${eng_id}")
  done < <(echo "${ENGINES_JSON}" | jq -r '.engines[]?.name | split("/") | last')
fi

if [[ ${#Target_Engines[@]} -eq 0 ]]; then
  echo "[ERROR] No Gemini Enterprise apps found in project ${GCP_PROJECT_ID}." >&2
  exit 1
fi

echo "=================================================================="
echo " Publishing & Sharing M365 Skills & Sub-Skills"
echo "------------------------------------------------------------------"
echo " GCP Project   : ${GCP_PROJECT_ID} (${PROJECT_NUMBER})"
echo " Location      : ${GE_LOCATION}"
echo " Primary Domain: ${CUSTOMER_PRIMARY_DOMAIN}"
echo " Target GE Apps: ${Target_Engines[*]}"
echo "=================================================================="

# ------------------------------------------------------------------------------
# Helper: Build zip archive base64 for Agent Platform Skill Registry
# ------------------------------------------------------------------------------
build_skill_zip_b64() {
  local skill_md_content="$1"
  python3 -c '
import base64, io, sys, zipfile
content = sys.stdin.read()
buf = io.BytesIO()
with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
    zf.writestr("SKILL.md", content.encode("utf-8"))
print(base64.b64encode(buf.getvalue()).decode("ascii"))
' <<< "${skill_md_content}"
}

# ------------------------------------------------------------------------------
# Helper: Publish skill to GCP Agent Platform Skill Registry & grant IAM
# ------------------------------------------------------------------------------
publish_to_agent_registry() {
  local skill_id="$1"
  local display_name="$2"
  local description="$3"
  local md_file="$4"

  local raw_md
  raw_md="$(cat "${md_file}")"
  local zip_b64
  zip_b64="$(build_skill_zip_b64 "${raw_md}")"

  local skill_res="projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/skills/private-${skill_id}"
  local get_code
  get_code="$(curl -s -o /tmp/ar_skill_get.json -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    "${AR_ENDPOINT}/v1alpha/${skill_res}")"

  if [[ "${get_code}" != "200" ]]; then
    local create_payload
    create_payload="$(jq -n \
      --arg dn "${skill_id}" \
      --arg desc "${description}" \
      --arg zb "${zip_b64}" \
      '{
        displayName: $dn,
        description: $desc,
        type: "SIMPLE",
        targetState: "TARGET_STATE_ACTIVE",
        scanningConfig: { policy: "ENABLED_NONBLOCKING" },
        initialRevision: {
          archiveUploadSource: { archiveContent: $zb }
        }
      }')"
    curl -s -o /tmp/ar_skill_create.json -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${AR_ENDPOINT}/v1alpha/projects/${GCP_PROJECT_ID}/locations/${GE_LOCATION}/skills?skillId=${skill_id}" \
      -d "${create_payload}" >/dev/null
    echo "  [OK] Registered in GCP Skill Registry: ${skill_res}"
  else
    echo "  [OK] Verified in GCP Skill Registry  : ${skill_res}"
  fi

  # Share in GCP Agent Platform Skill Registry across domain & departmental groups
  local iam_payload
  iam_payload="$(jq -n \
    --arg dom "domain:${CUSTOMER_PRIMARY_DOMAIN}" \
    --arg g1 "group:ge-platform-admins@${CUSTOMER_PRIMARY_DOMAIN}" \
    --arg g2 "group:ge-skill-developers@${CUSTOMER_PRIMARY_DOMAIN}" \
    --arg g3 "group:ge-service-desk-users@${CUSTOMER_PRIMARY_DOMAIN}" \
    --arg g4 "group:ge-finance-users@${CUSTOMER_PRIMARY_DOMAIN}" \
    --arg g5 "group:ge-hr-users@${CUSTOMER_PRIMARY_DOMAIN}" \
    '{
      policy: {
        bindings: [
          {
            role: "roles/agentregistry.skillUser",
            members: [$dom, $g1, $g2, $g3, $g4, $g5]
          }
        ]
      }
    }')"
  curl -s -o /dev/null -X POST \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Content-Type: application/json" \
    -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    "${AR_ENDPOINT}/v1alpha/${skill_res}:setIamPolicy" \
    -d "${iam_payload}" || true
}

# ------------------------------------------------------------------------------
# Helper: Render engine-specific SKILL.md instruction with 1P M365 tool paths
# ------------------------------------------------------------------------------
render_engine_skill_instruction() {
  local skill_id="$1"
  local engine_id="$2"
  local base_tool_prefix="projects/${PROJECT_NUMBER}/locations/${GE_LOCATION}/collections/default_collection/engines/${engine_id}/assistants/default_assistant/agents"
  local t_cal="${base_tool_prefix}/1p-skill-manta-data-connector-skill-type-outlook-calendar"
  local t_mail="${base_tool_prefix}/1p-skill-manta-data-connector-skill-type-outlook-email"
  local t_teams="${base_tool_prefix}/1p-skill-manta-data-connector-skill-type-teams"
  local t_sp="${base_tool_prefix}/1p-skill-manta-data-connector-skill-type-sharepoint"
  local t_od="${base_tool_prefix}/1p-skill-manta-data-connector-skill-type-onedrive"

  case "${skill_id}" in
    daily-morning-summary)
      cat <<EOF
# Daily Morning Summary (Composite M365 Skill)

Orchestrates 3 M365 Sub-Skills (\`m365-calendar-briefing\`, \`m365-outlook-triage\`, and \`m365-teams-incident-swarm\`) to compile an executive morning briefing.

## Required Tools
- \`${t_cal}\`: Fetch today's Outlook Calendar schedule, attendees, and conflicts.
- \`${t_mail}\`: Fetch unread high-priority Outlook emails from the last 24 hours.
- \`${t_teams}\`: Fetch unread Microsoft Teams @mentions, direct messages, and active incident channel updates.

## Step-by-Step Workflow
1. **Sub-Skill 1 (\`m365-calendar-briefing\`)**: Query \`${t_cal}\` for today's meetings, key participants, and overlapping slots.
2. **Sub-Skill 2 (\`m365-outlook-triage\`)**: Query \`${t_mail}\` for urgent/unread emails requiring same-day response.
3. **Sub-Skill 3 (\`m365-teams-incident-swarm\`)**: Query \`${t_teams}\` for direct @mentions and blockers.
4. Present a structured Markdown briefing with **Today's Schedule**, **Priority Emails**, **Microsoft Teams Highlights**, and **Top 3 Priorities**.
EOF
      ;;
    customer-escalation-resolver)
      cat <<EOF
# Customer Escalation Resolver (Composite M365 Skill)

Orchestrates 2 M365 Sub-Skills (\`m365-outlook-triage\` and \`sharepoint-policy-lookup\`) to triage customer escalations and recommend SLA-backed remediation.

## Required Tools
- \`${t_mail}\`: Search Outlook email threads for customer escalation history, severity, and SLA timestamps.
- \`${t_sp}\`: Search SharePoint Online for official SLA credit policies and escalation matrices.

## Step-by-Step Workflow
1. **Sub-Skill 1 (\`m365-outlook-triage\`)**: Query \`${t_mail}\` to extract customer sender, impacted service, severity, and elapsed SLA window.
2. **Sub-Skill 2 (\`sharepoint-policy-lookup\`)**: Query \`${t_sp}\` for the matching SLA policy tier, credit eligibility, and required approvers.
3. Output an **Executive Escalation Resolution Plan** and a ready-to-send **Customer Response Draft**.
EOF
      ;;
    service-desk-major-incident-bridge)
      cat <<EOF
# Service Desk Major Incident Bridge (Composite M365 Skill)

Orchestrates 4 M365 Sub-Skills (\`m365-teams-incident-swarm\`, \`sharepoint-policy-lookup\`, \`m365-onedrive-artifact-finder\`, and \`m365-outlook-triage\`) for P1/P2 major incident response.

## Required Tools
- \`${t_teams}\`: Search Microsoft Teams war-room channels for live incident timelines and mitigation owners.
- \`${t_sp}\`: Retrieve P1/P2 incident escalation SOPs and rollback checklists from SharePoint Online.
- \`${t_od}\`: Locate diagnostic spreadsheets, architecture diagrams, and RCA drafts in OneDrive.
- \`${t_mail}\`: Correlate inbound customer impact emails in Outlook and draft executive status updates.

## Step-by-Step Workflow
1. **Sub-Skill 1 (\`m365-teams-incident-swarm\`)**: Query \`${t_teams}\` for active war-room threads, root-cause hypotheses, and action owners.
2. **Sub-Skill 2 (\`sharepoint-policy-lookup\`)**: Query \`${t_sp}\` for the applicable major incident runbook and SLA cadence.
3. **Sub-Skill 3 (\`m365-onedrive-artifact-finder\`)**: Query \`${t_od}\` for live telemetry sheets and draft post-mortem documents.
4. **Sub-Skill 4 (\`m365-outlook-triage\`)**: Query \`${t_mail}\` for affected customer reports and synthesize a complete **Major Incident SitRep**.
EOF
      ;;
    m365-outlook-triage)
      cat <<EOF
# M365 Outlook Escalation Triage (Atomic Sub-Skill)

## Required Tools
- \`${t_mail}\`: Query Microsoft Outlook emails for urgent threads, VIP senders, and SLA deadlines.

## Execution Instructions
1. Search \`${t_mail}\` for unread or high-importance emails matching the user's topic or customer.
2. Return sender, subject, timestamp, severity, and concrete action items.
EOF
      ;;
    sharepoint-policy-lookup)
      cat <<EOF
# SharePoint SLA & Policy Lookup (Atomic Sub-Skill)

## Required Tools
- \`${t_sp}\`: Query Microsoft SharePoint Online sites and libraries for enterprise policies, SLA matrices, and SOP runbooks.

## Execution Instructions
1. Search \`${t_sp}\` for authoritative policy documents and runbooks matching the incident or customer tier.
2. Cite exact SharePoint document titles, SLA commitments, and approval rules.
EOF
      ;;
    m365-teams-incident-swarm)
      cat <<EOF
# M365 Teams Incident Swarm & War-Room Triage (Atomic Sub-Skill)

## Required Tools
- \`${t_teams}\`: Query Microsoft Teams channels, war-room chats, and @mentions.

## Execution Instructions
1. Search \`${t_teams}\` for active incident threads, @mentions, and operational blockers.
2. Return a chronological war-room timeline, root-cause hypotheses, and assigned mitigation owners.
EOF
      ;;
    m365-onedrive-artifact-finder)
      cat <<EOF
# M365 OneDrive RCA & Diagnostic Artifact Finder (Atomic Sub-Skill)

## Required Tools
- \`${t_od}\`: Query Microsoft OneDrive for diagnostic spreadsheets, RCA drafts, and architecture diagrams.

## Execution Instructions
1. Search \`${t_od}\` for recently modified documents matching the incident, customer, or project.
2. Extract key metrics, findings, and direct OneDrive file citations.
EOF
      ;;
    m365-calendar-briefing)
      cat <<EOF
# M365 Outlook Calendar Schedule & Conflict Briefing (Atomic Sub-Skill)

## Required Tools
- \`${t_cal}\`: Query Microsoft Outlook Calendar for scheduled events, attendees, and conflicts.

## Execution Instructions
1. Fetch events from \`${t_cal}\` for the target date window.
2. Highlight external/VIP meetings, overlapping conflicts, and preparation topics.
EOF
      ;;
  esac
}

# ------------------------------------------------------------------------------
# Helper: Upsert & share a skillAgentDefinition onto a Gemini Enterprise Engine
# ------------------------------------------------------------------------------
upsert_skill_on_engine() {
  local engine_id="$1"
  local skill_id="$2"
  local description="$3"

  local instruction
  instruction="$(render_engine_skill_instruction "${skill_id}" "${engine_id}")"
  local agents_base="${DE_ENDPOINT}/v1alpha/projects/${PROJECT_NUMBER}/locations/${GE_LOCATION}/collections/default_collection/engines/${engine_id}/assistants/default_assistant/agents"
  local target_url="${agents_base}/${skill_id}"

  local payload
  payload="$(jq -n \
    --arg dn "${skill_id}" \
    --arg desc "${description}" \
    --arg inst "${instruction}" \
    '{
      displayName: $dn,
      description: $desc,
      sharingConfig: { scope: "ALL_USERS" },
      skillAgentDefinition: {
        instruction: $inst
      }
    }')"

  local get_code
  get_code="$(curl -s -o /tmp/ge_skill_get.json -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    "${target_url}")"

  local agent_res_name=""
  if [[ "${get_code}" == "200" ]]; then
    curl -s -o /tmp/ge_skill_upsert.json -X PATCH \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${target_url}?updateMask=displayName,description,sharingConfig,skillAgentDefinition" \
      -d "${payload}" >/dev/null
    agent_res_name="$(jq -r '.name // empty' /tmp/ge_skill_upsert.json)"
  else
    curl -s -o /tmp/ge_skill_upsert.json -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${agents_base}?agentId=${skill_id}" \
      -d "${payload}" >/dev/null
    agent_res_name="$(jq -r '.name // empty' /tmp/ge_skill_upsert.json)"
  fi

  if [[ -n "${agent_res_name}" ]]; then
    curl -s -m 15 -o /dev/null -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}:publish" \
      -d '{}' || true
    curl -s -m 15 -o /dev/null -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}:requestAgentReview" \
      -d '{}' || true
    curl -s -m 15 -o /dev/null -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}:enableAgent" \
      -d '{}' || true

    local pol_json etag iam_body
    pol_json="$(curl -s -m 15 \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}:getIamPolicy")"
    etag="$(echo "${pol_json}" | jq -r '.etag // empty')"
    iam_body="$(echo "${pol_json}" | jq \
      --arg dom1 "domain:${CUSTOMER_PRIMARY_DOMAIN}" \
      --arg dom2 "domain:mohanrajs.altostrat.com" \
      --arg pradeep "user:pradeepg@${CUSTOMER_PRIMARY_DOMAIN}" \
      --arg etag "${etag}" '
      ([.bindings[]? | select(.role == "roles/discoveryengine.agentOwner") | .members[]?]) as $owners |
      ([.bindings[]? | select(.role != "roles/discoveryengine.agentUser")]) as $other_bindings |
      (([$dom1, $dom2, $pradeep] | unique) - $owners) as $user_members |
      {
        policy: (
          {
            bindings: ($other_bindings + [{
              role: "roles/discoveryengine.agentUser",
              members: $user_members
            }])
          } + (if $etag != "" then {etag: $etag} else {} end)
        )
      }')"
    curl -s -m 15 -o /dev/null -X POST \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}:setIamPolicy" \
      -d "${iam_body}" || true

    curl -s -m 15 -o /dev/null -X PATCH \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${DE_ENDPOINT}/v1alpha/${agent_res_name}?updateMask=sharingConfig" \
      -d '{"sharingConfig":{"scope":"ALL_USERS"}}' || true
    echo "  [OK] Enabled & Shared on ${engine_id} -> ${skill_id} (state=ENABLED, sharingState=SHARED, scope=ALL_USERS)"
  else
    echo "  [WARN] Could not upsert ${skill_id} on ${engine_id}: $(cat /tmp/ge_skill_upsert.json)" >&2
  fi
}

# ------------------------------------------------------------------------------
# Catalog of 8 M365 Skills & Sub-Skills (3 Composite Skills + 5 Sub-Skills)
# ------------------------------------------------------------------------------
SKILL_IDS=(
  "daily-morning-summary"
  "customer-escalation-resolver"
  "service-desk-major-incident-bridge"
  "m365-outlook-triage"
  "sharepoint-policy-lookup"
  "m365-teams-incident-swarm"
  "m365-onedrive-artifact-finder"
  "m365-calendar-briefing"
)

SKILL_DESCRIPTIONS=(
  "Composite M365 skill chaining m365-calendar-briefing, m365-outlook-triage, and m365-teams-incident-swarm for an executive Daily Morning Summary."
  "Composite M365 skill chaining m365-outlook-triage and sharepoint-policy-lookup to resolve customer escalations with SLA policy citations."
  "Composite M365 incident response skill chaining m365-teams-incident-swarm, sharepoint-policy-lookup, m365-onedrive-artifact-finder, and m365-outlook-triage."
  "Atomic M365 sub-skill that triages urgent Outlook emails and extracts sender, severity, and SLA timers via the M365 Outlook Connector."
  "Atomic M365 sub-skill that queries Microsoft SharePoint Online for SLA credit tiers, enterprise policies, and remediation runbooks."
  "Atomic M365 sub-skill that searches Microsoft Teams war-room channels and @mentions for incident timelines and mitigation owners."
  "Atomic M365 sub-skill that searches Microsoft OneDrive for diagnostic spreadsheets, architecture diagrams, and RCA drafts."
  "Atomic M365 sub-skill that queries Microsoft Outlook Calendar for today's schedule, VIP attendees, and meeting conflicts."
)

SKILL_PATHS=(
  "${REPO_ROOT}/skills_catalog/composite_skills/daily-morning-summary/SKILL.md"
  "${REPO_ROOT}/skills_catalog/composite_skills/customer-escalation-resolver/SKILL.md"
  "${REPO_ROOT}/skills_catalog/composite_skills/service-desk-major-incident-bridge/SKILL.md"
  "${REPO_ROOT}/skills_catalog/subskills/m365-outlook-triage/SKILL.md"
  "${REPO_ROOT}/skills_catalog/subskills/sharepoint-policy-lookup/SKILL.md"
  "${REPO_ROOT}/skills_catalog/subskills/m365-teams-incident-swarm/SKILL.md"
  "${REPO_ROOT}/skills_catalog/subskills/m365-onedrive-artifact-finder/SKILL.md"
  "${REPO_ROOT}/skills_catalog/subskills/m365-calendar-briefing/SKILL.md"
)

echo ""
echo ">>> [Step 1/3] Registering 8 M365 Skills & Sub-Skills in GCP Agent Platform Skill Registry..."
for idx in "${!SKILL_IDS[@]}"; do
  publish_to_agent_registry \
    "${SKILL_IDS[$idx]}" \
    "${SKILL_IDS[$idx]}" \
    "${SKILL_DESCRIPTIONS[$idx]}" \
    "${SKILL_PATHS[$idx]}"
done

echo ""
echo ">>> [Step 2/3] Publishing & Sharing 8 M365 Skills & Sub-Skills across all ${#Target_Engines[@]} Gemini Enterprise Apps..."
for engine_id in "${Target_Engines[@]}"; do
  echo "--- App: ${engine_id} ---"
  for idx in "${!SKILL_IDS[@]}"; do
    upsert_skill_on_engine \
      "${engine_id}" \
      "${SKILL_IDS[$idx]}" \
      "${SKILL_DESCRIPTIONS[$idx]}"
  done
done

echo ""
echo ">>> [Step 3/3] Updating Universal ADK Skill Orchestrator starterPrompts on all ${#Target_Engines[@]} Apps..."
for engine_id in "${Target_Engines[@]}"; do
  uni_url="${DE_ENDPOINT}/v1alpha/projects/${PROJECT_NUMBER}/locations/${GE_LOCATION}/collections/default_collection/engines/${engine_id}/assistants/default_assistant/agents/universal-skill-orchestrator"
  uni_code="$(curl -s -o /tmp/uni_agent_get.json -w "%{http_code}" \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
    "${uni_url}")"
  if [[ "${uni_code}" == "200" ]]; then
    uni_patch="$(jq -n '{
      description: "Universal ADK Skill & Sub-Skill Orchestrator integrated with the AI Skill Hub Registry and M365 Connectors (Outlook Mail & Calendar, SharePoint, Teams, OneDrive). Orchestrates composite skills (daily-morning-summary, customer-escalation-resolver, service-desk-major-incident-bridge) and atomic M365 sub-skills.",
      sharingConfig: { scope: "ALL_USERS" },
      starterPrompts: [
        { text: "Run daily-morning-summary across my M365 Calendar, Outlook Email, and Teams mentions." },
        { text: "Run service-desk-major-incident-bridge for P1 API latency across Teams war-room, SharePoint SOPs, and OneDrive RCA docs." },
        { text: "Run customer-escalation-resolver to triage the latest P1 customer email in Outlook and lookup SLA credits in SharePoint." },
        { text: "List all M365 composite skills and atomic sub-skills available in the Skill Registry." }
      ]
    }')"
    curl -s -o /dev/null -X PATCH \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "Content-Type: application/json" \
      -H "X-Goog-User-Project: ${GCP_PROJECT_ID}" \
      "${uni_url}?updateMask=description,sharingConfig,starterPrompts" \
      -d "${uni_patch}"
    echo "  [OK] Updated Universal Skill Orchestrator on ${engine_id} with M365 skills & starterPrompts"
  fi
done

echo "=================================================================="
echo " [SUCCESS] All 8 M365 Skills & Sub-Skills Registered and Shared!"
echo "=================================================================="
