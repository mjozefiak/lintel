# lintel-actions: post-meeting actions (prototype, iteration 1, 2026-11-26)

Clickable HTML prototype for the owner's vision of 2026-11-26: after a meeting you get **ready-to-run actions**, not a to-do list. The email is already written, the meeting is already set up, the Jira ticket is already filled in. You check each one and approve it with one click, all in one place. **Nothing here is decided until the owner picks it** (owner rule 2026-11-19: no default is accepted for actions or chat). This is design only, with no Swift code and no spec. The spec comes after the owner accepts the prototype and after the detection-quality spike (brainstorm decision 9).

- Open: `cd .ai/prototypes/lintel-actions && python3 -m http.server 8771 --bind 127.0.0.1`, then `http://127.0.0.1:8771/index.html`. Opening `index.html` directly also works.
- Built on the accepted direction sketch `.ai/prototypes/lintel-direction` (owner decisions 2026-11-24: notes explorer as the main view, the working ring, warm neutrals, Verdigris only on the primary button, the selection and live state, neutral links, Notes · My notes · Transcript tabs) and on spec #255 (`.ai/specs/2026-11-24-notes-explorer-main-window.md`). The tokens and primitives are copied unchanged from `lintel-direction/lintel.html`.
- Toolbar (not part of the design): screen, **Where (Q3)** layout variant, state, **Mail route** (Q1, decided), theme, language (EN/PL), text size (M/L/XL).
- Query: `?screen=note|inbox|apps|after&layout=tab|inline|inbox&state=ready|finding|none|done|errors|offline|graduate&mail=acct|mcp|nomail&theme=light|dark&lang=en|pl&ts=m|l|xl&sel=a1..a5|s1|s2&chrome=0`.
- All names, addresses, companies and data are fictional (`*.example`).

## What you can click

- **Meeting note → Actions tab**: five actions from "Client call: Nordlys Energy". Click a row to open its card. The fields are editable in place. **Send** starts a 10-second countdown with **Undo**. "Add to Calendar" and "Create in Jira" finish at once and show Undo for 6 seconds. **Dismiss** greys the row out and offers Restore. **Show in Transcript** jumps to the sentence the action came from. ⌘↩ approves and ⌘⌫ dismisses the open card. After each approval the next card that needs you opens.
- **Other speaker** (a4): Ingrid said an email address. The card says who asked, leaves **To** empty, and Send asks you to add the recipient.
- **Unsure speaker** (a5): two people were on the same microphone. The card asks "Who will do it?" (You, Marek Lis, or No one, dismiss). The assignee fills in from the answer.
- **States**: Finding (ring closing and placeholder rows), None found, All done (results with "Open in Jira / Calendar / Gmail" links), Errors (no internet for mail, Jira needs a component), Not connected (Jira not connected, Google sign-in expired; the draft stays), Ask less (the offer to stop asking for events just for you, shown on Weekly sales sync).
- **Actions inbox** (layout C): one list of every waiting action across meetings, with the card on the right.
- **Connected apps** (Settings): Google, Calendar on this Mac, Microsoft 365, other mail through a connector, Jira, Linear, Asana, and "When Lintel may act without asking".
- **After the meeting**: one macOS notification per meeting and the menu bar ring with a dot plus "Actions to review 5".

## Decisions applied

From the 2026-11-23 brainstorm (not asked again): actions before chat; approval is always a click, and "always allow" exists only for actions that affect only the user (an event without guests, a ticket assigned to yourself); email, anything for other people and every MCP tool always ask; actions are found by the provider that writes the notes; the other-speaker guard takes no recipients, links or attachments from someone else's words and never graduates; when the speaker is uncertain, the card asks; Jira uses an API token in the Keychain; MCP only from a Lintel-curated list.

**Owner decision 2026-11-26 (Q1, mail)**: the main path sends from Lintel through a connected **Google or Microsoft** account. Sending through an **MCP mail connector** from the curated list is an extra path. **Open as Draft** is always the fallback. If Google or Microsoft app verification blocks for long, start with the paths that need no verification (MCP, draft). The OAuth research is in `.ai/specs/research/2026-11-26-actions-mail-oauth.md`.

## Shape (om-ux-shape, short)

**Recommendation.** After notes are written, Lintel lists the meeting's actions as cards in the note, with one card open at a time. Each card shows the sentence it came from and who said it, the exact fields that will be sent, and one filled button that names the result ("Send", "Add and Invite 2 People", "Create in Jira"). The decisive trade-off is one open card at a time against seeing everything expanded. It keeps a single primary button on screen and makes each approval a real check, at the cost of one click to open each card.

