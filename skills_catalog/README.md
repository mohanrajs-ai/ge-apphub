# Version-Controlled AI Skills & Sub-Skills Catalog (`skills_catalog/`)

This directory contains Git-managed **Atomic Sub-Skills** and **Composite Parent Skills** that can be submitted to the **6-Stage Skill Governance Factory** (`backend/skill_workflow_service/`) and orchestrated at runtime by the single **Universal Skill Orchestrator ADK Agent** (`agents/universal_skill_orchestrator/`).

## Structure
- **`subskills/`**: Single-purpose, reusable atomic skills bound to a specific enterprise connector (`outlook`, `sharepoint`, `teams`, `jira`, etc.) using environment placeholders (`{{ENGINE_ID}}`, `{{DATA_STORE_IDS}}`).
- **`composite_skills/`**: Multi-step orchestration skills (`SKILL.md` + `manifest.json`) that chain multiple `subskills` via `execute_subskill`.
