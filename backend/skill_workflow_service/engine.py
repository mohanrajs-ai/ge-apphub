"""5-Stage Skill Governance, InfoSec Approval, Registry & Sharing Engine."""

import base64
import datetime
import io
import logging
import os
import re
import smtplib
import zipfile
from email import message as email_message
from typing import Any

import google.auth
from google.auth.transport import requests as google_requests
from sqlalchemy import orm

from app import config
from app import db_models
from app import models
from app.services import ge_agent_publisher
from skill_workflow_service.agents import infosec_agent
from skill_workflow_service.agents import skill_eval_agent

LOGGER = logging.getLogger(__name__)
DEFAULT_INFOSEC_RECIPIENT = "infosec-team@mohanrajs.altostrat.com"


def _utc_now() -> datetime.datetime:
    """Returns current UTC datetime."""
    return datetime.datetime.now(datetime.timezone.utc)


def workflow_record_to_model(
    row: db_models.SkillWorkflowRecord,
) -> models.SkillWorkflowItem:
    """Converts a SkillWorkflowRecord ORM row into a SkillWorkflowItem."""
    eval_rep = dict(row.eval_report or {})
    templatized = str(
        row.templatized_instruction
        or eval_rep.get("templatized_instruction")
        or ""
    )
    req_connectors = list(
        row.required_connectors or eval_rep.get("required_connectors") or []
    )
    sub_skills = list(
        row.sub_skills or eval_rep.get("sub_skills") or []
    )
    return models.SkillWorkflowItem(
        workflow_id=row.workflow_id,
        skill_id=row.skill_id,
        engine_id=row.engine_id,
        skill_display_name=row.skill_display_name,
        owner_email=row.owner_email,
        current_stage=row.current_stage,
        status=row.status,
        eval_score=row.eval_score,
        eval_status=row.eval_status,
        eval_report=eval_rep,
        templatized_instruction=templatized,
        required_connectors=req_connectors,
        requested_groups=list(row.requested_groups or []),
        distribution_scope=str(row.distribution_scope or "SINGLE_APP"),
        target_engines=list(row.target_engines or [row.engine_id]),
        target_app_evaluations=list(row.target_app_evaluations or []),
        distributed_apps=list(row.distributed_apps or []),
        sub_skills=sub_skills,
        infosec_risk_level=row.infosec_risk_level,
        infosec_status=row.infosec_status,
        infosec_report=dict(row.infosec_report or {}),
        approval_status=row.approval_status,
        approved_by=row.approved_by,
        approval_notes=row.approval_notes,
        approved_at=(
            row.approved_at.isoformat() if row.approved_at else None
        ),
        registry_id=row.registry_id,
        shared_in_ge=row.shared_in_ge,
        shared_principals=list(row.shared_principals or []),
        started_at=row.started_at.isoformat() if row.started_at else None,
        updated_at=row.updated_at.isoformat() if row.updated_at else None,
        completed_at=(
            row.completed_at.isoformat() if row.completed_at else None
        ),
    )


def send_infosec_approval_email(
    session: orm.Session,
    workflow: db_models.SkillWorkflowRecord,
    skill: db_models.GESkillRecord,
) -> db_models.WorkflowEmailRecord:
    """Dispatches Stage 3 InfoSec review email via SMTP and local outbox."""
    recipient = os.environ.get(
        "INFOSEC_APPROVAL_EMAIL", DEFAULT_INFOSEC_RECIPIENT
    )
    subject = (
        f"[InfoSec Approval Required] GE Skill '{skill.display_name}' "
        f"({skill.engine_id})"
    )
    proposals_text = ", ".join(
        str(p.get("principal", "")) for p in (skill.iam_proposals or [])
    )
    body = (
        f"Hello InfoSec Governance Team,\n\n"
        f"A user-created Gemini Enterprise skill is awaiting Stage 3 "
        f"InfoSec Approval before Registry publication and GE App sharing.\n\n"
        f"• Skill Name: {skill.display_name}\n"
        f"• Parent GE App: {skill.app_display_name} ({skill.engine_id})\n"
        f"• Skill Owner: {skill.owner_email}\n"
        f"• Share Requested For: {proposals_text or 'App Users'}\n"
        f"• Stage 1 (Skill Evaluation ADK Agent): {workflow.eval_status} "
        f"(Score: {workflow.eval_score}/100)\n"
        f"• Stage 2 (InfoSec ADK Agent): {workflow.infosec_status} "
        f"(Risk Level: {workflow.infosec_risk_level})\n\n"
        f"Please review and click 'Approve & Publish' in the Gemini "
        f"Enterprise AppHub -> Skills -> Pending Review tab.\n"
    )

    delivery_status = "QUEUED_LOCAL_OUTBOX"
    smtp_host = os.environ.get("SMTP_HOST", "").strip()
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    if smtp_host:
        try:
            msg = email_message.EmailMessage()
            msg["Subject"] = subject
            msg["From"] = os.environ.get(
                "SMTP_FROM", "ge-apphub@mohanrajs.altostrat.com"
            )
            msg["To"] = recipient
            msg.set_content(body)
            with smtplib.SMTP(smtp_host, smtp_port, timeout=5.0) as client:
                client.send_message(msg)
            delivery_status = "SENT_SMTP"
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.debug("SMTP send skipped/failed (%s); saved to outbox.", exc)

    record = db_models.WorkflowEmailRecord(
        workflow_id=workflow.workflow_id,
        skill_id=skill.skill_id,
        recipient_email=recipient,
        subject=subject,
        body_text=body,
        delivery_status=delivery_status,
        created_at=_utc_now(),
    )
    session.add(record)
    session.flush()
    return record


