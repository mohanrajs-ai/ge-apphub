"""FastAPI router for Gemini Enterprise application catalog endpoints."""

import fastapi

from app import auth
from app import config
from app import models
from app.services import catalog
from app.services import discovery
from app.services import firestore as firestore_service

router = fastapi.APIRouter(prefix="/api/v1/apps", tags=["catalog"])


def get_catalog_service() -> catalog.CatalogService:
    """Provides a configured CatalogService instance.

    Returns:
        Configured CatalogService instance.
    """
    settings = config.get_settings()
    disc_service = discovery.DiscoveryEngineService(settings=settings)
    fs_service = firestore_service.FirestoreMetadataService(settings=settings)
    return catalog.CatalogService(
        discovery_service=disc_service,
        firestore_service=fs_service,
    )


@router.get("", response_model=models.CatalogResponse)
def list_apps(
    q: str | None = fastapi.Query(default=None, description="Search query"),
    category: str | None = fastapi.Query(
        default=None,
        description="Filter by business category",
    ),
    department: str | None = fastapi.Query(
        default=None,
        description="Filter by department",
    ),
    tag: str | None = fastapi.Query(
        default=None,
        description="Filter by capability tag",
    ),
    group: str | None = fastapi.Query(
        default=None,
        description="Filter by Cloud Identity group email",
    ),
    user: models.UserContext = fastapi.Depends(auth.resolve_current_user),
    catalog_service: catalog.CatalogService = fastapi.Depends(
        get_catalog_service
    ),
) -> models.CatalogResponse:
    """Returns the role-filtered, searchable list of GE applications."""
    all_visible = catalog_service.list_visible_applications(
        user_roles=user.roles,
        user_email=user.email,
        user_groups=user.groups or None,
    )
    filtered = catalog_service.list_applications(
        user_roles=user.roles,
        query=q,
        category=category,
        department=department,
        tag=tag,
        group=group,
        user_email=user.email,
        user_groups=user.groups or None,
    )
    categories = sorted({item.category for item in all_visible})
    departments = sorted({item.department for item in all_visible})
    groups: set[str] = set(user.groups)
    for item in all_visible:
        for role in item.allowed_roles:
            if role.startswith("group:"):
                groups.add(role.split(":", 1)[1].strip().lower())
    return models.CatalogResponse(
        items=filtered,
        total=len(filtered),
        categories=categories,
        departments=departments,
        groups=sorted(groups),
    )
