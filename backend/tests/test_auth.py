"""Unit tests for user identity and role resolution in the backend."""

from fastapi import testclient

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
    """Verifies fallback anonymous/employee identity when IAP header absent."""
    monkeypatch.setenv("USE_MOCK_DATA", "false")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/me")

    assert response.status_code == 200
    data = response.json()
    assert data["email"] == "anonymous@enterprise.example.com"
    assert data["roles"] == ["employee"]
    assert data["auth_source"] == "unauthenticated_fallback"
