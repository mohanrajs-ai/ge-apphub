"""Authentication and role resolution dependencies for FastAPI."""

import base64
import datetime
import hashlib
import hmac
import json
import os
import secrets
import urllib.parse
from typing import Any

import fastapi
import google.auth
import httpx
from google.auth import _cloud_sdk
from google.auth.transport import requests as google_requests
from google.oauth2 import id_token as google_id_token
from sqlalchemy import orm

from app import config
from app import database
from app import db_models
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


def get_oauth_client_credentials(
    settings: config.Settings,
) -> tuple[str, str]:
    """Resolves Google OAuth 2.0 client ID and secret for redirect sign-in.

    Uses configured GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET when set, and falls
    back to the local ADC OAuth client config for local development.

    Args:
        settings: Active application settings.

    Returns:
        Tuple of (client_id, client_secret).
    """
    if settings.google_client_id:
        return settings.google_client_id, settings.google_client_secret
    try:
        adc_path = _cloud_sdk.get_application_default_credentials_path()
        if os.path.isfile(adc_path):
            with open(adc_path, encoding="utf-8") as adc_file:
                data = json.load(adc_file)
            cid = str(data.get("client_id") or "").strip()
            csec = str(data.get("client_secret") or "").strip()
            if cid:
                return cid, csec
    except Exception:  # pylint: disable=broad-except
        pass
    return "local-google-oauth-client", ""


def create_oauth_state_token(payload: dict[str, str], secret: str) -> str:
    """Signs an OAuth 2.0 state dictionary with HMAC-SHA256.

    Args:
        payload: Dictionary of state values (code_verifier, redirect_uri, etc).
        secret: Server signing secret.

    Returns:
        Signed URL-safe state string.
    """
    payload_bytes = json.dumps(
        payload, separators=(",", ":"), sort_keys=True
    ).encode("utf-8")
    encoded_payload = base64.urlsafe_b64encode(payload_bytes).decode("ascii")
    signature = hmac.new(
        secret.encode("utf-8"),
        encoded_payload.encode("ascii"),
        hashlib.sha256,
    ).hexdigest()
    return f"{encoded_payload}.{signature}"


def verify_oauth_state_token(
    state: str,
    secret: str,
) -> dict[str, str] | None:
    """Verifies an HMAC-SHA256 signed OAuth 2.0 state token.

    Args:
        state: Signed state string from the OAuth callback.
        secret: Server signing secret.

    Returns:
        Decoded state dictionary if valid, otherwise None.
    """
    if not state or "." not in state:
        return None
    encoded_payload, signature = state.rsplit(".", 1)
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
        if isinstance(data, dict):
            return {str(k): str(v) for k, v in data.items()}
    except Exception:  # pylint: disable=broad-except
        return None
    return None


def build_google_oauth_authorize_url(
    email: str | None,
    redirect_uri: str,
    frontend_origin: str,
    settings: config.Settings,
) -> str:
    """Builds the Google Cloud Identity OAuth 2.0 authorization redirect URL.

    When a federated domain email (such as @mohanrajs.demo.altostrat.com) is
    provided, includes login_hint and hd so Google Cloud Identity automatically
    redirects the user to the configured Inbound SAML IdP (Microsoft 365).

    Args:
        email: Optional user email address for login_hint and domain discovery.
        redirect_uri: OAuth 2.0 callback URL on this application.
        frontend_origin: Origin URL to redirect back to after authentication.
        settings: Active application settings.

    Returns:
        Full https://accounts.google.com/o/oauth2/v2/auth redirect URL.
    """
    client_id, _ = get_oauth_client_credentials(settings)
    code_verifier = secrets.token_urlsafe(48)
    challenge_digest = hashlib.sha256(code_verifier.encode("ascii")).digest()
    code_challenge = (
        base64.urlsafe_b64encode(challenge_digest).decode("ascii").rstrip("=")
    )
    state = create_oauth_state_token(
        {
            "v": code_verifier,
            "r": frontend_origin,
            "u": redirect_uri,
        },
        settings.session_secret,
    )
    params: dict[str, str] = {
        "response_type": "code",
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "scope": "openid email profile",
        "state": state,
        "code_challenge": code_challenge,
        "code_challenge_method": "S256",
    }
    clean_email = (email or "").strip().lower()
    if clean_email and "@" in clean_email:
        params["login_hint"] = clean_email
    else:
        params["prompt"] = "select_account"
    query = urllib.parse.urlencode(params)
    return f"https://accounts.google.com/o/oauth2/v2/auth?{query}"


