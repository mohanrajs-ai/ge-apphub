"""Authentication and role resolution dependencies for FastAPI."""

import base64
import hashlib
import hmac
import json
import os

import fastapi
import google.auth
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token

from app import config
from app import models

_CACHED_ADC_EMAIL: str | None = None
_ADC_LOOKUP_ATTEMPTED: bool = False


def create_session_token(user: models.UserContext, secret: str) -> str:
    """Creates an HMAC-SHA256 signed session token for a UserContext.

    Args:
        user: Authenticated UserContext.
        secret: Server signing secret.

    Returns:
        Signed URL-safe token string.
    """
    payload_bytes = json.dumps(
        user.model_dump(), separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    encoded_payload = base64.urlsafe_b64encode(payload_bytes).decode("ascii")
    signature = hmac.new(
        secret.encode("utf-8"),
        encoded_payload.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return f"{encoded_payload}.{signature}"


def verify_session_token(
    token: str,
    secret: str,
) -> models.UserContext | None:
    """Verifies an HMAC-SHA256 signed session token and returns UserContext.

    Args:
        token: Signed token string.
        secret: Server signing secret.

    Returns:
        Decoded UserContext if valid, otherwise None.
    """
    if not token or "." not in token:
        return None
    encoded_payload, signature = token.rsplit(".", 1)
    expected_sig = hmac.new(
        secret.encode("utf-8"),
        encoded_payload.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    if not hmac.compare_digest(signature, expected_sig):
        return None
    try:
        raw_bytes = base64.urlsafe_b64decode(encoded_payload.encode("ascii"))
        data = json.loads(raw_bytes.decode("utf-8"))
        return models.UserContext(**data)
    except Exception:  # pylint: disable=broad-except
        return None


def verify_google_id_token_email(
    raw_id_token: str,
    client_id: str | None = None,
) -> str | None:
    """Verifies a Google OAuth 2.0 ID token and returns the user email.

    Args:
        raw_id_token: Encoded Google OIDC JWT string.
        client_id: Optional expected OAuth client ID audience.

    Returns:
        Verified lowercase email address or None if invalid.
    """
    try:
        request_adapter = google_requests.Request()
        audience = client_id if client_id else None
        claims = google_id_token.verify_oauth2_token(
            raw_id_token, request_adapter, audience=audience
        )
        email = claims.get("email")
        if email and "@" in str(email):
            return str(email).strip().lower()
    except Exception:  # pylint: disable=broad-except
        pass
    return None


def _resolve_adc_user_email() -> str | None:
    """Resolves the active Google Cloud ADC user email when running locally.

    Returns:
        Lowercase email string if available, otherwise None.
    """
    global _CACHED_ADC_EMAIL, _ADC_LOOKUP_ATTEMPTED  # pylint: disable=global-statement
    env_email = os.environ.get("DEFAULT_USER_EMAIL")
    if env_email and env_email.strip():
        return env_email.strip().lower()
    if _ADC_LOOKUP_ATTEMPTED:
        return _CACHED_ADC_EMAIL
    _ADC_LOOKUP_ATTEMPTED = True
    try:
        credentials, _ = google.auth.default()
        session = google_requests.AuthorizedSession(credentials)
        response = session.get(
            "https://oauth2.googleapis.com/tokeninfo", timeout=3.0
        )
        if response.status_code == 200:
            email = response.json().get("email")
            if email and "@" in str(email):
                _CACHED_ADC_EMAIL = str(email).strip().lower()
    except Exception:  # pylint: disable=broad-except
        pass
    return _CACHED_ADC_EMAIL


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

    auth_header = headers.get("authorization")
    if auth_header and auth_header.lower().startswith("bearer "):
        raw_token = auth_header.split(" ", 1)[1].strip()
        token_user = verify_session_token(raw_token, settings.session_secret)
        if token_user is not None:
            dev_role = headers.get("x-dev-user-role")
            if dev_role and "@" not in dev_role:
                token_user.roles = _normalize_roles(dev_role)
            return token_user

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
    if dev_email or dev_role:
        if dev_role and "@" in dev_role and not dev_email:
            resolved_email = dev_role.strip().lower()
            resolved_roles = ["employee"]
        elif dev_email:
            resolved_email = dev_email.strip().lower()
            resolved_roles = _normalize_roles(dev_role)
        elif settings.use_mock_data:
            resolved_email = "developer@enterprise.example.com"
            resolved_roles = _normalize_roles(dev_role)
        else:
            adc_email = _resolve_adc_user_email()
            resolved_email = adc_email or "anonymous@enterprise.example.com"
            resolved_roles = _normalize_roles(dev_role)
        return models.UserContext(
            email=resolved_email,
            user_id=resolved_email,
            roles=resolved_roles,
            auth_source="dev_override",
        )

    if settings.use_mock_data:
        return models.UserContext(
            email="developer@enterprise.example.com",
            user_id="dev-user-001",
            roles=["employee", "engineering", "data-analyst"],
            auth_source="mock_default",
        )

    adc_email = _resolve_adc_user_email()
    if adc_email:
        roles = ["employee"]
        if adc_email in settings.admin_users:
            roles.insert(0, "admin")
        return models.UserContext(
            email=adc_email,
            user_id=adc_email,
            roles=roles,
            auth_source="gcp_adc",
        )

    return models.UserContext(
        email="anonymous@enterprise.example.com",
        user_id="anonymous",
        roles=["employee"],
        auth_source="unauthenticated_fallback",
    )
