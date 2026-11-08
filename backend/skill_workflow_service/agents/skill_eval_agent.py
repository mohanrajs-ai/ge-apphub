"""Stage 1 & 2: ADK Skill Evaluation, Templatization & Multi-App Readiness."""

import re
from collections import Counter
from typing import Any

CONNECTOR_CATALOG: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    (
        "outlook-calendar",
        "Outlook Calendar",
        ("calendar", "m365-ol", "outlook"),
    ),
    (
        "outlook-email",
        "Outlook Email",
        ("mail", "m365-ol", "outlook"),
    ),
    (
        "teams",
        "Microsoft Teams",
        ("teams", "channel-message", "chat-message"),
    ),
    (
        "onedrive",
        "Microsoft OneDrive",
        ("onedrive", "m365-od"),
    ),
    (
        "sharepoint",
        "Microsoft SharePoint",
        ("sharepoint", "m365-sp"),
    ),
    (
        "enterprise-knowledge",
        "Enterprise Knowledge Store",
        ("enterprise-knowledge", "knowledge-ds"),
    ),
)


def templatize_skill_environment(instruction: str) -> str:
    """ADK Tool: Replaces app-specific engine & datastore IDs with variables.

    Normalizes `/engines/{dev_engine_id}/` into `/engines/{{engine_id}}/` and
    `{dev_engine_id}-enterprise-knowledge-ds-01` into
    `{{app_knowledge_datastore_id}}` so a single governed SKILL.md artifact can
    be published to the central Skill Registry and rendered per target GE App.

    Args:
        instruction: Raw SKILL.md markdown instruction text from the Dev App.

    Returns:
        Templatized SKILL.md markdown string.
    """
    raw = (instruction or "").strip()
    if not raw:
        return ""
    templatized = re.sub(
        r"/engines/[^/\s`'\"()]+/",
        "/engines/{{engine_id}}/",
        raw,
    )
    templatized = re.sub(
        r"[a-zA-Z0-9_-]+-enterprise-knowledge-ds-01",
        "{{app_knowledge_datastore_id}}",
        templatized,
    )
    return templatized


def render_skill_for_engine(
    templatized_instruction: str,
    target_engine_id: str,
) -> str:
    """Renders a templatized SKILL.md instruction for a specific target GE App.

    Args:
        templatized_instruction: SKILL.md containing `{{engine_id}}` variables.
        target_engine_id: Target Discovery Engine ID (e.g. `finance-app-01`).

    Returns:
        Engine-specific SKILL.md markdown string.
    """
    rendered = (templatized_instruction or "").replace(
        "{{engine_id}}", target_engine_id
    )
    rendered = rendered.replace(
        "{{app_knowledge_datastore_id}}",
        f"{target_engine_id}-enterprise-knowledge-ds-01",
    )
    return rendered


def extract_required_connectors(instruction: str) -> list[dict[str, str]]:
    """ADK Tool: Identifies 1P/3P enterprise connectors required by SKILL.md.

    Args:
        instruction: Raw or templatized SKILL.md markdown text.

    Returns:
        List of connector metadata dicts (`connector_id`, `display_name`).
    """
    text = (instruction or "").lower()
    found: list[dict[str, str]] = []
    seen: set[str] = set()

    explicit_agents = re.findall(r"/agents/([a-z0-9_-]+)", text)
    for agent_slug in explicit_agents:
        for cid, label, _patterns in CONNECTOR_CATALOG:
            if cid == agent_slug and cid not in seen:
                seen.add(cid)
                found.append(
                    {
                        "connector_id": cid,
                        "display_name": label,
                    }
                )

    keyword_checks: tuple[tuple[str, tuple[str, ...]], ...] = (
        ("outlook-calendar", ("outlook-calendar", "outlook calendar")),
        ("outlook-email", ("outlook-email", "outlook email", "unread email")),
        ("teams", ("/agents/teams", "microsoft teams", "teams mention")),
        ("onedrive", ("onedrive", "one drive")),
        ("sharepoint", ("sharepoint", "share point")),
        (
            "enterprise-knowledge",
            ("enterprise-knowledge-ds", "app_knowledge_datastore_id"),
        ),
    )
    label_map = {cid: label for cid, label, _ in CONNECTOR_CATALOG}
    for cid, keywords in keyword_checks:
        if cid in seen:
            continue
        if any(kw in text for kw in keywords):
            seen.add(cid)
            found.append(
                {
                    "connector_id": cid,
                    "display_name": label_map.get(cid, cid),
                }
            )
    return found


def _default_datastores_for_engine(engine_id: str) -> list[str]:
    """Returns fallback datastore IDs when an engine row predates sync."""
    clean = engine_id.strip().lower()
    if "new5" in clean:
        return [
            "onedrive_1791378339625_file",
            "outlook_1791378136223_mail",
            "outlook_1791378136223_calendar",
            "sharepoint_1791387159192_file",
        ]
    return [
        "m365-od-test_file",
        "m365-ol-test_calendar",
        "m365-ol-test_contact",
        "m365-ol-test_mail",
        "m365-ol-test_mail-attachment",
        "m365-sp_file",
        "m365-sp_page",
        "m365-teams-test_channel-message",
        "m365-teams-test_chat-message",
        f"{engine_id}-enterprise-knowledge-ds-01",
    ]


