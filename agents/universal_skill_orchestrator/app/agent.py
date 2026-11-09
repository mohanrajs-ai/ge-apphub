"""Single Universal Enterprise Skill & Sub-Skill Orchestrator ADK Agent."""

import os

try:
    from app.tools.skill_orchestration import (
        current_ge_user_token,
        execute_python_equity_quant_forecast,
        execute_python_sla_finops_analysis,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
except ImportError:
    from agents.universal_skill_orchestrator.tools.skill_orchestration import (
        current_ge_user_token,
        execute_python_equity_quant_forecast,
        execute_python_sla_finops_analysis,
        execute_subskill,
        extract_forwarded_ge_user_token,
        load_skill_bundle,
    )
from typing import Any

try:
    from google.adk.agents import LlmAgent
    from google.adk.agents.callback_context import CallbackContext
    from google.adk.agents.readonly_context import ReadonlyContext
    from google.adk.apps import App
    from google.adk.models.llm_request import LlmRequest
except ImportError:
    CallbackContext = Any  # type: ignore[misc,assignment]
    ReadonlyContext = Any  # type: ignore[misc,assignment]
    LlmRequest = Any  # type: ignore[misc,assignment]

    class LlmAgent:  # type: ignore[no-redef]
        def __init__(self, **kwargs: Any) -> None:
            self.__dict__.update(kwargs)

    class App:  # type: ignore[no-redef]
        def __init__(self, **kwargs: Any) -> None:
            self.__dict__.update(kwargs)

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
    """Dynamically builds the orchestrator instruction per session."""
    active_name = ctx.state.get("active_skill_name", "None loaded")
    active_md = ctx.state.get("active_skill_markdown", "")
    subskills = ctx.state.get(
        "available_subskills_summary",
        "Dynamically discovered from Skill Registry via load_skill_bundle",
    )
    return (
        "You are the Universal Enterprise Skill Orchestrator running inside "
        "Gemini Enterprise.\n"
        "1. When a user asks to run any composite or quantitative skill, first "
        "call `load_skill_bundle` with the skill ID/name to fetch its pure "
        "`SKILL.md` instruction and `sub_skills` list from the Skill Registry.\n"
        "2. Follow the loaded `SKILL.md` instructions step-by-step.\n"
        "3. When a step delegates work to a sub-skill, call `execute_subskill` "
        "with the sub-skill ID and task input.\n"
        "4. When a step invokes a governed quantitative MCP/ADK tool "
        "(`execute_python_sla_finops_analysis` or "
        "`execute_python_equity_quant_forecast`), call that tool directly.\n"
        "5. Synthesize all sub-skill and tool outputs into a clear "
        "executive response.\n\n"
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
        "Universal Enterprise Skill Orchestrator that dynamically loads "
        "governed Parent Skills (`SKILL.md`), chains reusable M365 Sub-Skills, "
        "and invokes governed quantitative MCP/ADK tools."
    ),
    instruction=build_dynamic_skill_instruction,
    before_model_callback=capture_calling_ge_user_token,
    tools=[
        load_skill_bundle,
        execute_subskill,
        execute_python_sla_finops_analysis,
        execute_python_equity_quant_forecast,
    ],
)

app = App(root_agent=root_agent, name="app")
