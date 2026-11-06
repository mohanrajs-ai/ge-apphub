"""FastAPI application entrypoint for Gemini Enterprise AppHub."""

import asyncio
import contextlib
import pathlib
from collections import abc

import fastapi
from fastapi import responses
from fastapi import staticfiles
from fastapi.middleware import cors

from app import auth
from app import config
from app import database
from app import db_models
from app import models
from app.routers import apps
from app.routers import auth as auth_router
from app.routers import groups as groups_router
from app.routers import skills as skills_router
from app.routers import sync as sync_router
from app.services import sync as sync_service
from skill_workflow_service import router as workflow_router

DEFAULT_FRONTEND_DIST = (
    pathlib.Path(__file__).resolve().parents[2] / "frontend" / "dist"
)


@contextlib.asynccontextmanager
async def _app_lifespan(
    _app: fastapi.FastAPI,
) -> abc.AsyncIterator[None]:
    """Initializes database schema, startup sync, and periodic scheduler."""
    settings = config.get_settings()
    database.init_db()
    if settings.sync_enabled and settings.sync_on_startup:
        with database.session_scope() as session:
            has_apps = (
                session.query(db_models.GEApplicationRecord).count() > 0
            )
            if not has_apps:
                svc = sync_service.CatalogSyncService(settings=settings)
                svc.run_sync(session=session, trigger_source="startup")

    worker_task: asyncio.Task[None] | None = None
    if settings.sync_enabled:
        worker_task = asyncio.create_task(
            sync_service.periodic_sync_worker(
                settings.sync_interval_seconds
            )
        )
    try:
        yield
    finally:
        if worker_task is not None:
            worker_task.cancel()
            with contextlib.suppress(asyncio.CancelledError):
                await worker_task


def create_app(
    static_dir: pathlib.Path | None = None,
) -> fastapi.FastAPI:
    """Creates and configures the FastAPI application instance.

    Args:
        static_dir: Optional directory containing compiled SPA static files.

    Returns:
        Configured FastAPI application.
    """
    application = fastapi.FastAPI(
        title="Gemini Enterprise AppHub API",
        description=(
            "Centralized hub and marketplace API for discovering and "
            "accessing Gemini Enterprise applications."
        ),
        version="0.1.0",
        lifespan=_app_lifespan,
    )

    application.add_middleware(
        cors.CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @application.get("/api/v1/health", tags=["system"])
    def health_check() -> dict[str, str]:
        """Returns service health status and current execution mode."""
        settings = config.get_settings()
        mode = "mock" if settings.use_mock_data else "live"
        return {
            "status": "ok",
            "service": "ge-apphub-backend",
            "mode": mode,
            "gcp_project_id": settings.gcp_project_id,
        }

    @application.get(
        "/api/v1/me",
        response_model=models.UserContext,
        tags=["auth"],
    )
    def get_current_user(
        user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    ) -> models.UserContext:
        """Returns the resolved identity and roles for the current user."""
        return user

    application.include_router(auth_router.router)
    application.include_router(apps.router)
    application.include_router(groups_router.router)
    application.include_router(skills_router.router)
    application.include_router(workflow_router.router)
    application.include_router(sync_router.router)

    resolved_dist = static_dir or DEFAULT_FRONTEND_DIST
    index_html = resolved_dist / "index.html"
    assets_dir = resolved_dist / "assets"
    if assets_dir.is_dir():
        application.mount(
            "/assets",
            staticfiles.StaticFiles(directory=str(assets_dir)),
            name="assets",
        )
    if index_html.is_file():
        @application.get("/", include_in_schema=False)
        def serve_spa_root() -> responses.FileResponse:
            """Serves the compiled React SPA entrypoint."""
            return responses.FileResponse(str(index_html))

    return application


app = create_app()
