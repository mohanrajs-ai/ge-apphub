---
name: m365-outlook-triage
description: Extracts key customer escalation threads, sender sentiment, and SLA timestamps from Microsoft 365 Exchange/Outlook mail stores.
---

# Sub-Skill: M365 Outlook Escalation Triage

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connector:** `outlook`

## Execution Steps
1. Search the user's accessible Outlook/Exchange mail data store (`{{DATA_STORE_IDS}}`) on engine `{{ENGINE_ID}}` for the specified customer or incident topic.
2. Extract a chronological timeline of emails, key stakeholders, promised SLA commitments, and unresolved blockers.
3. Return a structured JSON summary containing `timeline`, `stakeholders`, `current_severity`, and `open_questions`.
