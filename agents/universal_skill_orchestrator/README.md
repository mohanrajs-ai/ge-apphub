# Universal Enterprise Skill & Sub-Skill Orchestrator (`universal_skill_orchestrator`)

This directory contains the **single deployable ADK Agent** for Vertex AI Agent Runtime (`reasoningEngines`) and Gemini Enterprise (`assistants/default_assistant/agents`).

## Key Architectural Capabilities
1. **Deploy Once, Run Any Governed Skill (`build_dynamic_skill_instruction`):**
   - Uses ADK's dynamic `InstructionProvider` to load any published **Parent Skill (`SKILL.md`)** and its **Sub-Skills** from the `geapphub` Published Skill Registry (`/api/v1/skills/registry`) at runtime.
2. **Per-User OAuth Token Passthrough (`capture_calling_ge_user_token`):**
   - Extracts the calling Gemini Enterprise user's forwarded OAuth 2.0 token injected via `authorizationConfig.toolAuthorizations` (`ge-user-auth`) so downstream `:streamAssist` calls execute under the **calling user's GE seat quota and M365 ACLs**.
3. **Pinned Assistant in Gemini Enterprise:**
   - Registered under `engines/{engine_id}/assistants/default_assistant/agents` with `defaultPinned: true` and synced `starterPrompts` right alongside Google's built-in **Deep Research** agent.
