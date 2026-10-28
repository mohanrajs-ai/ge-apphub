"""FastAPI application entrypoint for Gemini Enterprise AppHub."""

import pathlib

import fastapi
from fastapi import responses
from fastapi import staticfiles
from fastapi.middleware import cors

from app import auth
from app import config
from app import models
from app.routers import apps

DEFAULT_FRONTEND_DIST = (
    pathlib.Path(__file__).resolve().parents[2] / "frontend" / "dist"
)


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

    application.include_router(apps.router)

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
