---
name: m365-onedrive-artifact-finder
description: Locates and extracts diagnostic spreadsheets, RCA draft documents, architecture diagrams, and operational runbooks stored in Microsoft OneDrive using the M365 OneDrive Connector.
category: subskill
parent_skills:
  - service-desk-major-incident-bridge
  - customer-escalation-resolver
---

# M365 OneDrive Artifact Finder (Atomic Sub-Skill)

## Purpose
This atomic sub-skill queries the **M365 OneDrive Connector** (`m365-onedrive-connector` / `1p-skill-manta-data-connector-skill-type-onedrive`) to locate, summarize, and cite relevant working documents, incident spreadsheets, customer call notes, and architecture artifacts stored in Microsoft OneDrive.

## Inputs
- `search_query` *(required)*: Incident ID, customer name, project code, or artifact keyword.
- `file_types` *(optional, default: `["docx", "xlsx", "pdf", "pptx"]`)*: Preferred document formats to inspect.

## Execution Instructions
1. Query the **M365 OneDrive Connector** (`@1p-skill-manta-data-connector-skill-type-onedrive`) using `search_query` and filter by recently modified files.
2. Rank matching OneDrive artifacts by relevance and recency (`lastModifiedDateTime`).
3. Extract key metrics, tables, action items, or RCA notes from the top matching OneDrive documents.
4. Return a structured JSON summary containing:
   - `artifact_title`: Document filename and title
   - `owner`: Document author / last modifier
   - `last_modified`: ISO-8601 timestamp
   - `key_excerpts`: Extracted findings, metrics, or remediation steps
   - `onedrive_url`: Direct citation link to the OneDrive file

## Guardrails
- Respect per-user OAuth 2.0 3LO ACL boundaries enforced by the M365 OneDrive connector.
- Always include exact document titles and last-modified timestamps when citing OneDrive files.
