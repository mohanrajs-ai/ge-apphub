"""Cloud Firestore metadata enrichment service for Gemini Enterprise AppHub."""

import logging
from collections import abc
from typing import Any

from google.cloud import firestore

from app import config
from app import models

LOGGER = logging.getLogger(__name__)


def _create_default_firestore_client(project_id: str) -> firestore.Client:
    """Creates a Cloud Firestore client for the given project ID.

    Args:
        project_id: GCP Project ID.

    Returns:
        Configured Firestore Client instance.
    """
    return firestore.Client(project=project_id)


def get_mock_enrichment_map() -> dict[str, models.AppEnrichmentMetadata]:
    """Returns curated Firestore enrichment metadata for mock/demo mode.

    Returns:
        Dictionary mapping engine_id to AppEnrichmentMetadata.
    """
    items = [
        models.AppEnrichmentMetadata(
            engine_id="ge-enterprise-search",
            description=(
                "Search across Confluence, Google Drive, Jira, and internal "
                "wikis with grounded generative answers and citations."
            ),
            category="Productivity",
            department="Organization-Wide",
            tags=["search", "knowledge-base", "citations", "workspace"],
            icon_name="Search",
            launch_url=(
                "https://auth.cloud.google/signin/locations/global/"
                "workforcePools/mohan-entra-id-oidc-pool/providers/"
                "entra-id-oidc-pool-provider?continueUrl=https%3A%2F%2F"
                "vertexaisearch.cloud.google%2Fhome%2Fcid%2F"
                "a8265c54-515b-413b-aaa2-828f0d65d29e&hl=en_US"
            ),
            allowed_roles=["*"],
            featured=True,
        ),
        models.AppEnrichmentMetadata(
            engine_id="ge-code-assist-hub",
            description=(
                "Accelerate architecture reviews, internal SDK lookups, and "
                "production runbook synthesis across engineering repositories."
            ),
            category="Engineering",
            department="Engineering",
            tags=["code", "architecture", "runbooks", "developer-tools"],
            icon_name="Code2",
            allowed_roles=["*", "engineering", "admin"],
            featured=True,
        ),
        models.AppEnrichmentMetadata(
            engine_id="ge-finops-insights",
            description=(
                "Analyze GCP billing trends, forecast commitments, and "
                "identify idle cloud resources using natural language queries."
            ),
            category="Data & Analytics",
            department="Finance",
            tags=["finops", "bigquery", "cost-optimization", "analytics"],
            icon_name="BarChart3",
            allowed_roles=["*", "data-analyst", "finance", "admin"],
            featured=True,
        ),
        models.AppEnrichmentMetadata(
            engine_id="ge-customer-support-copilot",
            description=(
                "Draft accurate customer responses, summarize multi-thread "
                "escalations, and surface relevant troubleshooting KB articles."
            ),
            category="Customer Experience",
            department="Support & Success",
            tags=["support", "crm", "copilot", "troubleshooting"],
            icon_name="Headphones",
            allowed_roles=["*"],
            featured=False,
        ),
        models.AppEnrichmentMetadata(
            engine_id="ge-hr-people-portal",
            description=(
                "Instant answers on global benefits, leave policies, "
                "onboarding checklists, and learning & development programs."
            ),
            category="Productivity",
            department="People & HR",
            tags=["hr", "benefits", "onboarding", "policy"],
            icon_name="Users",
            allowed_roles=["*"],
            featured=False,
        ),
        models.AppEnrichmentMetadata(
            engine_id="ge-secops-threat-radar",
            description=(
                "Restricted security operations assistant for correlating "
                "IAM audit logs, CVE advisories, and compliance posture checks."
            ),
            category="Security & Governance",
            department="Information Security",
            tags=["security", "iam", "compliance", "secops"],
            icon_name="ShieldAlert",
            allowed_roles=["admin", "security"],
            featured=False,
        ),
    ]
    return {item.engine_id: item for item in items}


class FirestoreMetadataService:
    """Retrieves application catalog enrichment metadata from Firestore."""

    def __init__(
        self,
        settings: config.Settings,
        client_factory: abc.Callable[[str], Any] | None = None,
    ) -> None:
        """Initializes FirestoreMetadataService.

        Args:
            settings: Application settings.
            client_factory: Optional factory for Firestore Client injection.
        """
        self._settings = settings
        self._client_factory = (
            client_factory or _create_default_firestore_client
        )

    def get_enrichment_map(self) -> dict[str, models.AppEnrichmentMetadata]:
        """Fetches enrichment documents keyed by engine_id.

        Returns:
            Dictionary mapping engine_id to AppEnrichmentMetadata.
        """
        if self._settings.use_mock_data:
            return get_mock_enrichment_map()

        try:
            client = self._client_factory(self._settings.gcp_project_id)
            collection_ref = client.collection(
                self._settings.firestore_collection
            )
            enrichment_map: dict[str, models.AppEnrichmentMetadata] = {}
            for doc in collection_ref.stream():
                raw = doc.to_dict() or {}
                engine_id = str(raw.get("engine_id") or doc.id)
                enrichment_map[engine_id] = models.AppEnrichmentMetadata(
                    engine_id=engine_id,
                    description=str(raw.get("description", "")),
                    category=str(raw.get("category", "Productivity")),
                    department=str(raw.get("department", "General")),
                    tags=[str(tag) for tag in raw.get("tags", [])],
                    icon_name=str(raw.get("icon_name", "Sparkles")),
                    launch_url=raw.get("launch_url"),
                    allowed_roles=[
                        str(role).lower()
                        for role in raw.get("allowed_roles", ["*"])
                    ],
                    featured=bool(raw.get("featured", False)),
                )
            return enrichment_map
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.warning(
                "Firestore metadata lookup failed (%s); using mock metadata.",
                exc,
            )
            return get_mock_enrichment_map()
