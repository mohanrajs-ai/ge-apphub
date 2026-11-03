"""Unit tests for Firestore metadata enrichment and CatalogService."""

from unittest import mock

from app import config
from app.services import catalog
from app.services import discovery
from app.services import firestore as firestore_service


def test_firestore_service_mock_mode() -> None:
    """Verifies FirestoreMetadataService returns mock enrichment records."""
    settings = config.Settings(use_mock_data=True)
    service = firestore_service.FirestoreMetadataService(settings=settings)
    records = service.get_enrichment_map()

    assert "ge-enterprise-search" in records
    assert "ge-secops-threat-radar" in records
    ent_search = records["ge-enterprise-search"]
    assert ent_search.launch_url == (
        "https://vertexaisearch.cloud.google.com/home/cid/"
        "a8265c54-515b-413b-aaa2-828f0d65d29e"
    )
    secops = records["ge-secops-threat-radar"]
    assert "admin" in secops.allowed_roles or "security" in secops.allowed_roles


def test_firestore_service_live_mode_reads_documents() -> None:
    """Verifies live mode reads documents from Firestore collection."""
    settings = config.Settings(
        gcp_project_id="prod-project",
        firestore_collection="custom_catalog",
        use_mock_data=False,
    )

    fake_doc = mock.MagicMock()
    fake_doc.id = "ge-custom-engine"
    fake_doc.to_dict.return_value = {
        "description": "Custom AI assistant for legal review.",
        "category": "Legal & Compliance",
        "department": "Legal",
        "tags": ["contracts", "compliance"],
        "icon_name": "Shield",
        "launch_url": "https://legal-ai.internal.example.com",
        "allowed_roles": ["legal", "admin"],
        "featured": True,
    }

    fake_collection = mock.MagicMock()
    fake_collection.stream.return_value = [fake_doc]
    fake_client = mock.MagicMock()
    fake_client.collection.return_value = fake_collection

    service = firestore_service.FirestoreMetadataService(
        settings=settings,
        client_factory=lambda _project_id: fake_client,
    )
    records = service.get_enrichment_map()

    assert "ge-custom-engine" in records
    meta = records["ge-custom-engine"]
    assert meta.category == "Legal & Compliance"
    assert meta.department == "Legal"
    assert meta.launch_url == "https://legal-ai.internal.example.com"
    assert meta.allowed_roles == ["legal", "admin"]
    assert meta.featured is True
    fake_client.collection.assert_called_once_with("custom_catalog")


def test_firestore_service_live_mode_fallback_on_error() -> None:
    """Verifies FirestoreMetadataService returns empty dict on error."""
    settings = config.Settings(use_mock_data=False)

    def _failing_client(_project: str):
        raise RuntimeError("Firestore unreachable")

    service = firestore_service.FirestoreMetadataService(
        settings=settings,
        client_factory=_failing_client,
    )
    records = service.get_enrichment_map()
    assert records == {}


def test_catalog_service_role_visibility_and_filtering() -> None:
    """Verifies CatalogService merges data, enforces roles, and filters."""
    settings = config.Settings(use_mock_data=True)
    disc_svc = discovery.DiscoveryEngineService(settings=settings)
    fs_svc = firestore_service.FirestoreMetadataService(settings=settings)
    cat_svc = catalog.CatalogService(
        discovery_service=disc_svc,
        firestore_service=fs_svc,
    )

    employee_apps = cat_svc.list_applications(user_roles=["employee"])
    employee_ids = {app.engine_id for app in employee_apps}
    assert "ge-enterprise-search" in employee_ids
    assert "ge-secops-threat-radar" not in employee_ids

    admin_apps = cat_svc.list_applications(user_roles=["admin", "employee"])
    admin_ids = {app.engine_id for app in admin_apps}
    assert "ge-secops-threat-radar" in admin_ids

    searched = cat_svc.list_applications(
        user_roles=["admin", "employee"],
        query="finops",
    )
    assert len(searched) == 1
    assert searched[0].engine_id == "ge-finops-insights"

    by_category = cat_svc.list_applications(
        user_roles=["admin", "employee"],
        category="Engineering",
    )
    assert len(by_category) >= 1
    assert all(app.category == "Engineering" for app in by_category)

    by_department = cat_svc.list_applications(
        user_roles=["admin", "employee"],
        department="Finance",
    )
    assert len(by_department) == 1
    assert by_department[0].engine_id == "ge-finops-insights"

    by_tag = cat_svc.list_applications(
        user_roles=["admin", "employee"],
        tag="security",
    )
    assert len(by_tag) == 1
    assert by_tag[0].engine_id == "ge-secops-threat-radar"


def test_catalog_service_group_based_visibility() -> None:
    """Verifies CatalogService filters engines by Cloud Identity groups."""
    settings = config.Settings(
        gcp_project_id="mohandemo",
        gcp_location="global",
        use_mock_data=False,
    )
    fake_hr = mock.MagicMock()
    fake_hr.name = (
        "projects/mohandemo/locations/global/collections/"
        "default_collection/engines/hr-app-01"
    )
    fake_hr.display_name = "Gemini HR App"
    fake_hr.solution_type.name = "SOLUTION_TYPE_SEARCH"
    fake_hr.industry_vertical.name = "GENERIC"
    fake_hr.app_type.name = "APP_TYPE_INTRANET"

    fake_fin = mock.MagicMock()
    fake_fin.name = (
        "projects/mohandemo/locations/global/collections/"
        "default_collection/engines/finance-app-01"
    )
    fake_fin.display_name = "Gemini Finance App"
    fake_fin.solution_type.name = "SOLUTION_TYPE_SEARCH"
    fake_fin.industry_vertical.name = "GENERIC"
    fake_fin.app_type.name = "APP_TYPE_INTRANET"

    mock_client = mock.MagicMock()
    mock_client.list_engines.return_value = [fake_hr, fake_fin]

    iam_map = {
        "hr-app-01": ["group:hr-app-01-users@mohanrajs.altostrat.com"],
        "finance-app-01": [
            "group:finance-app-01-users@mohanrajs.altostrat.com"
        ],
    }
    membership_map = {
        (
            "mohanraj@mohanrajs.altostrat.com",
            "hr-app-01-users@mohanrajs.altostrat.com",
        ): True,
        (
            "admin@mohanrajs.altostrat.com",
            "finance-app-01-users@mohanrajs.altostrat.com",
        ): True,
    }

    disc_svc = discovery.DiscoveryEngineService(
        settings=settings,
        client_factory=lambda _loc: mock_client,
        iam_policy_resolver=lambda _proj, _loc, eid: iam_map.get(eid, []),
        group_membership_checker=lambda u, g, _p: membership_map.get(
            (u, g), False
        ),
    )
    fs_svc = firestore_service.FirestoreMetadataService(
        settings=settings,
        client_factory=lambda _proj: mock.MagicMock(
            collection=lambda _c: mock.MagicMock(stream=lambda: [])
        ),
    )
    cat_svc = catalog.CatalogService(
        discovery_service=disc_svc,
        firestore_service=fs_svc,
    )

    mohan_apps = cat_svc.list_applications(
        user_roles=["employee"],
        user_email="mohanraj@mohanrajs.altostrat.com",
    )
    assert [app.engine_id for app in mohan_apps] == ["hr-app-01"]

    admin_user_apps = cat_svc.list_applications(
        user_roles=["employee"],
        user_email="admin@mohanrajs.altostrat.com",
    )
    assert [app.engine_id for app in admin_user_apps] == ["finance-app-01"]
