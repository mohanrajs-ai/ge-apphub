"""Catalog service merging Discovery Engine apps with Firestore metadata."""

from app import models
from app.services import discovery
from app.services import firestore as firestore_service


def _is_user_authorized(
    allowed_roles: list[str],
    user_roles: list[str],
) -> bool:
    """Checks whether the user's roles grant visibility to an application.

    Args:
        allowed_roles: Roles permitted by the application metadata.
        user_roles: Roles assigned to the current user.

    Returns:
        True if the user may view and launch the application.
    """
    normalized_allowed = {role.strip().lower() for role in allowed_roles}
    if not normalized_allowed or "*" in normalized_allowed:
        return True
    if "public" in normalized_allowed:
        return True
    normalized_user = {role.strip().lower() for role in user_roles}
    if "admin" in normalized_user:
        return True
    return bool(normalized_allowed.intersection(normalized_user))


def _matches_search_query(
    app: models.CatalogApplication,
    query: str | None,
) -> bool:
    """Checks whether an application matches a free-text search query.

    Args:
        app: Enriched CatalogApplication object.
        query: Optional search substring.

    Returns:
        True if query is empty or matches any searchable field.
    """
    if not query or not query.strip():
        return True
    needle = query.strip().lower()
    haystacks = [
        app.display_name.lower(),
        app.description.lower(),
        app.category.lower(),
        app.department.lower(),
        app.engine_id.lower(),
        *(tag.lower() for tag in app.tags),
    ]
    return any(needle in text for text in haystacks)


class CatalogService:
    """Merges discovered GE engines with Firestore metadata and filters."""

    def __init__(
        self,
        discovery_service: discovery.DiscoveryEngineService,
        firestore_service: firestore_service.FirestoreMetadataService,
    ) -> None:
        """Initializes CatalogService.

        Args:
            discovery_service: Service for listing Discovery Engine apps.
            firestore_service: Service for fetching Firestore metadata.
        """
        self._discovery = discovery_service
        self._firestore = firestore_service

    def list_visible_applications(
        self,
        user_roles: list[str],
    ) -> list[models.CatalogApplication]:
        """Returns all enriched applications visible to the user's roles.

        Args:
            user_roles: Active user roles.

        Returns:
            List of role-filtered CatalogApplication items.
        """
        engines = self._discovery.list_engines()
        enrichment_map = self._firestore.get_enrichment_map()

        merged: list[models.CatalogApplication] = []
        for engine in engines:
            meta = enrichment_map.get(engine.engine_id)
            allowed_roles = meta.allowed_roles if meta else ["*"]
            if not _is_user_authorized(allowed_roles, user_roles):
                continue

            description = (
                meta.description
                if meta and meta.description
                else (
                    f"Gemini Enterprise {engine.solution_type} application "
                    f"hosted in {engine.location}."
                )
            )
            launch_url = (
                meta.launch_url
                if meta and meta.launch_url
                else engine.default_launch_url
            )
            merged.append(
                models.CatalogApplication(
                    engine_id=engine.engine_id,
                    display_name=engine.display_name,
                    description=description,
                    category=meta.category if meta else "Productivity",
                    department=meta.department if meta else "General",
                    tags=meta.tags if meta else ["gemini-enterprise"],
                    icon_name=meta.icon_name if meta else "Sparkles",
                    launch_url=launch_url,
                    location=engine.location,
                    solution_type=engine.solution_type,
                    allowed_roles=allowed_roles,
                    featured=meta.featured if meta else False,
                )
            )
        return merged

    def list_applications(
        self,
        user_roles: list[str],
        query: str | None = None,
        category: str | None = None,
        department: str | None = None,
        tag: str | None = None,
    ) -> list[models.CatalogApplication]:
        """Lists visible applications filtered by search and facets.

        Args:
            user_roles: Active user roles.
            query: Optional free-text search query.
            category: Optional exact category filter.
            department: Optional exact department filter.
            tag: Optional tag filter.

        Returns:
            Filtered list of CatalogApplication objects.
        """
        visible = self.list_visible_applications(user_roles=user_roles)
        results: list[models.CatalogApplication] = []
        for app in visible:
            if not _matches_search_query(app, query):
                continue
            if category and app.category.lower() != category.strip().lower():
                continue
            if (
                department
                and app.department.lower() != department.strip().lower()
            ):
                continue
            if tag and tag.strip().lower() not in {
                t.lower() for t in app.tags
            }:
                continue
            results.append(app)
        return results
