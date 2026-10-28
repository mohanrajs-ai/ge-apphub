"""Authentication and role resolution dependencies for FastAPI."""

import fastapi

from app import config
from app import models


def _strip_iap_prefix(raw_value: str) -> str:
    """Removes the Google Cloud IAP prefix (e.g., accounts.google.com:).

    Args:
        raw_value: Raw header string from IAP.

    Returns:
        Cleaned identifier or email string.
    """
    if ":" in raw_value:
        return raw_value.split(":", 1)[1].strip()
    return raw_value.strip()


def _normalize_roles(raw_roles: str | None) -> list[str]:
    """Parses comma-separated role names and ensures 'employee' base role.

    Args:
        raw_roles: Optional comma-separated role string.

    Returns:
        Ordered list of unique lower-case role identifiers.
    """
    roles: list[str] = []
    if raw_roles:
        for part in raw_roles.split(","):
            cleaned = part.strip().lower()
            if cleaned and cleaned not in roles:
                roles.append(cleaned)
    if "employee" not in roles:
        roles.append("employee")
    return roles


def resolve_current_user(request: fastapi.Request) -> models.UserContext:
    """Resolves the active user context from IAP or development headers.

    Args:
        request: Incoming FastAPI HTTP request.

    Returns:
        Resolved UserContext instance.
    """
    settings = config.get_settings()
    headers = request.headers

    iap_email = headers.get("x-goog-authenticated-user-email")
    iap_id = headers.get("x-goog-authenticated-user-id")
    if iap_email:
        clean_email = _strip_iap_prefix(iap_email).lower()
        clean_id = _strip_iap_prefix(iap_id) if iap_id else clean_email
        roles: list[str] = []
        if clean_email in settings.admin_users:
            roles.append("admin")
        roles.append("employee")
        return models.UserContext(
            email=clean_email,
            user_id=clean_id,
            roles=roles,
            auth_source="gcp_iap",
        )

    dev_email = headers.get("x-dev-user-email")
    dev_role = headers.get("x-dev-user-role")
    if settings.use_mock_data and (dev_email or dev_role):
        resolved_email = (
            dev_email.strip().lower()
            if dev_email
            else "developer@enterprise.example.com"
        )
        return models.UserContext(
            email=resolved_email,
            user_id=resolved_email,
            roles=_normalize_roles(dev_role),
            auth_source="dev_override",
        )

    if settings.use_mock_data:
        return models.UserContext(
            email="developer@enterprise.example.com",
            user_id="dev-user-001",
            roles=["employee", "engineering", "data-analyst"],
            auth_source="mock_default",
        )

    return models.UserContext(
        email="anonymous@enterprise.example.com",
        user_id="anonymous",
        roles=["employee"],
        auth_source="unauthenticated_fallback",
    )