def parameterize_skill_instruction(instruction: str) -> str:
    """Replaces hardcoded Discovery Engine IDs with {{engine_id}} template."""
    return skill_eval_agent.templatize_skill_environment(instruction)


def render_skill_instruction_for_engine(
    instruction: str,
    target_engine_id: str,
) -> str:
    """Renders a parameterized SKILL.md instruction for a target engine_id."""
    if not instruction:
        return ""
    parameterized = parameterize_skill_instruction(instruction)
    return skill_eval_agent.render_skill_for_engine(
        parameterized, target_engine_id
    )


_FEDERATED_GROUP_TO_ENGINE: dict[str, str] = {
    "ge-finance-users": "finance-app-01",
    "ge-hr-users": "hr-app-01",
    "ge-marketing-users": "marketing-app-01",
    "ge-ops-users": "ops-app-01",
    "ge-sales-users": "sales-app-01",
    "ge-service-desk-users": "service-desk-app-01",
}


def resolve_target_engines_from_groups(
    session: orm.Session,
    skill: db_models.GESkillRecord,
    principals: list[str],
) -> tuple[str, list[str]]:
    """Resolves ('GLOBAL' | 'MULTI_APP' | 'SINGLE_APP', target_engine_ids).

    Maps shared Cloud Identity / M365 group names from IAM proposals to their
    bound Gemini Enterprise App engine_ids. If a global group (e.g.,
    'global-skills@...', 'all-ge-apps-users@...', 'all-apps@...') is present,
    all discovered GE Apps are targeted.
    """
    all_apps = [
        r.engine_id
        for r in session.query(db_models.GEApplicationRecord).all()
        if r.engine_id
    ]
    bindings = (
        session.query(db_models.AppGroupBindingRecord)
        .filter_by(principal_type="group")
        .all()
    )
    group_to_engines: dict[str, set[str]] = {}
    for b in bindings:
        grp = (b.principal_identifier or "").strip().lower()
        if grp:
            group_to_engines.setdefault(grp, set()).add(b.engine_id)

    target_engines: set[str] = {skill.engine_id} if skill.engine_id else set()
    is_global = False

    for raw in principals:
        clean = raw.strip().lower()
        if clean.startswith("group:"):
            grp_email = clean.split(":", 1)[1].strip()
        elif "@" in clean and not clean.startswith("user:"):
            grp_email = clean
        else:
            continue

        local_part = grp_email.split("@", 1)[0]
        if any(
            kw in local_part
            for kw in (
                "global",
                "all-ge-apps",
                "all-apps",
                "all-users",
                "org-wide",
            )
        ):
            is_global = True
            break

        if grp_email in group_to_engines:
            target_engines.update(group_to_engines[grp_email])
        elif local_part in _FEDERATED_GROUP_TO_ENGINE:
            target_engines.add(_FEDERATED_GROUP_TO_ENGINE[local_part])
        elif local_part.endswith("-users"):
            candidate_eng = local_part[: -len("-users")]
            for app_id in all_apps:
                if app_id == candidate_eng or app_id.startswith(candidate_eng):
                    target_engines.add(app_id)

    if is_global and all_apps:
        return "GLOBAL", sorted(set(all_apps) | target_engines)
    sorted_targets = sorted(target_engines)
    scope = "MULTI_APP" if len(sorted_targets) > 1 else "SINGLE_APP"
    return scope, sorted_targets


