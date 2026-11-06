"""Skills router for querying synced Gemini Enterprise skills and approvals."""

import fastapi
from sqlalchemy import orm

from app import auth
from app import database
from app import models
from app.services import sync as sync_service

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
