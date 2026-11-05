"""FastAPI router for triggering and inspecting scheduled database syncs."""

import fastapi
from sqlalchemy import orm

from app import config
from app import database
from app import models
from app.services import sync

router = fastapi.APIRouter(prefix="/api/v1/sync", tags=["sync"])


def get_sync_service() -> sync.CatalogSyncService:
    """Provides a configured CatalogSyncService instance."""
    settings = config.get_settings()
    return sync.CatalogSyncService(settings=settings)


@router.post("", response_model=models.SyncRunSummary)
def trigger_sync(
    session: orm.Session = fastapi.Depends(database.get_db_session),
    sync_service: sync.CatalogSyncService = fastapi.Depends(get_sync_service),
) -> models.SyncRunSummary:
    """Triggers an immediate synchronization of GE apps and Cloud Identity."""
    return sync_service.run_sync(session=session, trigger_source="manual_api")


@router.get("/status", response_model=models.SyncStatusResponse)
def read_sync_status(
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.SyncStatusResponse:
    """Returns the current sync schedule configuration and DB entity counts."""
    settings = config.get_settings()
    return sync.get_sync_status(session=session, settings=settings)
