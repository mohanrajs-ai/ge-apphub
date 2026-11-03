"""FastAPI router for user authentication and Cloud Identity group login."""

import fastapi

from app import auth
from app import config
from app import models
from app.services import discovery

router = fastapi.APIRouter(prefix="/api/v1/auth", tags=["auth"])

SUGGESTED_USERS: list[models.SuggestedUser] = [
    models.SuggestedUser(
        email="mohanraj@mohanrajs.altostrat.com",
        label="Mohanraj Shanmugam",
        description="Member of HR & Ops Cloud Identity groups (2 GE apps)",
    ),
    models.SuggestedUser(
        email="admin@mohanrajs.altostrat.com",
        label="Workspace Admin User",
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
    return models.AuthConfigResponse(
        google_client_id=settings.google_client_id,
        suggested_users=SUGGESTED_USERS,
    )


@router.post("/login", response_model=models.LoginResponse)
def login_user(payload: models.LoginRequest) -> models.LoginResponse:
    """Authenticates a user via Google ID token or Workspace email."""
    settings = config.get_settings()
    resolved_email: str | None = None

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

    disc_service = discovery.DiscoveryEngineService(settings=settings)
    engines = disc_service.list_engines()
    user_groups = disc_service.resolve_user_groups(
        user_email=resolved_email,
        engines=engines,
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
