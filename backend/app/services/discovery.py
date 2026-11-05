"""Discovery Engine SDK integration service for Gemini Enterprise AppHub."""

import logging
import urllib.parse
from collections import abc
from typing import Any

import google.auth
from google.api_core import client_options as gcp_client_options
from google.auth.transport import requests as google_requests
from google.cloud import discoveryengine_v1 as discoveryengine

from app import config
from app import models

LOGGER = logging.getLogger(__name__)
_WIDGET_URL_CACHE: dict[tuple[int, str, str, str], str] = {}
_ENGINE_IAM_CACHE: dict[tuple[int, str, str, str], list[str]] = {}
_GROUP_NAME_CACHE: dict[tuple[int, str], str | None] = {}
_GROUP_MEMBERSHIP_CACHE: dict[tuple[int, str, str], bool] = {}


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


def _is_workforce_identity_enabled(
    session: Any,
    endpoint: str,
    project_id: str,
    location: str,
) -> bool:
    """Checks whether the location aclConfig uses a third-party Workforce IdP.

    Args:
        session: Authorized HTTP session.
        endpoint: Discovery Engine regional/global host.
        project_id: GCP Project ID.
        location: Engine location (e.g., global, us, eu).

    Returns:
        True if Workforce Identity (THIRD_PARTY) is active, False if GSUITE.
    """
    acl_url = (
        f"https://{endpoint}/v1alpha/projects/{project_id}/locations/"
        f"{location}/aclConfig"
    )
    try:
        response = session.get(acl_url, timeout=5.0)
        if response.status_code == 200:
            idp_type = (response.json().get("idpConfig") or {}).get("idpType")
            if idp_type:
                return str(idp_type).upper() == "THIRD_PARTY"
    except Exception:  # pylint: disable=broad-except
        pass
    return True


def _resolve_widget_launch_url(
    project_id: str,
    location: str,
    engine_id: str,
) -> str:
    """Resolves the Gemini Enterprise web app launch URL from widgetConfig.

    Queries the Discovery Engine v1alpha default_search_widget_config to
    retrieve the web app configId and optional Workforce Identity Pool
    provider (when the location aclConfig uses THIRD_PARTY identity),
    falling back to the Cloud Console engine URL if unavailable.

    Args:
        project_id: GCP Project ID.
        location: Engine location (e.g., global, us, eu).
        engine_id: Discovery Engine identifier.

    Returns:
        Direct web app or Workforce Identity sign-in launch URL.
    """
    cache_key = (
        id(google_requests.AuthorizedSession),
        project_id,
        location,
        engine_id,
    )
    if cache_key in _WIDGET_URL_CACHE:
        return _WIDGET_URL_CACHE[cache_key]

    endpoint = (
        "discoveryengine.googleapis.com"
        if location == "global"
        else f"{location}-discoveryengine.googleapis.com"
    )
    url = (
        f"https://{endpoint}/v1alpha/projects/{project_id}/locations/"
        f"{location}/collections/default_collection/engines/{engine_id}/"
        "widgetConfigs/default_search_widget_config"
    )
    try:
        credentials, _ = google.auth.default()
        session = google_requests.AuthorizedSession(credentials)
        response = session.get(url, timeout=5.0)
        if response.status_code == 200:
            payload = response.json()
            config_id = payload.get("configId")
            if config_id:
                access_settings = payload.get("accessSettings") or {}
                workforce_provider = access_settings.get(
                    "workforceIdentityPoolProvider"
                )
                if workforce_provider and _is_workforce_identity_enabled(
                    session=session,
                    endpoint=endpoint,
                    project_id=project_id,
                    location=location,
                ):
                    wf_web_app_url = (
                        "https://vertexaisearch.cloud.google/home/cid/"
                        f"{config_id}"
                    )
                    provider_path = str(workforce_provider).lstrip("/")
                    encoded_continue = urllib.parse.quote(
                        wf_web_app_url, safe=""
                    )
                    resolved = (
                        f"https://auth.cloud.google/signin/{provider_path}"
                        f"?continueUrl={encoded_continue}&hl=en_US"
                    )
                    _WIDGET_URL_CACHE[cache_key] = resolved
                    return resolved
                resolved = (
                    "https://vertexaisearch.cloud.google.com/home/cid/"
                    f"{config_id}"
                )
                _WIDGET_URL_CACHE[cache_key] = resolved
                return resolved
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Widget config lookup failed for engine %s (%s); using default.",
            engine_id,
            exc,
        )
    return _build_default_console_url(
        project_id=project_id,
        location=location,
        engine_id=engine_id,
    )


