"""Single Universal Enterprise Skill & Sub-Skill Orchestrator ADK Agent."""

import os

try:
    from app.tools.skill_orchestration import (
        BUILTIN_M365_SKILL_REGISTRY,
        current_ge_user_token,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
except ImportError:
    from agents.universal_skill_orchestrator.tools.skill_orchestration import (
        BUILTIN_M365_SKILL_REGISTRY,
        current_ge_user_token,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.agents.readonly_context import ReadonlyContext
from google.adk.apps import App
from google.adk.models.llm_request import LlmRequest

DEFAULT_CATALOG_SUMMARY = ", ".join(
    f"{item['skill_name']} ({item['skill_id']})"
    for item in BUILTIN_M365_SKILL_REGISTRY
)


def capture_calling_ge_user_token(
    callback_context: CallbackContext,
    llm_request: LlmRequest,
) -> None:
    """Captures the calling GE user's forwarded OAuth token before LLM turns."""
    _ = llm_request
    state_dict = callback_context.state.to_dict()
    token = extract_forwarded_ge_user_token(state_dict)
    if token:
        current_ge_user_token.set(token)


def build_dynamic_skill_instruction(ctx: ReadonlyContext) -> str:
    """Dynamically builds the orchestrator system instruction per session."""
    active_name = ctx.state.get("active_skill_name", "None loaded")
    active_md = ctx.state.get("active_skill_markdown", "")
    subskills = ctx.state.get(
        "available_subskills_summary",
        DEFAULT_CATALOG_SUMMARY,
    )
    return (
        "You are the Universal Enterprise Skill Orchestrator running inside "
        "Gemini Enterprise.\n"
        "1. When a user asks to run a skill or workflow, call "
        "`load_skill_bundle` to load the governed Parent Skill.\n"
        "2. Follow the Parent Skill instructions step-by-step.\n"
        "3. When a step delegates work to a specialized sub-skill, call "
        "`execute_subskill` with the sub-skill name and input.\n"
        "4. Synthesize all sub-skill outputs into a clear enterprise "
        "response.\n\n"
        f"ACTIVE SKILL: {active_name}\n"
        f"ACTIVE SKILL INSTRUCTION:\n{active_md}\n\n"
        f"AVAILABLE M365 SKILLS & SUB-SKILLS:\n{subskills}"
    )


DEFAULT_MODEL = os.getenv(
    "ADK_ORCHESTRATOR_MODEL",
    "projects/mohandemo/locations/us-central1/publishers/google/models/gemini-2.5-flash",
)

root_agent = LlmAgent(
    name="universal_skill_orchestrator",
    model=DEFAULT_MODEL,
    description=(
        "Universal Enterprise Skill Orchestrator that dynamically loads "
        "governed Parent Skills and chains reusable Sub-Skills from the "
        "AI Skill Hub using the calling Gemini Enterprise user's identity."
    ),
    instruction=build_dynamic_skill_instruction,
    before_model_callback=capture_calling_ge_user_token,
    tools=[load_skill_bundle, execute_subskill],
)

app = App(root_agent=root_agent, name="app")