def evaluate_target_apps_readiness(
    display_name: str,
    description: str,
    instruction: str,
    target_apps: list[dict[str, Any]],
    base_eval: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Stage 2 ADK Tool: Evaluates skill readiness & tokens on each target app.

    Verifies that every target GE App has the required connectors/datastores
    attached, renders the templatized SKILL.md for that target engine, and
    computes per-app quality & token optimization metrics.

    Args:
        display_name: Skill display name.
        description: Skill description.
        instruction: Raw or templatized SKILL.md instruction.
        target_apps: List of target GE App dicts (`engine_id`, `display_name`,
            `location`, `data_store_ids`).
        base_eval: Optional precomputed Stage 1 evaluation dict.

    Returns:
        List of per-target-app evaluation result dictionaries.
    """
    templatized = templatize_skill_environment(instruction)
    required = extract_required_connectors(instruction)
    pattern_map = {
        cid: patterns for cid, _label, patterns in CONNECTOR_CATALOG
    }
    token_opt = (
        base_eval.get("token_optimization")
        if base_eval and isinstance(base_eval.get("token_optimization"), dict)
        else evaluate_token_optimization(display_name, description, instruction)
    )
    base_score = int(base_eval.get("score", 95)) if base_eval else 95

    results: list[dict[str, Any]] = []
    for app in target_apps:
        eng_id = str(app.get("engine_id") or "").strip()
        if not eng_id:
            continue
        app_name = str(app.get("display_name") or eng_id)
        location = str(app.get("location") or "global")
        raw_ds = app.get("data_store_ids")
        ds_ids = (
            [str(x).lower() for x in raw_ds if str(x).strip()]
            if isinstance(raw_ds, list) and raw_ds
            else [
                x.lower() for x in _default_datastores_for_engine(eng_id)
            ]
        )
        ds_joined = " ".join(ds_ids)

        matched: list[str] = []
        missing: list[str] = []
        for req in required:
            cid = req["connector_id"]
            patterns = pattern_map.get(cid, (cid,))
            if any(pat in ds_joined for pat in patterns):
                matched.append(cid)
            else:
                missing.append(cid)

        is_ready = len(missing) == 0
        penalty = len(missing) * 20
        app_score = max(40, base_score - penalty)
        rendered_md = render_skill_for_engine(templatized, eng_id)
        rendered_tokens = _estimate_tokens(rendered_md) + int(
            token_opt.get("discovery_tokens", 55)
        )

        results.append(
            {
                "engine_id": eng_id,
                "app_display_name": app_name,
                "location": location,
                "connector_readiness": (
                    "READY" if is_ready else "MISSING_CONNECTORS"
                ),
                "matched_connectors": matched,
                "missing_connectors": missing,
                "data_store_count": len(ds_ids),
                "eval_score": app_score,
                "eval_status": (
                    "PASSED" if is_ready and app_score >= 70 else "WARNING"
                ),
                "rendered_tokens": rendered_tokens,
                "optimized_tokens": int(
                    token_opt.get("optimized_total_tokens", rendered_tokens)
                ),
                "tokens_saved": int(token_opt.get("tokens_saved", 0)),
                "reduction_pct": float(token_opt.get("reduction_pct", 0.0)),
                "efficiency_grade": str(
                    token_opt.get("efficiency_grade", "A")
                ),
            }
        )
    return results


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


def extract_sub_skills(instruction: str) -> list[str]:
    """ADK Tool: Extracts sub_skills declared in YAML frontmatter or steps.

    Args:
        instruction: Raw or templatized SKILL.md markdown text.

    Returns:
        Ordered list of referenced sub-skill identifiers.
    """
    text = (instruction or "").strip()
    if not text:
        return []
    found: list[str] = []
    seen: set[str] = set()

    frontmatter_match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if frontmatter_match:
        fm = frontmatter_match.group(1)
        inline_match = re.search(r"sub_skills:\s*\[([^\]]+)\]", fm)
        if inline_match:
            for item in inline_match.group(1).split(","):
                slug = item.strip().strip("'\"").lower()
                if slug and slug not in seen:
                    seen.add(slug)
                    found.append(slug)
        else:
            block_match = re.search(
                r"sub_skills:\s*\n((?:\s*-\s*[a-zA-Z0-9_-]+\s*\n?)+)", fm
            )
            if block_match:
                for line in block_match.group(1).splitlines():
                    slug = (
                        re.sub(r"^\s*-\s*", "", line)
                        .strip()
                        .strip("'\"")
                        .lower()
                    )
                    if slug and slug not in seen:
                        seen.add(slug)
                        found.append(slug)

    for step_ref in re.findall(
        r"sub-skill\s+`([a-zA-Z0-9_-]+)`", text, re.IGNORECASE
    ):
        slug = step_ref.strip().lower()
        if slug and slug not in seen:
            seen.add(slug)
            found.append(slug)
    return found


def inspect_skill_markdown_structure(instruction: str) -> dict[str, Any]:
    """ADK Tool: Inspects SKILL.md markdown structure and required sections.

    Args:
        instruction: Raw SKILL.md markdown instruction text.

    Returns:
        Dictionary of structural checks and section coverage.
    """
    text = (instruction or "").strip()
    lower = text.lower()
    has_title = text.startswith("#") or "\n# " in text
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
                templatize_skill_environment,
                extract_required_connectors,
                extract_sub_skills,
                inspect_skill_markdown_structure,
                evaluate_tool_references,
                evaluate_token_optimization,
                evaluate_target_apps_readiness,
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
        templatized = templatize_skill_environment(instruction)
        required_connectors = extract_required_connectors(instruction)
        sub_skills = extract_sub_skills(instruction)
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
            "templatized_instruction": templatized,
            "required_connectors": required_connectors,
            "sub_skills": sub_skills,
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
