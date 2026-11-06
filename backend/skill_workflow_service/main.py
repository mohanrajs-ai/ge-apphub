"""Standalone FastAPI microservice for Skill Governance & Approval Workflows."""

import contextlib
from collections import abc

import fastapi
from fastapi.middleware import cors

from app import config
from app import database
from skill_workflow_service import router as workflow_router


@contextlib.asynccontextmanager
async def _workflow_lifespan(
    _app: fastapi.FastAPI,
) -> abc.AsyncIterator[None]:
    """Initializes shared database schema on microservice startup."""
    database.init_db()
    yield


def create_workflow_app() -> fastapi.FastAPI:
    """Creates the standalone Skill Workflow Microservice FastAPI app."""
    service_app = fastapi.FastAPI(
        title="Gemini Enterprise Skill Governance Workflow Microservice",
        description=(
            "Standalone microservice orchestrating Stage 1 ADK Skill "
            "Evaluation, Stage 2 ADK InfoSec Scan, Stage 3 InfoSec Email & "
            "Approval, Stage 4 Skill Registry Publication, and Stage 5 GE "
            "App Sharing."
        ),
        version="0.1.0",
        lifespan=_workflow_lifespan,
    )

    service_app.add_middleware(
        cors.CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    @service_app.get("/api/v1/health", tags=["system"])
    def health_check() -> dict[str, str]:
        """Returns microservice health status."""
        settings = config.get_settings()
        return {
            "status": "ok",
            "service": "ge-skill-workflow-service",
            "gcp_project_id": settings.gcp_project_id,
        }

    service_app.include_router(workflow_router.router)
    return service_app


app = create_workflow_app()
