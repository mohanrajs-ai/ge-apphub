"""Unit tests for Cloud Identity & Discovery Engine scheduled sync service."""

from typing import Any

from fastapi import testclient

from app import config
from app import database
from app import db_models
from app import main
from app import models
from app.services import discovery
from app.services import sync


class _FakeFirestoreService:
    """In-memory fake Firestore metadata service for sync tests."""

    def get_enrichment_map(self) -> dict[str, models.AppEnrichmentMetadata]:
        """Returns test enrichment metadata."""
        return {
            "hr-app-01": models.AppEnrichmentMetadata(
                engine_id="hr-app-01",
                description="Curated HR assistant",
                category="Productivity",
                department="People & HR",
                tags=["hr", "policy"],
                icon_name="Users",
                allowed_roles=["group:hr-app-01-users@mohanrajs.altostrat.com"],
                featured=True,
            ),
        }


class _FakeDiscoveryService:
    """In-memory fake Discovery Engine & Cloud Identity service for tests."""

    def list_engines(self) -> list[models.DiscoveredEngine]:
        """Returns two fake engines with Cloud Identity group IAM bindings."""
        return [
            models.DiscoveredEngine(
                engine_id="hr-app-01",
                display_name="Gemini HR App",
                location="global",
                solution_type="SOLUTION_TYPE_SEARCH",
                default_launch_url=(
                    "https://vertexaisearch.cloud.google.com/home/cid/hr"
                ),
                iam_principals=[
                    "group:hr-app-01-users@mohanrajs.altostrat.com",
                    "user:direct@mohanrajs.altostrat.com",
                ],
            ),
            models.DiscoveredEngine(
                engine_id="ops-app-01",
                display_name="Gemini Ops App",
                location="global",
                solution_type="SOLUTION_TYPE_SEARCH",
                default_launch_url=(
                    "https://vertexaisearch.cloud.google.com/home/cid/ops"
                ),
                iam_principals=[
                    "group:ops-app-01-users@mohanrajs.altostrat.com",
                ],
            ),
        ]

    def fetch_group_details_and_members(
        self,
        group_email: str,
        candidate_users: list[str] | None = None,
    ) -> dict[str, Any]:
        """Returns fake Cloud Identity group metadata and member emails."""
        del candidate_users
        if group_email == "hr-app-01-users@mohanrajs.altostrat.com":
            return {
                "group_email": group_email,
                "group_resource_name": "groups/hr01",
                "display_name": "HR App 01 Users",
                "description": "HR group",
                "members": ["mohanraj@mohanrajs.altostrat.com"],
            }
        return {
            "group_email": group_email,
            "group_resource_name": "groups/ops01",
            "display_name": "Ops App 01 Users",
            "description": "Ops group",
            "members": [
                "mohanraj@mohanrajs.altostrat.com",
                "admin@mohanrajs.altostrat.com",
            ],
        }

    def list_skills(
        self,
        engines: list[models.DiscoveredEngine] | None = None,
    ) -> list[models.DiscoveredSkill]:
        """Returns fake Gemini Enterprise skills including pending review."""
        del engines
        return discovery.get_mock_skills()


def test_catalog_sync_service_populates_database(monkeypatch) -> None:
    """Verifies CatalogSyncService upserts apps, groups, and users."""
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    database.reset_engine_cache()
    database.init_db()

    settings = config.get_settings()
    sync_service = sync.CatalogSyncService(
        settings=settings,
        discovery_service=_FakeDiscoveryService(),  # type: ignore[arg-type]
        firestore_service=_FakeFirestoreService(),  # type: ignore[arg-type]
    )

    with database.session_scope() as session:
        result = sync_service.run_sync(
            session=session,
            trigger_source="unit_test",
        )
        assert result.status == "completed"
        assert result.apps_synced == 2
        assert result.groups_synced == 2
        assert result.memberships_synced == 3

        apps = session.query(db_models.GEApplicationRecord).all()
        assert len(apps) == 2

        groups = session.query(db_models.CloudIdentityGroupRecord).all()
        assert len(groups) == 2

        mohan_groups = (
            session.query(db_models.UserGroupMembershipRecord)
            .filter_by(user_email="mohanraj@mohanrajs.altostrat.com")
            .all()
        )
        assert len(mohan_groups) == 2

        # Run a second sync to verify idempotent upserts
        result_again = sync_service.run_sync(
            session=session,
            trigger_source="scheduled",
        )
        assert result_again.status == "completed"
        assert session.query(db_models.GEApplicationRecord).count() == 2
        assert session.query(db_models.SyncRunRecord).count() == 2