def _resolve_engine_iam_principals(
    project_id: str,
    location: str,
    engine_id: str,
) -> list[str]:
    """Resolves IAM principals granted access on a Discovery Engine app.

    Queries the Discovery Engine v1alpha engines:getIamPolicy endpoint and
    extracts all unique member principals (e.g., 'group:...', 'user:...').

    Args:
        project_id: GCP Project ID.
        location: Engine location (e.g., global, us, eu).
        engine_id: Discovery Engine identifier.

    Returns:
        Sorted list of lowercase IAM principal strings.
    """
    cache_key = (
        id(google_requests.AuthorizedSession),
        project_id,
        location,
        engine_id,
    )
    if cache_key in _ENGINE_IAM_CACHE:
        return _ENGINE_IAM_CACHE[cache_key]

    endpoint = (
        "discoveryengine.googleapis.com"
        if location == "global"
        else f"{location}-discoveryengine.googleapis.com"
    )
    url = (
        f"https://{endpoint}/v1alpha/projects/{project_id}/locations/"
        f"{location}/collections/default_collection/engines/{engine_id}"
        ":getIamPolicy"
    )
    try:
        credentials, _ = google.auth.default()
        session = google_requests.AuthorizedSession(credentials)
        response = session.get(url, timeout=5.0)
        if response.status_code == 200:
            bindings = response.json().get("bindings") or []
            principals: set[str] = set()
            for binding in bindings:
                for member in binding.get("members") or []:
                    cleaned = str(member).strip().lower()
                    if cleaned:
                        principals.add(cleaned)
            resolved = sorted(principals)
            _ENGINE_IAM_CACHE[cache_key] = resolved
            return resolved
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Engine IAM policy lookup failed for %s (%s).",
            engine_id,
            exc,
        )
    return []


def check_cloud_identity_group_membership(
    user_email: str,
    group_email: str,
    project_id: str,
) -> bool:
    """Checks whether a user belongs to a Cloud Identity group.

    Args:
        user_email: User email address to check.
        group_email: Target Cloud Identity group email address.
        project_id: Quota/billing GCP project ID.

    Returns:
        True if the user is a transitive member of the group.
    """
    clean_user = user_email.strip().lower()
    clean_group = group_email.strip().lower()
    if not clean_user or not clean_group or "@" not in clean_user:
        return False
    sess_id = id(google_requests.AuthorizedSession)
    mem_key = (sess_id, clean_group, clean_user)
    if mem_key in _GROUP_MEMBERSHIP_CACHE:
        return _GROUP_MEMBERSHIP_CACHE[mem_key]
    try:
        credentials, _ = google.auth.default(
            scopes=[
                "https://www.googleapis.com/auth/cloud-platform",
                "https://www.googleapis.com/auth/cloud-identity.groups.readonly",
            ]
        )
        session = google_requests.AuthorizedSession(credentials)
        session.headers["x-goog-user-project"] = project_id
        grp_key = (sess_id, clean_group)
        if grp_key in _GROUP_NAME_CACHE:
            group_name = _GROUP_NAME_CACHE[grp_key]
        else:
            encoded_group = urllib.parse.quote(clean_group, safe="")
            lookup_url = (
                "https://cloudidentity.googleapis.com/v1/groups:lookup"
                f"?groupKey.id={encoded_group}"
            )
            lookup_resp = session.get(lookup_url, timeout=5.0)
            group_name = (
                lookup_resp.json().get("name")
                if lookup_resp.status_code == 200
                else None
            )
            _GROUP_NAME_CACHE[grp_key] = group_name
        if not group_name:
            _GROUP_MEMBERSHIP_CACHE[mem_key] = False
            return False
        query = urllib.parse.quote(f"member_key_id=='{clean_user}'", safe="")
        check_url = (
            f"https://cloudidentity.googleapis.com/v1/{group_name}/"
            f"memberships:checkTransitiveMembership?query={query}"
        )
        check_resp = session.get(check_url, timeout=5.0)
        if check_resp.status_code == 200:
            result = bool(check_resp.json().get("hasMembership", False))
            _GROUP_MEMBERSHIP_CACHE[mem_key] = result
            return result
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Cloud Identity membership check failed for %s in %s (%s).",
            clean_user,
            clean_group,
            exc,
        )
    return False