def exchange_google_oauth_code(
    code: str,
    redirect_uri: str,
    code_verifier: str,
    settings: config.Settings,
) -> dict[str, str]:
    """Exchanges an OAuth 2.0 authorization code for verified user claims.

    Args:
        code: Authorization code from Google OAuth callback.
        redirect_uri: Redirect URI used in the initial authorization request.
        code_verifier: PKCE code verifier recovered from the signed state.
        settings: Active application settings.

    Returns:
        Dictionary containing 'email', 'sub', and 'name'.

    Raises:
        ValueError: If code exchange fails or no verified email is returned.
    """
    client_id, client_secret = get_oauth_client_credentials(settings)
    token_data: dict[str, str] = {
        "grant_type": "authorization_code",
        "code": code,
        "client_id": client_id,
        "redirect_uri": redirect_uri,
        "code_verifier": code_verifier,
    }
    if client_secret:
        token_data["client_secret"] = client_secret

    token_resp = httpx.post(
        "https://oauth2.googleapis.com/token",
        data=token_data,
        timeout=10.0,
    )
    if token_resp.status_code != 200:
        raise ValueError(
            f"OAuth token exchange failed (HTTP {token_resp.status_code})."
        )
    tokens = token_resp.json()
    raw_id_token = tokens.get("id_token")
    access_token = tokens.get("access_token")

    if raw_id_token:
        try:
            request_adapter = google_requests.Request()
            claims = google_id_token.verify_oauth2_token(
                raw_id_token,
                request_adapter,
                audience=client_id,
            )
            email = str(claims.get("email", "")).strip().lower()
            if email and "@" in email:
                return {
                    "email": email,
                    "sub": str(claims.get("sub") or email),
                    "name": str(claims.get("name") or ""),
                }
        except Exception:  # pylint: disable=broad-except
            pass

    if access_token:
        userinfo_resp = httpx.get(
            "https://openidconnect.googleapis.com/v1/userinfo",
            headers={"Authorization": f"Bearer {access_token}"},
            timeout=10.0,
        )
        if userinfo_resp.status_code == 200:
            info = userinfo_resp.json()
            email = str(info.get("email", "")).strip().lower()
            if email and "@" in email:
                return {
                    "email": email,
                    "sub": str(info.get("sub") or email),
                    "name": str(info.get("name") or ""),
                }

    raise ValueError("Unable to verify user email from Google OAuth response.")


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


def upsert_authenticated_user(
    session: orm.Session,
    email: str,
    roles: list[str],
    auth_source: str,
    user_id: str | None = None,
    display_name: str | None = None,
) -> db_models.UserRecord:
    """Upserts an authenticated user profile into PostgreSQL.

    Args:
        session: Active SQLAlchemy database session.
        email: Lowercase user email address.
        roles: Normalized user role list.
        auth_source: Source of authentication (e.g. google_cloud_identity).
        user_id: Optional external subject/user identifier.
        display_name: Optional user display name.

    Returns:
        Persisted UserRecord instance.
    """
    clean_email = email.strip().lower()
    now = datetime.datetime.now(datetime.timezone.utc)
    default_name = (
        display_name
        or clean_email.split("@", 1)[0].replace(".", " ").title()
    )
    record = (
        session.query(db_models.UserRecord)
        .filter_by(email=clean_email)
        .one_or_none()
    )
    if record is None:
        record = db_models.UserRecord(
            email=clean_email,
            user_id=user_id or clean_email,
            display_name=default_name,
            roles=list(roles),
            auth_source=auth_source,
            last_login_at=now,
            updated_at=now,
        )
        session.add(record)
    else:
        record.roles = list(roles)
        record.auth_source = auth_source
        record.last_login_at = now
        record.updated_at = now
    session.commit()
    return record


