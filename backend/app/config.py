"""Configuration management for the Gemini Enterprise AppHub backend."""

import os

import pydantic

DEFAULT_ADMIN_USERS: tuple[str, ...] = (
    "admin@mohanrajs.altostrat.com",
    "infosec@mohanrajs.altostrat.com",
    "infosec-admin@mohanrajs.altostrat.com",
)


class Settings(pydantic.BaseModel):
    """Application settings resolved from environment variables."""

    gcp_project_id: str = "mohandemo"
    gcp_location: str = "global"
    firestore_collection: str = "ge_app_catalog"
    use_mock_data: bool = False
    admin_users: list[str] = pydantic.Field(
        default_factory=lambda: list(DEFAULT_ADMIN_USERS)
    )
    google_client_id: str = ""
    google_client_secret: str = ""
    session_secret: str = "ge-apphub-session-secret-key"
    database_url: str = "postgresql+psycopg://localhost:5432/geapphub"
    sync_enabled: bool = True
    sync_interval_seconds: int = 900
    sync_on_startup: bool = True


def _parse_bool(value: str | None, default: bool = False) -> bool:
    """Parses a boolean environment variable string.

    Args:
        value: Raw environment variable value.
        default: Default boolean when value is None.

    Returns:
        Parsed boolean value.
    """
    if value is None:
        return default
    return value.strip().lower() in ("1", "true", "yes", "on")


def _parse_csv(value: str | None) -> list[str]:
    """Parses a comma-separated environment variable into a list of strings.

    Args:
        value: Raw comma-separated string.

    Returns:
        List of non-empty trimmed strings.
    """
    if not value:
        return []
    return [item.strip().lower() for item in value.split(",") if item.strip()]


def _parse_int(value: str | None, default: int) -> int:
    """Parses an integer environment variable string.

    Args:
        value: Raw environment variable value.
        default: Default integer when value is None or invalid.

    Returns:
        Parsed integer value.
    """
    if value is None or not value.strip():
        return default
    try:
        return int(value.strip())
    except ValueError:
        return default


def get_settings() -> Settings:
    """Loads and returns current application settings from the environment.

    Returns:
        Configured Settings instance.
    """
    return Settings(
        gcp_project_id=os.environ.get("GCP_PROJECT_ID", "mohandemo"),
        gcp_location=os.environ.get("GCP_LOCATION", "global"),
        firestore_collection=os.environ.get(
            "FIRESTORE_COLLECTION", "ge_app_catalog"
        ),
        use_mock_data=_parse_bool(
            os.environ.get("USE_MOCK_DATA"), default=False
        ),
        admin_users=sorted(
            set(DEFAULT_ADMIN_USERS).union(
                _parse_csv(os.environ.get("ADMIN_USERS"))
            )
        ),
        google_client_id=os.environ.get("GOOGLE_CLIENT_ID", "").strip(),
        google_client_secret=os.environ.get(
            "GOOGLE_CLIENT_SECRET", ""
        ).strip(),
        session_secret=os.environ.get(
            "SESSION_SECRET", "ge-apphub-session-secret-key"
        ),
        database_url=os.environ.get(
            "DATABASE_URL", "postgresql+psycopg://localhost:5432/geapphub"
        ).strip(),
        sync_enabled=_parse_bool(
            os.environ.get("SYNC_ENABLED"), default=True
        ),
        sync_interval_seconds=_parse_int(
            os.environ.get("SYNC_INTERVAL_SECONDS"), default=900
        ),
        sync_on_startup=_parse_bool(
            os.environ.get("SYNC_ON_STARTUP"), default=True
        ),
    )
