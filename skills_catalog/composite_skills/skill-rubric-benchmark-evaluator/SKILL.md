---
name: skill-rubric-benchmark-evaluator
description: Meta-Evaluation composite skill that evaluates any target skill in the Skill Registry across 6 weighted rubrics (Instruction Quality, Connector Correctness, Multi-Turn Trajectory, Latency SLA, Token Optimization, and InfoSec Zero-Trust) by executing its 3 bundled Python scripts (`scripts/generate_eval_dataset.py`, `scripts/execute_skill_benchmark.py`, `scripts/report_rubric_scorecard.py`) via `execute_skill_script`.
sub_skills: []
---

# Composite Skill: Enterprise Skill Rubric Benchmark & Optimization Evaluator (`skill-rubric-benchmark-evaluator`)

> **Runtime Requirement:** Runs in the skill-agnostic **Universal ADK Skill Orchestrator (`universal-skill-orchestrator`)** and executes its 3 bundled Python scripts (`scripts/generate_eval_dataset.py`, `scripts/execute_skill_benchmark.py`, `scripts/report_rubric_scorecard.py`) dynamically fetched from the Skill Registry via `execute_skill_script`.

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Bundled Python Scripts (`scripts/`):**
  - `scripts/generate_eval_dataset.py`
  - `scripts/execute_skill_benchmark.py`
  - `scripts/report_rubric_scorecard.py`

## Step-by-Step Workflow
1. **Step 1 — Load Target Skill Metadata (`load_skill_bundle`):**
   - Call `load_skill_bundle(skill_name_or_id=<target_skill_id>, engine_id=<engine_id>)` to retrieve the target skill's instruction, sub-skills, and required connectors.
2. **Step 2 — Execute Bundled Dataset Generator Script (`scripts/generate_eval_dataset.py`):**
   - Call `execute_skill_script(skill_id="skill-rubric-benchmark-evaluator", script_name="scripts/generate_eval_dataset.py", script_args_json='{"target_skill_id": "<target_skill_id>", "skill_metadata": {...}, "num_cases": 5}')` to synthesize the multi-case `EvaluationDataset` and `rubric_groups`.
3. **Step 3 — Execute Bundled Benchmark Profiler Script (`scripts/execute_skill_benchmark.py`):**
   - Call `execute_skill_script(skill_id="skill-rubric-benchmark-evaluator", script_name="scripts/execute_skill_benchmark.py", script_args_json='{"dataset": {...}, "skill_metadata": {...}, "engine_id": "<engine_id>"}')` to profile step `p50`/`p95`/`p99` latency, monolithic vs. sub-skill isolated token compression, and 1P Manta connector binding accuracy.
4. **Step 4 — Execute Bundled Rubric Scorecard Reporter Script (`scripts/report_rubric_scorecard.py`):**
   - Call `execute_skill_script(skill_id="skill-rubric-benchmark-evaluator", script_name="scripts/report_rubric_scorecard.py", script_args_json='{"dataset": {...}, "benchmark": {...}, "skill_metadata": {...}}')` to grade the target skill across all 6 weighted rubrics (`R1`–`R6`), generate the ASCII Rubric Bar Chart, and compute the SHA-256 Evaluation Certificate Digest.
5. **Step 5 — Present Executive Skill Benchmark Report:**
   - Present the Generated Dataset table, Latency & Token FinOps telemetry, the 6-Rubric Scorecard table, the ASCII Rubric Bar Chart, Optimization Recommendations, and the SHA-256 Evaluation Certificate.
