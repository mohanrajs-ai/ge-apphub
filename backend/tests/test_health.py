"""Unit tests for backend configuration and health check endpoint."""

from fastapi import testclient

from app import config
from app import main


def test_default_settings(monkeypatch) -> None:
    """Verifies default configuration values when env vars are unset."""
    monkeypatch.delenv("GCP_PROJECT_ID", raising=False)
    monkeypatch.delenv("GCP_LOCATION", raising=False)
    monkeypatch.delenv("FIRESTORE_COLLECTION", raising=False)
    monkeypatch.delenv("USE_MOCK_DATA", raising=False)

    settings = config.get_settings()
    assert settings.gcp_location == "global"
    assert settings.firestore_collection == "ge_app_catalog"
    assert settings.use_mock_data is True


def test_custom_settings_from_env(monkeypatch) -> None:
    """Verifies configuration values loaded from environment variables."""
    monkeypatch.setenv("GCP_PROJECT_ID", "my-enterprise-project")
    monkeypatch.setenv("GCP_LOCATION", "us")
    monkeypatch.setenv("FIRESTORE_COLLECTION", "custom_catalog")
    monkeypatch.setenv("USE_MOCK_DATA", "false")

    settings = config.get_settings()
    assert settings.gcp_project_id == "my-enterprise-project"
    assert settings.gcp_location == "us"
    assert settings.firestore_collection == "custom_catalog"
    assert settings.use_mock_data is False


def test_health_endpoint_returns_ok(monkeypatch) -> None:
    """Verifies GET /api/v1/health returns status and operating mode."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")
    monkeypatch.setenv("GCP_PROJECT_ID", "demo-gcp-project")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["service"] == "ge-apphub-backend"
    assert payload["mode"] == "mock"
    assert payload["gcp_project_id"] == "demo-gcp-project"


def test_health_endpoint_live_mode(monkeypatch) -> None:
    """Verifies GET /api/v1/health reports live mode when mock is disabled."""
    monkeypatch.setenv("USE_MOCK_DATA", "false")
    monkeypatch.setenv("GCP_PROJECT_ID", "prod-gcp-project")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "ok"
    assert payload["mode"] == "live"
