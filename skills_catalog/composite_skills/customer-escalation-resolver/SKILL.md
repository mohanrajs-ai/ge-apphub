---
name: customer-escalation-resolver
description: Multi-step composite enterprise skill that orchestrates Outlook thread triage and SharePoint SLA policy lookup to produce an executive customer escalation response plan.
---

# Composite Skill: Customer Escalation Resolver

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}`
- **Required Connectors:** `outlook`, `sharepoint`
- **Delegated Sub-Skills:** `m365-outlook-triage`, `sharepoint-policy-lookup`

## Orchestration Workflow
1. **Step 1 — Triage Communications (`m365-outlook-triage`):**
   - Invoke `execute_subskill("m365-outlook-triage", task_input)` to retrieve the customer email timeline, stakeholders, and open blockers from Outlook (`{{DATA_STORE_IDS}}`).
2. **Step 2 — Verify Contractual SLA & Runbook (`sharepoint-policy-lookup`):**
   - Pass the customer tier and issue type to `execute_subskill("sharepoint-policy-lookup", ...)` to fetch the governing SharePoint SLA clauses and technical runbook.
3. **Step 3 — Synthesize Executive Resolution Plan:**
   - Combine the Outlook timeline and SharePoint SLA citations into an executive brief containing:
     - **Incident Summary & SLA Breach Risk**
     - **Grounded Action Plan with Owners**
     - **Ready-to-Send Customer Executive Reply**