def publish_skill_to_agent_platform_registry(
    skill: db_models.GESkillRecord,
    settings: config.Settings,
) -> tuple[str, str]:
    """Publishes skill to GCP Agent Platform Skill Registry (agentregistry)."""
    slug = re.sub(r"[^a-z0-9-]+", "-", skill.display_name.lower()).strip("-")
    if len(slug) < 4:
        slug = f"skill-{slug or 'custom'}"
    slug = slug[:60]
    project = settings.gcp_project_id or "mohandemo"
    location = settings.gcp_location or "global"
    default_res = (
        f"projects/{project}/locations/{location}/skills/private-{slug}"
    )
    default_urn = (
        f"urn:skill:projects-{project}:locations:{location}:private-{slug}"
    )

    if settings.use_mock_data:
        return default_urn, default_res

    try:
        credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        authed = google_requests.AuthorizedSession(credentials)
        authed.headers["x-goog-user-project"] = project

        get_url = f"https://agentregistry.googleapis.com/v1alpha/{default_res}"
        existing = authed.get(get_url, timeout=10.0)
        if existing.status_code == 200:
            data = existing.json()
            return (
                str(data.get("skillId") or default_urn),
                str(data.get("name") or default_res),
            )

        raw_instruction = skill.instruction or f"# {skill.display_name}\n"
        instruction = parameterize_skill_instruction(raw_instruction)
        desc_clean = (
            (skill.description or skill.display_name).replace("\n", " ").strip()
        )
        if not instruction.lstrip().startswith("---"):
            skill_md = (
                f"---\nname: {slug}\ndescription: >-\n"
                f"  {desc_clean}\n---\n\n{instruction}"
            )
        else:
            skill_md = instruction

        buf = io.BytesIO()
        with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
            zf.writestr("SKILL.md", skill_md.encode("utf-8"))
        zip_b64 = base64.b64encode(buf.getvalue()).decode("ascii")

        create_url = (
            f"https://agentregistry.googleapis.com/v1alpha/"
            f"projects/{project}/locations/{location}/skills?skillId={slug}"
        )
        payload: dict[str, Any] = {
            "displayName": slug,
            "description": skill.description or skill.display_name,
            "type": "SIMPLE",
            "targetState": "TARGET_STATE_ACTIVE",
            "scanningConfig": {"policy": "ENABLED_NONBLOCKING"},
            "initialRevision": {
                "archiveUploadSource": {"archiveContent": zip_b64}
            },
        }
        create_resp = authed.post(create_url, json=payload, timeout=20.0)
        if create_resp.status_code in (200, 201):
            check_resp = authed.get(get_url, timeout=10.0)
            if check_resp.status_code == 200:
                c_data = check_resp.json()
                return (
                    str(c_data.get("skillId") or default_urn),
                    str(c_data.get("name") or default_res),
                )
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Agent Platform Skill Registry publish note for %s: %s",
            skill.skill_id,
            exc,
        )
    return default_urn, default_res


