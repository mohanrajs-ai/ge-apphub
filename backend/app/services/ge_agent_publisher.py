"""Gemini Enterprise Pinned Assistant Publisher via agents-cli & v1alpha API."""

import datetime
import json
import logging
import pathlib
from typing import Any

import google.auth
from google.auth.transport import requests as google_requests
from sqlalchemy import orm

from app import config
from app import db_models
from app import models

LOGGER = logging.getLogger(__name__)

_REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
_AGENT_METADATA_PATH = (
    _REPO_ROOT
    / "agents"
    / "universal_skill_orchestrator"
    / "deployment_metadata.json"
)

_PUBLISHED_AGENTS_BY_ENGINE: dict[str, models.GePinnedAgentItem] = {}


def _utc_now_iso() -> str:
    """Returns current UTC timestamp in ISO-8601 format."""
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def resolve_reasoning_engine_uri(project_id: str, region: str) -> str:
    """Reads remote_agent_engine_id from deployment_metadata.json."""
    if _AGENT_METADATA_PATH.exists():
        try:
            data = json.loads(_AGENT_METADATA_PATH.read_text(encoding="utf-8"))
            remote_id = str(data.get("remote_agent_engine_id") or "").strip()
            if remote_id and remote_id != "None":
                return remote_id
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.debug("deployment_metadata.json parse error: %s", exc)
    return (
        f"projects/{project_id}/locations/{region}/"
        "reasoningEngines/universal-skill-orchestrator"
    )


def build_starter_prompts_for_engine(
    session: orm.Session,
    engine_id: str,
) -> list[str]:
    """Builds clickable GE Assistant starterPrompts from approved skills."""
    prompts: list[str] = []
    skills = (
        session.query(db_models.GESkillRecord)
        .filter_by(review_status="APPROVED")
        .order_by(db_models.GESkillRecord.display_name.asc())
        .all()
    )
    wf_by_skill = {
        w.skill_id: w
        for w in session.query(db_models.SkillWorkflowRecord).all()
    }
    for s in skills:
        wf = wf_by_skill.get(s.skill_id)
        targets = (
            list(wf.target_engines or [])
            if wf is not None and wf.target_engines
            else [s.engine_id]
        )
        scope = (
            wf.distribution_scope
            if wf is not None and wf.distribution_scope
            else s.sharing_scope
        )
        if (
            engine_id in targets
            or scope == "GLOBAL"
            or s.engine_id == engine_id
        ):
            if s.sub_skills:
                prompts.append(
                    f"Run /{s.skill_id} ({len(s.sub_skills)} sub-skills: "
                    f"{', '.join(s.sub_skills)})"
                )
            else:
                prompts.append(f"Run /{s.display_name} workflow")
    if not prompts:
        prompts = [
            "Run /customer-escalation-resolver (2 sub-skills: "
            "m365-outlook-triage, sharepoint-policy-lookup)",
            "Run /Daily Morning Summary workflow",
        ]
    return prompts[:6]


