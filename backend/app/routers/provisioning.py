"""Admin-only Terraform & REST provisioning API endpoints."""

import json
from collections import abc

import fastapi
from fastapi import responses
from sqlalchemy import orm

from app import auth
from app import database
from app import db_models
from app import models
from app.services import ge_agent_publisher
from app.services import terraform_runner

router = fastapi.APIRouter(
    prefix="/api/v1/admin/provisioning",
    tags=["admin-provisioning"],
)


@router.get(
    "/jobs",
    response_model=models.ProvisioningJobListResponse,
)
def list_provisioning_jobs(
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobListResponse:
    """Returns all Terraform provisioning jobs ordered newest first."""
    records = (
        session.query(db_models.ProvisioningJobRecord)
        .order_by(db_models.ProvisioningJobRecord.id.desc())
        .all()
    )
    items = [terraform_runner.to_job_item(r) for r in records]
    return models.ProvisioningJobListResponse(
        items=items,
        total=len(items),
        active_workspace_locks=terraform_runner.get_active_workspace_locks(),
    )


@router.get(
    "/jobs/{job_id}",
    response_model=models.ProvisioningJobItem,
)
def get_provisioning_job(
    job_id: str,
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Returns a single Terraform provisioning job by job_id."""
    record = (
        session.query(db_models.ProvisioningJobRecord)
        .filter_by(job_id=job_id)
        .one_or_none()
    )
    if record is None:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_404_NOT_FOUND,
            detail=f"Provisioning job '{job_id}' not found.",
        )
    return terraform_runner.to_job_item(record)


@router.get("/jobs/{job_id}/stream")
def stream_provisioning_job_logs(
    job_id: str,
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> responses.StreamingResponse:
    """Streams redacted provisioning job logs via Server-Sent Events (SSE)."""
    record = (
        session.query(db_models.ProvisioningJobRecord)
        .filter_by(job_id=job_id)
        .one_or_none()
    )
    if record is None:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_404_NOT_FOUND,
            detail=f"Provisioning job '{job_id}' not found.",
        )
    item = terraform_runner.to_job_item(record)

    def _event_generator() -> abc.Iterator[str]:
        for idx, line in enumerate(item.log_lines):
            payload = json.dumps({"index": idx, "line": line})
            yield f"event: log\ndata: {payload}\n\n"
        done_payload = json.dumps(
            {
                "job_id": item.job_id,
                "status": item.status,
                "workspace_key": item.workspace_key,
                "outputs": item.outputs,
            }
        )
        yield f"event: status\ndata: {done_payload}\n\n"

    return responses.StreamingResponse(
        _event_generator(),
        media_type="text/event-stream",
    )


@router.post(
    "/ge-app",
    response_model=models.ProvisioningJobItem,
    status_code=fastapi.status.HTTP_201_CREATED,
)
def provision_ge_app(
    payload: models.GeAppProvisionRequest,
    admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Starts Stack 02 (GE App Instance) Terraform plan or apply."""
    svc = terraform_runner.TerraformProvisioningService()
    try:
        record = svc.create_and_run_plan(
            session=session,
            stack_type="GE_APP",
            raw_config=payload.model_dump(),
            initiated_by=admin.email,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    return terraform_runner.to_job_item(record)


@router.post(
    "/identity",
    response_model=models.ProvisioningJobItem,
    status_code=fastapi.status.HTTP_201_CREATED,
)
def provision_identity_wif(
    payload: models.IdentityProvisionRequest,
    admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Starts Stack 01 (Identity & WIF Foundation) Terraform plan or apply."""
    svc = terraform_runner.TerraformProvisioningService()
    try:
        record = svc.create_and_run_plan(
            session=session,
            stack_type="IDENTITY_WIF",
            raw_config=payload.model_dump(),
            initiated_by=admin.email,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    return terraform_runner.to_job_item(record)


@router.post(
    "/m365",
    response_model=models.ProvisioningJobItem,
    status_code=fastapi.status.HTTP_201_CREATED,
)
def provision_m365_connectors(
    payload: models.M365ConnectorProvisionRequest,
    admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Starts Stack 03 (M365 Data Connectors) Terraform plan or apply."""
    svc = terraform_runner.TerraformProvisioningService()
    try:
        record = svc.create_and_run_plan(
            session=session,
            stack_type="M365_CONNECTORS",
            raw_config=payload.model_dump(),
            initiated_by=admin.email,
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    return terraform_runner.to_job_item(record)


@router.post(
    "/jobs/{job_id}/approve",
    response_model=models.ProvisioningJobItem,
)
def approve_and_apply_job(
    job_id: str,
    payload: models.ProvisioningApprovalRequest,
    admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Approves a PENDING_APPROVAL Terraform plan and runs terraform apply."""
    svc = terraform_runner.TerraformProvisioningService()
    try:
        record = svc.approve_and_apply(
            session=session,
            job_id=job_id,
            approver_email=admin.email,
            notes=payload.notes,
        )
    except KeyError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    return terraform_runner.to_job_item(record)


@router.post(
    "/jobs/{job_id}/reject",
    response_model=models.ProvisioningJobItem,
)
def reject_planned_job(
    job_id: str,
    payload: models.ProvisioningApprovalRequest,
    admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.ProvisioningJobItem:
    """Rejects a PENDING_APPROVAL Terraform plan and releases state lock."""
    svc = terraform_runner.TerraformProvisioningService()
    try:
        record = svc.reject_job(
            session=session,
            job_id=job_id,
            reviewer_email=admin.email,
            notes=payload.notes,
        )
    except KeyError as exc:
        raise fastapi.HTTPException(
            status_code=fastapi.status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    return terraform_runner.to_job_item(record)


@router.get(
    "/ge-agents",
    response_model=models.GePinnedAgentListResponse,
)
def list_pinned_ge_agents(
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.GePinnedAgentListResponse:
    """Lists all Pinned Universal Skill Orchestrator registrations in GE."""
    svc = ge_agent_publisher.GeAgentPublisherService()
    return svc.list_registered_agents(session=session)


@router.post(
    "/ge-agents/publish",
    response_model=models.GePinnedAgentItem,
    status_code=fastapi.status.HTTP_201_CREATED,
)
def publish_pinned_ge_agent(
    payload: models.GePinnedAgentPublishRequest,
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.GePinnedAgentItem:
    """Registers & pins Universal Skill Orchestrator via agents-cli publish."""
    svc = ge_agent_publisher.GeAgentPublisherService()
    return svc.publish_pinned_agent(session=session, payload=payload)


@router.post(
    "/ge-agents/{engine_id}/sync-starter-prompts",
    response_model=models.GePinnedAgentItem,
)
def sync_pinned_agent_starter_prompts(
    engine_id: str,
    _admin: models.UserContext = fastapi.Depends(auth.require_admin),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.GePinnedAgentItem:
    """Syncs approved skills as starterPrompts on a pinned GE agent."""
    svc = ge_agent_publisher.GeAgentPublisherService()
    return svc.sync_starter_prompts_for_engine(
        session=session,
        engine_id=engine_id,
    )

