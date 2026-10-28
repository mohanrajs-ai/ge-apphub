"""FastAPI application entrypoint for Gemini Enterprise AppHub."""

import fastapi
from fastapi.middleware import cors

from app import config


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

    return application


app = create_app()
