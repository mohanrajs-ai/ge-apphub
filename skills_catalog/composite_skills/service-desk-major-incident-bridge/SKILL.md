---
name: service-desk-major-incident-bridge
description: Composite M365 incident response skill that coordinates Microsoft Teams war-room chats, SharePoint SOP runbooks, OneDrive RCA artifacts, and Outlook executive status broadcasts for P1/P2 major incidents.
category: composite_skill
sub_skills:
  - servicenow-itsm-ticket-triage
  - m365-teams-incident-swarm
  - sharepoint-policy-lookup
  - m365-onedrive-artifact-finder
  - m365-outlook-triage
---

# Service Desk Major Incident Bridge (Composite ServiceNow + M365 Skill)

## Purpose
This composite parent skill orchestrates five atomic sub-skills across **ServiceNow ITSM & Knowledge**, **Microsoft Teams**, **SharePoint Online**, **OneDrive**, and **Outlook Email** to accelerate P1/P2 major incident response and executive communication:
1. [`servicenow-itsm-ticket-triage`](../../subskills/servicenow-itsm-ticket-triage/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-servicenow`) — Queries ServiceNow `incident` and `knowledge_base` tables for active P1/P2 tickets, known-error KB articles, and BAP incident actions (`create_incident`, `update_incident`, `add_comment_to_incident`).
2. [`m365-teams-incident-swarm`](../../subskills/m365-teams-incident-swarm/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-teams`) — Extracts live war-room decisions, root-cause hypotheses, and mitigation owners from Microsoft Teams channels.
3. [`sharepoint-policy-lookup`](../../subskills/sharepoint-policy-lookup/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-sharepoint`) — Retrieves official P1/P2 incident escalation SOPs, SLA matrices, and rollback checklists from SharePoint Online.
4. [`m365-onedrive-artifact-finder`](../../subskills/m365-onedrive-artifact-finder/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-onedrive`) — Locates live diagnostic spreadsheets, architecture diagrams, and draft RCA documents in OneDrive.
5. [`m365-outlook-triage`](../../subskills/m365-outlook-triage/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-outlook-email`) — Correlates inbound customer impact emails in Outlook and drafts an executive Incident Status Broadcast.

## Orchestration Workflow
### Step 0: ServiceNow Ticket & Known-Error KB Triage (`servicenow-itsm-ticket-triage`)
- Search `@1p-skill-manta-data-connector-skill-type-servicenow` (`cymbal-servicenow_incident`, `cymbal-servicenow_knowledge_base`) for active incident records (`INC*`), affected Configuration Items, and known-error KB articles.

### Step 1: War-Room Telemetry (`m365-teams-incident-swarm`)
- Search `@1p-skill-manta-data-connector-skill-type-teams` for the active incident ID or service name to construct a chronological timeline and identify mitigation owners.

### Step 2: Runbook & SLA Verification (`sharepoint-policy-lookup`)
- Search `@1p-skill-manta-data-connector-skill-type-sharepoint` for the matching major incident SOP and SLA communication cadence.

### Step 3: Diagnostic & RCA Artifact Discovery (`m365-onedrive-artifact-finder`)
- Search `@1p-skill-manta-data-connector-skill-type-onedrive` for working post-mortem drafts, telemetry spreadsheets, or architecture diagrams related to the impacted service.

### Step 4: Customer Impact & Executive SitRep (`m365-outlook-triage`)
- Search `@1p-skill-manta-data-connector-skill-type-outlook-email` for affected customer threads and synthesize a structured **Major Incident SitRep**:
  1. **Incident Summary & Severity** (Impact scope, start time, SLA timer)
  2. **Teams War-Room Timeline & Active Mitigations** (Owners & next checkpoint)
  3. **Applicable SharePoint Runbook & OneDrive RCA Artifacts** (With direct citations)
  4. **Ready-to-Send Executive & Customer Outlook Broadcast**
