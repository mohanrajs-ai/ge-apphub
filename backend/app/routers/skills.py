"""Skills router for querying synced Gemini Enterprise skills and approvals."""

import fastapi
from sqlalchemy import orm

from app import auth
from app import config
from app import database
from app import models
from app.services import sync as sync_service
from skill_workflow_service.agents import ge_discovery_llm

router = fastapi.APIRouter(prefix="/api/v1/skills", tags=["skills"])


@router.get("", response_model=models.SkillListResponse)
def list_skills(
    review_status: str | None = fastapi.Query(
        default=None,
        description="Filter by review status (PENDING_REVIEW, APPROVED, ALL).",
    ),
    engine_id: str | None = fastapi.Query(
        default=None,
        description="Filter by Gemini Enterprise application engine_id.",
    ),
    q: str | None = fastapi.Query(
        default=None,
        description="Free-text search across skill name, description, owner.",
    ),
    _user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillListResponse:
    """Returns synced Gemini Enterprise skills and pending review status."""
    return sync_service.list_synced_skills(
        session=session,
        review_status=review_status,
        engine_id=engine_id,
        q=q,
    )


@router.post(
    "/seed-catalog",
    response_model=models.SkillCatalogSeedResponse,
)
def seed_skills_catalog(
    _user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillCatalogSeedResponse:
    """Seeds atomic sub-skills and composite parent skills from catalog."""
    seeded = ge_discovery_llm.seed_composite_skills_catalog(session)
    return models.SkillCatalogSeedResponse(
        seeded_skills=seeded,
        total_seeded=len(seeded),
    )


@router.post(
    "/orchestrate",
    response_model=models.SkillOrchestrateResponse,
)
def orchestrate_skill(
    payload: models.SkillOrchestrateRequest,
    request: fastapi.Request,
    user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SkillOrchestrateResponse:
    """Executes a Parent Skill and its Sub-Skills via GE :streamAssist."""
    svc = ge_discovery_llm.UniversalSkillOrchestratorService(
        settings=config.get_settings()
    )
    try:
        return svc.orchestrate_skill(
            session=session,
            payload=payload,
            calling_user_email=user.email,
            request_headers=dict(request.headers),
        )
    except ValueError as exc:
        raise fastapi.HTTPException(
            status_code=404, detail=str(exc)
        ) from exc


@router.get("/{skill_id}", response_model=models.DiscoveredSkill)
def get_skill(
    skill_id: str,
    _user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.DiscoveredSkill:
    """Returns full details and SKILL.md instruction for a single GE skill."""
    skill = sync_service.get_synced_skill(session=session, skill_id=skill_id)
    if skill is None:
        raise fastapi.HTTPException(
            status_code=404,
            detail=f"Skill '{skill_id}' not found.",
        )
    return skill
