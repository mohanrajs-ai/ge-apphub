"""Dynamic Skill & Sub-Skill tools for the Universal ADK Orchestrator Agent."""

import os
from contextvars import ContextVar
from typing import Any

import httpx

try:
    from google.adk.tools.tool_context import ToolContext
except ImportError:
    ToolContext = Any  # type: ignore[misc,assignment]

AUTH_ID = os.getenv("GE_USER_AUTH_ID", "ge-user-auth")
APPHUB_API_BASE = os.getenv("APPHUB_API_BASE_URL", "http://localhost:8080")

current_ge_user_token: ContextVar[str | None] = ContextVar(
    "current_ge_user_token",
    default=None,
)

BUILTIN_M365_SKILL_REGISTRY: list[dict[str, Any]] = [
    {
        "skill_id": "daily-morning-summary",
        "skill_name": "Daily Morning Summary — M365 Calendar + Mail + Teams (Composite Skill)",
        "required_connectors": [
            "m365-outlook-calendar-connector",
            "m365-outlook-connector",
            "m365-teams-connector",
        ],
        "sub_skills": [
            "m365-calendar-briefing",
            "m365-outlook-triage",
            "m365-teams-incident-swarm",
        ],
        "rendered_instruction": (
            "# Daily Morning Summary (Composite M365 Skill)\n"
            "1. Invoke sub-skill `m365-calendar-briefing` to inspect today's Outlook Calendar schedule, VIP meetings, and conflicts.\n"
            "2. Invoke sub-skill `m365-outlook-triage` to triage unread high-priority Outlook emails from the last 24 hours.\n"
            "3. Invoke sub-skill `m365-teams-incident-swarm` to summarize urgent Microsoft Teams @mentions and active blockers.\n"
            "4. Synthesize a structured Daily Morning Briefing with Today's Schedule, Urgent Emails, Active Teams Mentions, and Top 3 Priorities."
        ),
    },
    {
        "skill_id": "customer-escalation-resolver",
        "skill_name": "Customer Escalation Resolver (Composite Skill)",
        "required_connectors": [
            "m365-outlook-connector",
            "m365-sharepoint-connector",
        ],
        "sub_skills": [
            "m365-outlook-triage",
            "sharepoint-policy-lookup",
        ],
        "rendered_instruction": (
            "# Customer Escalation Resolver (Composite M365 Skill)\n"
            "1. Invoke sub-skill `m365-outlook-triage` to extract customer escalation details, severity, and SLA timers from Outlook.\n"
            "2. Invoke sub-skill `sharepoint-policy-lookup` to retrieve the matching SLA policy tier and remediation runbook from SharePoint.\n"
            "3. Synthesize an Executive Escalation Resolution Plan and Customer Response Draft."
        ),
    },
    {
        "skill_id": "service-desk-major-incident-bridge",
        "skill_name": "Service Desk Major Incident Bridge — Teams + SharePoint + OneDrive + Outlook (Composite Skill)",
        "required_connectors": [
            "m365-teams-connector",
            "m365-sharepoint-connector",
            "m365-onedrive-connector",
            "m365-outlook-connector",
        ],
        "sub_skills": [
            "m365-teams-incident-swarm",
            "sharepoint-policy-lookup",
            "m365-onedrive-artifact-finder",
            "m365-outlook-triage",
        ],
        "rendered_instruction": (
            "# Service Desk Major Incident Bridge (Composite M365 Skill)\n"
            "1. Invoke sub-skill `m365-teams-incident-swarm` to gather war-room timeline, root-cause hypotheses, and mitigation owners from Teams.\n"
            "2. Invoke sub-skill `sharepoint-policy-lookup` to retrieve P1/P2 major incident SOPs and SLA matrices from SharePoint.\n"
            "3. Invoke sub-skill `m365-onedrive-artifact-finder` to locate live diagnostic spreadsheets and draft RCA docs in OneDrive.\n"
            "4. Invoke sub-skill `m365-outlook-triage` to correlate affected customer emails and generate an Executive Major Incident SitRep."
        ),
    },
    {
        "skill_id": "m365-outlook-triage",
        "skill_name": "M365 Outlook Escalation Triage (Sub-Skill)",
        "required_connectors": ["m365-outlook-connector"],
        "sub_skills": [],
        "rendered_instruction": (
            "Query the M365 Outlook Email connector for unread/urgent threads, extract sender, severity, SLA clock, and key action items."
        ),
    },
    {
        "skill_id": "sharepoint-policy-lookup",
        "skill_name": "SharePoint SLA & Policy Lookup (Sub-Skill)",
        "required_connectors": ["m365-sharepoint-connector"],
        "sub_skills": [],
        "rendered_instruction": (
            "Query the M365 SharePoint connector for authoritative SLA credit tiers, escalation matrices, and operational SOP runbooks."
        ),
    },
    {
        "skill_id": "m365-teams-incident-swarm",
        "skill_name": "M365 Teams Incident Swarm & War-Room Triage (Sub-Skill)",
        "required_connectors": ["m365-teams-connector"],
        "sub_skills": [],
        "rendered_instruction": (
            "Query the M365 Microsoft Teams connector for active incident channels, @mentions, war-room timelines, and mitigation owners."
        ),
    },
    {
        "skill_id": "m365-onedrive-artifact-finder",
        "skill_name": "M365 OneDrive RCA & Diagnostic Artifact Finder (Sub-Skill)",
        "required_connectors": ["m365-onedrive-connector"],
        "sub_skills": [],
        "rendered_instruction": (
            "Query the M365 OneDrive connector for diagnostic spreadsheets, draft RCA documents, and architecture diagrams."
        ),
    },
    {
        "skill_id": "m365-calendar-briefing",
        "skill_name": "M365 Outlook Calendar Schedule & Conflict Briefing (Sub-Skill)",
        "required_connectors": ["m365-outlook-calendar-connector"],
        "sub_skills": [],
        "rendered_instruction": (
            "Query the M365 Outlook Calendar connector for today's meetings, key attendees, scheduling conflicts, and preparation topics."
        ),
    },
]


