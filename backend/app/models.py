"""Pydantic data models for the Gemini Enterprise AppHub backend."""

import pydantic


class UserContext(pydantic.BaseModel):
    """Represents the authenticated user identity and resolved roles."""

    email: str
    user_id: str
    roles: list[str]
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
