# lintel-actions: post-meeting actions (prototype, iteration 4, accepted by the owner 2026-11-26)

Clickable HTML prototype for the owner's vision of 2026-11-26: after a meeting you get **ready-to-run actions**, not a to-do list. The email is already written, the meeting is already set up, the Jira ticket is already filled in. You check each one and approve it with one click, all in one place. **Nothing here is decided until the owner picks it** (owner rule 2026-11-19: no default is accepted for actions or chat). This is design only, with no Swift code and no spec. The spec comes after the owner accepts the prototype and after the detection-quality spike (brainstorm decision 9).

- Open: `cd .ai/prototypes/lintel-actions && python3 -m http.server 8771 --bind 127.0.0.1`, then `http://127.0.0.1:8771/index.html`. Opening `index.html` directly also works.
- Built on the accepted direction sketch `.ai/prototypes/lintel-direction` (owner decisions 2026-11-24: notes explorer as the main view, the working ring, warm neutrals, Verdigris only on the primary button, the selection and live state, neutral links, Notes · My notes · Transcript tabs) and on spec #255 (`.ai/specs/2026-11-24-notes-explorer-main-window.md`). The tokens and primitives are copied unchanged from `lintel-direction/lintel.html`.
- Toolbar (not part of the design): screen, state, **Account** (Google/Microsoft, connector (MCP), no account; Q1 and Q2 decided), theme, language (EN/PL), text size (M/L/XL), Reset.
- Query: `?screen=note|inbox|apps|after&tab=notes|actions|mine|transcript&pop=a1..a5&phase=proc|ready&state=ready|finding|none|done|errors|offline&mail=acct|mcp|nomail&theme=light|dark&lang=en|pl&ts=m|l|xl&sel=a1..a5|s1|s2&chrome=0`.
- All names, addresses, companies and data are fictional (`*.example`).

## What you can click