def test_sync_and_groups_api_endpoints(monkeypatch) -> None:
    """Verifies sync trigger, sync status, and group list endpoints."""
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    monkeypatch.setenv("USE_MOCK_DATA", "true")
    monkeypatch.setenv("SYNC_ON_STARTUP", "true")
    database.reset_engine_cache()
    database.init_db()

    app = main.create_app()
    with testclient.TestClient(app) as client:
        # Check sync status after startup sync
        status_resp = client.get("/api/v1/sync/status")
        assert status_resp.status_code == 200
        status_payload = status_resp.json()
        assert status_payload["total_apps"] >= 6
        assert status_payload["total_groups"] >= 2
        assert status_payload["last_run"]["status"] == "completed"

        # Trigger manual sync
        sync_resp = client.post("/api/v1/sync")
        assert sync_resp.status_code == 200
        sync_payload = sync_resp.json()
        assert sync_payload["status"] == "completed"
        assert sync_payload["apps_synced"] >= 6
        assert sync_payload["groups_synced"] >= 2

        # Query synced Cloud Identity groups from database
        groups_resp = client.get(
            "/api/v1/groups",
            headers={"X-Dev-User-Email": "mohanraj@mohanrajs.altostrat.com"},
        )
        assert groups_resp.status_code == 200
        groups_payload = groups_resp.json()
        assert groups_payload["total"] >= 2
        assert any(item["is_member"] for item in groups_payload["items"])

        # Query synced skills and pending review filter
        skills_resp = client.get(
            "/api/v1/skills",
            params={"review_status": "PENDING_REVIEW"},
            headers={"X-Dev-User-Email": "mohanraj@mohanrajs.altostrat.com"},
        )
        assert skills_resp.status_code == 200
        skills_payload = skills_resp.json()
        assert skills_payload["pending_review_count"] >= 1
        assert skills_payload["total"] >= 1
        skill_id = skills_payload["items"][0]["skill_id"]

        # Query single skill detail
        detail_resp = client.get(
            f"/api/v1/skills/{skill_id}",
            headers={"X-Dev-User-Email": "mohanraj@mohanrajs.altostrat.com"},
        )
        assert detail_resp.status_code == 200
        assert detail_resp.json()["display_name"] == "daily-morning-summary"

        # 404 on unknown skill
        missing_resp = client.get(
            "/api/v1/skills/nonexistent",
            headers={"X-Dev-User-Email": "mohanraj@mohanrajs.altostrat.com"},
        )
        assert missing_resp.status_code == 404


def test_fetch_engine_skills_helper(monkeypatch) -> None:
    """Verifies Gemini Enterprise Skill API discovery and review_status."""
    class _FakeResp:
        def __init__(self, status_code: int, data: dict[str, Any]) -> None:
            self.status_code = status_code
            self._data = data

        def json(self) -> dict[str, Any]:
            return self._data

    agent_res = (
        "projects/720923281941/locations/global/collections/"
        "default_collection/engines/service-desk-app-01/assistants/"
        "default_assistant/agents/16453101121688192599"
    )

    class _FakeSession:
        def __init__(self, _creds: Any) -> None:
            self.headers: dict[str, str] = {}

        def get(self, url: str, timeout: float = 5.0) -> _FakeResp:
            del timeout
            if url.endswith("/assistants/default_assistant/agents"):
                return _FakeResp(
                    200,
                    {
                        "agents": [
                            {
                                "name": agent_res,
                                "displayName": "daily-morning-summary",
                                "description": "Morning briefing skill",
                                "state": "DISABLED",
                                "hasActiveIamProposals": True,
                                "sharingConfig": {"scope": "RESTRICTED"},
                                "skillAgentDefinition": {
                                    "gcsUri": "gs://bucket/skill/",
                                    "instruction": "# Morning Summary",
                                },
                                "createTime": "2026-10-31T12:08:33Z",
                                "updateTime": "2026-10-31T12:08:33Z",
                            },
                            {
                                "name": f"{agent_res}_deep",
                                "displayName": "Deep Research",
                                "managedAgentDefinition": {},
                            },
                        ]
                    },
                )
            if url.endswith(":getAgentView"):
                return _FakeResp(
                    200,
                    {
                        "agentView": {
                            "agentType": "SKILL_AGENT",
                            "agentSharingState": "PENDING",
                            "ownerUserPrincipal": (
                                "admin@mohanrajs.altostrat.com"
                            ),
                            "skillAgentInfo": {
                                "instruction": "# Morning Summary",
                                "subfiles": [
                                    {
                                        "fileName": "SKILL.md",
                                        "mimeType": "text/markdown",
                                    }
                                ],
                            },
                        }
                    },
                )
            if url.endswith("/iamProposals"):
                return _FakeResp(
                    200,
                    {
                        "agentIamProposals": [
                            {
                                "name": f"{agent_res}/iamProposals/84203720",
                                "principal": (
                                    "user:mohanraj@mohanrajs.altostrat.com"
                                ),
                                "role": "roles/discoveryengine.agentUser",
                                "state": "ACTIVE",
                                "createTime": "2026-11-02T12:59:45Z",
                                "expireTime": "2026-12-17T12:59:44Z",
                            }
                        ]
                    },
                )
            if url.endswith(":getIamPolicy"):
                return _FakeResp(
                    200,
                    {
                        "bindings": [
                            {
                                "role": "roles/discoveryengine.agentOwner",
                                "members": [
                                    "user:admin@mohanrajs.altostrat.com"
                                ],
                            }
                        ]
                    },
                )
            return _FakeResp(404, {})

    monkeypatch.setattr(
        discovery.google.auth,
        "default",
        lambda **_kwargs: (object(), "mohandemo"),
    )
    monkeypatch.setattr(
        discovery.google_requests,
        "AuthorizedSession",
        _FakeSession,
    )
    skills = discovery.fetch_engine_skills(
        project_id="mohandemo",
        location="global",
        engine_id="service-desk-app-01",
        app_display_name="service-desk-app-01",
    )
    assert len(skills) == 1
    assert skills[0].display_name == "daily-morning-summary"
    assert skills[0].review_status == "PENDING_REVIEW"
    assert skills[0].owner_email == "admin@mohanrajs.altostrat.com"
    assert len(skills[0].iam_proposals) == 1
    assert (
        skills[0].iam_proposals[0].principal
        == "user:mohanraj@mohanrajs.altostrat.com"
    )


