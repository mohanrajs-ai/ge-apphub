"""Single Skill-Agnostic Universal Enterprise Skill & Sub-Skill Orchestrator ADK Agent."""

import os

try:
    from app.tools.skill_orchestration import (
        current_ge_user_token,
        execute_skill_script,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
except ImportError:
    from agents.universal_skill_orchestrator.tools.skill_orchestration import (
        current_ge_user_token,
        execute_skill_script,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
from google.adk.agents import LlmAgent
from google.adk.agents.callback_context import CallbackContext
from google.adk.agents.readonly_context import ReadonlyContext
from google.adk.apps import App
from google.adk.models.llm_request import LlmRequest

DEFAULT_CATALOG_SUMMARY = (
    "Dynamically discovered from Skill Registry via load_skill_bundle"
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
    """Dynamically builds the skill-agnostic orchestrator instruction per session."""
    active_name = ctx.state.get("active_skill_name", "None loaded")
    active_md = ctx.state.get("active_skill_markdown", "")
    subskills = ctx.state.get(
        "available_subskills_summary",
        "Dynamically discovered from Skill Registry via load_skill_bundle",
    )
    return (
        "You are the Universal Enterprise Skill Orchestrator running inside "
        "Gemini Enterprise. You are 100% skill-agnostic and independent of "
        "any specific use case or hardcoded script.\n"
        "1. When a user asks to run any skill or workflow, first call "
        "`load_skill_bundle` with the skill ID/name to dynamically fetch its "
        "`SKILL.md` instruction, sub-skills list, and `bundled_scripts` "
        "manifest from the Skill Registry.\n"
        "2. Follow the loaded `SKILL.md` instructions step-by-step.\n"
        "3. When a step in `SKILL.md` delegates work to a sub-skill, call "
        "`execute_subskill` with the sub-skill ID and task input.\n"
        "4. When a step in `SKILL.md` requires running a bundled Python "
        "script (`scripts/*.py`), call `execute_skill_script` with the "
        "`skill_id`, `script_name`, and `script_args_json`. This tool "
        "dynamically downloads the script from the Skill Registry/GCS bucket "
        "and executes it in an isolated Python subprocess.\n"
        "5. Synthesize all sub-skill and script outputs into a clear "
        "enterprise response.\n\n"
        f"ACTIVE SKILL: {active_name}\n"
        f"ACTIVE SKILL INSTRUCTION:\n{active_md}\n\n"
        f"DISCOVERED REGISTRY SKILLS:\n{subskills}"
    )


DEFAULT_MODEL = os.getenv(
    "ADK_ORCHESTRATOR_MODEL",
    "projects/mohandemo/locations/us-central1/publishers/google/models/gemini-2.5-flash",
)

root_agent = LlmAgent(
    name="universal_skill_orchestrator",
    model=DEFAULT_MODEL,
    description=(
        "Skill-agnostic Universal Enterprise Skill Orchestrator that "
        "dynamically loads governed Parent Skills, chains reusable Sub-Skills, "
        "and executes bundled Python scripts (`scripts/*.py`) fetched at "
        "runtime from the AI Skill Hub Registry & GCS."
    ),
    instruction=build_dynamic_skill_instruction,
    before_model_callback=capture_calling_ge_user_token,
    tools=[
        load_skill_bundle,
        execute_subskill,
        execute_skill_script,
    ],
)

app = App(root_agent=root_agent, name="app")
