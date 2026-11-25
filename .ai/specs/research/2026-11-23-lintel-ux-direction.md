# Lintel UX direction

> Status: **revision 2, accepted by the owner on 2026-11-24** (decisions in "Owner decisions" below, which win over any older wording in this doc or the sketch). Design-only: no Swift, no settings keys, no strings in `Localizable.xcstrings`. Sketch: `.ai/prototypes/lintel-direction/lintel.html`. Revision 1 (2026-11-23, three directions A, B, C with a Home dashboard) is in the PR history.

## What changed in revision 2

Owner feedback on revision 1 (2026-11-24): A Quiet Native and C Friendly Guide were liked most; the brand character got lost; the main view must be the notes explorer, not a Home dashboard; settings were not rethought enough; notes and dictation are the core, while quick search (launcher and file search), clipboard history and window layouts are add-ons that are off by default.

Three research reports were written for this round (`~/.lintel-agents/2026-11-24/`): a competitor UI teardown (Wispr Flow, Circleback, Fireflies, Granola), foolproof UI rules with a 19-item checklist, and a settings IA built from scratch with a 20-task tree test. Revision 2 follows them:

1. **One direction, "Quiet Native with warmth"**: A's native structure and controls with C's warmth (warm neutrals, rounded empty states, an illustrated step rail in onboarding). B is dropped: warm cream with a serif and green already reads as Granola. A neutral grey tone is kept as the one contrasting variant (`tone=neutral`) because the owner has to decide whether the warmth stays.
2. **The brand signature is the working ring**, not a typeface or a palette (below).
3. **Main window = three-column notes explorer.** There is no Home dashboard, no stats and no upsell.
4. **Settings rebuilt** to the IA research: 7 sidebar items, one home per setting, an Add-ons page where everything is off, a single Privacy & data page, and one AI assistant choice.
5. **Onboarding rebuilt**: goal → privacy → access with reasons → practice dictation → first meeting, with the copy fixes from the audit.
6. **Every sketched screen is checked** against the 19-item foolproof checklist (results below and in the PR body).

## Decision being made

The look, the vocabulary and the IA that the three design tracks (main window, settings rebuild, onboarding) follow, so each spec starts from one accepted direction instead of inventing its own. Code changes (inverting plugin defaults, the settings rebuild, the new main window) come later in their own PRs.

## Inputs

- Owner feedback 2026-11-24 (above) and the owner decisions of 2026-11-19: Claude as an optional notes writer (off by default, with consent text), notes are summaries without timestamps, **no per-line AI or human authorship marks**, chat over notes and post-meeting actions are prototype-first and decided by the owner (not part of this direction).
- `research-competitors-ui.md`: everyone in the category separates "mine" from "AI" (Wispr's My thoughts tab, Granola's black and grey lines); personalisation such as the dictionary lives in the main window, while Settings stay short and systemic; one list of notes with search beats an assistant dashboard (Fireflies collects complaints about clutter); none of the four has a Polish UI, and local privacy is the weak spot of Wispr and Granola.
- `research-foolproof-ui.md`: 15 rules (R1-R15), the 19-item checklist (C1-C19) and the ten worst violations on `main` and in revision 1.
- `research-settings-ia.md`: the 7-item sidebar, a page-by-page row table with defaults, removed items, search with synonyms, the 20-task tree test, and the contradictions in `main` and in revision 1.
- Revision 1 research (Wispr Flow setup, Granola, Superhuman, Linear, Raycast, Things, Apple Notes, Otter, Notion) still holds; sources are in the PR history.

## Personas (assumptions; Lintel has no telemetry or interviews)

1. **Anna, sales manager**: 8+ calls a day, writes follow-ups between calls. Success: the follow-up is sent before the next call.
2. **Piotr, lawyer / consultant**: confidential client work, dictates memos. Success: he trusts it with a client memo, and nothing leaves the Mac.
3. **Kasia, recruiter / HR**: interviews, Polish and English. Success: she sets it up in 3 minutes without help.

## Tone of voice

Calm, plain, second person, short sentences (about 15 words), verbs on buttons, no exclamation marks, no AI hype words ("magic", "supercharge", "AI-powered"), no technical nouns. Say what happens to the user's words, not how the machine works. Headings are nouns; questions only as onboarding titles. Polish uses "Ty" forms with capitals in direct address ("Twoje słowa") and never declines the name Lintel. English buttons use title case (macOS), labels sentence case.