**Problem.** Tasks agreed in a meeting have to be re-typed into mail, the calendar and Jira, and some get lost. Competitors either push items automatically by rules (Circleback to Linear, Fireflies to Jira and Asana) or only save drafts (Fireflies' Email Assistant). Neither documents a pre-approval card that shows the quote (`.ai/specs/research/2026-11-26-actions-competitors.md`). Wrong owners are the main complaint in this market (market scan 2026-11-23).

**Outcome.** The user handles a meeting's follow-ups from Lintel within the hour, without opening other apps. Signal (local only, no telemetry): approved ÷ (approved + dismissed + left waiting) per meeting, and how much a field was edited before approval. Guardrail: nothing goes to another person without a click, and no recipient comes from another speaker's words.

**Now.** Mail, a calendar event (just for you or with guests), a Jira ticket and one curated connector (Linear) as cards; edit in place; approve, dismiss, restore and undo; evidence with the speaker; the other-speaker and unsure-speaker cards; errors and not-connected states that keep the draft; the Connected apps page.
**Later.** More connectors, bulk approval (if the owner wants it), learning from edits, actions from dictations, chat over notes (its own brief).
**Not doing.** Automatic sending to other people; taking addresses or links from another speaker; local stdio MCP servers; tools from servers outside the curated list.

**Riskiest belief.** That detection finds the right actions with the right owner often enough for "approve" to beat "write it yourself". The parallel spike (brainstorm decision 9) measures this. If most cards need heavy edits, the cards become prefilled drafts and the copy stops saying "ready".

## Open questions for the owner (no defaults; each has a recommendation)

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q2 | Meetings with guests: EventKit cannot add attendees (Apple docs) | A) through the same Google/Microsoft account as mail; B) EventKit + .ics invitation by mail; C) EventKit, then add people in Calendar; D) A + a calendar connector (MCP) | A now, D with the mail connector |
| Q3 | Where the actions live (toolbar "Where") | A) Actions tab in the note; B) at the top of the Notes tab; C) tab + an Actions inbox in the sidebar across meetings | C |
| Q4 | Which tab a meeting opens on while actions wait | A) Actions, until all are handled; B) always Notes | A |
| Q5 | Card form | A) one card open at a time, editable in place (prototype); B) all cards expanded; C) read-only card with Edit | A |
| Q6 | Evidence on the card | A) quote + speaker always visible (prototype); B) behind "Why?"; C) quote + surrounding lines | A |
| Q7 | Undo after approval | A) mail held 10 s with Undo, other actions undone by deleting what was created (prototype); B) no Undo, only a result link | A |
| Q8 | Two filled buttons on the note screen (Record Meeting + the card's approve button) | A) keep both filled; B) the card button tinted; C) Record Meeting unfilled while Actions is open | A |
| Q9 | Bulk approval | A) none in v1; B) "Approve all just for you"; C) "Approve all" | A |
| Q10 | How you learn actions are ready | A) only in the app; B) + one macOS notification per meeting; C) B + a dot on the menu bar ring (prototype) | C |
| Q11 | When to offer "ask less" (only-you actions) | A) after 3 approvals without edits, plus a Settings switch (prototype); B) only the switch; C) not in v1 | A |
| Q12 | "Assigned to you" in Jira | A) you said it AND the Jira assignee is you; B) only the assignee | A |
| Q13 | Curated MCP connectors in v1 (plus the mail connectors from Q1) | A) Linear + Asana; B) + Notion and Slack; C) Linear only | A |
| Q14 | When detection runs | A) automatically after the notes; B) only when you click "Find actions" | A |

Sent to the owner through L0: Q2 alone; Q3–Q8 (card and layout) and Q9–Q14 (behaviour) as two batches.

## Design notes

- **One filled button per screen** is broken on the note screen (Record Meeting + approve); that is Q8.
- **Speaker labels are gender-neutral** ("Ty:" / "You:"). Polish verbs never assume the user's gender.
- **No timestamps in notes** (owner 2026-11-19). The card shows the quote and "Show in Transcript", with no time.
- Calendar conflict checks are not shown: write-only calendar access cannot read events. Through a Google or Microsoft account it becomes possible (Q2).

## Evidence limits

The prototype is HTML that represents native controls, so fonts and controls are approximate. Checked in Chrome: light and dark, EN and PL, layouts A/B/C, every state, and the approve, undo, dismiss, restore and speaker-choice flows. Not checked: XL text on every state, VoiceOver, Increase Contrast. Competitor UIs were not inspected directly, only their documentation (see the research file).

## Process note (om-mockup-prototype)

The brief asks for a prototype in the style of the accepted app design, in `.ai/prototypes/lintel-actions/`, so this prototype departs from the skill's defaults on purpose: it uses the brand tokens instead of a neutral wireframe, and a single folder instead of `revision-NNN` with `prototype.json`. Each iteration is a commit on `docs/actions-prototype`. The toolbar's **Reset** button returns to the start of the selected state and clears your edits. Synthetic panels were not used: the owner is the reviewer. Every simulated value is fictional and is not research evidence.
