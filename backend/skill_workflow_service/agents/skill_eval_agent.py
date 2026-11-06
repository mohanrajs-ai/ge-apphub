"""Stage 1: Local ADK Skill Evaluation Agent for Gemini Enterprise Skills."""

from typing import Any


def inspect_skill_markdown_structure(instruction: str) -> dict[str, Any]:
    """ADK Tool: Inspects SKILL.md markdown structure and required sections.

    Args:
        instruction: Raw SKILL.md markdown instruction text.

    Returns:
        Dictionary of structural checks and section coverage.
    """
    text = (instruction or "").strip()
    lower = text.lower()
    has_title = text.startswith("#")
    has_when_to_use = "when to use" in lower or "trigger" in lower
    has_expected_io = (
        "expected input" in lower
        or "expected output" in lower
        or "format" in lower
    )
    has_workflow_steps = (
        "step" in lower or "workflow" in lower or "instruction" in lower
    )
    word_count = len(text.split())
    return {
        "has_title": has_title,
        "has_when_to_use": has_when_to_use,
        "has_expected_io": has_expected_io,
        "has_workflow_steps": has_workflow_steps,
        "word_count": word_count,
    }


def evaluate_tool_references(instruction: str) -> dict[str, Any]:
    """ADK Tool: Evaluates tool and connector references in SKILL.md.

    Args:
        instruction: Raw SKILL.md markdown instruction text.

    Returns:
        Dictionary describing referenced tools and grounding readiness.
    """
    text = (instruction or "").strip()
    lower = text.lower()
    has_tools_section = "required tools" in lower or "tools" in lower
    connector_refs = [
        line.strip()
        for line in text.splitlines()
        if "agents/" in line or "collections/" in line
    ]
    return {
        "has_tools_section": has_tools_section,
        "connector_reference_count": len(connector_refs),
    }


class SkillEvaluationAdkAgent:
    """Local Google ADK Agent for evaluating Gemini Enterprise Skills.

    Structured around the Google ADK Agent pattern (`name`, `model`,
    `instruction`, `tools`) so an external ADK Runner or Vertex AI Agent Engine
    deployment can be swapped in seamlessly.
    """

    def __init__(self, model: str = "gemini-2.5-flash") -> None:
        """Initializes the local ADK Skill Evaluation Agent."""
        self._model = model
        self.agent_definition: dict[str, Any] = {
            "name": "skill_evaluation_adk_agent",
            "model": self._model,
            "description": (
                "Evaluates Gemini Enterprise SKILL.md artifacts for "
                "structural completeness, trigger clarity, and workflow "
                "quality before enterprise sharing."
            ),
            "instruction": (
                "You are the Enterprise Skill Evaluation ADK Agent. Inspect "
                "the submitted SKILL.md instruction, description, and "
                "subfiles using your tools and output a quality score "
                "(0-100) and pass/fail determination."
            ),
            "tools": [
                inspect_skill_markdown_structure,
                evaluate_tool_references,
            ],
        }

    def evaluate_skill(
        self,
        display_name: str,
        description: str,
        instruction: str,
        subfiles: list[dict[str, str]] | None = None,
    ) -> dict[str, Any]:
        """Executes the local ADK Skill Evaluation rubric on a GE skill.

        Args:
            display_name: Skill display name.
            description: Skill summary description.
            instruction: Full SKILL.md markdown instruction.
            subfiles: Optional list of subfile metadata dicts.

        Returns:
            Evaluation report with `score`, `passed`, `checks`, and `summary`.
        """
        struct = inspect_skill_markdown_structure(instruction)
        tools_check = evaluate_tool_references(instruction)
        files = subfiles or []
        has_skill_md = any(
            str(f.get("file_name") or f.get("fileName") or "").upper()
            == "SKILL.MD"
            for f in files
        )

        score = 0
        checks: list[dict[str, Any]] = []

        desc_ok = len((description or "").strip()) >= 15
        score += 20 if desc_ok else 5
        checks.append(
            {
                "check": "Description Clarity",
                "passed": desc_ok,
                "detail": (
                    "Clear skill summary provided."
                    if desc_ok
                    else "Description is missing or too brief."
                ),
            }
        )

        title_ok = bool(struct["has_title"] and struct["word_count"] >= 20)
        score += 25 if title_ok else 0
        checks.append(
            {
                "check": "SKILL.md Markdown Heading & Depth",
                "passed": title_ok,
                "detail": f"Word count: {struct['word_count']} words.",
            }
        )

        triggers_ok = bool(struct["has_when_to_use"])
        score += 20 if triggers_ok else 5
        checks.append(
            {
                "check": "Trigger Phrases & When-to-Use Section",
                "passed": triggers_ok,
                "detail": (
                    "Includes explicit trigger scenarios."
                    if triggers_ok
                    else "Missing explicit trigger guidance."
                ),
            }
        )

        io_ok = bool(struct["has_expected_io"])
        score += 20 if io_ok else 5
        checks.append(
            {
                "check": "Expected Input / Output Specification",
                "passed": io_ok,
                "detail": (
                    "Defines structured expected inputs and outputs."
                    if io_ok
                    else "Input/Output expectations not explicitly sectioned."
                ),
            }
        )

        workflow_ok = bool(struct["has_workflow_steps"] or has_skill_md)
        score += 15 if workflow_ok else 0
        checks.append(
            {
                "check": "Step-by-Step Execution Workflow & Tooling",
                "passed": workflow_ok,
                "detail": (
                    f"Referenced {tools_check['connector_reference_count']} "
                    "enterprise connector tool(s)."
                ),
            }
        )

        passed = score >= 70
        return {
            "agent_name": self.agent_definition["name"],
            "model": self._model,
            "skill_name": display_name,
            "score": score,
            "passed": passed,
            "verdict": "PASSED" if passed else "FAILED",
            "checks": checks,
            "summary": (
                f"Skill '{display_name}' passed ADK evaluation with score "
                f"{score}/100."
                if passed
                else (
                    f"Skill '{display_name}' scored {score}/100 (minimum 70 "
                    "required)."
                )
            ),
        }