## Design principles

1. **Open on the user's content.** The window opens on the notes explorer; the first-run checklist is one row that can be hidden (R2).
2. **Core on, add-ons off.** A fresh install has dictation and meeting notes; add-ons have no trace in the main window, onboarding or the sidebar until turned on (R1).
3. **One obvious next step per screen**: one filled button, and it names what happens ("Record Meeting", "Stop and Write Notes") (R3).
4. **Show the result, not the machinery.** No model, server, engine or index names outside "More options" (R4).
5. **One home per setting.** Other pages only point to it with a "›" row; search finds it by the user's word in English or Polish (IA research).
6. **Five rows, then More options**, never "Advanced" (R5).
7. **Pick from a list instead of typing**: apps, folders, shortcuts (R6).
8. **Prevent, then explain.** Continue is never greyed out without a reason; errors say what happened, what to do, and offer one fix button (R7, R9).
9. **Mine is never rewritten.** What the user types stays in My notes; Lintel's notes are a separate tab, not marks on each line (owner 2026-11-19).
10. **Privacy where the data is**: one sentence per page, "On this Mac" on every note, Privacy & data as the only place for permissions, retention and deletion.
11. **Native, plus one signature**: macOS controls and layout everywhere; the brand is the working ring and Verdigris for what is live (R15).
12. **Bilingual and large-text safe**: every screen is checked in Polish and at XL text without truncation (R14).

## Brand signature: the working ring

The cut ring from the logo is the one element that carries the brand inside the product. It is a working element, not a decoration, and it appears in five states:

| State | Where | Look |
|---|---|---|
| Record button | toolbar of the main window (the only filled button) | white ring on Verdigris + "Record Meeting" |
| Live (recording, listening) | toolbar pill while recording, the recording panel, the "Now" row, Hold to Talk in onboarding, the dictation HUD | Verdigris ring that slowly turns, the centre dot breathes; static under Reduce Motion |
| Working (writing notes) | the note's row in the list | the ring closes as the notes are written ("Writing notes…") |
| Note type | every row and the Meetings / Dictations filters | meeting = ring with the centre dot, dictation = ring without it, always with the word in the meta line (never shape alone) |
| Empty | empty notes view | an outlined ring and one sentence with one action |

