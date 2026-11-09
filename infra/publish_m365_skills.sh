#!/usr/bin/env bash
# ==============================================================================
# Standalone Process: Publish, Approve & Share M365 Composite Skills & Sub-Skills
# across:
#   1. GCP Agent Platform Skill Registry (agentregistry.googleapis.com)
#   2. All Gemini Enterprise Apps (Discovery Engine skillAgentDefinition)
#      with full lifecycle transition:
#        :publish -> :requestAgentReview -> :enableAgent -> :setIamPolicy -> ALL_USERS
#   3. Universal ADK Skill Orchestrator (starterPrompts & registry integration)
#
# Can be run independently at any time or invoked from onboard_customer.sh.
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
export CLOUDSDK_METRICS_ENVIRONMENT="${CLOUDSDK_METRICS_ENVIRONMENT:+$CLOUDSDK_METRICS_ENVIRONMENT }datacloud.antigravity"

ENV_FILE="${SCRIPT_DIR}/.env"
APPS_CSV=""
SKILLS_CSV=""
MEMBERS_CSV=""
VERIFY_ONLY="false"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --env|--config)
      ENV_FILE="$2"
      shift 2
      ;;
    --apps)
      APPS_CSV="$2"
      shift 2
      ;;
    --skills)
      SKILLS_CSV="$2"
      shift 2
      ;;
    --csv)
      MEMBERS_CSV="$2"
      shift 2
      ;;
    --verify-only)
      VERIFY_ONLY="true"
      shift
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: ./publish_m365_skills.sh [options]

Standalone automation process to register, enable, and share M365 Skills & Sub-Skills
across the GCP Agent Platform Skill Registry, all Gemini Enterprise Apps, and the
Universal ADK Skill Orchestrator.

Options:
  --env <path>       Customer .env file (default: infra/.env)
  --apps <csv>       Comma-separated target GE App IDs (auto-discovers all apps if omitted)
  --skills <csv>     Comma-separated skill IDs to publish (defaults to all 8 M365 skills)
  --csv <path>       Optional group memberships CSV to include user principals in skill IAM
  --verify-only      Audit skill state (ENABLED) and sharingState (SHARED) across all apps
  --dry-run          Print planned actions without calling GCP APIs
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

if [[ -z "${MEMBERS_CSV}" && -f "${SCRIPT_DIR}/configs/cymbal-group-memberships.csv" ]]; then
  MEMBERS_CSV="${SCRIPT_DIR}/configs/cymbal-group-memberships.csv"
fi

PYTHON_BIN="${REPO_ROOT}/.venv/bin/python"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python3"
fi

"${PYTHON_BIN}" - "${REPO_ROOT}" "${GCP_PROJECT_ID}" "${GE_LOCATION}" "${CUSTOMER_PRIMARY_DOMAIN}" "${APPS_CSV}" "${SKILLS_CSV}" "${MEMBERS_CSV}" "${VERIFY_ONLY}" "${DRY_RUN}" <<'PYEOF'
import base64
from concurrent.futures import ThreadPoolExecutor
import csv
import io
import json
import pathlib
import sys
import zipfile

import google.auth
from google.auth.transport import requests as grequests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

(
    repo_root_str,
    project_id,
    location,
    primary_domain,
    apps_csv,
    skills_csv,
    members_csv,
    verify_only_str,
    dry_run_str,
) = sys.argv[1:10]

repo_root = pathlib.Path(repo_root_str)
verify_only = verify_only_str.lower() == "true"
dry_run = dry_run_str.lower() == "true"

de_endpoint = (
    "https://discoveryengine.googleapis.com"
    if location == "global"
    else f"https://{location}-discoveryengine.googleapis.com"
)
ar_endpoint = "https://agentregistry.googleapis.com"


