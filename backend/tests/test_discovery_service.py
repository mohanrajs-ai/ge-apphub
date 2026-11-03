"""Unit tests for the Google Cloud Discovery Engine client service."""

from unittest import mock

from app import config
from app.services import discovery


def test_list_engines_mock_mode() -> None:
    """Verifies DiscoveryEngineService returns curated mock engines."""
    settings = config.Settings(
        gcp_project_id="demo-gcp-project",
        gcp_location="global",
        use_mock_data=True,
    )
    service = discovery.DiscoveryEngineService(settings=settings)
    engines = service.list_engines()

    assert len(engines) >= 5
    engine_ids = {engine.engine_id for engine in engines}
    assert "ge-enterprise-search" in engine_ids
    assert "ge-code-assist-hub" in engine_ids
    for engine in engines:
        assert engine.display_name
        assert engine.location
        assert engine.default_launch_url.startswith("https://")


def test_list_engines_live_mode_parses_sdk_response() -> None:
    """Verifies live mode calls EngineServiceClient.list_engines and maps it."""
    settings = config.Settings(
        gcp_project_id="prod-project",
        gcp_location="global",
        use_mock_data=False,
    )

    fake_engine = mock.MagicMock()
    fake_engine.name = (
        "projects/prod-project/locations/global/collections/"
        "default_collection/engines/hr-policy-assistant"
    )
    fake_engine.display_name = "HR Policy Assistant"
    fake_engine.solution_type.name = "SOLUTION_TYPE_SEARCH"
    fake_engine.industry_vertical.name = "GENERIC"
    fake_engine.app_type.name = "APP_TYPE_INTRANET"

    mock_client = mock.MagicMock()
    mock_client.list_engines.return_value = [fake_engine]

    service = discovery.DiscoveryEngineService(
        settings=settings,
        client_factory=lambda _location: mock_client,
    )
    engines = service.list_engines()

    assert len(engines) == 1
    engine = engines[0]
    assert engine.engine_id == "hr-policy-assistant"
    assert engine.display_name == "HR Policy Assistant"
    assert engine.location == "global"
    assert engine.solution_type == "SOLUTION_TYPE_SEARCH"
    assert "hr-policy-assistant" in engine.default_launch_url
    mock_client.list_engines.assert_called_once_with(
        parent=(
            "projects/prod-project/locations/global/"
            "collections/default_collection"
        )
    )


def test_list_engines_live_mode_graceful_fallback_on_error() -> None:
    """Verifies live mode returns an empty list if SDK raises an error."""
    settings = config.Settings(
        gcp_project_id="prod-project",
        gcp_location="us",
        use_mock_data=False,
    )

    def _failing_factory(_location: str):
        raise RuntimeError("ADC credentials unavailable")

    service = discovery.DiscoveryEngineService(
        settings=settings,
        client_factory=_failing_factory,
    )
    engines = service.list_engines()

    assert engines == []


def test_resolve_widget_launch_url_workforce_and_direct(monkeypatch) -> None:
    """Verifies _resolve_widget_launch_url builds OIDC or direct web app URL."""
    monkeypatch.setattr(
        discovery.google.auth,
        "default",
        lambda: (mock.MagicMock(), "mohandemo"),
    )

    class FakeResponse:
        def __init__(
            self, status_code: int, payload: dict[str, object]
        ) -> None:
            self.status_code = status_code
            self._payload = payload

        def json(self) -> dict[str, object]:
            return self._payload

    class FakeSession:
        def __init__(self, _creds: object) -> None:
            pass

        def get(self, url: str, timeout: float = 5.0) -> FakeResponse:
            del timeout
            if url.endswith("/aclConfig"):
                if "gsuite-project" in url:
                    return FakeResponse(
                        200, {"idpConfig": {"idpType": "GSUITE"}}
                    )
                return FakeResponse(
                    200, {"idpConfig": {"idpType": "THIRD_PARTY"}}
                )
            if "workforce-engine" in url:
                return FakeResponse(
                    200,
                    {
                        "configId": "cid-123",
                        "accessSettings": {
                            "workforceIdentityPoolProvider": (
                                "locations/global/workforcePools/pool-1/"
                                "providers/prov-1"
                            )
                        },
                    },
                )
            if "direct-engine" in url:
                return FakeResponse(200, {"configId": "cid-456"})
            return FakeResponse(404, {})

    monkeypatch.setattr(
        discovery.google_requests,
        "AuthorizedSession",
        FakeSession,
    )

    wf_url = discovery._resolve_widget_launch_url(
        "mohandemo", "global", "workforce-engine"
    )
    assert wf_url == (
        "https://auth.cloud.google/signin/locations/global/workforcePools/"
        "pool-1/providers/prov-1?continueUrl=https%3A%2F%2F"
        "vertexaisearch.cloud.google%2Fhome%2Fcid%2Fcid-123&hl=en_US"
    )

    gsuite_url = discovery._resolve_widget_launch_url(
        "gsuite-project", "global", "workforce-engine"
    )
    assert (
        gsuite_url == "https://vertexaisearch.cloud.google.com/home/cid/cid-123"
    )

    direct_url = discovery._resolve_widget_launch_url(
        "mohandemo", "global", "direct-engine"
    )
    assert (
        direct_url == "https://vertexaisearch.cloud.google.com/home/cid/cid-456"
    )

    fallback_url = discovery._resolve_widget_launch_url(
        "mohandemo", "us", "missing-engine"
    )
    assert "console.cloud.google.com" in fallback_url