def test_catalog_sync_service_records_failure(monkeypatch) -> None:
    """Verifies failed sync records status='failed' and error_message."""
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    database.reset_engine_cache()
    database.init_db()

    class _FailingDiscovery:
        def list_engines(self) -> list[models.DiscoveredEngine]:
            raise RuntimeError("Discovery API unavailable")

    settings = config.get_settings()
    sync_service = sync.CatalogSyncService(
        settings=settings,
        discovery_service=_FailingDiscovery(),  # type: ignore[arg-type]
    )
    with database.session_scope() as session:
        result = sync_service.run_sync(session=session, trigger_source="test")
        assert result.status == "failed"
        assert "Discovery API unavailable" in (result.error_message or "")


def test_cloud_identity_fetch_group_members_helper(monkeypatch) -> None:
    """Verifies Cloud Identity groups:lookup and memberships:list parsing."""
    class _FakeResp:
        def __init__(self, status_code: int, data: dict[str, Any]) -> None:
            self.status_code = status_code
            self._data = data

        def json(self) -> dict[str, Any]:
            return self._data

    class _FakeSession:
        def __init__(self, _creds: Any) -> None:
            self.headers: dict[str, str] = {}

        def get(self, url: str, timeout: float = 5.0) -> _FakeResp:
            del timeout
            if "groups:lookup" in url:
                if "ge-hr-users" in url:
                    return _FakeResp(200, {"name": "groups/sub456"})
                return _FakeResp(200, {"name": "groups/g123"})
            if url.endswith("groups/g123"):
                return _FakeResp(
                    200,
                    {
                        "name": "groups/g123",
                        "displayName": "HR Users",
                        "description": "HR Group",
                    },
                )
            if url.endswith("groups/sub456"):
                return _FakeResp(
                    200,
                    {
                        "name": "groups/sub456",
                        "displayName": "M365 HR Subgroup",
                        "description": "Federated Subgroup",
                    },
                )
            if "groups/g123/memberships" in url:
                return _FakeResp(
                    200,
                    {
                        "memberships": [
                            {
                                "preferredMemberKey": {
                                    "id": "mohanraj@mohanrajs.altostrat.com"
                                },
                                "type": "USER",
                            },
                            {
                                "preferredMemberKey": {
                                    "id": (
                                        "ge-hr-users@"
                                        "mohanrajs.demo.altostrat.com"
                                    )
                                },
                                "type": "GROUP",
                            },
                        ]
                    },
                )
            if "groups/sub456/memberships" in url:
                return _FakeResp(
                    200,
                    {
                        "memberships": [
                            {
                                "preferredMemberKey": {
                                    "id": (
                                        "pradeepg@mohanrajs.demo.altostrat.com"
                                    )
                                },
                                "type": "USER",
                            }
                        ]
                    },
                )
            return _FakeResp(404, {})

    monkeypatch.setattr(
        discovery.google.auth,
        "default",
        lambda **_kwargs: (object(), "mohandemo"),
    )
    monkeypatch.setattr(
        discovery.google_requests,
        "AuthorizedSession",
        _FakeSession,
    )
    discovery._GROUP_NAME_CACHE.clear()
    info = discovery.fetch_cloud_identity_group_details(
        group_email="hr-app-01-users@mohanrajs.altostrat.com",
        project_id="mohandemo",
    )
    assert info["group_resource_name"] == "groups/g123"
    assert info["display_name"] == "HR Users"
    assert "mohanraj@mohanrajs.altostrat.com" in info["members"]
    assert "pradeepg@mohanrajs.demo.altostrat.com" in info["members"]
    assert "ge-hr-users@mohanrajs.demo.altostrat.com" in info["subgroups"]