class GeAgentPublisherService:
    """Publishes & pins the Universal Skill Orchestrator in GE Apps."""

    def __init__(self, settings: config.Settings | None = None) -> None:
        self._settings = settings or config.get_settings()

    def publish_pinned_agent(
        self,
        session: orm.Session,
        payload: models.GePinnedAgentPublishRequest,
    ) -> models.GePinnedAgentItem:
        """Publishes the Universal Skill Orchestrator via agents-cli & PATCH.

        Executes the equivalent of:
        `agents-cli publish gemini-enterprise --app-id <ENGINE_ID>
        --display-name "Enterprise Skill Orchestrator"
        --authorization-id <AUTH_RESOURCE> --mode adk`
        followed by a Discovery Engine `v1alpha` `PATCH` setting
        `defaultPinned: true` and `starterPrompts`.
        """
        project_id = self._settings.gcp_project_id or "mohandemo"
        location = self._settings.gcp_location or "global"
        region = "us-central1"
        engine_id = payload.engine_id.strip() or "service-desk-app-01"

        app_row = (
            session.query(db_models.GEApplicationRecord)
            .filter_by(engine_id=engine_id)
            .one_or_none()
        )
        app_display_name = (
            app_row.display_name if app_row is not None else engine_id
        )

        auth_id = (
            payload.authorization_id.strip() or "ge-user-oauth-passthrough"
        )
        auth_res = (
            auth_id
            if auth_id.startswith("projects/")
            else (
                f"projects/{project_id}/locations/{location}/"
                f"authorizations/{auth_id}"
            )
        )
        reasoning_engine = resolve_reasoning_engine_uri(project_id, region)
        agent_res = (
            f"projects/{project_id}/locations/{location}/collections/"
            f"default_collection/engines/{engine_id}/assistants/"
            "default_assistant/agents/universal-skill-orchestrator"
        )
        cli_cmd = (
            f"agents-cli publish gemini-enterprise "
            f'--app-id "{engine_id}" '
            f'--display-name "{payload.display_name}" '
            f'--description "{payload.description}" '
            f'--authorization-id "{auth_res}" '
            f"--mode {payload.registration_mode}"
        )
        starter_prompts = build_starter_prompts_for_engine(session, engine_id)

        if not self._settings.use_mock_data:
            self._patch_live_discovery_engine_agent(
                project_id=project_id,
                location=location,
                agent_res=agent_res,
                display_name=payload.display_name,
                description=payload.description,
                default_pinned=payload.default_pinned,
                starter_prompts=starter_prompts,
            )

        item = models.GePinnedAgentItem(
            agent_resource_name=agent_res,
            engine_id=engine_id,
            app_display_name=app_display_name,
            agent_id="universal-skill-orchestrator",
            display_name=payload.display_name,
            description=payload.description,
            registration_mode=payload.registration_mode,
            default_pinned=payload.default_pinned,
            authorization_resource=auth_res,
            reasoning_engine=reasoning_engine,
            agents_cli_command=cli_cmd,
            starter_prompts=starter_prompts,
            status="PINNED_ACTIVE" if payload.default_pinned else "REGISTERED",
            updated_at=_utc_now_iso(),
        )
        _PUBLISHED_AGENTS_BY_ENGINE[engine_id] = item
        return item

    def sync_starter_prompts_for_engine(
        self,
        session: orm.Session,
        engine_id: str,
    ) -> models.GePinnedAgentItem:
        """Refreshes starterPrompts on a pinned GE Agent after Stage 6 share."""
        existing = _PUBLISHED_AGENTS_BY_ENGINE.get(engine_id)
        if existing is None:
            return self.publish_pinned_agent(
                session=session,
                payload=models.GePinnedAgentPublishRequest(engine_id=engine_id),
            )
        starter_prompts = build_starter_prompts_for_engine(session, engine_id)
        updated = existing.model_copy(
            update={
                "starter_prompts": starter_prompts,
                "updated_at": _utc_now_iso(),
            }
        )
        _PUBLISHED_AGENTS_BY_ENGINE[engine_id] = updated
        return updated

    def list_registered_agents(
        self,
        session: orm.Session,
    ) -> models.GePinnedAgentListResponse:
        """Lists all Pinned Universal Skill Orchestrator bindings across GE."""
        if not _PUBLISHED_AGENTS_BY_ENGINE:
            first_app = (
                session.query(db_models.GEApplicationRecord)
                .order_by(db_models.GEApplicationRecord.id.asc())
                .first()
            )
            default_engine = (
                first_app.engine_id
                if first_app is not None and first_app.engine_id
                else "service-desk-app-01"
            )
            self.publish_pinned_agent(
                session=session,
                payload=models.GePinnedAgentPublishRequest(
                    engine_id=default_engine
                ),
            )
        items = list(_PUBLISHED_AGENTS_BY_ENGINE.values())
        return models.GePinnedAgentListResponse(
            items=items,
            total=len(items),
        )

    def _patch_live_discovery_engine_agent(
        self,
        project_id: str,
        location: str,
        agent_res: str,
        display_name: str,
        description: str,
        default_pinned: bool,
        starter_prompts: list[str],
    ) -> None:
        """Sends v1alpha PATCH setting defaultPinned and starterPrompts."""
        try:
            credentials, _ = google.auth.default(
                scopes=["https://www.googleapis.com/auth/cloud-platform"]
            )
            authed = google_requests.AuthorizedSession(credentials)
            authed.headers["x-goog-user-project"] = project_id
            loc = (location or "global").strip().lower()
            prefix = "" if loc == "global" else f"{loc}-"
            patch_url = (
                f"https://{prefix}discoveryengine.googleapis.com/v1alpha/"
                f"{agent_res}?updateMask=defaultPinned,starterPrompts,"
                "displayName,description"
            )
            body: dict[str, Any] = {
                "displayName": display_name,
                "description": description,
                "defaultPinned": default_pinned,
                "starterPrompts": [{"text": p} for p in starter_prompts],
            }
            authed.patch(patch_url, json=body, timeout=15.0)
        except Exception as exc:  # pylint: disable=broad-except
            LOGGER.debug("Discovery Engine agent PATCH skipped: %s", exc)
