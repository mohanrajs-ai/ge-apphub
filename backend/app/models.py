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
