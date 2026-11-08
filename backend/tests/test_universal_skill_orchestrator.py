"""Tests for Track 2: Universal ADK Skill & Sub-Skill Orchestrator Agent."""

import os
from collections import abc

import pytest
from fastapi import testclient

from app import database
from app import main
from skill_workflow_service.agents import ge_discovery_llm
from skill_workflow_service.agents import skill_eval_agent


@pytest.fixture(autouse=True)
def _use_isolated_memory_db(
    monkeypatch: pytest.MonkeyPatch,
) -> abc.Generator[None, None, None]:
    """Forces in-memory SQLite database during orchestrator tests."""
    monkeypatch.setenv("USE_MOCK_DATA", "true")
    os.environ.pop("DATABASE_URL", None)
    database.reset_engine_cache()
    database.init_db()
    yield
    database.reset_engine_cache()


def test_extract_sub_skills_from_yaml_frontmatter_and_steps() -> None:
    """Verifies YAML frontmatter and inline step sub_skills extraction."""
    md = (
        "---\n"
        "name: customer-escalation-resolver\n"
        "sub_skills:\n"
        "  - m365-outlook-triage\n"
        "  - sharepoint-policy-lookup\n"
        "---\n\n"
        "# Customer Escalation Resolver\n"
        "## When to Use\n"
        "Trigger on P1 customer escalations.\n"
        "## Expected Input & Output\n"
        "Input: email thread. Output: action plan.\n"
        "## Step-by-Step Workflow\n"
        "1. Delegate to sub-skill `m365-outlook-triage`.\n"
        "2. Delegate to sub-skill `sharepoint-policy-lookup`.\n"
    )
    extracted = skill_eval_agent.extract_sub_skills(md)
    assert extracted == ["m365-outlook-triage", "sharepoint-policy-lookup"]

    eval_res = skill_eval_agent.SkillEvaluationAdkAgent().evaluate_skill(
        display_name="Customer Escalation Resolver",
        description="Resolves P1 customer escalations using sub-skills.",
        instruction=md,
    )
    assert eval_res["passed"] is True
    assert eval_res["sub_skills"] == [
        "m365-outlook-triage",
        "sharepoint-policy-lookup",
    ]


