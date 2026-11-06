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
        eval_report=dict(row.eval_report or {}),
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

        instruction = skill.instruction or f"# {skill.display_name}\n"
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
            f"{base}/{skill.resource_name}:enableAgent",
            json={},
            timeout=5.0,
        )

        pol_url = f"{base}/{skill.resource_name}:getIamPolicy"
        pol_resp = authed.get(pol_url, timeout=5.0)
        bindings: list[dict[str, Any]] = []
        etag = ""
        if pol_resp.status_code == 200:
            pol_json = pol_resp.json()
            bindings = list(pol_json.get("bindings") or [])
            etag = str(pol_json.get("etag") or "")

        user_members = [
            p if ":" in p else f"user:{p}"
            for p in principals
            if p and not p.startswith("group:")
        ]
        updated_role = False
        for b in bindings:
            if b.get("role") == "roles/discoveryengine.agentUser":
                merged = sorted(set(b.get("members") or []).union(user_members))
                b["members"] = merged
                updated_role = True
        if not updated_role and user_members:
            bindings.append(
                {
                    "role": "roles/discoveryengine.agentUser",
                    "members": sorted(set(user_members)),
                }
            )
        set_pol_url = f"{base}/{skill.resource_name}:setIamPolicy"
        policy_body: dict[str, Any] = {"policy": {"bindings": bindings}}
        if etag:
            policy_body["policy"]["etag"] = etag
        authed.post(set_pol_url, json=policy_body, timeout=5.0)

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


class SkillWorkflowEngine:
    """Orchestrates the 5-stage Skill Evaluation, InfoSec & Registry flow."""

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
        """Starts or advances the workflow for a skill through Stages 1-3."""
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

        # Stage 1: Invoke Local ADK Skill Evaluation Agent
        eval_result = self._eval_agent.evaluate_skill(
            display_name=skill.display_name,
            description=skill.description,
            instruction=skill.instruction,
            subfiles=list(skill.subfiles or []),
        )
        wf.eval_score = int(eval_result.get("score", 0))
        wf.eval_status = "PASSED" if eval_result.get("passed") else "FAILED"
        wf.eval_report = eval_result
        wf.updated_at = _utc_now()

        if not eval_result.get("passed"):
            wf.current_stage = "SKILL_EVALUATION"
            wf.status = "FAILED"
            session.commit()
            return workflow_record_to_model(wf)

        # Stage 2: Invoke Local ADK InfoSec Agent
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

        # Stage 3: Send InfoSec Approval Email & Wait for Human Approval
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
    ) -> models.SkillWorkflowItem:
        """Executes Stage 3 Approval -> Stage 4 Registry -> Stage 5 GE Share."""
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

        # Stage 4: Publish the Skill in the GCP Agent Platform Skill Registry
        wf.current_stage = "PUBLISH_REGISTRY"
        reg_id, reg_res_name = publish_skill_to_agent_platform_registry(
            skill=skill,
            settings=self._settings,
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
                instruction=skill.instruction,
                version="1.0.0",
                owner_email=skill.owner_email,
                eval_score=wf.eval_score,
                infosec_risk_level=wf.infosec_risk_level,
                approved_by=clean_approver,
                shared_principals=sorted_principals,
                published_at=now,
            )
            session.add(reg_row)
        else:
            reg_row.registry_id = reg_id
            reg_row.resource_name = reg_res_name
            reg_row.approved_by = clean_approver
            reg_row.eval_score = wf.eval_score
            reg_row.infosec_risk_level = wf.infosec_risk_level
            reg_row.shared_principals = sorted_principals
            reg_row.published_at = now
        wf.registry_id = reg_id

        # Stage 5: Share the Skill from the Agent Platform Skill Registry
        wf.current_stage = "SHARE_TO_APP"
        share_skill_in_discovery_engine(
            skill=skill,
            principals=sorted_principals,
            settings=self._settings,
            registry_resource_name=reg_res_name,
        )
        skill.review_status = "APPROVED"
        skill.state = "ENABLED"
        skill.sharing_state = "SHARED"
        skill.has_active_iam_proposals = False
        skill.iam_proposals = updated_proposals
        skill.shared_principals = sorted_principals

        wf.shared_in_ge = True
        wf.shared_principals = sorted_principals
        wf.current_stage = "COMPLETED"
        wf.status = "COMPLETED"
        wf.completed_at = now
        wf.updated_at = now
        session.commit()
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