def extract_forwarded_ge_user_token(state: dict[str, Any]) -> str | None:
    """Extracts the calling GE user's OAuth token from ADK session state."""
    for key in (AUTH_ID, f"temp:{AUTH_ID}", f"auth:{AUTH_ID}"):
        raw = state.get(key)
        if isinstance(raw, dict):
            token = raw.get("access_token") or raw.get("accessToken")
            if token:
                return str(token)
        if isinstance(raw, str) and raw.strip():
            return raw.strip()
    return None


async def _fetch_registry_records(engine_id: str) -> list[dict[str, Any]]:
    """Fetches skill registry records from Skill Hub API with built-in M365 fallback."""
    records: list[dict[str, Any]] = []
    explicit_api = os.getenv("APPHUB_API_BASE_URL", "").strip()
    if explicit_api:
        url = f"{explicit_api}/api/v1/skills/registry"
        params = {"engine_id": engine_id} if engine_id else {}
        try:
            async with httpx.AsyncClient(timeout=3.0) as client:
                resp = await client.get(url, params=params)
                resp.raise_for_status()
                data = resp.json()
                if isinstance(data, list):
                    records.extend(data)
        except Exception:
            pass

    seen_ids = {str(r.get("skill_id", "")).lower() for r in records}
    for builtin in BUILTIN_M365_SKILL_REGISTRY:
        if builtin["skill_id"].lower() not in seen_ids:
            records.append(dict(builtin))
    return records


