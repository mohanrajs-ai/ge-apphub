"""Stage 1: Local ADK Skill Evaluation Agent for Gemini Enterprise Skills."""

import re
from collections import Counter
from typing import Any


def _estimate_tokens(text: str) -> int:
    """Estimates Gemini BPE token count for Markdown/resource-URI content."""
    cleaned = (text or "").strip()
    if not cleaned:
        return 0
    pieces = re.findall(r"[A-Za-z0-9_]+|[^\sA-Za-z0-9_]", cleaned)
    return max(1, round((len(pieces) * 0.9) + (len(cleaned) / 9.0)))


def evaluate_token_optimization(
    display_name: str,
    description: str,
    instruction: str,
) -> dict[str, Any]:
    """ADK Tool: Calculates token footprint and context optimization savings.

    Analyzes discovery tokens (loaded into every assistant session) and full
    instruction tokens (loaded on skill invocation), and computes savings from
    engine_id parameterization, deduplicating full GCP resource URIs, and
    compacting Markdown structure.

    Args:
        display_name: Skill display name.
        description: Skill summary description.
        instruction: Raw SKILL.md markdown instruction text.

    Returns:
        Dictionary of token metrics, savings, grade, and recommendations.
    """
    discovery_text = f"{display_name}: {(description or '').strip()}"
    discovery_tokens = _estimate_tokens(discovery_text)
    raw_instr = (instruction or "").strip()
    instruction_tokens = _estimate_tokens(raw_instr)
    total_tokens = discovery_tokens + instruction_tokens

    full_uris = re.findall(
        r"projects/[^\s`'\")]+/agents/[a-zA-Z0-9_-]+", raw_instr
    )
    uri_counts = Counter(full_uris)
    duplicate_uri_count = sum(
        count - 1 for count in uri_counts.values() if count > 1
    )

    compacted = re.sub(
        r"/engines/[^/\s`]+/", "/engines/{{engine_id}}/", raw_instr
    )
    seen_uris: set[str] = set()

    def _dedup_uri(match: re.Match[str]) -> str:
        uri = match.group(0)
        if uri not in seen_uris:
            seen_uris.add(uri)
            return uri
        short_id = uri.rsplit("/agents/", 1)[-1]
        return short_id

    compacted = re.sub(
        r"projects/[^\s`'\")]+/agents/[a-zA-Z0-9_-]+", _dedup_uri, compacted
    )
    compacted = re.sub(r"\n---\n", "\n", compacted)
    compacted = re.sub(r"\n{3,}", "\n\n", compacted).strip()

    optimized_instruction_tokens = _estimate_tokens(compacted)
    optimized_total_tokens = discovery_tokens + optimized_instruction_tokens
    tokens_saved = max(0, total_tokens - optimized_total_tokens)
    reduction_pct = (
        round((tokens_saved / total_tokens) * 100.0, 1)
        if total_tokens > 0
        else 0.0
    )

    recommendations: list[str] = []
    if discovery_tokens <= 60:
        recommendations.append(
            f"Discovery router footprint is concise ({discovery_tokens} "
            "tokens, within <=60 token budget)."
        )
    else:
        recommendations.append(
            f"Trim skill description from {discovery_tokens} to <=60 tokens "
            "to reduce per-turn router overhead."
        )
    if duplicate_uri_count > 0:
        recommendations.append(
            f"Deduplicate {duplicate_uri_count} repeated full GCP connector "
            "URI(s) in workflow steps by referencing short tool aliases."
        )
    if tokens_saved > 0:
        recommendations.append(
            f"Compacting Markdown & parameterizing {{{{engine_id}}}} saves "
            f"~{tokens_saved} tokens ({reduction_pct}% reduction per call)."
        )

    if discovery_tokens <= 60 and reduction_pct <= 25.0:
        efficiency_grade = "A"
    elif discovery_tokens <= 90:
        efficiency_grade = "B"
    else:
        efficiency_grade = "C"

    return {
        "discovery_tokens": discovery_tokens,
        "instruction_tokens": instruction_tokens,
        "total_tokens": total_tokens,
        "optimized_instruction_tokens": optimized_instruction_tokens,
        "optimized_total_tokens": optimized_total_tokens,
        "tokens_saved": tokens_saved,
        "reduction_pct": reduction_pct,
        "duplicate_uri_count": duplicate_uri_count,
        "efficiency_grade": efficiency_grade,
        "recommendations": recommendations,
    }


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
                evaluate_token_optimization,
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
        token_opt = evaluate_token_optimization(
            display_name=display_name,
            description=description,
            instruction=instruction,
        )
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

        token_ok = bool(token_opt["discovery_tokens"] <= 90)
        checks.append(
            {
                "check": "Token Context & Prompt Optimization",
                "passed": token_ok,
                "detail": (
                    f"Total: {token_opt['total_tokens']} tokens -> "
                    f"Optimized: {token_opt['optimized_total_tokens']} tokens "
                    f"(saves {token_opt['tokens_saved']} tokens / "
                    f"{token_opt['reduction_pct']}%, Grade "
                    f"{token_opt['efficiency_grade']})."
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
            "token_optimization": token_opt,
            "summary": (
                f"Skill '{display_name}' passed ADK evaluation with score "
                f"{score}/100 ({token_opt['total_tokens']} -> "
                f"{token_opt['optimized_total_tokens']} tokens, "
                f"-{token_opt['reduction_pct']}%)."
                if passed
                else (
                    f"Skill '{display_name}' scored {score}/100 (minimum 70 "
                    "required)."
                )
            ),
        }