def test_create_default_sdk_client_regional_endpoint(monkeypatch) -> None:
    """Verifies regional client options are passed for non-global locations."""
    recorded_kwargs: dict[str, object] = {}

    class FakeClient:
        def __init__(self, **kwargs: object) -> None:
            recorded_kwargs.update(kwargs)

    monkeypatch.setattr(
        discovery.discoveryengine,
        "EngineServiceClient",
        FakeClient,
    )

    discovery._create_default_sdk_client("global")
    assert recorded_kwargs["client_options"] is None

    discovery._create_default_sdk_client("us")
    client_opts = recorded_kwargs["client_options"]
    assert getattr(client_opts, "api_endpoint", None) == (
        "us-discoveryengine.googleapis.com"
    )


def test_resolve_engine_iam_and_cloud_identity_membership(monkeypatch) -> None:
    """Verifies engine IAM policy extraction and Cloud Identity group check."""
    monkeypatch.setattr(
        discovery.google.auth,
        "default",
        lambda **_kwargs: (mock.MagicMock(), "mohandemo"),
    )

    class FakeResponse:
        def __init__(
            self, status_code: int, payload: dict[str, object]
        ) -> None:
            self.status_code = status_code
            self._payload = payload

        def json(self) -> dict[str, object]:
            return self._payload

    class FakeSession:
        def __init__(self, _creds: object) -> None:
            self.headers: dict[str, str] = {}

        def get(self, url: str, timeout: float = 5.0) -> FakeResponse:
            del timeout
            if ":getIamPolicy" in url:
                return FakeResponse(
                    200,
                    {
                        "bindings": [
                            {
                                "role": "roles/discoveryengine.agentspaceUser",
                                "members": [
                                    "group:hr-app-01-users@mohanrajs.altostrat.com"
                                ],
                            }
                        ]
                    },
                )
            if "groups:lookup" in url:
                if "hr-app-01-users" in url:
                    return FakeResponse(200, {"name": "groups/hr123"})
                return FakeResponse(404, {})
            if "checkTransitiveMembership" in url:
                if "mohanraj%40" in url and "groups/hr123" in url:
                    return FakeResponse(200, {"hasMembership": True})
                return FakeResponse(200, {"hasMembership": False})
            return FakeResponse(404, {})

    monkeypatch.setattr(
        discovery.google_requests,
        "AuthorizedSession",
        FakeSession,
    )

    principals = discovery._resolve_engine_iam_principals(
        "mohandemo", "global", "hr-app-01"
    )
    assert principals == ["group:hr-app-01-users@mohanrajs.altostrat.com"]

    assert (
        discovery.check_cloud_identity_group_membership(
            "mohanraj@mohanrajs.altostrat.com",
            "hr-app-01-users@mohanrajs.altostrat.com",
            "mohandemo",
        )
        is True
    )
    assert (
        discovery.check_cloud_identity_group_membership(
            "admin@mohanrajs.altostrat.com",
            "hr-app-01-users@mohanrajs.altostrat.com",
            "mohandemo",
        )
        is False
    )

