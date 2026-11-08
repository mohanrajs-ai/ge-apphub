---
name: m365-teams-incident-swarm
description: Atomic sub-skill that queries Microsoft Teams channels, 1:1 chats, and @mentions via the M365 Teams connector to surface active incident discussions, blockers, and action items.
---

# Sub-Skill: M365 Teams Incident Swarm & Mention Aggregator

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `teams` (`cymbal-m365-teams_channel-message`, `cymbal-m365-teams_chat-message`)

## Execution Instructions
1. Search Microsoft Teams channel messages and direct chat messages using the M365 Teams connector (`1p-skill-manta-data-connector-skill-type-teams`).
2. Filter for:
   - Recent `@mentions` targeting the calling user or on-call group.
   - Messages containing incident keywords (`SEV1`, `SEV2`, `outage`, `escalation`, `blocker`, `urgent`).
3. Return a structured JSON/Markdown summary with **Channel/Sender**, **Timestamp**, **Summary of Blocker**, and **Recommended Follow-Up**.
