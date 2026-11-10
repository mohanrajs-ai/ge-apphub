---
name: servicenow-itsm-ticket-triage
description: Queries and updates ServiceNow IT Incidents, Knowledge Base articles, and Service Catalog items via the Gemini Enterprise ServiceNow Connector and BAP Actions.
---

# Sub-Skill: ServiceNow ITSM Ticket & Knowledge Triage

## Environment Bindings
- **Target Gemini Enterprise Engine:** `{{ENGINE_ID}}`
- **Bound Data Stores:** `{{DATA_STORE_IDS}}` (`cymbal-sn-fed_incident`, `cymbal-sn-fed_catalog`)
- **Required Connector:** `servicenow` (`@1p-skill-manta-data-connector-skill-type-servicenow`)

## Execution Steps
1. Search the user's accessible ServiceNow `incident` and `catalog` data stores (`{{DATA_STORE_IDS}}`) on engine `{{ENGINE_ID}}` for matching P0/P1/P2 incidents (searching both `"P0"`, `"P1"`, and ServiceNow priority `"1 - Critical"` / `"2 - High"`), affected Configuration Items (CIs), SLA breach timers, and known-error KB articles.
2. When requested to log an incident, invoke the governed ServiceNow BAP action (`create_incident`) while strictly enforcing user-level ACLs.
3. Return a structured JSON summary containing `incident_number`, `priority`, `state`, `assigned_to`, `kb_articles`, `catalog_items`, and `recommended_remediation`.