def test_seed_catalog_and_orchestrate_composite_skill() -> None:
    """Verifies seeding composite skills and orchestrating sub-skills."""
    client = testclient.TestClient(main.app)
    headers = {
        "X-Goog-Authenticated-User-Email": "admin@mohanrajs.altostrat.com"
    }

    seed_resp = client.post("/api/v1/skills/seed-catalog", headers=headers)
    assert seed_resp.status_code == 200
    seed_data = seed_resp.json()
    assert seed_data["total_seeded"] == 8
    for expected_skill_id in (
        "customer-escalation-resolver",
        "daily-morning-summary",
        "service-desk-major-incident-bridge",
        "m365-outlook-triage",
        "sharepoint-policy-lookup",
        "m365-teams-incident-swarm",
        "m365-onedrive-artifact-finder",
        "m365-calendar-briefing",
    ):
        assert expected_skill_id in seed_data["seeded_skills"]

    skill_resp = client.get(
        "/api/v1/skills/customer-escalation-resolver",
        headers=headers,
    )
    assert skill_resp.status_code == 200
    skill_json = skill_resp.json()
    assert skill_json["sub_skills"] == [
        "m365-outlook-triage",
        "sharepoint-policy-lookup",
    ]

    orch_resp = client.post(
        "/api/v1/skills/orchestrate",
        headers={
            **headers,
            "X-GE-User-OAuth-Token": "Bearer ya29.mock-ge-user-oauth-token",
        },
        json={
            "skill_id": "customer-escalation-resolver",
            "engine_id": "service-desk-app-01",
            "user_prompt": (
                "Triage the P1 escalation from vp-infra@contoso.com and "
                "recommend SLA credit."
            ),
        },
    )
    assert orch_resp.status_code == 200
    orch_data = orch_resp.json()
    assert orch_data["agent_name"] == "universal_skill_orchestrator"
    assert orch_data["is_composite_skill"] is True
    assert orch_data["identity_passthrough_mode"] == "USER_OAUTH_PASSTHROUGH"
    assert orch_data["sub_skills_loaded"] == [
        "m365-outlook-triage",
        "sharepoint-policy-lookup",
    ]
    assert len(orch_data["sub_skill_traces"]) == 2
    assert (
        orch_data["sub_skill_traces"][0]["sub_skill_name"]
        == "m365-outlook-triage"
    )
    assert (
        orch_data["sub_skill_traces"][1]["sub_skill_name"]
        == "sharepoint-policy-lookup"
    )
    assert "Universal ADK Skill Orchestrator" in orch_data["final_response"]
    assert orch_data["total_tokens_saved"] >= 840

    morning_resp = client.post(
        "/api/v1/skills/orchestrate",
        headers={
            **headers,
            "X-GE-User-OAuth-Token": "Bearer ya29.mock-ge-user-oauth-token",
        },
        json={
            "skill_id": "daily-morning-summary",
            "engine_id": "cymbal-service-desk-app",
            "user_prompt": (
                "Generate my Daily Morning Briefing across Outlook Calendar, "
                "Outlook Email, and Microsoft Teams."
            ),
        },
    )
    assert morning_resp.status_code == 200
    morning_data = morning_resp.json()
    assert morning_data["sub_skills_loaded"] == [
        "m365-calendar-briefing",
        "m365-outlook-triage",
        "m365-teams-incident-swarm",
    ]
    assert len(morning_data["sub_skill_traces"]) == 3

    bridge_resp = client.post(
        "/api/v1/skills/orchestrate",
        headers={
            **headers,
            "X-GE-User-OAuth-Token": "Bearer ya29.mock-ge-user-oauth-token",
        },
        json={
            "skill_id": "service-desk-major-incident-bridge",
            "engine_id": "cymbal-service-desk-app",
            "user_prompt": (
                "Run Major Incident Bridge for P1 Contoso API Latency across "
                "Teams, SharePoint, OneDrive, and Outlook."
            ),
        },
    )
    assert bridge_resp.status_code == 200
    bridge_data = bridge_resp.json()
    assert bridge_data["sub_skills_loaded"] == [
        "m365-teams-incident-swarm",
        "sharepoint-policy-lookup",
        "m365-onedrive-artifact-finder",
        "m365-outlook-triage",
    ]
    assert len(bridge_data["sub_skill_traces"]) == 4


def test_extract_forwarded_ge_user_token_variants() -> None:
    """Verifies token extraction from headers, state, and explicit input."""
    token1 = ge_discovery_llm.extract_forwarded_ge_user_token(
        headers={"X-GE-User-OAuth-Token": "Bearer ya29.header-token"}
    )
    assert token1 == "ya29.header-token"

    token2 = ge_discovery_llm.extract_forwarded_ge_user_token(
        state={"user_access_token": "ya29.state-token"}
    )
    assert token2 == "ya29.state-token"


def test_publish_pinned_ge_agent_and_sync_starter_prompts() -> None:
    """Verifies Track 3: agents-cli publish & starterPrompts sync."""
    client = testclient.TestClient(main.app)
    headers = {
        "X-Goog-Authenticated-User-Email": "admin@mohanrajs.altostrat.com"
    }
    client.post("/api/v1/skills/seed-catalog", headers=headers)

    pub_resp = client.post(
        "/api/v1/admin/provisioning/ge-agents/publish",
        headers=headers,
        json={
            "engine_id": "service-desk-app-01",
            "display_name": "Enterprise Skill Orchestrator",
            "description": "Pinned ADK Skill & Sub-Skill Orchestrator.",
            "authorization_id": "ge-user-oauth-passthrough",
            "registration_mode": "adk",
            "default_pinned": True,
        },
    )
    assert pub_resp.status_code == 201
    pub_data = pub_resp.json()
    assert pub_data["default_pinned"] is True
    assert pub_data["status"] == "PINNED_ACTIVE"
    assert (
        "agents-cli publish gemini-enterprise" in pub_data["agents_cli_command"]
    )
    assert len(pub_data["starter_prompts"]) >= 1

    sync_resp = client.post(
        "/api/v1/admin/provisioning/ge-agents/"
        "service-desk-app-01/sync-starter-prompts",
        headers=headers,
    )
    assert sync_resp.status_code == 200

    list_resp = client.get(
        "/api/v1/admin/provisioning/ge-agents",
        headers=headers,
    )
    assert list_resp.status_code == 200
    assert list_resp.json()["total"] >= 1

