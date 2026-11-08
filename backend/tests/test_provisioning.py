"""Unit tests for the Admin Terraform Provisioning Studio API and runner."""

import pytest
from fastapi import testclient

from app import database
from app import main
from app.services import terraform_runner


@pytest.fixture(autouse=True)
def _isolated_mock_db(monkeypatch: pytest.MonkeyPatch) -> None:
    """Uses an isolated in-memory SQLite DB for provisioning unit tests."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")
    monkeypatch.delenv("DATABASE_URL", raising=False)
    database.reset_engine_cache()
    terraform_runner._ACTIVE_WORKSPACE_LOCKS.clear()  # pylint: disable=protected-access


def test_provisioning_requires_admin_role() -> None:
    """Verifies non-admin users receive 403 Forbidden on provisioning APIs."""
    client = testclient.TestClient(main.create_app())
    headers = {
        "X-Dev-User-Email": "alice@enterprise.example.com",
        "X-Dev-User-Role": "employee",
    }
    resp = client.get("/api/v1/admin/provisioning/jobs", headers=headers)
    assert resp.status_code == 403


def test_ge_app_plan_gate_workspace_lock_and_approve_sync() -> None:
    """Tests Plan-Before-Apply gate, workspace state lock, and catalog sync."""
    terraform_runner._ACTIVE_WORKSPACE_LOCKS.clear()  # pylint: disable=protected-access
    client = testclient.TestClient(main.create_app())
    admin_headers = {
        "X-Dev-User-Email": "admin@mohanrajs.altostrat.com",
        "X-Dev-User-Role": "admin",
    }

    payload = {
        "gcp_project_id": "mohandemo",
        "ge_location": "global",
        "ge_app_id": "hr-benefits-assistant",
        "ge_app_display_name": "HR Benefits Assistant",
        "tf_state_bucket": "mohandemo-tfstate",
        "execution_mode": "PLAN_AND_WAIT",
    }
    plan_resp = client.post(
        "/api/v1/admin/provisioning/ge-app",
        json=payload,
        headers=admin_headers,
    )
    assert plan_resp.status_code == 201
    job = plan_resp.json()
    job_id = job["job_id"]
    assert job["status"] == "PENDING_APPROVAL"
    assert job["workspace_key"] == "app-global-hr-benefits-assistant"
    assert job["state_backend_type"] == "GCS_REMOTE"
    assert (
        job["state_prefix"]
        == "gemini-enterprise/apps/global/hr-benefits-assistant"
    )

    # Concurrent provisioning on the same workspace_key must fail with 409
    conflict_resp = client.post(
        "/api/v1/admin/provisioning/ge-app",
        json=payload,
        headers=admin_headers,
    )
    assert conflict_resp.status_code == 409
    assert "lock" in conflict_resp.json()["detail"].lower()

    # Different GE App gets an isolated workspace and succeeds concurrently
    other_resp = client.post(
        "/api/v1/admin/provisioning/ge-app",
        json={
            **payload,
            "ge_location": "us",
            "ge_app_id": "legal-contract-assistant",
            "ge_app_display_name": "Legal Contract Assistant",
            "execution_mode": "DRY_RUN",
        },
        headers=admin_headers,
    )
    assert other_resp.status_code == 201
    assert (
        other_resp.json()["workspace_key"]
        == "app-us-legal-contract-assistant"
    )
    assert other_resp.json()["status"] == "SUCCEEDED"

    # Approve the planned HR app job -> runs apply, releases lock, syncs catalog
    approve_resp = client.post(
        f"/api/v1/admin/provisioning/jobs/{job_id}/approve",
        json={"notes": "Reviewed Terraform plan"},
        headers=admin_headers,
    )
    assert approve_resp.status_code == 200
    approved_job = approve_resp.json()
    assert approved_job["status"] == "SUCCEEDED"
    assert approved_job["approved_by"] == "admin@mohanrajs.altostrat.com"
    assert approved_job["outputs"]["engine_id"] == "hr-benefits-assistant"

    # Verify lock was released
    list_resp = client.get(
        "/api/v1/admin/provisioning/jobs",
        headers=admin_headers,
    )
    assert list_resp.status_code == 200
    assert (
        "app-global-hr-benefits-assistant"
        not in list_resp.json()["active_workspace_locks"]
    )


def test_m365_and_identity_secret_redaction_and_sse_stream() -> None:
    """Verifies secrets are never stored in plaintext or leaked in SSE logs."""
    terraform_runner._ACTIVE_WORKSPACE_LOCKS.clear()  # pylint: disable=protected-access
    client = testclient.TestClient(main.create_app())
    admin_headers = {
        "X-Dev-User-Email": "admin@mohanrajs.altostrat.com",
        "X-Dev-User-Role": "admin",
    }
    raw_secret = "TopSecretEntraClientValue987654"
    m365_resp = client.post(
        "/api/v1/admin/provisioning/m365",
        json={
            "gcp_project_id": "mohandemo",
            "ge_location": "global",
            "m365_collection_prefix": "corp-m365",
            "ge_app_id": "hr-benefits-assistant",
            "m365_tenant_id": "11111111-2222-3333-4444-555555555555",
            "m365_client_id": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
            "m365_client_secret": raw_secret,
            "execution_mode": "APPLY",
        },
        headers=admin_headers,
    )
    assert m365_resp.status_code == 201
    m365_job = m365_resp.json()
    assert m365_job["status"] == "SUCCEEDED"
    assert (
        m365_job["sanitized_config"]["m365_client_secret"] == "***REDACTED***"
    )
    assert raw_secret not in str(m365_job)
    assert "corp-m365-sp" in m365_job["outputs"]["provisioned_data_store_ids"]

    stream_resp = client.get(
        f"/api/v1/admin/provisioning/jobs/{m365_job['job_id']}/stream",
        headers=admin_headers,
    )
    assert stream_resp.status_code == 200
    assert "event: log" in stream_resp.text
    assert "event: status" in stream_resp.text
    assert raw_secret not in stream_resp.text