def resolve_user_groups_from_db(
    session: orm.Session,
    user_email: str,
    settings: config.Settings | None = None,
    discovery_service: Any | None = None,
    allow_live_fallback: bool = False,
) -> list[str]:
    """Resolves a user's Cloud Identity groups from PostgreSQL with fallback.

    Args:
        session: Active SQLAlchemy database session.
        user_email: Authenticated user email address.
        settings: Optional Settings instance.
        discovery_service: Optional DiscoveryEngineService for live fallback.
        allow_live_fallback: Whether to query live Cloud Identity on DB miss.

    Returns:
        Sorted list of Cloud Identity group email addresses.
    """
    clean_email = user_email.strip().lower()
    if not clean_email or "@" not in clean_email:
        return []

    rows = (
        session.query(db_models.UserGroupMembershipRecord)
        .filter_by(user_email=clean_email)
        .all()
    )
    if rows:
        return sorted({r.group_email.strip().lower() for r in rows})

    if not allow_live_fallback:
        return []

    active_settings = settings or config.get_settings()
    if active_settings.use_mock_data:
        return []

    synced_groups = [
        g.group_email
        for g in session.query(db_models.CloudIdentityGroupRecord).all()
    ]
    if synced_groups and discovery_service is not None:
        now = datetime.datetime.now(datetime.timezone.utc)
        matched: list[str] = []
        for group_email in sorted(set(synced_groups)):
            if discovery_service._group_membership_checker(  # pylint: disable=protected-access
                clean_email,
                group_email,
                active_settings.gcp_project_id,
            ):
                matched.append(group_email)
                session.add(
                    db_models.UserGroupMembershipRecord(
                        user_email=clean_email,
                        group_email=group_email,
                        membership_role="MEMBER",
                        synced_at=now,
                    )
                )
        if matched:
            session.commit()
        return matched

    if discovery_service is not None:
        engines = discovery_service.list_engines()
        live_groups = discovery_service.resolve_user_groups(
            user_email=clean_email,
            engines=engines,
        )
        now = datetime.datetime.now(datetime.timezone.utc)
        for group_email in live_groups:
            session.add(
                db_models.UserGroupMembershipRecord(
                    user_email=clean_email,
                    group_email=group_email,
                    membership_role="MEMBER",
                    synced_at=now,
                )
            )
        if live_groups:
            session.commit()
        return live_groups
    return []


def _enrich_groups_from_db(user: models.UserContext) -> models.UserContext:
    """Populates user.groups from PostgreSQL if not already present."""
    if user.groups:
        return user
    try:
        with database.session_scope() as session:
            groups = resolve_user_groups_from_db(
                session=session,
                user_email=user.email,
            )
            if groups:
                user.groups = groups
    except Exception:  # pylint: disable=broad-except
        pass
    return user


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
            return _enrich_groups_from_db(token_user)

    iap_email = headers.get("x-goog-authenticated-user-email")
    iap_id = headers.get("x-goog-authenticated-user-id")
    if iap_email:
        clean_email = _strip_iap_prefix(iap_email).lower()
        clean_id = _strip_iap_prefix(iap_id) if iap_id else clean_email
        roles: list[str] = []
        if clean_email in settings.admin_users:
            roles.append("admin")
        roles.append("employee")
        return _enrich_groups_from_db(
            models.UserContext(
                email=clean_email,
                user_id=clean_id,
                roles=roles,
                auth_source="gcp_iap",
            )
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
        return _enrich_groups_from_db(
            models.UserContext(
                email=resolved_email,
                user_id=resolved_email,
                roles=resolved_roles,
                auth_source="dev_override",
            )
        )

    if settings.use_mock_data:
        return _enrich_groups_from_db(
            models.UserContext(
                email="developer@enterprise.example.com",
                user_id="dev-user-001",
                roles=["employee", "engineering", "data-analyst"],
                auth_source="mock_default",
            )
        )

    adc_email = _resolve_adc_user_email()
    if adc_email:
        roles = ["employee"]
        if adc_email in settings.admin_users:
            roles.insert(0, "admin")
        return _enrich_groups_from_db(
            models.UserContext(
                email=adc_email,
                user_id=adc_email,
                roles=roles,
                auth_source="gcp_adc",
            )
        )

    return models.UserContext(
        email="anonymous@enterprise.example.com",
        user_id="anonymous",
        roles=["employee"],
        auth_source="unauthenticated_fallback",
    )