def share_skill_in_discovery_engine(
    skill: db_models.GESkillRecord,
    principals: list[str],
    settings: config.Settings,
    registry_resource_name: str = "",
    target_engines: list[str] | None = None,
) -> bool:
    """Applies Stage 5 IAM sharing from Agent Platform Skill Registry & GE."""
    if settings.use_mock_data or not skill.resource_name:
        return True
    try:
        credentials, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        authed = google_requests.AuthorizedSession(credentials)
        project = settings.gcp_project_id or "mohandemo"
        location = settings.gcp_location or "global"
        authed.headers["x-goog-user-project"] = project
        base = "https://discoveryengine.googleapis.com/v1alpha"

        for prop in skill.iam_proposals or []:
            prop_id = str(prop.get("proposal_id") or "").strip()
            if prop_id:
                app_url = (
                    f"{base}/{skill.resource_name}/iamProposals/"
                    f"{prop_id}:approve"
                )
                authed.post(app_url, json={}, timeout=5.0)

        authed.post(
            f"{base}/{skill.resource_name}:publish",
            json={},
            timeout=5.0,
        )
        authed.post(
            f"{base}/{skill.resource_name}:requestAgentReview",
            json={},
            timeout=5.0,
        )
        authed.post(
            f"{base}/{skill.resource_name}:enableAgent",
            json={},
            timeout=5.0,
        )
        authed.patch(
            f"{base}/{skill.resource_name}?updateMask=sharingConfig",
            json={"sharingConfig": {"scope": "ALL_USERS"}},
            timeout=5.0,
        )

        pol_url = f"{base}/{skill.resource_name}:getIamPolicy"
        pol_resp = authed.get(pol_url, timeout=5.0)
        bindings: list[dict[str, Any]] = []
        etag = ""
        owners: set[str] = set()
        if pol_resp.status_code == 200:
            pol_json = pol_resp.json()
            bindings = list(pol_json.get("bindings") or [])
            etag = str(pol_json.get("etag") or "")
            for b in bindings:
                if b.get("role") == "roles/discoveryengine.agentOwner":
                    owners.update(b.get("members") or [])

        user_members = [
            p if ":" in p else f"user:{p}"
            for p in principals
            if p and not p.startswith("group:")
        ]
        de_members = (
            set(user_members) | {"domain:mohanrajs.altostrat.com"}
        ) - owners
        updated_role = False
        for b in bindings:
            if b.get("role") == "roles/discoveryengine.agentUser":
                merged = sorted(
                    (set(b.get("members") or []) | de_members) - owners
                )
                b["members"] = merged
                updated_role = True
        if not updated_role and de_members:
            bindings.append(
                {
                    "role": "roles/discoveryengine.agentUser",
                    "members": sorted(de_members),
                }
            )
        set_pol_url = f"{base}/{skill.resource_name}:setIamPolicy"
        policy_body: dict[str, Any] = {"policy": {"bindings": bindings}}
        if etag:
            policy_body["policy"]["etag"] = etag
        authed.post(set_pol_url, json=policy_body, timeout=5.0)

        for eng_id in target_engines or []:
            if not eng_id or eng_id == skill.engine_id:
                continue
            agents_url = (
                f"{base}/projects/{project}/locations/{location}/"
                f"collections/default_collection/engines/{eng_id}/"
                "assistants/default_assistant/agents"
            )
            list_resp = authed.get(agents_url, timeout=8.0)
            if list_resp.status_code != 200:
                continue
            existing_agents = list_resp.json().get("agents") or []
            matched = next(
                (
                    a
                    for a in existing_agents
                    if a.get("displayName") == skill.display_name
                ),
                None,
            )
            rendered_instruction = render_skill_instruction_for_engine(
                skill.instruction, eng_id
            )
            if matched is None:
                create_resp = authed.post(
                    agents_url,
                    json={
                        "displayName": skill.display_name,
                        "description": skill.description,
                        "sharingConfig": {"scope": "ALL_USERS"},
                        "skillAgentDefinition": {
                            "instruction": rendered_instruction
                        },
                    },
                    timeout=10.0,
                )
                target_ag_name = (
                    str(create_resp.json().get("name") or "")
                    if create_resp.status_code in (200, 201)
                    else ""
                )
            else:
                target_ag_name = str(matched.get("name") or "")
            if target_ag_name:
                authed.post(
                    f"{base}/{target_ag_name}:publish",
                    json={},
                    timeout=8.0,
                )
                authed.post(
                    f"{base}/{target_ag_name}:requestAgentReview",
                    json={},
                    timeout=8.0,
                )
                authed.post(
                    f"{base}/{target_ag_name}:enableAgent",
                    json={},
                    timeout=8.0,
                )
                t_pol = authed.get(
                    f"{base}/{target_ag_name}:getIamPolicy",
                    timeout=5.0,
                )
                if t_pol.status_code == 200:
                    t_json = t_pol.json()
                    t_etag = str(t_json.get("etag") or "")
                    t_bindings = list(t_json.get("bindings") or [])
                    t_owners = {
                        m
                        for b in t_bindings
                        if b.get("role") == "roles/discoveryengine.agentOwner"
                        for m in (b.get("members") or [])
                    }
                    t_members = sorted((de_members | {"domain:mohanrajs.demo.altostrat.com"}) - t_owners)
                    t_bindings = [
                        b
                        for b in t_bindings
                        if b.get("role") != "roles/discoveryengine.agentUser"
                    ]
                    if t_members:
                        t_bindings.append(
                            {
                                "role": "roles/discoveryengine.agentUser",
                                "members": t_members,
                            }
                        )
                    t_body: dict[str, Any] = {"policy": {"bindings": t_bindings}}
                    if t_etag:
                        t_body["policy"]["etag"] = t_etag
                    authed.post(
                        f"{base}/{target_ag_name}:setIamPolicy",
                        json=t_body,
                        timeout=5.0,
                    )
                authed.patch(
                    f"{base}/{target_ag_name}?updateMask=sharingConfig",
                    json={"sharingConfig": {"scope": "ALL_USERS"}},
                    timeout=5.0,
                )

        if registry_resource_name:
            ar_base = "https://agentregistry.googleapis.com/v1alpha"
            ar_pol_url = f"{ar_base}/{registry_resource_name}:getIamPolicy"
            ar_resp = authed.get(ar_pol_url, timeout=8.0)
            if ar_resp.status_code == 200:
                ar_json = ar_resp.json()
                ar_bindings = list(ar_json.get("bindings") or [])
                ar_etag = str(ar_json.get("etag") or "")
                reg_members: set[str] = {"domain:mohanrajs.altostrat.com"}
                for mem in user_members:
                    reg_members.add(mem)
                    raw_email = mem.split(":", 1)[-1]
                    reg_members.add(
                        "principalSet://agents.global.org-962907136954."
                        "system.id.goog/attribute."
                        f"agentResourceProjectAgentUser/720923281941/{raw_email}"
                    )
                viewer_updated = False
                for b in ar_bindings:
                    if b.get("role") == "roles/agentregistry.viewer":
                        b["members"] = sorted(
                            set(b.get("members") or []).union(reg_members)
                        )
                        viewer_updated = True
                if not viewer_updated:
                    ar_bindings.append(
                        {
                            "role": "roles/agentregistry.viewer",
                            "members": sorted(reg_members),
                        }
                    )
                ar_body: dict[str, Any] = {
                    "policy": {"bindings": ar_bindings}
                }
                if ar_etag:
                    ar_body["policy"]["etag"] = ar_etag
                authed.post(
                    f"{ar_base}/{registry_resource_name}:setIamPolicy",
                    json=ar_body,
                    timeout=8.0,
                )
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Discovery Engine skill share IAM update note for %s: %s",
            skill.skill_id,
            exc,
        )
    return True


