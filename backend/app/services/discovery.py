"""Discovery Engine SDK integration service for Gemini Enterprise AppHub."""

import logging
from collections import abc
from typing import Any

from google.api_core import client_options as gcp_client_options
from google.cloud import discoveryengine_v1 as discoveryengine

from app import config
from app import models

LOGGER = logging.getLogger(__name__)


def _build_default_console_url(
    project_id: str,
    location: str,
    engine_id: str,
) -> str:
    """Builds the default Gemini Enterprise / Cloud Console launch URL.

    Args:
        project_id: GCP Project ID.
        location: Engine location (e.g., global, us, eu).
        engine_id: Discovery Engine identifier.

    Returns:
        HTTPS URL string for launching the application.
    """
    return (
        "https://console.cloud.google.com/gen-app-builder/locations/"
        f"{location}/engines/{engine_id}?project={project_id}"
    )


def _create_default_sdk_client(
    location: str,
) -> discoveryengine.EngineServiceClient:
    """Creates a Discovery Engine EngineServiceClient for a location.

    Args:
        location: Target GCP location (global, us, eu).

    Returns:
        Configured EngineServiceClient instance.
    """
    options = None
    if location != "global":
        api_endpoint = f"{location}-discoveryengine.googleapis.com"
        options = gcp_client_options.ClientOptions(api_endpoint=api_endpoint)
    return discoveryengine.EngineServiceClient(client_options=options)


def get_mock_engines(project_id: str) -> list[models.DiscoveredEngine]:
    """Returns curated mock Gemini Enterprise engines for local/demo mode.

    Args:
        project_id: Active GCP project ID used in default launch URLs.

    Returns:
        List of DiscoveredEngine records.
    """
    raw_items = [
        (
            "ge-enterprise-search",
            "Gemini Enterprise Knowledge Search",
            "global",
            "SOLUTION_TYPE_SEARCH",
        ),
        (
            "ge-code-assist-hub",
            "Gemini Engineering & Architecture Assistant",
            "global",
            "SOLUTION_TYPE_CHAT",
        ),
        (
            "ge-finops-insights",
            "Cloud FinOps & Spend Intelligence Agent",
            "us",
            "SOLUTION_TYPE_GENERATIVE_CHAT",
        ),
        (
            "ge-customer-support-copilot",
            "Customer Support Case Resolution Copilot",
            "us",
            "SOLUTION_TYPE_CHAT",
        ),
        (
            "ge-hr-people-portal",
            "People Operations & Policy Concierge",
            "global",
            "SOLUTION_TYPE_SEARCH",
        ),
        (
            "ge-secops-threat-radar",
            "Security Operations & Compliance Analyzer",
            "us",
            "SOLUTION_TYPE_SEARCH",
        ),
    ]
    return [
        models.DiscoveredEngine(
            engine_id=engine_id,
            display_name=display_name,
            location=location,
            solution_type=solution_type,
            industry_vertical="GENERIC",
            app_type="APP_TYPE_INTRANET",
            default_launch_url=_build_default_console_url(
                project_id=project_id,
                location=location,
                engine_id=engine_id,
            ),
        )
        for engine_id, display_name, location, solution_type in raw_items
    ]


class DiscoveryEngineService:
    """Fetches Gemini Enterprise applications via Discovery Engine API."""

    def __init__(
        self,
        settings: config.Settings,
        client_factory: abc.Callable[[str], Any] | None = None,
    ) -> None:
        """Initializes DiscoveryEngineService.

        Args:
            settings: Application settings.
            client_factory: Optional factory for EngineServiceClient injection.
        """
        self._settings = settings
        self._client_factory = client_factory or _create_default_sdk_client

    def list_engines(self) -> list[models.DiscoveredEngine]:
        """Lists Gemini Enterprise engines from GCP or mock fallback.

        Returns:
            List of normalized DiscoveredEngine objects.
        """
        if self._settings.use_mock_data:
            return get_mock_engines(self._settings.gcp_project_id)

        location = self._settings.gcp_location
        parent = (
            f"projects/{self._settings.gcp_project_id}/locations/{location}/"
            "collections/default_collection"
        )
        try:
            client = self._client_factory(location)
            response = client.list_engines(parent=parent)
            discovered: list[models.DiscoveredEngine] = []
            for item in response:
                engine_id = item.name.split("/")[-1]
                solution_type = getattr(
                    getattr(item, "solution_type", None),
                    "name",
                    "SOLUTION_TYPE_SEARCH",
                )
                industry_vertical = getattr(
                    getattr(item, "industry_vertical", None),
                    "name",
                    "GENERIC",
                )
                app_type = getattr(
                    getattr(item, "app_type", None),
                    "name",
                    "APP_TYPE_INTRANET",
                )
                discovered.append(
                    models.DiscoveredEngine(
                        engine_id=engine_id,
                        display_name=item.display_name or engine_id,
                        location=location,
                        solution_type=str(solution_type),
                        industry_vertical=str(industry_vertical),
                        app_type=str(app_type),
                        default_launch_url=_build_default_console_url(
                            project_id=self._settings.gcp_project_id,
                            location=location,
                            engine_id=engine_id,
                        ),
                    )
                )
            return discovered
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.warning(
                "Discovery Engine SDK call failed (%s); falling back to mock.",
                exc,
            )
            return get_mock_engines(self._settings.gcp_project_id)