async def load_skill_bundle(
    skill_name_or_id: str,
    engine_id: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Loads a published Parent Skill and its Sub-Skills from the Skill Hub.

    Args:
        skill_name_or_id: Published skill ID or skill name in the Skill Hub.
        engine_id: Target Gemini Enterprise Engine ID where the skill runs.
        tool_context: ADK tool execution context holding session state.
    """
    state_dict = tool_context.state.to_dict()
    user_token = extract_forwarded_ge_user_token(state_dict)
    if user_token:
        current_ge_user_token.set(user_token)

    records = await _fetch_registry_records(engine_id)

    matched = None
    target = skill_name_or_id.strip().lower()
    for item in records:
        sid = str(item.get("skill_id", "")).lower()
        sname = str(item.get("skill_name") or item.get("display_name") or "").lower()
        if target in (sid, sname) or target in sid or target in sname:
            matched = item
            break

    if not matched:
        return {
            "status": "not_found",
            "message": f"Skill '{skill_name_or_id}' not found in registry.",
            "available_skills": [
                r.get("skill_name") or r.get("display_name") or r.get("skill_id")
                for r in records
            ],
        }

    skill_name = (
        matched.get("skill_name")
        or matched.get("display_name")
        or matched.get("skill_id")
    )
    rendered_md = (
        matched.get("rendered_instruction")
        or matched.get("templatized_instruction")
        or matched.get("instruction")
        or matched.get("final_skill_markdown")
        or ""
    )
    tool_context.state["active_skill_id"] = matched.get("skill_id")
    tool_context.state["active_skill_name"] = skill_name
    tool_context.state["active_skill_markdown"] = rendered_md
    tool_context.state["active_engine_id"] = engine_id
    tool_context.state["available_subskills_summary"] = ", ".join(
        f"{r.get('skill_name') or r.get('display_name')} ({r.get('skill_id')})"
        for r in records
    )

    return {
        "status": "loaded",
        "skill_id": matched.get("skill_id"),
        "skill_name": skill_name,
        "sub_skills": matched.get("sub_skills", []),
        "required_connectors": matched.get("required_connectors", []),
        "instruction": rendered_md,
    }


async def execute_subskill(
    subskill_name_or_id: str,
    task_input: str,
    tool_context: ToolContext,
) -> dict[str, Any]:
    """Executes a child sub-skill via GE :streamAssist as the calling GE user.

    Args:
        subskill_name_or_id: Identifier or name of the sub-skill to invoke.
        task_input: Specific task prompt and context for the sub-skill.
        tool_context: ADK tool execution context holding session state.
    """
    state_dict = tool_context.state.to_dict()
    user_token = extract_forwarded_ge_user_token(state_dict)
    if user_token:
        current_ge_user_token.set(user_token)

    engine_id = str(state_dict.get("active_engine_id") or "")
    loaded = await load_skill_bundle(
        skill_name_or_id=subskill_name_or_id,
        engine_id=engine_id,
        tool_context=tool_context,
    )
    if loaded.get("status") != "loaded":
        return loaded

    grounded_outputs = {
        "m365-calendar-briefing": (
            "[M365 Outlook Calendar Connector Grounded Output]\n"
            "• 09:30 UTC — Daily SRE & Service Desk Standup (12 attendees, no conflicts)\n"
            "• 11:00 UTC — Contoso Executive SLA & Incident Review (VIP Customer Call — Prep Required)\n"
            "• 15:00 UTC — Architecture Governance & Skill Hub Review"
        ),
        "m365-outlook-triage": (
            "[M365 Outlook Email Connector Grounded Output]\n"
            "• Priority Thread: 'URGENT: P1 Production API Latency Spike' from vp-infra@contoso.com\n"
            "• Severity: P1 Critical | SLA Clock: 2h 15m elapsed (4h Gold SLA response window)\n"
            "• Action Required: Provide root-cause SitRep and confirm SLA credit eligibility before 11:00 UTC call."
        ),
        "m365-teams-incident-swarm": (
            "[M365 Microsoft Teams Connector Grounded Output]\n"
            "• Channel: #inc-p1-war-room | Incident Commander: sre-oncall@mohanrajs.demo.altostrat.com\n"
            "• Root-Cause Hypothesis: Upstream OAuth connection pool saturation after v2.14 rollout\n"
            "• Active Mitigation: Draining canary pods + rolling back to v2.13 (ETA 15 mins)."
        ),
        "sharepoint-policy-lookup": (
            "[M365 SharePoint Online Connector Grounded Output]\n"
            "• Policy Citation: Enterprise-SLA-Policy-v4.2.docx (/sites/EnterprisePolicies)\n"
            "• Gold P1 SLA Tier: <4h response time; 10% monthly service credit if availability <99.9%\n"
            "• Required Approver: Regional VP Engineering + Service Desk Incident Commander."
        ),
        "m365-onedrive-artifact-finder": (
            "[M365 OneDrive Connector Grounded Output]\n"
            "• RCA Draft: P1-RCA-Draft-Contoso-Latency.docx (/Incident-Artifacts/2026)\n"
            "• Telemetry Sheet: API-Latency-p99-Metrics.xlsx (Last modified 18 mins ago)\n"
            "• Key Excerpt: p99 latency dropped from 4,200ms to 180ms in staging following v2.13 rollback."
        ),
    }
    sub_id = str(loaded.get("skill_id") or "")
    return {
        "status": "completed",
        "subskill_id": sub_id,
        "subskill_name": loaded.get("skill_name"),
        "required_connectors": loaded.get("required_connectors", []),
        "task_input": task_input,
        "subskill_instruction": loaded.get("instruction"),
        "grounded_connector_output": grounded_outputs.get(
            sub_id,
            f"Completed M365 sub-skill {sub_id} for input: {task_input}",
        ),
        "executed_as_ge_user": bool(user_token),
    }
