"""Unit tests for user identity and role resolution in the backend."""

from fastapi import testclient

from app import auth
from app import main


def test_me_endpoint_default_dev_user(monkeypatch) -> None:
    """Verifies GET /api/v1/me returns default mock user in mock mode."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/me")

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "developer@enterprise.example.com"
    assert "employee" in data["roles"]
    assert data["auth_source"] == "mock_default"


def test_me_endpoint_dev_header_override(monkeypatch) -> None:
    """Verifies X-Dev-User-Email and X-Dev-User-Role override identity."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get(
        "/api/v1/me",
        headers={
            "X-Dev-User-Email": "alice@enterprise.example.com",
            "X-Dev-User-Role": "admin, data-analyst",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "alice@enterprise.example.com"
    assert data["roles"] == ["admin", "data-analyst", "employee"]
    assert data["auth_source"] == "dev_override"


def test_me_endpoint_iap_headers(monkeypatch) -> None:
    """Verifies Google Cloud IAP header extraction in live or mock mode."""
    monkeypatch.setenv("USE_MOCK_DATA", "false")
    monkeypatch.setenv("ADMIN_USERS", "secops@google.com")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get(
        "/api/v1/me",
        headers={
            "X-Goog-Authenticated-User-Email": (
                "accounts.google.com:secops@google.com"
            ),
            "X-Goog-Authenticated-User-Id": "accounts.google.com:123456789",
        },
    )

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "secops@google.com"
    assert data["user_id"] == "123456789"
    assert "admin" in data["roles"]
    assert "employee" in data["roles"]
    assert data["auth_source"] == "gcp_iap"


def test_me_endpoint_live_mode_without_iap_header(monkeypatch) -> None:
    """Verifies fallback anonymous/employee identity when IAP/ADC absent."""
    monkeypatch.setenv("USE_MOCK_DATA", "false")
    monkeypatch.setattr(auth, "_resolve_adc_user_email", lambda: None)

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/me")

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "anonymous@enterprise.example.com"
    assert data["roles"] == ["employee"]
    assert data["auth_source"] == "unauthenticated_fallback"


def test_me_endpoint_live_mode_adc_and_email_role_preview(monkeypatch) -> None:
    """Verifies ADC email fallback and email role switcher in live mode."""
    monkeypatch.setenv("USE_MOCK_DATA", "false")
    monkeypatch.setattr(
        auth,
        "_resolve_adc_user_email",
        lambda: "admin@mohanrajs.altostrat.com",
    )

    app = main.create_app()
    client = testclient.TestClient(app)

    adc_resp = client.get("/api/v1/me")
    assert adc_resp.status_code == 200
    assert adc_resp.json()["email"] == "admin@mohanrajs.altostrat.com"
    assert adc_resp.json()["auth_source"] == "gcp_adc"

    preview_resp = client.get(
        "/api/v1/me",
        headers={"X-Dev-User-Role": "mohanraj@mohanrajs.altostrat.com"},
    )
    assert preview_resp.status_code == 200
    assert preview_resp.json()["email"] == "mohanraj@mohanrajs.altostrat.com"
    assert preview_resp.json()["roles"] == ["employee"]
    assert preview_resp.json()["auth_source"] == "dev_override"


def test_auth_login_bearer_session_and_logout(monkeypatch) -> None:
    """Verifies /api/v1/auth/config, login, Bearer token on /me, and logout."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)

    cfg_resp = client.get("/api/v1/auth/config")
    assert cfg_resp.status_code == 200
    cfg_data = cfg_resp.json()
    assert "suggested_users" in cfg_data
    assert any(
        u["email"] == "mohanraj@mohanrajs.altostrat.com"
        for u in cfg_data["suggested_users"]
    )

    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "mohanraj@mohanrajs.altostrat.com"},
    )
    assert login_resp.status_code == 200
    login_data = login_resp.json()
    token = login_data["token"]
    assert token
    assert login_data["user"]["email"] == "mohanraj@mohanrajs.altostrat.com"
    assert login_data["user"]["auth_source"] == "session_token"

    me_resp = client.get(
        "/api/v1/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert me_resp.status_code == 200
    assert me_resp.json()["email"] == "mohanraj@mohanrajs.altostrat.com"
    assert me_resp.json()["auth_source"] == "session_token"

    bad_login = client.post("/api/v1/auth/login", json={"email": "invalid"})
    assert bad_login.status_code == 400

    logout_resp = client.post("/api/v1/auth/logout")
    assert logout_resp.status_code == 200
    assert logout_resp.json()["status"] == "logged_out"

    monkeypatch.setattr(
        auth,
        "verify_google_id_token_email",
        lambda token, client_id=None: (
            "admin@mohanrajs.altostrat.com" if token == "valid-jwt" else None
        ),
    )
    id_tok_resp = client.post(
        "/api/v1/auth/login",
        json={"id_token": "valid-jwt"},
    )
    assert id_tok_resp.status_code == 200
    assert (
        id_tok_resp.json()["user"]["email"] == "admin@mohanrajs.altostrat.com"
    )

    bad_jwt_resp = client.post(
        "/api/v1/auth/login",
        json={"id_token": "bad-jwt"},
    )
    assert bad_jwt_resp.status_code == 401

    assert auth.verify_session_token("invalid", "secret") is None
    assert auth.verify_session_token("a.b", "secret") is None
    assert auth.verify_google_id_token_email("invalid-jwt") is None
    monkeypatch.setenv("DEFAULT_USER_EMAIL", "env@mohanrajs.altostrat.com")
    assert auth._resolve_adc_user_email() == "env@mohanrajs.altostrat.com"


def test_login_persists_user_and_resolves_groups_from_db(monkeypatch) -> None:
    """Verifies /api/v1/auth/login upserts UserRecord and reads DB groups."""
    from app import database
    from app import db_models

    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    monkeypatch.setenv("USE_MOCK_DATA", "false")
    monkeypatch.setenv("SYNC_ON_STARTUP", "false")
    database.reset_engine_cache()
    database.init_db()

    with database.session_scope() as session:
        session.add(
            db_models.CloudIdentityGroupRecord(
                group_email="hr-app-01-users@mohanrajs.altostrat.com",
                group_resource_name="groups/hr01",
                display_name="HR App 01 Users",
            )
        )
        session.add(
            db_models.UserGroupMembershipRecord(
                user_email="mohanraj@mohanrajs.altostrat.com",
                group_email="hr-app-01-users@mohanrajs.altostrat.com",
            )
        )
        session.commit()

    app = main.create_app()
    client = testclient.TestClient(app)

    login_resp = client.post(
        "/api/v1/auth/login",
        json={"email": "mohanraj@mohanrajs.altostrat.com"},
    )
    assert login_resp.status_code == 200
    payload = login_resp.json()
    assert payload["user"]["groups"] == [
        "hr-app-01-users@mohanrajs.altostrat.com"
    ]

    with database.session_scope() as session:
        saved_user = (
            session.query(db_models.UserRecord)
            .filter_by(email="mohanraj@mohanrajs.altostrat.com")
            .one_or_none()
        )
        assert saved_user is not None
        assert saved_user.auth_source == "cloud_identity_workspace"

        # Test upsert update path and live fallback when user has no DB groups
        updated = auth.upsert_authenticated_user(
            session=session,
            email="mohanraj@mohanrajs.altostrat.com",
            roles=["admin", "employee"],
            auth_source="google_cloud_identity",
        )
        assert "admin" in updated.roles

        class _FakeDisc:
            def _group_membership_checker(
                self, user_email: str, group_email: str, _proj: str
            ) -> bool:
                return (
                    user_email == "newuser@mohanrajs.altostrat.com"
                    and group_email == "hr-app-01-users@mohanrajs.altostrat.com"
                )

        fallback_groups = auth.resolve_user_groups_from_db(
            session=session,
            user_email="newuser@mohanrajs.altostrat.com",
            discovery_service=_FakeDisc(),
            allow_live_fallback=True,
        )
        assert fallback_groups == ["hr-app-01-users@mohanrajs.altostrat.com"]

        # Test empty synced_groups fallback to list_engines
        session.query(db_models.CloudIdentityGroupRecord).delete()
        session.commit()

        class _FakeDiscNoSynced:
            def list_engines(self):
                return []

            def resolve_user_groups(self, user_email: str, engines: list):
                del user_email, engines
                return ["ops-app-01-users@mohanrajs.altostrat.com"]

        live_groups = auth.resolve_user_groups_from_db(
            session=session,
            user_email="third@mohanrajs.altostrat.com",
            discovery_service=_FakeDiscNoSynced(),
            allow_live_fallback=True,
        )
        assert live_groups == ["ops-app-01-users@mohanrajs.altostrat.com"]

    monkeypatch.setattr(
        auth.google_id_token,
        "verify_oauth2_token",
        lambda _tok, _req, audience=None: {
            "email": "verified@mohanrajs.altostrat.com",
            "aud": audience,
        },
    )
    assert (
        auth.verify_google_id_token_email("jwt", client_id="cid")
        == "verified@mohanrajs.altostrat.com"
    )
