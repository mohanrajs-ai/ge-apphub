"""Configuration management for the Gemini Enterprise AppHub backend."""

import os

import pydantic


class Settings(pydantic.BaseModel):
    """Application settings resolved from environment variables."""

    gcp_project_id: str = "demo-gcp-project"
    gcp_location: str = "global"
    firestore_collection: str = "ge_app_catalog"
    use_mock_data: bool = True
    admin_users: list[str] = pydantic.Field(default_factory=list)


def _parse_bool(value: str | None, default: bool = True) -> bool:
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


def get_settings() -> Settings:
    """Loads and returns current application settings from the environment.

    Returns:
        Configured Settings instance.
    """
    return Settings(
        gcp_project_id=os.environ.get("GCP_PROJECT_ID", "demo-gcp-project"),
        gcp_location=os.environ.get("GCP_LOCATION", "global"),
        firestore_collection=os.environ.get(
            "FIRESTORE_COLLECTION", "ge_app_catalog"
        ),
        use_mock_data=_parse_bool(
            os.environ.get("USE_MOCK_DATA"), default=True
        ),
        admin_users=_parse_csv(os.environ.get("ADMIN_USERS")),
    )
