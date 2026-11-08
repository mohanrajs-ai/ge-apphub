---
name: daily-morning-summary
description: Composite M365 productivity skill that orchestrates Outlook Calendar, Outlook Email, and Microsoft Teams connectors to deliver an executive Daily Morning Briefing with schedule priorities, high-priority emails, and urgent Teams mentions.
category: composite_skill
sub_skills:
  - m365-calendar-briefing
  - m365-outlook-triage
  - m365-teams-incident-swarm
---

# Daily Morning Summary (Composite M365 Skill)

## Purpose
This composite parent skill chains three atomic M365 sub-skills across **Outlook Calendar**, **Outlook Email**, and **Microsoft Teams** to generate a unified morning executive briefing:
1. [`m365-calendar-briefing`](../../subskills/m365-calendar-briefing/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-outlook-calendar`) — Pulls today's meetings, key attendees, and scheduling conflicts.
2. [`m365-outlook-triage`](../../subskills/m365-outlook-triage/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-outlook-email`) — Identifies unread VIP/urgent emails and pending action items from the last 24 hours.
3. [`m365-teams-incident-swarm`](../../subskills/m365-teams-incident-swarm/SKILL.md) (`@1p-skill-manta-data-connector-skill-type-teams`) — Summarizes direct `@mentions`, active operational threads, and unresolved blockers in Microsoft Teams.

## Orchestration Workflow
### Step 1: Calendar & Meeting Prep (`m365-calendar-briefing`)
- Check `@1p-skill-manta-data-connector-skill-type-outlook-calendar` for today's schedule.
- Highlight external customer calls, leadership reviews, and any overlapping slots.

### Step 2: Priority Inbox Triage (`m365-outlook-triage`)
- Query `@1p-skill-manta-data-connector-skill-type-outlook-email` for unread or high-importance threads over the last 24 hours, especially threads from today's meeting attendees.

### Step 3: Urgent Teams Mentions & Swarm Activity (`m365-teams-incident-swarm`)
- Query `@1p-skill-manta-data-connector-skill-type-teams` for direct `@mentions`, unanswered questions, and active incident channels from the last 24 hours.

### Step 4: Consolidated Briefing Output
Present a clean, scannable Markdown briefing with four sections:
1. **Today's Schedule & Prep Notes** (Chronological meetings + related email/Teams context)
2. **Urgent Emails Requiring Reply** (Sender, subject, deadline/SLA, and suggested response)
3. **Active Teams Mentions & Blockers** (Channel/chat, requester, and action needed)
4. **Top 3 Recommended Priorities for Today**
