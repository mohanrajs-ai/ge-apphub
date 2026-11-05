"""Catalog service querying PostgreSQL and merging Discovery Engine metadata."""

from sqlalchemy import orm

from app import auth
from app import config
from app import db_models
from app import models
from app.services import discovery
from app.services import firestore as firestore_service
from app.services import sync


def _is_user_authorized(
    allowed_roles: list[str],
    user_roles: list[str],
    user_email: str = "",
    user_groups: list[str] | None = None,
    iam_principals: list[str] | None = None,
) -> bool:
    """Checks whether the user's roles or groups grant visibility to an app.

    Args:
        allowed_roles: Roles permitted by the application metadata.
        user_roles: Roles assigned to the current user.
        user_email: Active user email address.
        user_groups: Cloud Identity group emails the user belongs to.
        iam_principals: Optional Discovery Engine IAM principals.

    Returns:
        True if the user may view and launch the application.
    """
    normalized_user = {role.strip().lower() for role in user_roles}
    if "admin" in normalized_user:
        return True

    if iam_principals:
        normalized_iam = {
            p.strip().lower() for p in iam_principals if p.strip()
        }
        clean_email = user_email.strip().lower()
        if clean_email:
            if f"user:{clean_email}" in normalized_iam:
                return True
            if "@" in clean_email:
                domain = clean_email.split("@", 1)[1]
                if f"domain:{domain}" in normalized_iam:
                    return True
        active_groups = {
            g.strip().lower() for g in (user_groups or []) if g.strip()
        }
        for group_email in active_groups:
            if (
                group_email in normalized_iam
                or f"group:{group_email}" in normalized_iam
            ):
                return True
        for role in normalized_user:
            if role in normalized_iam or f"group:{role}" in normalized_iam:
                return True
        return False

    normalized_allowed = {role.strip().lower() for role in allowed_roles}
    if not normalized_allowed or "*" in normalized_allowed:
        return True
    if "public" in normalized_allowed:
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
    """Queries synced GE applications from PostgreSQL or live services."""

    def __init__(
        self,
        discovery_service: discovery.DiscoveryEngineService,
        firestore_service: firestore_service.FirestoreMetadataService,
        session: orm.Session | None = None,
    ) -> None:
        """Initializes CatalogService.

        Args:
            discovery_service: Service for listing Discovery Engine apps.
            firestore_service: Service for fetching Firestore metadata.
            session: Optional SQLAlchemy database session for DB-backed queries.
        """
        self._discovery = discovery_service
        self._firestore = firestore_service
        self._session = session

    def _list_visible_from_db(
        self,
        session: orm.Session,
        user_roles: list[str],
        user_email: str = "",
        user_groups: list[str] | None = None,
    ) -> list[models.CatalogApplication]:
        """Queries GE applications and user groups directly from PostgreSQL."""
        rows = (
            session.query(db_models.GEApplicationRecord)
            .order_by(db_models.GEApplicationRecord.id.asc())
            .all()
        )
        if not rows:
            settings = getattr(
                self._discovery, "_settings", None
            ) or config.get_settings()
            sync_svc = sync.CatalogSyncService(
                settings=settings,
                discovery_service=self._discovery,
                firestore_service=self._firestore,
            )
            sync_svc.run_sync(session=session, trigger_source="auto_seed")
            rows = (
                session.query(db_models.GEApplicationRecord)
                .order_by(db_models.GEApplicationRecord.id.asc())
                .all()
            )

        resolved_groups = user_groups
        if resolved_groups is None and user_email:
            settings = getattr(
                self._discovery, "_settings", None
            ) or config.get_settings()
            resolved_groups = auth.resolve_user_groups_from_db(
                session=session,
                user_email=user_email,
                settings=settings,
                discovery_service=self._discovery,
            )

        visible: list[models.CatalogApplication] = []
        for row in rows:
            if not _is_user_authorized(
                allowed_roles=list(row.allowed_roles or []),
                user_roles=user_roles,
                user_email=user_email,
                user_groups=resolved_groups,
                iam_principals=list(row.iam_principals or []),
            ):
                continue
            visible.append(
                models.CatalogApplication(
                    engine_id=row.engine_id,
                    display_name=row.display_name,
                    description=row.description,
                    category=row.category,
                    department=row.department,
                    tags=list(row.tags or []),
                    icon_name=row.icon_name,
                    launch_url=row.launch_url,
                    location=row.location,
                    solution_type=row.solution_type,
                    allowed_roles=list(row.allowed_roles or []),
                    featured=row.featured,
                )
            )
        return visible

    def list_visible_applications(
        self,
        user_roles: list[str],
        user_email: str = "",
        user_groups: list[str] | None = None,
    ) -> list[models.CatalogApplication]:
        """Returns all enriched applications visible to the user's roles/groups.

        Args:
            user_roles: Active user roles.
            user_email: Active user email address.
            user_groups: Optional pre-resolved Cloud Identity group emails.

        Returns:
            List of role- and group-filtered CatalogApplication items.
        """
        if self._session is not None:
            return self._list_visible_from_db(
                session=self._session,
                user_roles=user_roles,
                user_email=user_email,
                user_groups=user_groups,
            )
        engines = self._discovery.list_engines()
        enrichment_map = self._firestore.get_enrichment_map()

        resolved_groups = user_groups
        if (
            resolved_groups is None
            and user_email
            and any(engine.iam_principals for engine in engines)
        ):
            resolved_groups = self._discovery.resolve_user_groups(
                user_email=user_email,
                engines=engines,
            )

        merged: list[models.CatalogApplication] = []
        for engine in engines:
            meta = enrichment_map.get(engine.engine_id)
            allowed_roles = (
                meta.allowed_roles
                if meta
                else (engine.iam_principals or ["*"])
            )
            if not _is_user_authorized(
                allowed_roles=allowed_roles,
                user_roles=user_roles,
                user_email=user_email,
                user_groups=resolved_groups,
                iam_principals=engine.iam_principals,
            ):
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
        group: str | None = None,
        user_email: str = "",
        user_groups: list[str] | None = None,
    ) -> list[models.CatalogApplication]:
        """Lists visible applications filtered by search and facets.

        Args:
            user_roles: Active user roles.
            query: Optional free-text search query.
            category: Optional exact category filter.
            department: Optional exact department filter.
            tag: Optional tag filter.
            group: Optional Cloud Identity group email filter.
            user_email: Active user email address.
            user_groups: Optional pre-resolved Cloud Identity group emails.

        Returns:
            Filtered list of CatalogApplication objects.
        """
        visible = self.list_visible_applications(
            user_roles=user_roles,
            user_email=user_email,
            user_groups=user_groups,
        )
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
            if group:
                clean_grp = group.strip().lower().removeprefix("group:")
                app_roles = {r.strip().lower() for r in app.allowed_roles}
                if (
                    clean_grp not in app_roles
                    and f"group:{clean_grp}" not in app_roles
                ):
                    continue
            results.append(app)
        return results
