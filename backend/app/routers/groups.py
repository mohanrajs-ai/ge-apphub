"""FastAPI router for querying synced Cloud Identity groups from DB."""

import fastapi
from sqlalchemy import orm

from app import auth
from app import database
from app import models
from app.services import sync

router = fastapi.APIRouter(prefix="/api/v1/groups", tags=["groups"])


@router.get("", response_model=models.GroupListResponse)
def list_groups(
    user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.GroupListResponse:
    """Returns all Cloud Identity groups stored in the database."""
    return sync.list_synced_groups(session=session, user_email=user.email)
