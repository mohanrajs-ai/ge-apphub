"""Integration tests for the GET /api/v1/apps catalog endpoint."""

from fastapi import testclient

from app import main


def test_list_apps_endpoint_returns_visible_catalog(monkeypatch) -> None:
    """Verifies GET /api/v1/apps returns enriched apps for default user."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)
    response = client.get("/api/v1/apps")

    assert response.status_code == 200
    payload = response.json()
    assert "items" in payload
    assert "categories" in payload
    assert "departments" in payload
    assert payload["total"] == len(payload["items"])
    assert payload["total"] >= 4


def test_list_apps_endpoint_role_filtering(monkeypatch) -> None:
    """Verifies restricted apps are hidden for standard employee role."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)

    emp_res = client.get(
        "/api/v1/apps",
        headers={"X-Dev-User-Role": "employee"},
    )
    assert emp_res.status_code == 200
    emp_ids = {item["engine_id"] for item in emp_res.json()["items"]}
    assert "ge-secops-threat-radar" not in emp_ids

    admin_res = client.get(
        "/api/v1/apps",
        headers={"X-Dev-User-Role": "admin"},
    )
    assert admin_res.status_code == 200
    admin_ids = {item["engine_id"] for item in admin_res.json()["items"]}
    assert "ge-secops-threat-radar" in admin_ids


def test_list_apps_endpoint_search_and_facet_filters(monkeypatch) -> None:
    """Verifies query parameters q, category, department, and tag filter."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")

    app = main.create_app()
    client = testclient.TestClient(app)

    res = client.get(
        "/api/v1/apps",
        params={"q": "support", "category": "Customer Experience"},
    )
    assert res.status_code == 200
    items = res.json()["items"]
    assert len(items) == 1
    assert items[0]["engine_id"] == "ge-customer-support-copilot"
