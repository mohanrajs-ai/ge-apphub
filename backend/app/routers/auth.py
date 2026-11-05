"""FastAPI router for user authentication and Cloud Identity group login."""

import urllib.parse

import fastapi
from fastapi import responses
from sqlalchemy import orm

from app import auth
from app import config
from app import database
from app import models
from app.services import discovery

router = fastapi.APIRouter(prefix="/api/v1/auth", tags=["auth"])

SUGGESTED_USERS: list[models.SuggestedUser] = [
    models.SuggestedUser(
        email="pradeepg@mohanrajs.demo.altostrat.com",
        label="Pradeep Gupta (Microsoft 365 SSO)",
        description=(
            "Federated Entra ID user in ge-finance-users -> "
            "finance-app-01-users"
        ),
    ),
    models.SuggestedUser(
        email="mohanraj@mohanrajs.altostrat.com",
        label="Mohanraj Shanmugam (Cloud Identity)",
        description="Member of HR & Ops Cloud Identity groups (2 GE apps)",
    ),
    models.SuggestedUser(
        email="admin@mohanrajs.altostrat.com",
        label="Workspace Admin User (Cloud Identity)",
        description=(
            "Member of Finance, Marketing, Ops, Sales, Service Desk & Search "
            "groups (6 GE apps)"
        ),
    ),
]


@router.get("/config", response_model=models.AuthConfigResponse)
def get_auth_config() -> models.AuthConfigResponse:
    """Returns authentication client configuration and suggested accounts."""
    settings = config.get_settings()
    client_id, _ = auth.get_oauth_client_credentials(settings)
    return models.AuthConfigResponse(
        google_client_id=client_id,
        sso_redirect_enabled=not settings.use_mock_data,
        suggested_users=SUGGESTED_USERS,
    )


@router.get("/google/login")
def google_oauth_login(
    request: fastapi.Request,
    email: str = fastapi.Query(
        default="",
        description="Optional Workspace or M365 email for SSO login_hint",
    ),
    redirect_origin: str = fastapi.Query(
        default="",
        description="Frontend origin URL to redirect to after callback",
    ),
) -> responses.RedirectResponse:
    """Initiates Google Cloud Identity / Microsoft 365 SAML SSO OAuth login."""
    settings = config.get_settings()
    base_url = str(request.base_url).rstrip("/")
    frontend_origin = redirect_origin.strip().rstrip("/") or base_url
    redirect_uri = f"{frontend_origin}/api/v1/auth/google/callback"
    authorize_url = auth.build_google_oauth_authorize_url(
        email=email or None,
        redirect_uri=redirect_uri,
        frontend_origin=frontend_origin,
        settings=settings,
    )
    return responses.RedirectResponse(url=authorize_url, status_code=302)


