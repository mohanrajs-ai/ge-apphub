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
    """Verifies live mode falls back to mock engines if SDK raises an error."""
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

    assert len(engines) >= 5


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

