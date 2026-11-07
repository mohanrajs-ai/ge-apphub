# Implementation Plan: Multi-App AI Skill Hub (`multi_app_skill_hub_20261107`)

## Phase 1: Engine Connector Discovery & Database Schema Enrichment
- [x] **Task 1.1:** Update `backend/app/services/discovery.py` and `backend/app/db_models.py` (`GEApplicationRecord`) to persist each GE App's active `data_store_ids` (e.g., `m365-ol-test_calendar`, `m365-ol-test_mail`, `m365-teams-test_chat-message`, `{app}-enterprise-knowledge-ds-01`) during Discovery Engine sync.
- [x] **Task 1.2:** Extend `SkillWorkflowRecord` (`backend/app/db_models.py`) and `SkillWorkflowItem` (`backend/app/models.py`) with Multi-App Hub fields:
  - `source_engine_id` (Dev App ID)
  - `templatized_instruction` (Parameterized `SKILL.md` with `{{engine_id}}`, `{{app_knowledge_datastore_id}}`)
  - `required_connectors` (List of required 1P connector types & IDs extracted from `SKILL.md`)
  - `requested_groups` (List of group principals requested in Share dialog)
  - `distribution_scope` (`SINGLE_APP` | `MULTI_APP` | `GLOBAL`)
  - `target_engines` (List of resolved target GE App `engine_id`s)
  - `target_app_evaluations` (Per-app evaluation & connector compatibility matrix)
  - `distributed_apps` (Per-app distribution status and created resource names)

## Phase 2: Templatizer, Connector Analyzer & Multi-App Evaluation Agent
- [x] **Task 2.1:** Implement `templatize_skill_environment(instruction, source_engine_id)` and `extract_required_connectors(instruction)` in `backend/skill_workflow_service/agents/skill_eval_agent.py` to:
  - Parameterize `/engines/{source_engine_id}/` -> `/engines/{{engine_id}}/` and `{app}-enterprise-knowledge-ds-01` -> `{{app_knowledge_datastore_id}}`.
  - Detect required 1P Manta connectors (`outlook-calendar`, `outlook-email`, `teams`, `onedrive`, `sharepoint`) and map them to required engine `dataStoreIds` patterns (`_calendar`, `_mail`, `teams`, `od`, `sp`).
- [x] **Task 2.2:** Implement `evaluate_skill_across_target_apps(...)` in `SkillEvaluationAdkAgent` to evaluate the skill against every resolved target GE App:
  - Render `SKILL.md` for each target `engine_id`.
  - Check whether all `required_connectors` exist in that target engine's `data_store_ids`.
  - Compute per-app readiness (`READY` vs `MISSING_CONNECTORS`), rubric score (`0-100`), and token optimization metrics.

## Phase 3: 6-Stage Multi-App Workflow Engine & API Endpoints
- [x] **Task 3.1:** Update `SkillWorkflowEngine.start_or_run_workflow` (`backend/skill_workflow_service/engine.py`) so that when a skill on the Dev App enters `PENDING_REVIEW`, it automatically runs:
  1. Environment Templatization & Connector Extraction
  2. Group-to-Target-App Resolution (`resolve_target_engines_from_groups`)
  3. Multi-App Evaluation & Token Optimization across all resolved target apps
  4. InfoSec Security Scan (`InfoSecAdkAgent`)
  5. InfoSec Approval Email notification with full Target App & Connector Matrix
- [x] **Task 3.2:** Update `SkillWorkflowEngine.approve_workflow` and `POST /api/v1/skill-workflows/{skill_id}/approve` to accept an optional `target_engines: list[str] | None` override from the InfoSec/Admin approver, publish the templatized `SKILL.md` to the **GCP Agent Platform Skill Registry**, and distribute the rendered `SKILL.md` to each approved target GE App.

## Phase 4: Multi-App AI Skill Hub Frontend UI & Verification
- [x] **Task 4.1:** Update `frontend/src/types/catalog.ts`, `frontend/src/api/client.ts`, and `frontend/src/components/SkillsSection.tsx` to display the **Multi-App AI Skill Hub**:
  - **6-Stage Pipeline Stepper:** `1. Templatize & Connectors` -> `2. Multi-App Evals & Tokens` -> `3. InfoSec Scan` -> `4. InfoSec Approval` -> `5. Skill Registry` -> `6. Multi-App Distribution`.
  - **Required Connectors & Requested Groups Badges** on each skill card.
  - **Per-Target-App Evaluation & Connector Readiness Matrix** (showing which target apps have all required M365 connectors vs. missing connectors, plus interactive target app checkboxes for admin approval).
  - **Templatized `SKILL.md` vs. Rendered Per-App Preview** toggle in the skill inspection modal.
- [x] **Task 4.2:** Run backend unit/integration tests (`pytest`, `ruff check`), frontend build (`npm run build`), and verify on live `mohandemo` data.