def fetch_cloud_identity_group_details(
    group_email: str,
    project_id: str,
    candidate_users: list[str] | None = None,
    _visited: set[str] | None = None,
) -> dict[str, Any]:
    """Fetches Cloud Identity group metadata and direct/transitive members.

    Recursively expands nested Cloud Identity subgroups (type == 'GROUP')
    so federated Microsoft Entra ID / M365 subgroup members are included.

    Args:
        group_email: Target Cloud Identity group email.
        project_id: Quota/billing GCP project ID.
        candidate_users: Optional candidate user emails to verify transitively.
        _visited: Internal set of already-visited group emails to prevent loops.

    Returns:
        Dictionary with group_email, group_resource_name, display_name,
        description, members, and subgroups.
    """
    clean_group = group_email.strip().lower()
    default_label = clean_group.split("@", 1)[0].replace("-", " ").title()
    result: dict[str, Any] = {
        "group_email": clean_group,
        "group_resource_name": "",
        "display_name": default_label,
        "description": f"Cloud Identity access group ({clean_group})",
        "members": [],
        "subgroups": [],
    }
    if not clean_group or "@" not in clean_group:
        return result

    visited = set(_visited) if _visited is not None else set()
    visited.add(clean_group)

    members: set[str] = set()
    subgroups: set[str] = set()
    listed_memberships_ok = False
    try:
        credentials, _ = google.auth.default(
            scopes=[
                "https://www.googleapis.com/auth/cloud-platform",
                "https://www.googleapis.com/auth/cloud-identity.groups.readonly",
            ]
        )
        session = google_requests.AuthorizedSession(credentials)
        session.headers["x-goog-user-project"] = project_id
        sess_id = id(google_requests.AuthorizedSession)
        grp_key = (sess_id, clean_group)
        if grp_key in _GROUP_NAME_CACHE:
            group_name = _GROUP_NAME_CACHE[grp_key]
        else:
            encoded_group = urllib.parse.quote(clean_group, safe="")
            lookup_url = (
                "https://cloudidentity.googleapis.com/v1/groups:lookup"
                f"?groupKey.id={encoded_group}"
            )
            lookup_resp = session.get(lookup_url, timeout=5.0)
            group_name = (
                lookup_resp.json().get("name")
                if lookup_resp.status_code == 200
                else None
            )
            _GROUP_NAME_CACHE[grp_key] = group_name

        if group_name:
            result["group_resource_name"] = str(group_name)
            grp_resp = session.get(
                f"https://cloudidentity.googleapis.com/v1/{group_name}",
                timeout=5.0,
            )
            if grp_resp.status_code == 200:
                grp_json = grp_resp.json()
                if grp_json.get("displayName"):
                    result["display_name"] = str(grp_json["displayName"])
                if grp_json.get("description"):
                    result["description"] = str(grp_json["description"])

            mem_resp = session.get(
                f"https://cloudidentity.googleapis.com/v1/{group_name}/"
                "memberships?pageSize=200&view=FULL",
                timeout=5.0,
            )
            if mem_resp.status_code == 200:
                listed_memberships_ok = True
                for item in mem_resp.json().get("memberships") or []:
                    key_id = (item.get("preferredMemberKey") or {}).get("id")
                    if not key_id or "@" not in str(key_id):
                        continue
                    clean_id = str(key_id).strip().lower()
                    item_type = str(item.get("type", "USER")).strip().upper()
                    if item_type == "GROUP":
                        subgroups.add(clean_id)
                        if clean_id not in visited:
                            sub_info = fetch_cloud_identity_group_details(
                                group_email=clean_id,
                                project_id=project_id,
                                candidate_users=None,
                                _visited=visited,
                            )
                            for sub_member in sub_info.get("members") or []:
                                members.add(str(sub_member).strip().lower())
                    else:
                        members.add(clean_id)
    except Exception as exc:  # pylint: disable=broad-except
        LOGGER.debug(
            "Cloud Identity group details lookup failed for %s (%s).",
            clean_group,
            exc,
        )

    if group_name and not listed_memberships_ok:
        for candidate in candidate_users or []:
            clean_user = candidate.strip().lower()
            if (
                clean_user
                and clean_user not in members
                and clean_user not in subgroups
            ):
                if check_cloud_identity_group_membership(
                    user_email=clean_user,
                    group_email=clean_group,
                    project_id=project_id,
                ):
                    members.add(clean_user)

    result["members"] = sorted(members - subgroups)
    result["subgroups"] = sorted(subgroups)
    return result


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


def get_mock_group_directory() -> dict[str, dict[str, Any]]:
    """Returns curated Cloud Identity group records for mock/demo mode."""
    return {
        "hr-app-01-users@mohanrajs.altostrat.com": {
            "group_email": "hr-app-01-users@mohanrajs.altostrat.com",
            "group_resource_name": "groups/mock-hr-01",
            "display_name": "HR App 01 Users",
            "description": "Cloud Identity group for HR applications",
            "members": [
                "mohanraj@mohanrajs.altostrat.com",
                "developer@enterprise.example.com",
            ],
        },
        "ops-app-01-users@mohanrajs.altostrat.com": {
            "group_email": "ops-app-01-users@mohanrajs.altostrat.com",
            "group_resource_name": "groups/mock-ops-01",
            "display_name": "Ops App 01 Users",
            "description": "Cloud Identity group for Operations applications",
            "members": [
                "mohanraj@mohanrajs.altostrat.com",
                "admin@mohanrajs.altostrat.com",
                "developer@enterprise.example.com",
            ],
        },
    }


