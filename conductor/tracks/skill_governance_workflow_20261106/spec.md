# Specification: Automated Skill Evaluation, InfoSec Governance & Publishing Workflow Microservice

## 1. Overview
When a user creates a Skill in a Gemini Enterprise (GE) Application and requests to share it, the skill enters `PENDING_REVIEW` (`agentSharingState: PENDING`, `hasActiveIamProposals: true`, `state: DISABLED`). As soon as the AppHub backend sync detects a skill in `PENDING_REVIEW`, it automatically triggers a standalone **Skill Governance & Approval Workflow Microservice** (`skill_workflow_service/` running on port `8081`).

## 2. Functional Requirements (5-Stage Pipeline)
1. **Stage 1 — Skill Evaluation Local ADK Agent (`SKILL_EVALUATION`):**
   - Invokes a modular local ADK Agent (`skill_evaluation_agent`) that inspects `SKILL.md` instructions, metadata, trigger phrases, expected input/output structure, and required tool references.
   - Computes a quality score (`0–100`), checklist findings, and `PASSED` / `FAILED` verdict.
   - Designed with a clean local ADK `Agent` definition so external ADK agents can be plugged in and expanded later.
2. **Stage 2 — InfoSec Local ADK Agent (`INFOSEC_SCAN`):**
   - Once Stage 1 passes, invokes the local ADK InfoSec Agent (`infosec_agent`) to scan `SKILL.md`, subfiles, GCS artifact URI (`gs://...`), tool permissions, and IAM share proposals for prompt injection vectors, data exfiltration risks, hardcoded secrets/PII, and least-privilege compliance.
   - Produces a risk level (`LOW`, `MEDIUM`, `HIGH`), security findings, and `PASSED` / `FAILED` verdict.
3. **Stage 3 — InfoSec Human Approval & Email Notification (`INFOSEC_APPROVAL`):**
   - Once Stage 2 passes, sends a structured approval request email to the InfoSec team (configurable SMTP + persisted in `workflow_email_notifications` outbox table viewable in the UI).
   - Pauses at `AWAITING_INFOSEC_APPROVAL` until an InfoSec reviewer / Admin approves or rejects the skill in the UI (`POST /api/v1/workflows/skills/{skill_id}/approve` or `/reject`).
4. **Stage 4 — Publish to Skill Registry (`PUBLISH_REGISTRY`):**
   - Upon InfoSec approval, publishes the vetted skill into the centralized **Enterprise Skill Registry** (`skill_registry` table & `GET /api/v1/registry/skills`) with versioned metadata, evaluation scores, InfoSec sign-off details, and `SKILL.md` snapshot.
5. **Stage 5 — Share Skill to Gemini Enterprise App (`SHARE_TO_APP`):**
   - Applies the approved sharing configuration back to the Gemini Enterprise App via Discovery Engine API (`:setIamPolicy` / enabling and sharing the skill with the requested principals in the GE app) and updates `GESkillRecord.review_status` to `APPROVED` (`sharing_state: SHARED`, `state: ENABLED`).

## 3. Acceptance Criteria
- Syncing a skill with `review_status == "PENDING_REVIEW"` automatically starts the 5-stage workflow.
- Stage 1 (Skill Evaluation ADK Agent) and Stage 2 (InfoSec ADK Agent) execute automatically and persist structured JSON reports.
- Stage 3 dispatches an InfoSec approval email notification and waits at `AWAITING_INFOSEC_APPROVAL`.
- Clicking **Approve & Publish** in the UI executes Stage 4 (Skill Registry publication) and Stage 5 (sharing the skill to the GE App) and transitions the skill to `APPROVED`.
- All backend and frontend unit tests pass with >80% coverage.
