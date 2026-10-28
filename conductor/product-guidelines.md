# Product Guidelines: Gemini Enterprise AppHub (`ge-apphub`)

## 1. Visual Design & Aesthetic
- **Design Language:** Google Material 3 / Cloud Console-inspired aesthetic—clean, modern, and trustworthy, incorporating subtle Gemini AI accent gradients for primary branding elements.
- **Typography & Hierarchy:** High-legibility sans-serif typography (such as Inter or Google Sans / Roboto) with clear visual hierarchy between page headers, application titles, metadata badges, and body descriptions.
- **Theming:** Support for clean light and dark modes with high-contrast surfaces, subtle elevation/borders on catalog cards, and consistent spacing tokens.

## 2. Brand Voice, Tone & Prose Style
- **Professional, Clear & Action-Oriented:** All UI copy, empty states, and application summaries must be concise, jargon-free, and focused on user outcomes (what the application helps the user accomplish).
- **Consistent Terminology:** Refer to catalog items consistently as **Gemini Enterprise Applications** (or **GE Apps**) and use clear verbs for primary calls to action (e.g., *Launch App*, *Filter by Category*, *Search Applications*).
- **Scannable Copy:** Keep card descriptions brief (1–2 sentences on the catalog grid) so users can compare applications quickly.

## 3. Core UX Principles
- **Zero-Friction Discovery & Instant Search:**
  - The search bar and category/tag filters are immediately accessible at the top of the hub.
  - Search and filter interactions update the catalog view in real time without full-page reloads.
  - Minimize clicks from landing on the portal to launching a target Gemini Enterprise application in a centered standalone popup window over the hub.
- **Clarity & Predictability:**
  - Every application card displays a consistent structure: Application Icon, Title, Category/Department Badges, Brief Outcome-Oriented Summary, and a clear **Launch App** button that opens the target application in a centered popup overlay window.
  - Provide informative loading skeletons and clear empty/error states when filters return no matches.