def _collect_requested_groups_and_targets(
    session: orm.Session,
    skill: db_models.GESkillRecord,
    extra_principals: list[str] | None = None,
) -> tuple[list[str], str, list[str]]:
    """Extracts requested group principals and resolves target GE Apps."""
    raw_principals: list[str] = list(skill.shared_principals or [])
    for prop in skill.iam_proposals or []:
        p = str(prop.get("principal") or "").strip().lower()
        if p:
            raw_principals.append(p)
    for ep in extra_principals or []:
        if ep:
            raw_principals.append(ep.strip().lower())

    app_bindings = (
        session.query(db_models.AppGroupBindingRecord)
        .filter_by(engine_id=skill.engine_id, principal_type="group")
        .all()
    )
    for b in app_bindings:
        if b.principal_identifier:
            raw_principals.append(f"group:{b.principal_identifier}")

    groups: set[str] = set()
    for item in raw_principals:
        clean = item.strip().lower()
        if clean.startswith("group:"):
            groups.add(clean.split(":", 1)[1].strip())
        elif "@" in clean and not clean.startswith("user:"):
            groups.add(clean)

    scope, targets = resolve_target_engines_from_groups(
        session=session,
        skill=skill,
        principals=raw_principals,
    )
    return sorted(groups), scope, targets


def _evaluate_all_target_apps(
    session: orm.Session,
    skill: db_models.GESkillRecord,
    eval_result: dict[str, Any],
    selected_targets: list[str],
) -> list[dict[str, Any]]:
    """Evaluates skill readiness & token savings across candidate GE Apps."""
    app_rows = (
        session.query(db_models.GEApplicationRecord)
        .order_by(db_models.GEApplicationRecord.id.asc())
        .all()
    )
    candidate_apps: list[dict[str, Any]] = []
    seen_engines: set[str] = set()
    for r in app_rows:
        seen_engines.add(r.engine_id)
        candidate_apps.append(
            {
                "engine_id": r.engine_id,
                "display_name": r.display_name or r.engine_id,
                "location": r.location or "global",
                "data_store_ids": list(r.data_store_ids or []),
            }
        )
    for eng_id in selected_targets:
        if eng_id and eng_id not in seen_engines:
            seen_engines.add(eng_id)
            candidate_apps.append(
                {
                    "engine_id": eng_id,
                    "display_name": eng_id,
                    "location": "global",
                    "data_store_ids": [],
                }
            )

    evals = skill_eval_agent.evaluate_target_apps_readiness(
        display_name=skill.display_name,
        description=skill.description,
        instruction=skill.instruction,
        target_apps=candidate_apps,
        base_eval=eval_result,
    )
    selected_set = set(selected_targets)
    for item in evals:
        item["selected_for_distribution"] = (
            item.get("engine_id") in selected_set
        )
    return evals


