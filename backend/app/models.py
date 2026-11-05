"""Pydantic data models for the Gemini Enterprise AppHub backend."""

import pydantic


class UserContext(pydantic.BaseModel):
    """Represents the authenticated user identity and resolved roles."""

    email: str
    user_id: str
    roles: list[str]
    groups: list[str] = pydantic.Field(default_factory=list)
    auth_source: str


class DiscoveredEngine(pydantic.BaseModel):
    """Represents a raw Gemini Enterprise / Discovery Engine record."""

    engine_id: str
    display_name: str
    location: str
    solution_type: str = "SOLUTION_TYPE_SEARCH"
    industry_vertical: str = "GENERIC"
    app_type: str = "APP_TYPE_INTRANET"
    default_launch_url: str
    iam_principals: list[str] = pydantic.Field(default_factory=list)


class AppEnrichmentMetadata(pydantic.BaseModel):
    """Represents Firestore enrichment metadata for a GE application."""

    engine_id: str
    description: str = ""
    category: str = "Productivity"
    department: str = "General"
    tags: list[str] = pydantic.Field(default_factory=list)
    icon_name: str = "Sparkles"
    launch_url: str | None = None
    allowed_roles: list[str] = pydantic.Field(default_factory=lambda: ["*"])
    featured: bool = False


class CatalogApplication(pydantic.BaseModel):
    """Represents an enriched Gemini Enterprise application in the catalog."""

    engine_id: str
    display_name: str
    description: str
    category: str
    department: str
    tags: list[str]
    icon_name: str
    launch_url: str
    location: str
    solution_type: str
    allowed_roles: list[str]
    featured: bool = False


class CatalogResponse(pydantic.BaseModel):
    """Represents the API response payload for GET /api/v1/apps."""

    items: list[CatalogApplication]
    total: int
    categories: list[str]
    departments: list[str]
    groups: list[str] = pydantic.Field(default_factory=list)


class SuggestedUser(pydantic.BaseModel):
    """Represents a quick-select Workspace user account for sign-in."""

    email: str
    label: str
    description: str


class AuthConfigResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/auth/config."""

    google_client_id: str = ""
    suggested_users: list[SuggestedUser] = pydantic.Field(default_factory=list)


class LoginRequest(pydantic.BaseModel):
    """Represents the request payload for POST /api/v1/auth/login."""

    email: str | None = None
    id_token: str | None = None
    role: str | None = None


class LoginResponse(pydantic.BaseModel):
    """Represents the response payload for POST /api/v1/auth/login."""

    token: str
    user: UserContext


class SyncRunSummary(pydantic.BaseModel):
    """Represents a completed or failed synchronization audit record."""

    id: int
    trigger_source: str
    status: str
    apps_synced: int
    groups_synced: int
    memberships_synced: int
    error_message: str | None = None
    started_at: str | None = None
    completed_at: str | None = None


class SyncStatusResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/sync/status."""

    sync_enabled: bool
    sync_interval_seconds: int
    database_dialect: str
    total_apps: int
    total_groups: int
    total_users: int
    total_memberships: int
    last_run: SyncRunSummary | None = None


class CloudIdentityGroupInfo(pydantic.BaseModel):
    """Represents a synced Cloud Identity group stored in the database."""

    group_email: str
    group_resource_name: str
    display_name: str
    description: str = ""
    member_count: int = 0
    members: list[str] = pydantic.Field(default_factory=list)
    app_engine_ids: list[str] = pydantic.Field(default_factory=list)
    is_member: bool = False
    last_synced_at: str | None = None


class GroupListResponse(pydantic.BaseModel):
    """Represents the response payload for GET /api/v1/groups."""

    items: list[CloudIdentityGroupInfo]
    total: int
