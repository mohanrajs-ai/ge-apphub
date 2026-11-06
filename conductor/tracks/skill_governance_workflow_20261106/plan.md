# Implementation Plan: Automated Skill Evaluation, InfoSec Governance & Publishing Workflow Microservice

## Phase 1: Database Schema & Standalone Workflow Microservice Foundation
- [ ] Task: Define ORM & Pydantic Models for Workflows, Skill Registry, and Email Outbox
  - [ ] Write failing tests in `backend/tests/test_skill_workflow.py` verifying `SkillWorkflowRecord`, `SkillRegistryRecord`, and `WorkflowEmailRecord` persistence.
  - [ ] Implement SQLAlchemy models in `backend/app/db_models.py` and Pydantic schemas in `backend/app/models.py`.
- [ ] Task: Create Standalone Skill Workflow Microservice Package (`skill_workflow_service/`)
  - [ ] Write failing health and workflow router tests for the standalone FastAPI microservice (`skill_workflow_service/main.py` on port `8081`).
  - [ ] Implement `skill_workflow_service/` FastAPI app and mount/proxy workflow & registry routes in AppHub (`backend/app/main.py`).
- [ ] Task: Phase 1 Verification & Checkpoint (Refer to `workflow.md`)

## Phase 2: Local ADK Agents (Stage 1 Skill Evaluation Agent & Stage 2 InfoSec Agent)
- [ ] Task: Implement Local ADK Skill Evaluation Agent (`skill_workflow_service/agents/skill_eval_agent.py`)
  - [ ] Write failing unit tests for `SkillEvaluationAdkAgent` evaluating valid and incomplete `SKILL.md` definitions.
  - [ ] Implement the modular local ADK agent (`skill_eval_agent.py`) with structured rubric evaluation and extensible ADK `Agent` definition.
- [ ] Task: Implement Local ADK InfoSec Agent (`skill_workflow_service/agents/infosec_agent.py`)
  - [ ] Write failing unit tests for `InfoSecAdkAgent` scanning for prompt injection, credential exposure, unauthorized external calls, and IAM scope safety.
  - [ ] Implement `infosec_agent.py` returning structured `risk_level`, compliance checks, and `PASSED`/`FAILED` verdict.
- [ ] Task: Phase 2 Verification & Checkpoint (Refer to `workflow.md`)

## Phase 3: Workflow Engine (Stage 3 Email/Approval Gate, Stage 4 Registry Publish, Stage 5 GE App Sharing) & Auto-Trigger on Sync
- [ ] Task: Implement Stage 3 InfoSec Email Notification & Approval Gate
  - [ ] Write failing tests for SMTP + Local Outbox email dispatch (`workflow_email_notifications`) when Stage 2 passes, transitioning workflow to `AWAITING_INFOSEC_APPROVAL`.
  - [ ] Implement `NotificationService` and `/approve` & `/reject` workflow endpoints.
- [ ] Task: Implement Stage 4 (Skill Registry Publisher) & Stage 5 (Discovery Engine Skill Sharing) and Auto-Start on Sync
  - [ ] Write failing tests verifying that approving a workflow in Stage 3 publishes the skill to `skill_registry` (Stage 4) and calls Discovery Engine IAM/sharing API to share the skill with the GE App (Stage 5).
  - [ ] Implement Stage 4 & Stage 5 execution and wire `CatalogSyncService._sync_skills` to automatically start the workflow whenever a `PENDING_REVIEW` skill is synced.
- [ ] Task: Phase 3 Verification & Checkpoint (Refer to `workflow.md`)

## Phase 4: Frontend Workflow Tracker, InfoSec Review Console & Skill Registry Tab
- [ ] Task: Update `SkillsSection.tsx` with Live 5-Stage Workflow Stepper, Agent Reports, Email Preview & InfoSec Approve/Reject Controls
  - [ ] Write failing Vitest component tests in `frontend/src/__tests__/SkillsSection.test.tsx` for the 5-stage visual pipeline stepper, ADK agent evaluation & InfoSec scan report cards, InfoSec approval button, and Skill Registry tab.
  - [ ] Update `frontend/src/api/client.ts`, `frontend/src/types/catalog.ts`, and `frontend/src/components/SkillsSection.tsx` to display the 5-stage progress bar, inspect Stage 1/2 agent findings and Stage 3 email notification, allow InfoSec/Admin approval right from the UI, and view published skills in the **Skill Registry** tab.
- [ ] Task: Phase 4 Verification & Checkpoint (Refer to `workflow.md`)