def _build_distributed_apps_manifest(
    session: orm.Session,
    target_engines: list[str],
    now: datetime.datetime,
) -> list[dict[str, Any]]:
    """Builds the per-app distribution manifest for approved target GE Apps."""
    apps_by_id = {
        r.engine_id: r
        for r in session.query(db_models.GEApplicationRecord).all()
    }
    distributed: list[dict[str, Any]] = []
    for eng_id in target_engines:
        app_row = apps_by_id.get(eng_id)
        distributed.append(
            {
                "engine_id": eng_id,
                "app_display_name": (
                    app_row.display_name if app_row else eng_id
                ),
                "location": app_row.location if app_row else "global",
                "launch_url": app_row.launch_url if app_row else "",
                "status": "DISTRIBUTED",
                "sharing_scope": "ALL_USERS",
                "distributed_at": now.isoformat(),
            }
        )
    return distributed


class SkillWorkflowEngine:
    """Orchestrates the 6-stage Multi-App AI Skill Hub workflow."""

    def __init__(
        self,
        settings: config.Settings | None = None,
        eval_agent: skill_eval_agent.SkillEvaluationAdkAgent | None = None,
        sec_agent: infosec_agent.InfoSecAdkAgent | None = None,
    ) -> None:
        """Initializes SkillWorkflowEngine with Stage 1 & Stage 2 ADK agents."""
        self._settings = settings or config.get_settings()
        self._eval_agent = (
            eval_agent or skill_eval_agent.SkillEvaluationAdkAgent()
        )
        self._sec_agent = sec_agent or infosec_agent.InfoSecAdkAgent()

    def start_or_run_workflow(
        self,
        session: orm.Session,
        skill_id: str,
        force_restart: bool = False,
    ) -> models.SkillWorkflowItem:
        """Starts or advances the workflow for a skill through Stages 1-4."""
        skill = (
            session.query(db_models.GESkillRecord)
            .filter_by(skill_id=skill_id)
            .one_or_none()
        )
        if skill is None:
            raise ValueError(f"Skill '{skill_id}' not found.")

        wf = (
            session.query(db_models.SkillWorkflowRecord)
            .filter_by(skill_id=skill_id)
            .one_or_none()
        )
        now = _utc_now()
        if wf is not None and not force_restart:
            if wf.status in ("AWAITING_APPROVAL", "COMPLETED", "REJECTED"):
                return workflow_record_to_model(wf)

        raw_short = skill_id.replace(":", "-")
        if wf is None:
            wf = db_models.SkillWorkflowRecord(
                workflow_id=f"wf-{raw_short}",
                skill_id=skill.skill_id,
                engine_id=skill.engine_id,
                skill_display_name=skill.display_name,
                owner_email=skill.owner_email,
                current_stage="SKILL_EVALUATION",
                status="RUNNING",
                started_at=now,
                updated_at=now,
            )
            session.add(wf)
            session.flush()

        # Stage 1 & 2: Templatize Environment, Extract Connectors, Map Groups
        # and Evaluate Skill across all Target GE Apps
        eval_result = self._eval_agent.evaluate_skill(
            display_name=skill.display_name,
            description=skill.description,
            instruction=skill.instruction,
            subfiles=list(skill.subfiles or []),
        )
        req_groups, dist_scope, target_engines = (
            _collect_requested_groups_and_targets(
                session=session,
                skill=skill,
            )
        )
        target_app_evals = _evaluate_all_target_apps(
            session=session,
            skill=skill,
            eval_result=eval_result,
            selected_targets=target_engines,
        )
        wf.templatized_instruction = str(
            eval_result.get("templatized_instruction")
            or parameterize_skill_instruction(skill.instruction)
        )
        wf.required_connectors = list(
            eval_result.get("required_connectors") or []
        )
        extracted_subskills = list(
            skill.sub_skills
            or eval_result.get("sub_skills")
            or skill_eval_agent.extract_sub_skills(skill.instruction)
        )
        skill.sub_skills = extracted_subskills
        wf.sub_skills = extracted_subskills
        wf.requested_groups = req_groups
        wf.distribution_scope = dist_scope
        wf.target_engines = target_engines
        wf.target_app_evaluations = target_app_evals
        wf.eval_score = int(eval_result.get("score", 0))
        wf.eval_status = "PASSED" if eval_result.get("passed") else "FAILED"
        wf.eval_report = eval_result
        wf.updated_at = _utc_now()

        if not eval_result.get("passed"):
            wf.current_stage = "SKILL_EVALUATION"
            wf.status = "FAILED"
            session.commit()
            return workflow_record_to_model(wf)

        # Stage 3: Invoke Local ADK InfoSec Agent
        wf.current_stage = "INFOSEC_SCAN"
        sec_result = self._sec_agent.scan_skill(
            display_name=skill.display_name,
            instruction=skill.instruction,
            gcs_uri=skill.gcs_uri,
            iam_proposals=list(skill.iam_proposals or []),
        )
        wf.infosec_risk_level = str(sec_result.get("risk_level", "LOW"))
        wf.infosec_status = "PASSED" if sec_result.get("passed") else "FAILED"
        wf.infosec_report = sec_result
        wf.updated_at = _utc_now()

        if not sec_result.get("passed"):
            wf.current_stage = "INFOSEC_SCAN"
            wf.status = "FAILED"
            session.commit()
            return workflow_record_to_model(wf)

        # Stage 4: Send InfoSec Approval Email & Wait for Human Approval
        wf.current_stage = "AWAITING_INFOSEC_APPROVAL"
        wf.status = "AWAITING_APPROVAL"
        wf.approval_status = "PENDING"
        send_infosec_approval_email(
            session=session,
            workflow=wf,
            skill=skill,
        )
        wf.updated_at = _utc_now()
        session.commit()
        return workflow_record_to_model(wf)

    def approve_workflow(
        self,
        session: orm.Session,
        skill_id: str,
        approver_email: str,
        notes: str = "",
        target_engines: list[str] | None = None,
    ) -> models.SkillWorkflowItem:
        """Executes Approval -> Registry Publish -> Multi-App Distribution."""
        skill = (
            session.query(db_models.GESkillRecord)
            .filter_by(skill_id=skill_id)
            .one_or_none()
        )
        if skill is None:
            raise ValueError(f"Skill '{skill_id}' not found.")

        wf = (
            session.query(db_models.SkillWorkflowRecord)
            .filter_by(skill_id=skill_id)
            .one_or_none()
        )
        if wf is None:
            self.start_or_run_workflow(session=session, skill_id=skill_id)
            wf = (
                session.query(db_models.SkillWorkflowRecord)
                .filter_by(skill_id=skill_id)
                .one()
            )

        now = _utc_now()
        clean_approver = (
            approver_email.strip().lower()
            or "infosec-admin@mohanrajs.altostrat.com"
        )
        wf.approval_status = "APPROVED"
        wf.approved_by = clean_approver
        wf.approval_notes = (
            notes.strip() or "Approved by InfoSec review for GE App sharing."
        )
        wf.approved_at = now

        # Collect target principals from IAM proposals + GE App group bindings
        target_principals: set[str] = set(skill.shared_principals or [])
        updated_proposals: list[dict[str, Any]] = []
        for prop in skill.iam_proposals or []:
            p_copy = dict(prop)
            p_copy["state"] = "APPROVED"
            updated_proposals.append(p_copy)
            principal = str(prop.get("principal") or "").strip().lower()
            if principal:
                target_principals.add(principal)

        app_bindings = (
            session.query(db_models.AppGroupBindingRecord)
            .filter_by(engine_id=skill.engine_id, principal_type="group")
            .all()
        )
        for b in app_bindings:
            target_principals.add(f"group:{b.principal_identifier}")

        sorted_principals = sorted(target_principals)
        req_groups, resolved_scope, resolved_targets = (
            _collect_requested_groups_and_targets(
                session=session,
                skill=skill,
                extra_principals=sorted_principals,
            )
        )
        if target_engines:
            selected_targets = sorted(
                {e.strip() for e in target_engines if e.strip()}
                | ({skill.engine_id} if skill.engine_id else set())
            )
        elif wf.target_engines:
            selected_targets = sorted(
                set(wf.target_engines) | set(resolved_targets)
            )
        else:
            selected_targets = resolved_targets

        all_app_count = session.query(db_models.GEApplicationRecord).count()
        if all_app_count > 1 and len(selected_targets) >= all_app_count - 1:
            dist_scope = "GLOBAL"
        elif len(selected_targets) > 1:
            dist_scope = "MULTI_APP"
        else:
            dist_scope = resolved_scope

        for target_eng in selected_targets:
            eng_bindings = (
                session.query(db_models.AppGroupBindingRecord)
                .filter_by(engine_id=target_eng, principal_type="group")
                .all()
            )
            for eb in eng_bindings:
                if eb.principal_identifier:
                    target_principals.add(f"group:{eb.principal_identifier}")
                    if eb.principal_identifier not in req_groups:
                        req_groups.append(eb.principal_identifier)
        sorted_principals = sorted(target_principals)
        req_groups = sorted(set(req_groups))

        param_instruction = parameterize_skill_instruction(skill.instruction)
        req_connectors = list(
            wf.required_connectors
            or skill_eval_agent.extract_required_connectors(skill.instruction)
        )
        resolved_sub_skills = list(
            skill.sub_skills
            or wf.sub_skills
            or skill_eval_agent.extract_sub_skills(skill.instruction)
        )
        skill.sub_skills = resolved_sub_skills
        wf.sub_skills = resolved_sub_skills

        # Stage 5: Publish the Skill in the GCP Agent Platform Skill Registry
        wf.current_stage = "PUBLISH_REGISTRY"
        reg_id, reg_res_name = publish_skill_to_agent_platform_registry(
            skill=skill,
            settings=self._settings,
        )

        # Stage 6: Distribute Skill from Registry to each Target GE App
        wf.current_stage = "SHARE_TO_APP"
        share_skill_in_discovery_engine(
            skill=skill,
            principals=sorted_principals,
            settings=self._settings,
            registry_resource_name=reg_res_name,
            target_engines=selected_targets,
        )
        distributed_apps = _build_distributed_apps_manifest(
            session=session,
            target_engines=selected_targets,
            now=now,
        )

        reg_row = (
            session.query(db_models.SkillRegistryRecord)
            .filter_by(skill_id=skill.skill_id)
            .one_or_none()
        )
        if reg_row is None:
            reg_row = db_models.SkillRegistryRecord(
                registry_id=reg_id,
                skill_id=skill.skill_id,
                resource_name=reg_res_name,
                engine_id=skill.engine_id,
                app_display_name=skill.app_display_name or skill.engine_id,
                display_name=skill.display_name,
                description=skill.description,
                instruction=param_instruction,
                version="1.0.0",
                owner_email=skill.owner_email,
                eval_score=wf.eval_score,
                infosec_risk_level=wf.infosec_risk_level,
                approved_by=clean_approver,
                shared_principals=sorted_principals,
                required_connectors=req_connectors,
                target_engines=selected_targets,
                distributed_apps=distributed_apps,
                sub_skills=resolved_sub_skills,
                published_at=now,
            )
            session.add(reg_row)
        else:
            reg_row.registry_id = reg_id
            reg_row.resource_name = reg_res_name
            reg_row.instruction = param_instruction
            reg_row.approved_by = clean_approver
            reg_row.eval_score = wf.eval_score
            reg_row.infosec_risk_level = wf.infosec_risk_level
            reg_row.shared_principals = sorted_principals
            reg_row.required_connectors = req_connectors
            reg_row.target_engines = selected_targets
            reg_row.distributed_apps = distributed_apps
            reg_row.sub_skills = resolved_sub_skills
            reg_row.published_at = now
        wf.registry_id = reg_id

        skill.review_status = "APPROVED"
        skill.state = "ENABLED"
        skill.sharing_state = "SHARED"
        skill.has_active_iam_proposals = False
        skill.iam_proposals = updated_proposals
        skill.shared_principals = sorted_principals

        wf.templatized_instruction = param_instruction
        wf.required_connectors = req_connectors
        wf.requested_groups = req_groups
        wf.distribution_scope = dist_scope
        wf.target_engines = selected_targets
        wf.target_app_evaluations = _evaluate_all_target_apps(
            session=session,
            skill=skill,
            eval_result=dict(wf.eval_report or {}),
            selected_targets=selected_targets,
        )
        wf.distributed_apps = distributed_apps
        wf.shared_in_ge = True
        wf.shared_principals = sorted_principals
        wf.current_stage = "COMPLETED"
        wf.status = "COMPLETED"
        wf.completed_at = now
        wf.updated_at = now
        session.commit()

        publisher = ge_agent_publisher.GeAgentPublisherService(
            settings=self._settings
        )
        for target_eng in selected_targets:
            publisher.sync_starter_prompts_for_engine(
                session=session,
                engine_id=target_eng,
            )
        return workflow_record_to_model(wf)

    def reject_workflow(
        self,
        session: orm.Session,
        skill_id: str,
        approver_email: str,
        notes: str = "",
    ) -> models.SkillWorkflowItem:
        """Records Stage 3 InfoSec Rejection and halts workflow."""
        wf = (
            session.query(db_models.SkillWorkflowRecord)
            .filter_by(skill_id=skill_id)
            .one_or_none()
        )
        if wf is None:
            self.start_or_run_workflow(session=session, skill_id=skill_id)
            wf = (
                session.query(db_models.SkillWorkflowRecord)
                .filter_by(skill_id=skill_id)
                .one()
            )
        now = _utc_now()
        wf.approval_status = "REJECTED"
        wf.approved_by = approver_email.strip().lower()
        wf.approval_notes = notes.strip() or "Rejected by InfoSec review."
        wf.approved_at = now
        wf.current_stage = "REJECTED"
        wf.status = "REJECTED"
        wf.completed_at = now
        wf.updated_at = now
        session.commit()
        return workflow_record_to_model(wf)