- **Meeting note → Notes tab** (Q4): the meeting always opens on Notes. A task that has an action shows a small icon (mail, calendar, ticket, or a check when done, amber while it needs you). Pointing at the task for about half a second, or focusing it with Tab, opens a card with the action's details and **Show in Actions**. Esc closes it.
- **Meeting note → Actions tab**: five actions from "Client call: Nordlys Energy". Click a row to open its card. The fields are editable in place. **Send** starts a 10-second countdown with **Undo**. "Add to Calendar" and "Create in Jira" finish at once and show Undo for 6 seconds. **Dismiss** greys the row out and offers Restore. **Show in Transcript** jumps to the sentence the action came from. ⌘↩ approves and ⌘⌫ dismisses the open card. After each approval the next card that needs you opens.
- **Other speaker** (a4): Ingrid said an email address. The card says who asked, leaves **To** empty, and Send asks you to add the recipient.
- **Unsure speaker** (a5): two people were on the same microphone. The card asks "Who will do it?" (You, Marek Lis, or No one, dismiss). The assignee fills in from the answer.
- **States**: Finding (ring closing and placeholder rows), None found, All done (results with "Open in Jira / Calendar / Gmail" links), Errors (no internet for mail, Jira needs a component), Not connected (Jira not connected, Google sign-in expired; the draft stays).
- **Actions inbox** (Q3: the Actions tab plus this inbox in the sidebar): one list of every waiting action across meetings, with the card on the right.
- **Connected apps** (Settings): Google, Calendar on this Mac, Microsoft 365, other mail through a connector, Jira, Linear, Asana (Q13).
- **After the meeting** (Q10): once the audio is saved, the pill shows only the closing ring (#273 pill family, OD-9); hovering says "Writing notes" / "Finding actions". When notes and actions are both ready it becomes "Ready · 5 actions · Open ✕". No macOS notification. The screen plays the sequence on open ("Play again"); the caption switches the phase. After 8 s the pill goes and a dot stays on the menu bar ring until the actions are opened (Q15 = B).

## Decisions applied

From the 2026-11-23 brainstorm (not asked again): actions before chat; approval is always a click, and "always allow" exists only for actions that affect only the user (an event without guests, a ticket assigned to yourself); email, anything for other people and every MCP tool always ask; actions are found by the provider that writes the notes; the other-speaker guard takes no recipients, links or attachments from someone else's words and never graduates; when the speaker is uncertain, the card asks; Jira uses an API token in the Keychain; MCP only from a Lintel-curated list.

**Owner decision 2026-11-26 (Q1, mail)**: the main path sends from Lintel through a connected **Google or Microsoft** account. Sending through an **MCP mail connector** from the curated list is an extra path. **Open as Draft** is always the fallback. If Google or Microsoft app verification blocks for long, start with the paths that need no verification (MCP, draft). The OAuth research is in `.ai/specs/research/2026-11-26-actions-mail-oauth.md`.

**Owner decisions 2026-11-26 (Q2–Q4)**:
- **Q2 = A + D.** Events with guests go through the connected Google/Microsoft account, later also through a calendar connector (MCP). EventKit (Calendar on this Mac) is only for events without guests. Without an account, the event goes to Calendar on this Mac and the invitation opens as an email draft with an `.ics` file (toolbar "Account → No account").
- **Delivery order for sending:** draft → Microsoft → Google (the owner starts Google verification now, in parallel) → MCP.
- **Q3 = C.** The Actions tab in the note plus the Actions inbox in the sidebar (the layout switch is gone).
- **Q4 = changed by the owner.** A meeting always opens on Notes. A task linked to an action shows, on hover after a short delay, a card with the action's details and a way into the Actions section.

**Owner decisions 2026-11-26 (Q5–Q14)**:
- Q5 = A: one open card at a time, fields editable at once.
- Q6: quote + speaker on the card before approval, plus Show in Transcript. **Nothing is added to the created ticket, invitation or email** (no trace of the source); the fixture descriptions no longer say "Agreed on the client call…".
- Q7 = A (mail held 10 s with Undo; event and ticket undone by deleting). Q8 = A (both buttons filled). Q9: no bulk approval in v1.
- Q10 = changed by the owner: the pill after the recording (above), no macOS notification.
- **Q15 = B**: the Ready pill goes after 8 s, then a dot on the menu bar ring until the actions are opened; no macOS notification.

**The owner accepted the direction on 2026-11-26.** Next: the detection-quality spike, then the spec (no spec in this PR).
- Q11: "ask less" is **not in v1**: the state, the offer and the Settings section "When Lintel may act without asking" are removed.
- Q12 = A. Q13 = Linear + Asana (+ the mail connectors). Q14 = A (detection runs by itself after the notes).

## Shape (om-ux-shape, short)

**Recommendation.** After notes are written, Lintel lists the meeting's actions as cards in the note, with one card open at a time. Each card shows the sentence it came from and who said it, the exact fields that will be sent, and one filled button that names the result ("Send", "Add and Invite 2 People", "Create in Jira"). The decisive trade-off is one open card at a time against seeing everything expanded. It keeps a single primary button on screen and makes each approval a real check, at the cost of one click to open each card.

**Problem.** Tasks agreed in a meeting have to be re-typed into mail, the calendar and Jira, and some get lost. Competitors either push items automatically by rules (Circleback to Linear, Fireflies to Jira and Asana) or only save drafts (Fireflies' Email Assistant). Neither documents a pre-approval card that shows the quote (`.ai/specs/research/2026-11-26-actions-competitors.md`). Wrong owners are the main complaint in this market (market scan 2026-11-23).

**Outcome.** The user handles a meeting's follow-ups from Lintel within the hour, without opening other apps. Signal (local only, no telemetry): approved ÷ (approved + dismissed + left waiting) per meeting, and how much a field was edited before approval. Guardrail: nothing goes to another person without a click, and no recipient comes from another speaker's words.

**Now.** Mail, a calendar event (just for you or with guests), a Jira ticket and one curated connector (Linear) as cards; edit in place; approve, dismiss, restore and undo; evidence with the speaker; the other-speaker and unsure-speaker cards; errors and not-connected states that keep the draft; the Connected apps page.
**Later.** More connectors, bulk approval (if the owner wants it), learning from edits, actions from dictations, chat over notes (its own brief).
**Not doing.** Automatic sending to other people; taking addresses or links from another speaker; local stdio MCP servers; tools from servers outside the curated list.

**Riskiest belief.** That detection finds the right actions with the right owner often enough for "approve" to beat "write it yourself". The parallel spike (brainstorm decision 9) measures this. If most cards need heavy edits, the cards become prefilled drafts and the copy stops saying "ready".

## Open questions for the owner

None. Q1–Q15 are decided (above).

## Design notes

- **Two filled buttons on the note screen** (Record Meeting + approve): kept, owner Q8 = A.
- **Speaker labels are gender-neutral** ("Ty:" / "You:"). Polish verbs never assume the user's gender.
- **No timestamps in notes** (owner 2026-11-19). The card shows the quote and "Show in Transcript", with no time.
- Calendar conflict checks are not shown: write-only calendar access cannot read events. Through a Google or Microsoft account it becomes possible (Q2).

## Evidence limits

The prototype is HTML that represents native controls, so fonts and controls are approximate. Checked in Chrome: light and dark, EN and PL, layouts A/B/C, every state, and the approve, undo, dismiss, restore and speaker-choice flows. Iterations 2–4 also checked: the task hover card and Show in Actions, the no-account event card, the pill sequence and the 8 s dot. Not checked: XL text on every state, VoiceOver, Increase Contrast. Competitor UIs were not inspected directly, only their documentation (see the research file).

## Process note (om-mockup-prototype)

The brief asks for a prototype in the style of the accepted app design, in `.ai/prototypes/lintel-actions/`, so this prototype departs from the skill's defaults on purpose: it uses the brand tokens instead of a neutral wireframe, and a single folder instead of `revision-NNN` with `prototype.json`. Each iteration is a commit on `docs/actions-prototype`. The toolbar's **Reset** button returns to the start of the selected state and clears your edits. Synthetic panels were not used: the owner is the reviewer. Every simulated value is fictional and is not research evidence.