**Verdigris** (#267C6C light, #6BBDAB dark; text #036152 / #7FCDBB) appears only on the primary button, the selection (sidebar, list, onboarding step, chosen option; a 14 % tint with a 3 pt bar) and live state (the ring, the recording pill, "Writing notes…", the status line of a ready feature). Switches and checkboxes use it for "on", as macOS does; links are neutral text (owner decision 4). No gradients, glow, sparkles or purple-blue.

**Warmth** (from C): warm neutral surfaces (#F8F6F2 window, #EFECE6 sidebar; dark #1D1B18 / #242220), 10-12 pt corners on groups and cards, the outlined ring in empty states, and a warm step rail with the ring and "Your words, on this Mac." in onboarding. Not taken from C: icon circles on every row, rounded type, and questions as section headings.

**Variant (`tone=neutral`)**: the same screens on cool system greys (revision 1's A). It shows what the warmth adds and what it costs; one screenshot is in the PR.

## Information architecture

### Main window: the notes explorer

Three columns, like Mail and Notes.

- **Sidebar**: All notes · Meetings · Dictations (counts) → Folders (+ New Folder) → Dictionary at the bottom. Add-ons never appear here.
- **Toolbar**: Search notes · Record Meeting (ring, primary) · Settings (gear, ⌘,).
- **List**: grouped by day; each row has the type ring, the title (wraps up to 3 lines instead of truncating), meta ("Meeting · 42 min · 3 tasks"), time. Row states: ready, writing notes (closing ring), notes not written (warning text). The first-run checklist is one row above the list ("Finish setting up · 3 of 5 · Hear other people in calls [Allow] ✕").
- **Preview**: title, meta, "On this Mac" chip, Open and Copy, then the tabs **Notes · My notes · Transcript**. Notes = summary, decisions, tasks with the person who owns them; a footer says Lintel wrote them from the recording on this Mac. My notes = only what the user typed, with "Only you write here. Lintel never changes these notes." A dictation shows the text and where it was pasted.
- **Note in a full window** (Open or double-click): sidebar and list hidden, "‹ All notes" to go back.
- **Recording**: the toolbar button becomes a live pill (ring, time, Stop); a "Now" row is selected; the preview shows the live panel ("Lintel hears you and the other people in the call.", Stop and Write Notes), a consent reminder and a My notes pad for typing during the call. If Lintel hears only the microphone, a warning says so with a Fix Call Audio button.
- **Notes not written**: the preview says what happened, that the recording and transcript are safe, and offers Try Again.
- **Empty**: outlined ring, "Your notes will appear here", one sentence about recording and dictating, Try Dictation (Record Meeting stays the one primary in the toolbar).
- **Dictionary**: a page in the main window (its only home): search, Add Word, each word with Remove. (The sketch's "Added by you" / "Learned from your corrections" labels are dropped until Lintel learns words: #255 Q10.) Empty state: "Add names you use often, like clients and colleagues." + Add Word.

### Settings (separate window, ⌘,)

Sidebar: **General · Dictation · Meetings & notes · AI assistant · Privacy & data** | **Add-ons** (with "3 off") | **About & help**, plus "Search settings" on top. An enabled add-on gets an indented page under Add-ons. Each page: title (Dictation and Meetings & notes have their on/off switch there) → status line → up to 5 rows → More options → one privacy sentence.

| Page | Basic rows | More options |
|---|---|---|
| General | Languages I speak · Microphone (Automatic) · Text size (M/L/XL) · Open Lintel when I log in · Show Lintel in the Dock | Try new features early |
| Dictation | status "Ready to dictate" · Shortcut (⌥ Space) · Tidy up my text · Dictionary (12 words, Open) · "Dictations are kept for 30 days" › Privacy & data | After pasting, put back what I had copied · Paste my last dictation unedited (shortcut) |
| Meetings & notes | status (e.g. "Hears only you for now", Allow…) · Record a meeting (⌃⌥M) · Suggest recording when a call starts · Your name in notes · Notes written by: This Mac › AI assistant · Export all notes | Write notes after each meeting · Never suggest recording in (app picker) · Check call audio |
| AI assistant | status · one choice "Who writes your notes and tidies your text": This Mac (private, offline) / Claude (your account, words sent to Anthropic); with Claude: Use Claude for Meeting notes ☑ / Dictation ☐ and "Lintel asks you before the first meeting is sent." | Assistant on this Mac (Recommended for this Mac) · Downloaded files 3.7 GB (Show, Remove…) · Use my own AI server |
| Privacy & data | "Recordings, notes and dictations stay on this Mac." · What Lintel can use: Microphone, Hear other people in a call, Type into other apps (Allowed ✓ / Allow…) · What Lintel keeps: Meeting audio (Delete when notes are ready), the only retention choice, plus a read-only sentence for the rest (notes and transcripts kept until deleted) · Delete my data… (sheet: dictations 128 / meetings and notes 42 / everything, button "Delete 42 Meetings", Cancel is the default) · Recently deleted (30 days) | Remind me to tell people I'm recording |
| Add-ons | "Extra tools. All off until you turn them on." · Quick search · Clipboard history · Window layouts, each with "Off" next to its switch | — |
| ↳ Quick search (when on) | status "Choose a shortcut to start" · Shortcut (chosen by the user, never ⌘Space by default) · Also search files · Folders | Result order · Show hidden files · Skip these folders · Start over |
| ↳ Clipboard history / Window layouts | Shortcut · Never save from these apps (password managers preset) / Shortcut · Space between windows | the rest of today's controls |
| About & help | status "Lintel 1.0 beta 2 · Up to date" (Check Now) · Update automatically · What's new · Show welcome again · Send a problem report (shows what is sent) · Acknowledgements | — |

**Search** indexes every row's English and Polish label plus synonyms (hotkey/skrót, recordings/nagrania, delete/usuń, spell/literuj, disk space/miejsce, …). A result names its page (and "More options" when the row is there); choosing it opens the page, expands More options and highlights the row. Checked with 18 user words: spell, literuj, usuń, mikrofon, headset, recordings, stop saving, claude, disk space, slack, bigger, bug, clipboard, export, login, my name, tell people, zoom; all found after adding "login".

**Removed from today's settings**: the Features, Models, Permissions and Advanced panes (their rows moved to the pages above); the three text-model pickers, two speech-model pickers, the Whisper language, Speaker model, "Run on", the model-name footer, Bundle ID fields, Capture diagnostics (replaced by Send a problem report), Notes → Wrap lines and Notes model, a separate Clear in every pane, Reset Ranking and Rebuild (now "Start over" inside the add-on). Today's keys behind removed rows keep their stored values; which become "ignored" is decided in the settings rebuild spec with a BACKWARD_COMPATIBILITY review.

### Onboarding (one window, step rail on the left)

Steps adapt to the goal: Dictation skips First meeting and the call-audio permission; Meeting notes skips Try dictation and "Type into other apps".

1. **Your goal**: "What would you like Lintel to do?": Type what I say / Write my meeting notes / Both (default). "You can change this later in Settings."
2. **Privacy**: "Your words stay on this Mac": saved on this Mac, encrypted; nothing sent anywhere, Claude only if chosen later and Lintel asks first; no account. With meetings: "When you record a meeting, tell the other people. Lintel reminds you."
3. **Access**: "Lintel needs your OK for a few things": one row per permission with the reason in plain words and Allow; "(Opens System Settings)" where macOS does that; "You can skip any of these and allow them later in Settings → Privacy & data." Continue is always active.
4. **Try dictation**: the sample email, Hold to Talk or ⌥ Space, Change shortcut. **Copy fixes**: the false promise "No microphone handy? Press and hold the button instead." is replaced by "Can't talk right now? Continue, and try it later from the menu bar."; Continue is never greyed out.
5. **First meeting**: what the call suggestion looks like (a picture, not a live button), "You can also press Record Meeting in the Lintel window.", the Record a meeting shortcut (⌃⌥M) with Change Shortcut, Check call audio, the consent sentence, and **Open Lintel**, which lands on the empty notes view.

No account, no marketing questions, no add-ons.

## Glossary (current UI term → plain words; "More only" = never in the basic rows)

| Current term | English | Polish | Where |
|---|---|---|---|
| speech model, Parakeet, Whisper, WhisperKit | (none; recognition just works) | — | engine names never shown |
| LLM, built-in model, Qwen, Bielik, GGUF, notes model | AI assistant / assistant on this Mac | Asystent AI / asystent na tym Macu | AI assistant page; model names More only |
| notesProvider Claude / This Mac | Who writes your notes: This Mac / Claude (your account) | Kto pisze notatki: Ten Mac / Claude (Twoje konto) | AI assistant |
| Run on: Built-in / My server, endpoint, address, port | Use my own AI server | Użyj własnego serwera AI | More only |
| Clean up / formatting | Tidy up my text | Porządkuj mój tekst | Dictation |
| diarization, speaker model | (always on, no setting; speakers shown by name in the transcript) | — | — |
| retention, retentionDays, maximumEntries | What Lintel keeps · 30 days · Keep forever · Delete when notes are ready | Co Lintel przechowuje · 30 dni · Przechowuj zawsze · Usuń, gdy notatki są gotowe | Privacy & data |
| Erase Data, Clear Library, Clear History | Delete my data… → "Delete 42 Meetings" | Usuń moje dane… → „Usuń 42 spotkania” | Privacy & data |
| bundle ID | (pick an app: Add App…) | Dodaj aplikację… | More only |
| Full Disk Access | Search everywhere on this Mac | Szukaj wszędzie na tym Macu | Quick search add-on |
| Accessibility (permission) | Type into other apps | Pisz w innych aplikacjach | onboarding, Privacy & data |
| System Audio Recording | Hear other people in a call | Słysz innych w rozmowie | onboarding, Privacy & data, recording warning |
| Test System Audio, diagnostics | Check call audio · Send a problem report | Sprawdź dźwięk rozmowy · Zgłoś problem | Meetings & notes More, About & help |
| index, Rebuild Index, Reset Ranking | Start over | Zacznij od nowa | Quick search More only |
| launcher | Quick search | Szybkie wyszukiwanie | Add-ons |
| plugin, Features pane | Add-ons (extras) or nothing (core features have their switch in their page title) | Dodatki | Settings |
| vocabulary | Dictionary: names and words Lintel always spells your way | Słownik | main window |
| AI-written vs mine | Notes · My notes · Transcript | Notatki · Moje notatki · Transkrypcja | note tabs |
| Advanced | More options | Więcej opcji | every page |

## Foolproof checklist (C1-C19) on every sketched screen

Method: the sketch's `audit=1` mode checked each of 24 screen states in English and Polish at M and XL text (96 runs) for truncated or spilling text, filled primary buttons, jargon outside More options and small targets; contrast was computed from the tokens in all four tone/theme combinations; settings search was run with 18 user words; the rest was judged on the screenshots. ✓ pass · ✗ fail · ◐ partly (or not verifiable in HTML) · – not applicable.

| Screen | C1 | C2 | C3 | C4 | C5 | C6 | C7 | C8 | C9 | C10 | C11 | C12 | C13 | C14 | C15 | C16 | C17 | C18 | C19 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Onboarding 1 Goal | – | ✓ | ◐ | – | ✓ | – | – | – | ✓ | ✓ | – | – | – | – | ✓ | ◐ | ◐ | – | ✓ |
| Onboarding 2 Privacy | – | – | ◐ | – | ✓ | – | – | – | – | ✓ | – | – | – | – | ✓ | ◐ | ◐ | – | ✓ |
| Onboarding 3 Access | – | – | ◐ | – | ✓ | ✓ | – | ✓ | ✓ | ✓ | – | – | – | ✓ | ✓ | ◐ | ◐ | – | ✓ |
| Onboarding 4 Try dictation | – | – | ◐ | – | ✓ | – | – | – | ✓ | ✓ | – | – | – | – | ✓ | ◐ | ◐ | – | ◐ |
| Onboarding 5 First meeting | ✓ | – | ✓ | – | ✓ | ✓ | – | ✓ | ✓ | ✓ | – | – | – | – | ✓ | ◐ | ◐ | – | ✓ |
| Notes explorer | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ | ✓ | – | ✓ | ✓ | – | ✓ | ◐ | ◐ | – | ✓ |
| Empty notes | ✓ | ✓ | ✓ | ✓ | ✓ | – | – | – | – | ✓ | – | – | ✓ | – | ✓ | ◐ | ◐ | – | ✓ |
| Note, full window | – | – | ✓ | – | ✓ | – | – | – | – | ✓ | – | – | – | – | ✓ | ◐ | ◐ | – | ✓ |
| Recording (+ cannot hear the call) | – | ✓ | ✓ | ✓ | ✓ | – | – | – | – | ✓ | – | ✓ | – | ✓ | ✓ | ◐ | ◐ | – | ✓ |
| Dictionary | – | ✓ | ✓ | ✓ | ✓ | – | – | – | ✓ | ✓ | ◐ | – | ✗ | – | ✓ | ◐ | ◐ | – | ✓ |
| Settings: General | – | – | – | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | ✓ | – | – | – | – | ✓ | ◐ | ◐ | ✓ | ✓ |
| Settings: Dictation | – | – | – | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | ✓ | – | – | – | – | ✓ | ◐ | ◐ | ✓ | ◐ |
| Settings: Meetings & notes | – | – | – | ✓ | ✓ | ◐ | ✓ | ✓ | ✓ | ✓ | – | ✓ | ✓ | ✓ | ✓ | ◐ | ◐ | ✓ | ◐ |
| Settings: AI assistant | – | – | – | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ◐ | – | – | – | ✓ | ◐ | ◐ | ✓ | ✓ |
| Settings: Privacy & data (+ delete sheet) | – | – | ✓ | ✓ | ✓ | ◐ | ✓ | ✗ | ✓ | ✓ | ✓ | – | – | ✓ | ✓ | ◐ | ◐ | ✓ | ◐ |
| Settings: Add-ons (+ Quick search page) | – | ✓ | – | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ◐ | ✓ | – | – | ✓ | ◐ | ◐ | ✓ | ✓ |
| Settings: About & help | – | – | – | ✓ | ✓ | ◐ | ✓ | ✓ | – | ✓ | – | – | – | – | ✓ | ◐ | ◐ | ✓ | ✓ |
| Settings: search results | – | – | – | – | ✓ | – | – | – | – | ✓ | – | – | ◐ | – | ✓ | ◐ | ◐ | ✓ | ✓ |

What the ✗ and ◐ marks mean:

- **C8 ✗ Privacy & data** has 6 basic rows (3 permissions, 2 retention rows, Delete). **Accepted exception** (owner decision 3: one page, permissions included).
- **C13 ✗ Dictionary**: its empty state is not sketched yet (proposed: "Add names you use often, like clients and colleagues." + Add Word). Search with no results shows a hint but no action (◐). Follow-up: designed as a gallery scene in the main-window spec (#255 states table), not in this sketch.
- **C3 ◐ Onboarding 1-4**: one filled button, but "Continue" does not name a result (wizard convention; the last step says "Open Lintel"). Resolved by owner decision 5: each button names the step's result (wording in the onboarding spec, #254). Settings pages have no filled button on purpose (changes apply at once, as on macOS), hence "–".
- **C6 ◐**: self-explanatory rows have no help line (for example "Open Lintel when I log in", "Your name in notes", "What's new"); every help line that exists is under 15 words and describes the effect. Either the rule becomes "help where the label is not enough" or those rows get a line.
- **C11 ◐**: Dictionary's Remove, AI assistant's Remove… (downloads) and Quick search's Start Over need their confirmation or undo designed in the specs; only Delete my data is sketched (names the object and count, Cancel is the default, the destructive button says "Delete 42 Meetings").
- **C16 ◐ everywhere**: computed from the tokens, text is 4.6:1 or more and controls 3.1:1 or more in all four tone/theme combinations (after darkening the warning text to #8A4F00 and lightening dark red to #FFA8A0); Increase Contrast cannot be checked in HTML.
- **C17 ◐ everywhere**: every control is a real button or field with a visible focus ring, Esc and ⌘, work, Reduce Motion stops the ring and the typing; VoiceOver was not run.
- **C19 ◐**: links ("Change in Privacy & data ›", "Change shortcut") use the accent text colour in the sketch. Resolved by owner decision 4: links are neutral, Verdigris only on primary, selection and live state.
- **C12 ✓ explorer** covers the "notes not written" state; **C15 ✓** means no truncation in Polish at XL at the default window size (list titles wrap to up to 3 lines; panes scroll vertically).

## Validation plan

**Later, after the specs (owner decision 9: no test group now; cheap, no build):**

1. **Tree test, 20 tasks** (sidebar and page names as text only, no search), 5-8 people moderated first, then 30+ remote. Pass: at least 80 % success per task and at least 70 % correct first clicks. A task under the bar leads to a rename or a pointer row, never a second home. The most uncertain are tasks 2, 4, 10 and 18.

| # | Task | Expected place |
|---|---|---|
| 1 | Change my dictation shortcut | Dictation › Shortcut |
| 2 | Stop saving meeting recordings | Privacy & data › What Lintel keeps › Meeting audio |
| 3 | Turn on clipboard history | Add-ons › Clipboard history |
| 4 | Use my company's Claude for notes | AI assistant › Who writes your notes › Claude |
| 5 | Make Lintel spell a client's name right | main window › Dictionary (pointer in Dictation) |
| 6 | Delete all my meetings | Privacy & data › Delete my data |
| 7 | Lintel doesn't hear the others on Zoom | Privacy & data › Hear other people in a call (also the Meetings & notes status and the recording warning) |
| 8 | Dictate in Polish and English | General › Languages I speak |
| 9 | Stop Lintel changing my words | Dictation › Tidy up my text |
| 10 | Use my headset microphone | General › Microphone |
| 11 | Stop recording suggestions in Slack huddles | Meetings & notes › More options › Never suggest recording in |
| 12 | Get back clipboard items I cleared by mistake | Privacy & data › Recently deleted |
| 13 | Export all notes | Meetings & notes › Export all notes |
| 14 | Turn off the "tell people" reminder | Privacy & data › More options › Remind me… |
| 15 | Make the text bigger | General › Text size |
| 16 | Stop Lintel opening at login | General › Open Lintel when I log in |
| 17 | Open apps with a shortcut | Add-ons › Quick search |
| 18 | Free up disk space | AI assistant › More options › Downloaded files |
| 19 | Fix my name in meeting notes | Meetings & notes › Your name in notes |
| 20 | Report a bug | About & help › Send a problem report |

2. **Five-second test** on the notes explorer and the empty state (light, the person's language), five non-technical office workers, at least two Polish speakers: what does the app do, what would you click first, would you trust it with a client memo. Pass: 4 of 5 say "it types what I say and writes meeting notes".
3. **Warm vs neutral**: show both explorer screenshots side by side to the same five; record which feels "made for me" and which "looks like every other app".

**After the decision (in each track's own PR):** SwiftUI gallery snapshots of each screen in light and dark, M and XL, English and Polish; the 19-item checklist as the QA table before `needs-qa`; time from first launch to first dictation under 3 minutes in `--qa` runs; a VoiceOver walk of onboarding, the explorer and Settings.

## Follow-ups outside this PR

- **Invert the plugin defaults** (dictation and meetings on; apps, files, clipboard and windows off for new installs; existing users keep their values): code PR #251 with a BACKWARD_COMPATIBILITY review.
- **SwiftUI design gallery** (#248): tokens and the snapshot workflow; its Phase 1 and #251 land before the UI phases of the three specs below.
- **AI assistant as one choice**: an ADR and an additive contract for one shared assistant setting (today's three text-model pickers and two speech-model pickers), in the settings spec.
- **Settings rebuild spec** (`settings-ia-v2`, #253), written now (owner decision 9); update `.uxproof/conventions.md` with it, since today's conventions still prescribe the Models and Advanced panes.
- **Main window spec** (#255: explorer, recording, note tabs, failed state, Recently deleted, Dictionary) and **onboarding spec** (#254: steps, DMG window, permission helper), each citing this doc and the accepted sketch.
- A jargon gate: check C5 as a test over the basic-row strings in `Localizable.xcstrings`.

## Owner decisions (2026-11-24)

From the owner's comment on #247 (all nine open decisions of this revision), plus the retention decisions of the same day on #253. They win over older wording in this doc and over the sketch.

1. **Direction**: "Quiet Native with warmth" with the working ring as the brand signature, accepted.
2. **Tone**: warm neutrals (`tone=neutral` stays a sketch variant only).
3. **Privacy & data** stays one page, permissions included (the C8 exception).
4. **Links are neutral**; Verdigris only on the primary button, the selection and live state.
5. **Onboarding buttons name the step's result** (no plain "Continue").
6. **Mine vs AI as tabs**: Notes · My notes · Transcript.
7. **Default shortcuts**: dictation ⌥ Space, Record a meeting ⌃⌥M (as in #251); the user can record any shortcut in onboarding and at any time in Settings.
8. **Deleting** goes to **Recently deleted for 30 days** with Restore, plus an immediate **Undo** toast after every delete (no "This can't be undone." for a move to Recently deleted).
9. **Order of work**: no test group now; the specs are written now and the tree test and five-second test stay as the later validation plan above.
10. **Retention (#253, Q7)**: notes and transcripts are kept forever on new installs (existing installs keep their value, 90 days if none stored); the only retention choice in Settings is how long meeting audio stays on disk.
11. **Clipboard (#253, Q9)**: every delete, clipboard Clear included, goes to Recently deleted for 30 days, encrypted, with Restore and Undo; no exception.

Added scope for the installer (onboarding spec, #254): a designed DMG window (drag to Applications) and a floating helper with the Lintel icon to drag into the System Settings permission list.

**Where the sketch predates these decisions** (not redrawn; the gallery scenes of each spec are the source of truth): links in the accent colour (4); "Continue" on onboarding steps 1-4 (5); Record a meeting with "Set Shortcut" and no default (7); "This can't be undone." in the Delete my data sheet (8); a Dictations 30 days retention row and Notes and transcripts in More options (10); Dictionary source labels (#255 Q10).

**Still to settle across the specs**: where Recently deleted lives (one home: a main-window sidebar row in #255, a Privacy & data sub-page in #253) and whether bulk erasures, retention by age and the panel's ⌃X follow decision 11 (#255 Q2, Q3, Q13 say otherwise).

## Evidence limits

- Personas are assumptions; no user has seen the sketch.
- Competitor layouts come from help centres, changelogs and reviews, not from using the apps (see the research reports).
- The sketch is HTML, not SwiftUI: controls are drawn, Chrome may substitute fonts, and the window sizes (1000 × 640 main, 800 × 620 settings, 820 × 580 onboarding) are proposals.
- The audit checks layout facts, not meaning; C6, C7, C11-C14 and C19 were judged by eye. VoiceOver and Increase Contrast were not checked.
- Not sketched: the dictation HUD outside onboarding, the menu bar menu, the Dictionary empty state, confirmation sheets other than Delete my data, the add-on permission flow, and the Claude consent sheet.