class DiscoveryEngineService:
    """Fetches Gemini Enterprise applications via Discovery Engine API."""

    def __init__(
        self,
        settings: config.Settings,
        client_factory: abc.Callable[[str], Any] | None = None,
        widget_url_resolver: abc.Callable[[str, str, str], str] | None = None,
        iam_policy_resolver: (
            abc.Callable[[str, str, str], list[str]] | None
        ) = None,
        group_membership_checker: (
            abc.Callable[[str, str, str], bool] | None
        ) = None,
    ) -> None:
        """Initializes DiscoveryEngineService.

        Args:
            settings: Application settings.
            client_factory: Optional factory for EngineServiceClient injection.
            widget_url_resolver: Optional resolver for engine launch URLs.
            iam_policy_resolver: Optional resolver for engine IAM principals.
            group_membership_checker: Optional Cloud Identity group checker.
        """
        self._settings = settings
        self._client_factory = client_factory or _create_default_sdk_client
        if widget_url_resolver is not None:
            self._widget_url_resolver = widget_url_resolver
        elif client_factory is not None:
            self._widget_url_resolver = _build_default_console_url
        else:
            self._widget_url_resolver = _resolve_widget_launch_url

        if iam_policy_resolver is not None:
            self._iam_policy_resolver = iam_policy_resolver
        elif client_factory is not None:
            self._iam_policy_resolver = lambda *_args: []
        else:
            self._iam_policy_resolver = _resolve_engine_iam_principals

        self._group_membership_checker = (
            group_membership_checker or check_cloud_identity_group_membership
        )

    def resolve_user_groups(
        self,
        user_email: str,
        engines: list[models.DiscoveredEngine],
    ) -> list[str]:
        """Resolves which engine IAM groups the user belongs to.

        Args:
            user_email: Active user email address.
            engines: Discovered engines containing iam_principals.

        Returns:
            Sorted list of group email addresses the user is a member of.
        """
        if not user_email or self._settings.use_mock_data:
            return []
        candidate_groups: set[str] = set()
        for engine in engines:
            for principal in engine.iam_principals:
                if principal.startswith("group:"):
                    group_email = principal.split(":", 1)[1].strip().lower()
                    if group_email:
                        candidate_groups.add(group_email)

        matched_groups: list[str] = []
        for group_email in sorted(candidate_groups):
            if self._group_membership_checker(
                user_email,
                group_email,
                self._settings.gcp_project_id,
            ):
                matched_groups.append(group_email)
        return matched_groups

    def fetch_group_details_and_members(
        self,
        group_email: str,
        candidate_users: list[str] | None = None,
    ) -> dict[str, Any]:
        """Fetches Cloud Identity group details and members for a group email.

        Args:
            group_email: Target Cloud Identity group email.
            candidate_users: Optional candidate user emails to verify.

        Returns:
            Dictionary with group metadata and member emails.
        """
        clean_group = group_email.strip().lower()
        if self._settings.use_mock_data:
            mock_dir = get_mock_group_directory()
            if clean_group in mock_dir:
                return mock_dir[clean_group]
            return {
                "group_email": clean_group,
                "group_resource_name": f"groups/mock-{clean_group}",
                "display_name": clean_group.split("@", 1)[0].title(),
                "description": f"Mock Cloud Identity group ({clean_group})",
                "members": ["developer@enterprise.example.com"],
            }
        return fetch_cloud_identity_group_details(
            group_email=clean_group,
            project_id=self._settings.gcp_project_id,
            candidate_users=candidate_users,
        )

    def list_engines(self) -> list[models.DiscoveredEngine]:
        """Lists Gemini Enterprise engines from GCP or mock when configured.

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
                launch_url = self._widget_url_resolver(
                    self._settings.gcp_project_id,
                    location,
                    engine_id,
                )
                iam_principals = self._iam_policy_resolver(
                    self._settings.gcp_project_id,
                    location,
                    engine_id,
                )
                discovered.append(
                    models.DiscoveredEngine(
                        engine_id=engine_id,
                        display_name=item.display_name or engine_id,
                        location=location,
                        solution_type=str(solution_type),
                        industry_vertical=str(industry_vertical),
                        app_type=str(app_type),
                        default_launch_url=launch_url,
                        iam_principals=iam_principals,
                    )
                )
            return discovered
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.warning(
                "Discovery Engine SDK call failed (%s); returning empty list.",
                exc,
            )
            return []
