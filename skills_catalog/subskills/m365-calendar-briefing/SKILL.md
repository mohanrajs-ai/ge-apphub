---
name: m365-calendar-briefing
description: Retrieves today's meetings, attendee lists, scheduling conflicts, and preparation topics from Microsoft Outlook Calendar using the M365 Outlook Calendar Connector.
category: subskill
parent_skills:
  - daily-morning-summary
  - service-desk-major-incident-bridge
---

# M365 Calendar Briefing (Atomic Sub-Skill)

## Purpose
This atomic sub-skill queries the **M365 Outlook Calendar Connector** (`m365-outlook-calendar-connector` / `1p-skill-manta-data-connector-skill-type-outlook-calendar`) to inspect a user's upcoming meetings, identify high-priority customer or incident review sessions, detect calendar conflicts, and list key attendees.

## Inputs
- `time_window` *(optional, default: `"today"`)*: Time range to inspect (`"today"`, `"next_24h"`, `"this_week"`).
- `focus_filter` *(optional)*: Filter for specific meeting types (e.g., `"customer"`, `"incident"`, `"executive"`).

## Execution Instructions
1. Query the **M365 Outlook Calendar Connector** (`@1p-skill-manta-data-connector-skill-type-outlook-calendar`) for all scheduled events within `time_window`.
2. Group events chronologically and identify:
   - High-priority external/customer meetings or incident bridge calls
   - Overlapping or back-to-back scheduling conflicts
   - Meetings missing agendas or pre-read attachments
3. Return a structured JSON summary containing:
   - `meetings`: Chronological list of events (`start_time`, `end_time`, `subject`, `organizer`, `key_attendees`, `join_url`)
   - `conflicts`: Any overlapping calendar slots
   - `prep_topics`: Recommended topics and context to review before each priority meeting

## Guardrails
- Respect private/confidential calendar event flags (`sensitivity: private`).
- Always display meeting times clearly with timezone context.
