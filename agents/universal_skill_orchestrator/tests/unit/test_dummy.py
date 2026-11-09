# Copyright 2026 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
"""
You can add your unit tests here.
This is where you test your business logic, including agent functionality,
data processing, and other core components of your application.
"""


"""Unit tests for the Skill-Agnostic Universal Skill Orchestrator tools."""

import json

try:
    from app.tools.skill_orchestration import (
        execute_skill_script,
        execute_subskill,
        load_skill_bundle,
    )
except ImportError:
    from agents.universal_skill_orchestrator.tools.skill_orchestration import (
        execute_skill_script,
        execute_subskill,
        load_skill_bundle,
    )


def test_skill_agnostic_bundle_and_script_execution() -> None:
    """Verifies dynamic skill bundle loading and bundled Python script execution."""
    bundle = load_skill_bundle(
        "skill-rubric-benchmark-evaluator",
        "cymbal-service-desk-app",
    )
    assert bundle["skill_id"] == "skill-rubric-benchmark-evaluator"
    assert "scripts/generate_eval_dataset.py" in bundle["bundled_scripts"]
    assert "scripts/execute_skill_benchmark.py" in bundle["bundled_scripts"]
    assert "scripts/report_rubric_scorecard.py" in bundle["bundled_scripts"]

    sub_res = execute_subskill(
        "sharepoint-policy-lookup",
        "Retrieve AI Skill Governance rubrics",
    )
    assert sub_res["status"] == "SUBSKILL_LOADED"

    stage1 = execute_skill_script(
        "skill-rubric-benchmark-evaluator",
        "scripts/generate_eval_dataset.py",
        json.dumps(
            {
                "target_skill_id": "service-desk-major-incident-bridge",
                "engine_id": "cymbal-service-desk-app",
                "num_cases": 5,
            }
        ),
    )
    assert stage1["status"] == "SCRIPT_EXECUTED"
    dataset = stage1["script_output"]
    assert len(dataset["eval_cases"]) == 5

    stage2 = execute_skill_script(
        "skill-rubric-benchmark-evaluator",
        "scripts/execute_skill_benchmark.py",
        json.dumps({"dataset": dataset, "iterations": 6}),
    )
    assert stage2["status"] == "SCRIPT_EXECUTED"
    benchmark = stage2["script_output"]
    assert "latency_profile" in benchmark

    stage3 = execute_skill_script(
        "skill-rubric-benchmark-evaluator",
        "scripts/report_rubric_scorecard.py",
        json.dumps({"dataset": dataset, "benchmark": benchmark}),
    )
    assert stage3["status"] == "SCRIPT_EXECUTED"
    scorecard = stage3["script_output"]
    assert scorecard["overall_weighted_score_100"] >= 90.0
    assert len(scorecard["sha256_evaluation_certificate_digest"]) == 64
