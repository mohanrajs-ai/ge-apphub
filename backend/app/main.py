"""FastAPI application entrypoint for Gemini Enterprise AppHub."""

import fastapi
from fastapi.middleware import cors

from app import auth
from app import config
from app import models


def create_app() -> fastapi.FastAPI:
    """Creates and configures the FastAPI application instance.

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

    return application


app = create_app()