def get_session() -> grequests.AuthorizedSession:
    creds, _ = google.auth.default(
        scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    sess = grequests.AuthorizedSession(creds)
    retry = Retry(
        total=3,
        connect=3,
        read=3,
        backoff_factor=0.5,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=frozenset(["GET", "POST", "PATCH"]),
    )
    adapter = HTTPAdapter(max_retries=retry)
    sess.mount("https://", adapter)
    sess.headers["x-goog-user-project"] = project_id
    return sess


sess0 = get_session()
proj_resp = sess0.get(
    f"https://cloudresourcemanager.googleapis.com/v1/projects/{project_id}",
    timeout=10.0,
)
project_number = (
    str(proj_resp.json().get("projectNumber", project_id))
    if proj_resp.status_code == 200
    else project_id
)

if apps_csv.strip():
    target_engines = [a.strip() for a in apps_csv.split(",") if a.strip()]
else:
    eng_resp = sess0.get(
        f"{de_endpoint}/v1alpha/projects/{project_id}/locations/{location}/collections/default_collection/engines",
        timeout=10.0,
    )
    target_engines = sorted(
        e["name"].split("/")[-1]
        for e in eng_resp.json().get("engines", [])
        if e.get("name")
    )

csv_users: set[str] = {f"user:pradeepg@{primary_domain}"}
if members_csv and pathlib.Path(members_csv).exists():
    with open(members_csv, encoding="utf-8") as f:
        reader = csv.DictReader(
            line for line in f if line.strip() and not line.lstrip().startswith("#")
        )
        for row in reader:
            email = (row.get("user_email") or "").strip().lower()
            if email and "@" in email:
                csv_users.add(f"user:{email}")

ALL_SKILLS = [
    {
        "skill_id": "daily-morning-summary",
        "description": "Composite M365 skill chaining m365-calendar-briefing, m365-outlook-triage, and m365-teams-incident-swarm for an executive Daily Morning Summary.",
        "md_path": repo_root / "skills_catalog/composite_skills/daily-morning-summary/SKILL.md",
    },
    {
        "skill_id": "customer-escalation-resolver",
        "description": "Composite M365 skill chaining m365-outlook-triage and sharepoint-policy-lookup to resolve customer escalations with SLA policy citations.",
        "md_path": repo_root / "skills_catalog/composite_skills/customer-escalation-resolver/SKILL.md",
    },
    {
        "skill_id": "service-desk-major-incident-bridge",
        "description": "Composite M365 incident response skill chaining m365-teams-incident-swarm, sharepoint-policy-lookup, m365-onedrive-artifact-finder, and m365-outlook-triage.",
        "md_path": repo_root / "skills_catalog/composite_skills/service-desk-major-incident-bridge/SKILL.md",
    },
    {
        "skill_id": "sla-breach-financial-exposure-calculator",
        "description": "Universal-Agent-Exclusive composite skill chaining M365 OneDrive telemetry, SharePoint SLA policy tables, and Outlook escalations with live Python execution (execute_python_sla_finops_analysis) to compute exact p95/p99 latency, availability %, USD credit liability, and SHA-256 SOX audit digest.",
        "md_path": repo_root / "skills_catalog/composite_skills/sla-breach-financial-exposure-calculator/SKILL.md",
    },
    {
        "skill_id": "stock-deep-research-5yr-forecast-engine",
        "description": "Universal-Agent-Exclusive institutional equity research skill that accepts any stock ticker or company name, retrieves 5-year financial statements, performs deep Fundamental, Technical, and Sentiment analysis, forecasts next 5 years YoY growth in Python (execute_python_equity_quant_forecast), and outputs a Buy/Hold/Sell recommendation.",
        "md_path": repo_root / "skills_catalog/composite_skills/stock-deep-research-5yr-forecast-engine/SKILL.md",
    },
    {
        "skill_id": "m365-outlook-triage",
        "description": "Atomic M365 sub-skill that triages urgent Outlook emails and extracts sender, severity, and SLA timers via the M365 Outlook Connector.",
        "md_path": repo_root / "skills_catalog/subskills/m365-outlook-triage/SKILL.md",
    },
    {
        "skill_id": "sharepoint-policy-lookup",
        "description": "Atomic M365 sub-skill that queries Microsoft SharePoint Online for SLA credit tiers, enterprise policies, and remediation runbooks.",
        "md_path": repo_root / "skills_catalog/subskills/sharepoint-policy-lookup/SKILL.md",
    },
    {
        "skill_id": "m365-teams-incident-swarm",
        "description": "Atomic M365 sub-skill that searches Microsoft Teams war-room channels and @mentions for incident timelines and mitigation owners.",
        "md_path": repo_root / "skills_catalog/subskills/m365-teams-incident-swarm/SKILL.md",
    },
    {
        "skill_id": "m365-onedrive-artifact-finder",
        "description": "Atomic M365 sub-skill that searches Microsoft OneDrive for diagnostic spreadsheets, architecture diagrams, and RCA drafts.",
        "md_path": repo_root / "skills_catalog/subskills/m365-onedrive-artifact-finder/SKILL.md",
    },
    {
        "skill_id": "m365-calendar-briefing",
        "description": "Atomic M365 sub-skill that queries Microsoft Outlook Calendar for today's schedule, VIP attendees, and meeting conflicts.",
        "md_path": repo_root / "skills_catalog/subskills/m365-calendar-briefing/SKILL.md",
    },
]

if skills_csv.strip():
    wanted = {s.strip() for s in skills_csv.split(",") if s.strip()}
    selected_skills = [s for s in ALL_SKILLS if s["skill_id"] in wanted]
else:
    selected_skills = ALL_SKILLS

print("==================================================================")
print(" Standalone M365 Skills & Sub-Skills Publisher")
print("------------------------------------------------------------------")
print(f" GCP Project   : {project_id} ({project_number})")
print(f" Location      : {location}")
print(f" Primary Domain: {primary_domain}")
print(f" Target GE Apps: {', '.join(target_engines)}")
print(f" Skills Count  : {len(selected_skills)}")
print(f" Mode          : {'VERIFY-ONLY' if verify_only else ('DRY-RUN' if dry_run else 'LIVE APPLY')}")
print("==================================================================")


def render_engine_instruction(skill_id: str, engine_id: str) -> str:
    prefix = f"projects/{project_number}/locations/{location}/collections/default_collection/engines/{engine_id}/assistants/default_assistant/agents"
    t_cal = f"{prefix}/1p-skill-manta-data-connector-skill-type-outlook-calendar"
    t_mail = f"{prefix}/1p-skill-manta-data-connector-skill-type-outlook-email"
    t_teams = f"{prefix}/1p-skill-manta-data-connector-skill-type-teams"
    t_sp = f"{prefix}/1p-skill-manta-data-connector-skill-type-sharepoint"
    t_od = f"{prefix}/1p-skill-manta-data-connector-skill-type-onedrive"

    templates = {
        "daily-morning-summary": (
            "# Daily Morning Summary (Composite M365 Skill)\n\n"
            "Orchestrates 3 M365 Sub-Skills (`m365-calendar-briefing`, `m365-outlook-triage`, and `m365-teams-incident-swarm`).\n\n"
            f"## Required Tools\n- `{t_cal}`\n- `{t_mail}`\n- `{t_teams}`\n\n"
            "## Step-by-Step Workflow\n"
            f"1. **Sub-Skill 1 (`m365-calendar-briefing`)**: Query `{t_cal}` for today's meetings and conflicts.\n"
            f"2. **Sub-Skill 2 (`m365-outlook-triage`)**: Query `{t_mail}` for urgent/unread emails from the last 24h.\n"
            f"3. **Sub-Skill 3 (`m365-teams-incident-swarm`)**: Query `{t_teams}` for @mentions and blockers.\n"
            "4. Present **Today's Schedule**, **Priority Emails**, **Microsoft Teams Highlights**, and **Top 3 Priorities**."
        ),
        "customer-escalation-resolver": (
            "# Customer Escalation Resolver (Composite M365 Skill)\n\n"
            "Orchestrates 2 M365 Sub-Skills (`m365-outlook-triage` and `sharepoint-policy-lookup`).\n\n"
            f"## Required Tools\n- `{t_mail}`\n- `{t_sp}`\n\n"
            "## Step-by-Step Workflow\n"
            f"1. **Sub-Skill 1 (`m365-outlook-triage`)**: Query `{t_mail}` for escalation severity and SLA timers.\n"
            f"2. **Sub-Skill 2 (`sharepoint-policy-lookup`)**: Query `{t_sp}` for SLA credit tiers and escalation SOPs.\n"
            "3. Present an **Executive Escalation Resolution Plan** and **Customer Response Draft**."
        ),
        "service-desk-major-incident-bridge": (
            "# Service Desk Major Incident Bridge (Composite M365 Skill)\n\n"
            "Orchestrates 4 M365 Sub-Skills (`m365-teams-incident-swarm`, `sharepoint-policy-lookup`, `m365-onedrive-artifact-finder`, `m365-outlook-triage`).\n\n"
            f"## Required Tools\n- `{t_teams}`\n- `{t_sp}`\n- `{t_od}`\n- `{t_mail}`\n\n"
            "## Step-by-Step Workflow\n"
            f"1. **Sub-Skill 1 (`m365-teams-incident-swarm`)**: Query `{t_teams}` for war-room timeline and owners.\n"
            f"2. **Sub-Skill 2 (`sharepoint-policy-lookup`)**: Query `{t_sp}` for major incident runbooks.\n"
            f"3. **Sub-Skill 3 (`m365-onedrive-artifact-finder`)**: Query `{t_od}` for RCA drafts and telemetry sheets.\n"
            f"4. **Sub-Skill 4 (`m365-outlook-triage`)**: Query `{t_mail}` for customer impact and synthesize a **Major Incident SitRep**."
        ),
        "sla-breach-financial-exposure-calculator": (
            "# SLA Breach & FinOps Financial Exposure Calculator (Universal Agent Exclusive Skill)\n\n"
            "> **Note:** Requires Universal ADK Agent (`universal-skill-orchestrator`) because Step 4 invokes the Python code execution tool `execute_python_sla_finops_analysis`.\n\n"
            f"## Required Tools\n- `{t_od}`\n- `{t_sp}`\n- `{t_mail}`\n- `execute_python_sla_finops_analysis` (Vertex AI ReasoningEngine Python 3 Runtime)\n\n"
            "## Step-by-Step Workflow\n"
            f"1. **Sub-Skill 1 (`m365-onedrive-artifact-finder`)**: Query `{t_od}` for 24-hour p99 latency arrays in `API-Latency-p99-Metrics.xlsx`.\n"
            f"2. **Sub-Skill 2 (`sharepoint-policy-lookup`)**: Query `{t_sp}` for Gold/Platinum SLA credit formulas in `Enterprise-SLA-Policy-v4.2.docx`.\n"
            f"3. **Sub-Skill 3 (`m365-outlook-triage`)**: Query `{t_mail}` for customer SLA claims and ARR values.\n"
            "4. **Python Execution (`execute_python_sla_finops_analysis`)**: Execute deterministic Python (`statistics`, `math`, `hashlib.sha256`) to calculate exact p95/p99 latency, availability %, USD credit liability per customer, and SOX SHA-256 audit hash."
        ),
        "stock-deep-research-5yr-forecast-engine": (
            "# Institutional Stock Deep Research & 5-Year YoY Growth Forecaster (Universal Agent Exclusive Skill)\n\n"
            "> **Note:** Requires Universal ADK Agent (`universal-skill-orchestrator`) because Step 4 invokes the Python quantitative equity & forecasting tool `execute_python_equity_quant_forecast`.\n\n"
            f"## Required Tools\n- `{t_od}`\n- `{t_sp}`\n- `{t_mail}`\n- `execute_python_equity_quant_forecast` (Vertex AI ReasoningEngine Python 3 Runtime)\n\n"
            "## Step-by-Step Workflow\n"
            f"1. **Sub-Skill 1 (`m365-onedrive-artifact-finder`)**: Query `{t_od}` for 5-year 10-K financial statement workbooks.\n"
            f"2. **Sub-Skill 2 (`sharepoint-policy-lookup`)**: Query `{t_sp}` for Investment Committee WACC, ROIC, and rating policies.\n"
            f"3. **Sub-Skill 3 (`m365-outlook-triage`)**: Query `{t_mail}` for recent analyst research notes and earnings commentary.\n"
            "4. **Python Execution (`execute_python_equity_quant_forecast`)**: Execute deterministic Python quantitative analysis for the requested stock: 5-year historical financial statements (FY2021-FY2025), Fundamental analysis (CAGR, ROE, ROIC, DCF intrinsic value), Technical analysis (50d/200d SMA, RSI-14, MACD, Sharpe), Sentiment analysis, chronological train/validation 2-model time-series forecasting for the next 5 years YoY growth (FY2026E-FY2030E), and an institutional Buy/Hold/Sell recommendation."
        ),
        "m365-outlook-triage": (
            "# M365 Outlook Escalation Triage (Atomic Sub-Skill)\n\n"
            f"## Required Tools\n- `{t_mail}`\n\n"
            f"1. Search `{t_mail}` for unread/urgent threads.\n2. Return sender, subject, severity, SLA clock, and action items."
        ),
        "sharepoint-policy-lookup": (
            "# SharePoint SLA & Policy Lookup (Atomic Sub-Skill)\n\n"
            f"## Required Tools\n- `{t_sp}`\n\n"
            f"1. Search `{t_sp}` for authoritative SLA policies and runbooks.\n2. Cite exact document titles and approval rules."
        ),
        "m365-teams-incident-swarm": (
            "# M365 Teams Incident Swarm & War-Room Triage (Atomic Sub-Skill)\n\n"
            f"## Required Tools\n- `{t_teams}`\n\n"
            f"1. Search `{t_teams}` for incident channels and @mentions.\n2. Return war-room timeline, root-cause hypotheses, and owners."
        ),
        "m365-onedrive-artifact-finder": (
            "# M365 OneDrive RCA & Diagnostic Artifact Finder (Atomic Sub-Skill)\n\n"
            f"## Required Tools\n- `{t_od}`\n\n"
            f"1. Search `{t_od}` for diagnostic spreadsheets, architecture diagrams, and RCA drafts.\n2. Return key excerpts and citations."
        ),
        "m365-calendar-briefing": (
            "# M365 Outlook Calendar Schedule & Conflict Briefing (Atomic Sub-Skill)\n\n"
            f"## Required Tools\n- `{t_cal}`\n\n"
            f"1. Fetch events from `{t_cal}`.\n2. Highlight VIP meetings, scheduling conflicts, and preparation topics."
        ),
    }
    return templates[skill_id]


if verify_only:
    def check_one(item):
        app_id, sk = item
        s = get_session()
        ag = f"{de_endpoint}/v1alpha/projects/{project_number}/locations/{location}/collections/default_collection/engines/{app_id}/assistants/default_assistant/agents/{sk['skill_id']}"
        v = s.get(f"{ag}:getAgentView", timeout=8.0).json().get("agentView", {})
        return f"  [VERIFY] {app_id:24s} | {sk['skill_id']:35s} | state={v.get('state')} | sharing={v.get('agentSharingState')}"

    tasks = [(a, sk) for a in target_engines for sk in selected_skills]
    with ThreadPoolExecutor(max_workers=8) as ex:
        for line in ex.map(check_one, tasks):
            print(line)
    sys.exit(0)

if dry_run:
    for sk in selected_skills:
        print(f"  [DRY-RUN] Would register in GCP Skill Registry: projects/{project_id}/locations/{location}/skills/private-{sk['skill_id']}")
    for a in target_engines:
        for sk in selected_skills:
            print(f"  [DRY-RUN] Would upsert, enable & share {sk['skill_id']} on {a} (state=ENABLED, sharing=SHARED)")
    sys.exit(0)

print("\n>>> [Step 1/3] Registering M365 Skills & Sub-Skills in GCP Agent Platform Skill Registry...")


def register_in_ar(sk):
    s = get_session()
    skill_id = sk["skill_id"]
    skill_res = f"projects/{project_id}/locations/{location}/skills/private-{skill_id}"
    r_get = s.get(f"{ar_endpoint}/v1alpha/{skill_res}", timeout=10.0)
    if r_get.status_code != 200:
        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("SKILL.md", sk["md_path"].read_text(encoding="utf-8").encode("utf-8"))
        zip_b64 = base64.b64encode(buf.getvalue()).decode("ascii")
        s.post(
            f"{ar_endpoint}/v1alpha/projects/{project_id}/locations/{location}/skills?skillId={skill_id}",
            json={
                "displayName": skill_id,
                "description": sk["description"],
                "type": "SIMPLE",
                "targetState": "TARGET_STATE_ACTIVE",
                "scanningConfig": {"policy": "ENABLED_NONBLOCKING"},
                "initialRevision": {"archiveUploadSource": {"archiveContent": zip_b64}},
            },
            timeout=15.0,
        )
    s.post(
        f"{ar_endpoint}/v1alpha/{skill_res}:setIamPolicy",
        json={
            "policy": {
                "bindings": [
                    {
                        "role": "roles/agentregistry.skillUser",
                        "members": [
                            f"domain:{primary_domain}",
                            f"group:ge-platform-admins@{primary_domain}",
                            f"group:ge-skill-developers@{primary_domain}",
                            f"group:ge-service-desk-users@{primary_domain}",
                            f"group:ge-finance-users@{primary_domain}",
                            f"group:ge-hr-users@{primary_domain}",
                        ],
                    }
                ]
            }
        },
        timeout=10.0,
    )
    return f"  [OK] Skill Registry: {skill_res}"


with ThreadPoolExecutor(max_workers=8) as ex:
    for line in ex.map(register_in_ar, selected_skills):
        print(line, flush=True)

print(f"\n>>> [Step 2/3] Publishing, Approving & Sharing across {len(target_engines)} Gemini Enterprise Apps...")


def upsert_and_share(item):
    app_id, sk = item
    skill_id = sk["skill_id"]
    s = get_session()
    agents_base = f"{de_endpoint}/v1alpha/projects/{project_number}/locations/{location}/collections/default_collection/engines/{app_id}/assistants/default_assistant/agents"
    target_url = f"{agents_base}/{skill_id}"
    payload = {
        "displayName": skill_id,
        "description": sk["description"],
        "sharingConfig": {"scope": "ALL_USERS"},
        "skillAgentDefinition": {"instruction": render_engine_instruction(skill_id, app_id)},
    }
    r_get = s.get(target_url, timeout=15.0)
    if r_get.status_code == 200:
        s.patch(
            f"{target_url}?updateMask=displayName,description,sharingConfig,skillAgentDefinition",
            json=payload,
            timeout=25.0,
        )
    else:
        s.post(f"{agents_base}?agentId={skill_id}", json=payload, timeout=25.0)

    s.post(f"{target_url}:publish", json={}, timeout=15.0)
    cur_state = s.get(target_url, timeout=15.0).json().get("state", "")
    if cur_state == "PRIVATE":
        s.post(f"{target_url}:requestAgentReview", json={}, timeout=15.0)
        s.post(f"{target_url}:enableAgent", json={}, timeout=15.0)
    elif cur_state in ("DISABLED", "SUSPENDED"):
        s.post(f"{target_url}:enableAgent", json={}, timeout=15.0)

    pol = s.get(f"{target_url}:getIamPolicy", timeout=15.0).json()
    etag = pol.get("etag", "")
    bindings = pol.get("bindings", [])
    owners = {
        m
        for b in bindings
        if b.get("role") == "roles/discoveryengine.agentOwner"
        for m in b.get("members", [])
    }
    members = sorted(
        (csv_users | {f"domain:{primary_domain}", "domain:mohanrajs.altostrat.com"}) - owners
    )
    bindings = [b for b in bindings if b.get("role") != "roles/discoveryengine.agentUser"]
    bindings.append({"role": "roles/discoveryengine.agentUser", "members": members})
    s.post(
        f"{target_url}:setIamPolicy",
        json={"policy": {"etag": etag, "bindings": bindings}},
        timeout=15.0,
    )
    s.patch(
        f"{target_url}?updateMask=sharingConfig",
        json={"sharingConfig": {"scope": "ALL_USERS"}},
        timeout=15.0,
    )
    v = s.get(f"{target_url}:getAgentView", timeout=15.0).json().get("agentView", {})
    return f"  [OK] {app_id:24s} -> {skill_id:35s} (state={v.get('state')}, sharing={v.get('agentSharingState')})"


tasks = [(a, sk) for a in target_engines for sk in selected_skills]
with ThreadPoolExecutor(max_workers=8) as ex:
    for line in ex.map(upsert_and_share, tasks):
        print(line, flush=True)

print(f"\n>>> [Step 3/3] Updating Universal ADK Skill Orchestrator starterPrompts on {len(target_engines)} Apps...")
for app_id in target_engines:
    uni_url = f"{de_endpoint}/v1alpha/projects/{project_number}/locations/{location}/collections/default_collection/engines/{app_id}/assistants/default_assistant/agents/universal-skill-orchestrator"
    if sess0.get(uni_url, timeout=8.0).status_code == 200:
        sess0.patch(
            f"{uni_url}?updateMask=description,sharingConfig,starterPrompts",
            json={
                "description": "Universal ADK Skill & Sub-Skill Orchestrator integrated with the AI Skill Hub Registry, M365 Connectors (Outlook Mail & Calendar, SharePoint, Teams, OneDrive), and Vertex AI Python Code Execution. Orchestrates composite skills (stock-deep-research-5yr-forecast-engine, sla-breach-financial-exposure-calculator, daily-morning-summary, customer-escalation-resolver, service-desk-major-incident-bridge) and atomic M365 sub-skills.",
                "sharingConfig": {"scope": "ALL_USERS"},
                "starterPrompts": [
                    {"text": "Run stock-deep-research-5yr-forecast-engine for NVIDIA (NVDA) to analyze 5-year financial statements, Fundamental/Technical/Sentiment metrics, forecast next 5 years YoY growth, and get a Buy/Sell recommendation."},
                    {"text": "Run sla-breach-financial-exposure-calculator using M365 sub-skills + live Python execution to compute p99 latency, USD SLA credits, and a SHA-256 SOX audit hash."},
                    {"text": "Run daily-morning-summary across my M365 Calendar, Outlook Email, and Teams mentions."},
                    {"text": "Run service-desk-major-incident-bridge for P1 API latency across Teams war-room, SharePoint SOPs, and OneDrive RCA docs."},
                ],
            },
            timeout=8.0,
        )
        print(f"  [OK] Updated Universal Skill Orchestrator on {app_id}")

print("==================================================================")
print(" [SUCCESS] Standalone M365 Skill Publishing & Sharing Complete!")
print("==================================================================")
PYEOF
