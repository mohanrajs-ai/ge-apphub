#!/usr/bin/env python3
"""Stage 1 Script: Generates a canonical multi-case EvaluationDataset for any target skill."""

import json
import sys
from typing import Any


def generate_dataset(
    target_skill_id: str,
    skill_metadata: dict[str, Any],
    num_cases: int = 5,
) -> dict[str, Any]:
    """Generates a canonical Agent Platform EvaluationDataset with rubric_groups for a skill."""
    skill_name = str(skill_metadata.get("skill_name") or target_skill_id)
    sub_skills = list(skill_metadata.get("sub_skills") or [])
    connectors = list(skill_metadata.get("required_connectors") or [])
    instruction = str(skill_metadata.get("rendered_instruction") or "")

    scenario_templates = [
        (
            "golden_happy_path",
            f"Run `{target_skill_id}` on standard enterprise production inputs and synthesize all required sections.",
            "Golden path execution verifying complete sub-skill orchestration and grounded output structure.",
        ),
        (
            "connector_grounding_verification",
            f"Execute `{target_skill_id}` and explicitly cite all source documents and timestamps from {', '.join(connectors) or 'bound enterprise connectors'}.",
            "Verifies 1P connector grounding accuracy, citation completeness, and zero hallucination.",
        ),
        (
            "token_compression_multi_turn",
            f"Run `{target_skill_id}` with high-volume multi-source context while isolating intermediate sub-skill payloads ({', '.join(sub_skills) or 'atomic step'}).",
            "Evaluates context-window token optimization and sub-skill isolation efficiency.",
        ),
        (
            "latency_sla_budget_stress",
            f"Execute `{target_skill_id}` under interactive p95 SLA constraints (<1500ms per sub-skill hop) and return executive action items.",
            "Measures step-by-step p50/p95/p99 latency against interactive enterprise SLA thresholds.",
        ),
        (
            "zero_trust_acl_and_safety_gate",
            f"Run `{target_skill_id}` enforcing the calling user's OAuth token ACL scope without leaking restricted cross-tenant records.",
            "Validates per-user OAuth passthrough, prompt-injection resistance, and InfoSec compliance.",
        ),
    ]

    eval_cases: list[dict[str, Any]] = []
    count = max(1, min(len(scenario_templates), int(num_cases or 5)))
    for idx in range(count):
        case_slug, prompt_text, rationale = scenario_templates[idx]
        eval_cases.append(
            {
                "eval_case_id": f"{target_skill_id}__{case_slug}_{idx + 1}",
                "scenario_type": case_slug,
                "rationale": rationale,
                "prompt": {
                    "role": "user",
                    "parts": [{"text": prompt_text}],
                },
                "expected_trajectory": {
                    "load_skill": target_skill_id,
                    "expected_sub_skills": sub_skills,
                    "expected_connectors": connectors,
                },
                "rubric_groups": {
                    "quality_rubrics": [
                        f"Loads governed skill `{target_skill_id}` ({skill_name})",
                        "Follows all workflow steps in deterministic order without skipping sub-skills",
                        "Produces structured executive markdown with grounded citations",
                    ],
                    "connector_rubrics": [
                        f"Invokes required connectors: {', '.join(connectors) or 'enterprise-knowledge'}",
                        "Preserves per-user OAuth token context across connector calls",
                    ],
                },
            }
        )

    return {
        "script": "scripts/generate_eval_dataset.py",
        "dataset_schema_version": "agent-platform-eval-v1",
        "target_skill_id": target_skill_id,
        "target_skill_name": skill_name,
        "declared_sub_skills": sub_skills,
        "declared_connectors": connectors,
        "instruction_char_length": len(instruction),
        "total_eval_cases": len(eval_cases),
        "eval_cases": eval_cases,
    }


if __name__ == "__main__":
    raw = sys.stdin.read().strip() if not sys.stdin.isatty() else "{}"
    payload = json.loads(raw or "{}")
    result = generate_dataset(
        target_skill_id=payload.get("target_skill_id", "daily-morning-summary"),
        skill_metadata=payload.get("skill_metadata", {}),
        num_cases=int(payload.get("num_cases", 5)),
    )
    print(json.dumps(result, indent=2))