@router.get("/google/callback")
def google_oauth_callback(
    request: fastapi.Request,
    code: str = fastapi.Query(default=""),
    state: str = fastapi.Query(default=""),
    error: str = fastapi.Query(default=""),
    error_description: str = fastapi.Query(default=""),
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> responses.RedirectResponse:
    """Handles OAuth 2.0 callback from Google Cloud Identity / M365 SSO."""
    settings = config.get_settings()
    fallback_origin = str(request.base_url).rstrip("/")
    state_data = auth.verify_oauth_state_token(state, settings.session_secret)
    frontend_origin = (
        state_data.get("r", fallback_origin)
        if state_data is not None
        else fallback_origin
    )

    if error:
        msg = error_description or error
        encoded_err = urllib.parse.quote(f"SSO login error: {msg}")
        return responses.RedirectResponse(
            url=f"{frontend_origin}/?auth_error={encoded_err}",
            status_code=302,
        )

    if state_data is None or not code:
        encoded_err = urllib.parse.quote(
            "Invalid or expired SSO authorization state. Please try again."
        )
        return responses.RedirectResponse(
            url=f"{frontend_origin}/?auth_error={encoded_err}",
            status_code=302,
        )

    try:
        claims = auth.exchange_google_oauth_code(
            code=code,
            redirect_uri=state_data.get(
                "u", f"{frontend_origin}/api/v1/auth/google/callback"
            ),
            code_verifier=state_data.get("v", ""),
            settings=settings,
        )
    except Exception as exc:  # pylint: disable=broad-except
        encoded_err = urllib.parse.quote(str(exc))
        return responses.RedirectResponse(
            url=f"{frontend_origin}/?auth_error={encoded_err}",
            status_code=302,
        )

    resolved_email = claims["email"]
    roles = ["employee"]
    if resolved_email in settings.admin_users:
        roles.insert(0, "admin")

    auth.upsert_authenticated_user(
        session=session,
        email=resolved_email,
        roles=roles,
        auth_source="google_cloud_identity_sso",
        user_id=claims.get("sub") or resolved_email,
        display_name=claims.get("name") or None,
    )
    disc_service = discovery.DiscoveryEngineService(settings=settings)
    user_groups = auth.resolve_user_groups_from_db(
        session=session,
        user_email=resolved_email,
        settings=settings,
        discovery_service=disc_service,
        allow_live_fallback=True,
    )
    user_ctx = models.UserContext(
        email=resolved_email,
        user_id=claims.get("sub") or resolved_email,
        roles=roles,
        groups=user_groups,
        auth_source="google_cloud_identity_sso",
    )
    token = auth.create_session_token(user_ctx, settings.session_secret)
    encoded_token = urllib.parse.quote(token)
    return responses.RedirectResponse(
        url=f"{frontend_origin}/?auth_token={encoded_token}",
        status_code=302,
    )


@router.post("/login", response_model=models.LoginResponse)
def login_user(
    payload: models.LoginRequest,
    session: orm.Session = fastapi.Depends(database.get_db_session),
) -> models.LoginResponse:
    """Authenticates a user via Google ID token or Workspace email."""
    settings = config.get_settings()
    resolved_email: str | None = None
    db_auth_source = "cloud_identity_workspace"

    if payload.id_token:
        resolved_email = auth.verify_google_id_token_email(
            payload.id_token,
            client_id=settings.google_client_id or None,
        )
        if not resolved_email:
            raise fastapi.HTTPException(
                status_code=401,
                detail="Invalid Google OAuth ID token.",
            )
        db_auth_source = "google_cloud_identity"
    elif payload.email:
        candidate = payload.email.strip().lower()
        if "@" not in candidate or "." not in candidate.split("@", 1)[1]:
            raise fastapi.HTTPException(
                status_code=400,
                detail="Please provide a valid Workspace email address.",
            )
        resolved_email = candidate
    else:
        raise fastapi.HTTPException(
            status_code=400,
            detail="Either 'email' or 'id_token' is required to sign in.",
        )

    roles = auth._normalize_roles(payload.role)  # pylint: disable=protected-access
    if resolved_email in settings.admin_users and "admin" not in roles:
        roles.insert(0, "admin")

    auth.upsert_authenticated_user(
        session=session,
        email=resolved_email,
        roles=roles,
        auth_source=db_auth_source,
    )
    disc_service = discovery.DiscoveryEngineService(settings=settings)
    user_groups = auth.resolve_user_groups_from_db(
        session=session,
        user_email=resolved_email,
        settings=settings,
        discovery_service=disc_service,
        allow_live_fallback=True,
    )

    user_ctx = models.UserContext(
        email=resolved_email,
        user_id=resolved_email,
        roles=roles,
        groups=user_groups,
        auth_source="session_token",
    )
    token = auth.create_session_token(user_ctx, settings.session_secret)
    return models.LoginResponse(token=token, user=user_ctx)


@router.post("/logout")
def logout_user() -> dict[str, str]:
    """Logs out the current user session."""
    return {"status": "logged_out"}
