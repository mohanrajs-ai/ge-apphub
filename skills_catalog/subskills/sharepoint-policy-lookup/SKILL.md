---
name: sharepoint-policy-lookup
description: Retrieves standard operating procedures (SOPs), SLA contractual clauses, and remediation runbooks from Microsoft SharePoint and OneDrive data stores.
---

# Sub-Skill: SharePoint Policy & Runbook Lookup

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connector:** `sharepoint`

## Execution Steps
1. Query the SharePoint document library (`{{DATA_STORE_IDS}}`) on engine `{{ENGINE_ID}}` for the relevant SLA tier, policy document, or remediation runbook matching the escalation topic.
2. Cite exact policy sections, SLA response time requirements, and required approval escalation paths.
3. Return a concise markdown brief with grounded document citations.
