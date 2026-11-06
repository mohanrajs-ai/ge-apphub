"""REST API router for the Skill Governance & Approval Workflow Microservice."""

import fastapi
from sqlalchemy import orm

from app import auth
from app import config
from app import database
from app import db_models
from app import models
from skill_workflow_service import engine as wf_engine

router = fastapi.APIRouter(tags=["skill-workflows"])


@router.get(
    "/api/v1/workflows/skills",
    response_model=models.SkillWorkflowListResponse,
)
def list_skill_workflows(
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillWorkflowListResponse:
    """Lists all 5-stage skill governance workflows."""
    rows = (
        session.query(db_models.SkillWorkflowRecord)
        .order_by(db_models.SkillWorkflowRecord.id.desc())
        .all()
    )
    items = [wf_engine.workflow_record_to_model(r) for r in rows]
    return models.SkillWorkflowListResponse(items=items, total=len(items))


@router.post(
    "/api/v1/workflows/skills/start",
    response_model=models.SkillWorkflowItem,
)
def start_skill_workflow(
    payload: models.SkillWorkflowStartRequest,
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillWorkflowItem:
    """Starts or resumes the 5-stage governance workflow for a skill."""
    eng = wf_engine.SkillWorkflowEngine(settings=config.get_settings())
    try:
        return eng.start_or_run_workflow(
            session=session,
            skill_id=payload.skill_id,
            force_restart=True,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=404, detail=str(exc)
        ) from exc


@router.get(
    "/api/v1/workflows/skills/{skill_id}",
    response_model=models.SkillWorkflowItem,
)
def get_skill_workflow(
    skill_id: str,
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillWorkflowItem:
    """Returns workflow status and ADK agent reports for a skill."""
    row = (
        session.query(db_models.SkillWorkflowRecord)
        .filter_by(skill_id=skill_id)
        .one_or_none()
    )
    if row is None:
        eng = wf_engine.SkillWorkflowEngine(settings=config.get_settings())
        try:
            return eng.start_or_run_workflow(
                session=session, skill_id=skill_id
            )
        except ValueError as exc:
            raise fastapi.HTTPException(
                status_code=404, detail=str(exc)
            ) from exc
    return wf_engine.workflow_record_to_model(row)


@router.post(
    "/api/v1/workflows/skills/{skill_id}/approve",
    response_model=models.SkillWorkflowItem,
)
def approve_skill_workflow(
    skill_id: str,
    payload: models.SkillApprovalRequest | None = None,
    user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillWorkflowItem:
    """Approves Stage 3 InfoSec review, publishes to Registry & shares to GE."""
    approver = (
        payload.approver_email
        if payload and payload.approver_email
        else user.email
    )
    notes = payload.notes if payload else ""
    eng = wf_engine.SkillWorkflowEngine(settings=config.get_settings())
    try:
        return eng.approve_workflow(
            session=session,
            skill_id=skill_id,
            approver_email=approver,
            notes=notes,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=404, detail=str(exc)
        ) from exc


@router.post(
    "/api/v1/workflows/skills/{skill_id}/reject",
    response_model=models.SkillWorkflowItem,
)
def reject_skill_workflow(
    skill_id: str,
    payload: models.SkillApprovalRequest | None = None,
    user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillWorkflowItem:
    """Rejects Stage 3 InfoSec review and records reviewer notes."""
    approver = (
        payload.approver_email
        if payload and payload.approver_email
        else user.email
    )
    notes = payload.notes if payload else ""
    eng = wf_engine.SkillWorkflowEngine(settings=config.get_settings())
    try:
        return eng.reject_workflow(
            session=session,
            skill_id=skill_id,
            approver_email=approver,
            notes=notes,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=404, detail=str(exc)
        ) from exc


@router.get(
    "/api/v1/registry/skills",
    response_model=models.SkillRegistryListResponse,
)
def list_registry_skills(
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillRegistryListResponse:
    """Lists all vetted and approved skills published in the Skill Registry."""
    rows = (
        session.query(db_models.SkillRegistryRecord)
        .order_by(db_models.SkillRegistryRecord.id.desc())
        .all()
    )
    items = [
        models.SkillRegistryItem(
            registry_id=r.registry_id,
            skill_id=r.skill_id,
            resource_name=r.resource_name,
            engine_id=r.engine_id,
            app_display_name=r.app_display_name,
            display_name=r.display_name,
            description=r.description,
            instruction=r.instruction,
            version=r.version,
            owner_email=r.owner_email,
            eval_score=r.eval_score,
            infosec_risk_level=r.infosec_risk_level,
            approved_by=r.approved_by,
            shared_principals=list(r.shared_principals or []),
            published_at=(
                r.published_at.isoformat() if r.published_at else None
            ),
        )
        for r in rows
    ]
    return models.SkillRegistryListResponse(items=items, total=len(items))


@router.get(
    "/api/v1/workflows/notifications",
    response_model=models.WorkflowEmailListResponse,
)
def list_workflow_notifications(
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.WorkflowEmailListResponse:
    """Lists InfoSec approval email notifications sent by Stage 3."""
    rows = (
        session.query(db_models.WorkflowEmailRecord)
        .order_by(db_models.WorkflowEmailRecord.id.desc())
        .all()
    )
    items = [
        models.WorkflowEmailItem(
            id=r.id,
            workflow_id=r.workflow_id,
            skill_id=r.skill_id,
            recipient_email=r.recipient_email,
            subject=r.subject,
            body_text=r.body_text,
            delivery_status=r.delivery_status,
            created_at=r.created_at.isoformat() if r.created_at else None,
        )
        for r in rows
    ]
    return models.WorkflowEmailListResponse(items=items, total=len(items))
