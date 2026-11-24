# lintel-direction: one direction, "Quiet Native with warmth" (draft, revision 2, 2026-11-24)

Clickable sketch for the shared UX direction in `.ai/specs/research/2026-11-23-lintel-ux-direction.md`. Nothing here is accepted until the owner says so. Revision 1 (three directions A, B, C) is in the PR history.

- Files: `lintel.html` (styles, tokens for warm and neutral tone, light and dark) and `lintel.js` (copy in English and Polish, screens, interactions, the settings search index, the audit mode).
- Open: open `lintel.html` in a browser, or `cd .ai/prototypes/lintel-direction && python3 -m http.server 8766 --bind 127.0.0.1`.
- Screens: main window `explorer` (notes explorer), `empty`, `note` (full window), `rec` (recording), `dict` (Dictionary); `set` with `page=general|dictation|meetings|ai|privacy|addons|about` (and `quick` once the add-on is on); `onb` with `step=goal|privacy|access|try|meeting`.
- Query: `?screen=…&page=…&step=…&theme=light|dark&lang=en|pl&tone=warm|neutral&ts=m|l|xl&chrome=0`, plus states `tab=notes|mine|transcript`, `warn=1` (recording cannot hear the call), `more=1`, `sheet=delete`, `q=<settings search>`, `ai=claude`, `demo=listening|done`, `goal=both|dict|meet`, `addon=quick`.
- Clickable: Record Meeting → recording → Stop and Write Notes (the ring closes while the notes are written); sidebar filters and folders; notes, tabs, Open (or double-click a note); the gear or ⌘, opens Settings, Esc or the red light closes it; settings search with English and Polish synonyms (a result opens the page and highlights the row); switches, More options, the delete sheet, the AI assistant choice, add-on switches (an enabled add-on gets a page in the sidebar), Text size (M/L/XL rescales the whole sketch); onboarding goal choice (the steps adapt), Allow buttons, hold the button or ⌥ Space to dictate, Check call audio, Open Lintel (ends on the empty notes view).
- `audit=1` writes layout facts into `<pre id="audit">` (truncated or spilling text, filled primary buttons, jargon outside More options, small targets); the PR's foolproof checklist uses it.
- Data is fictional. Native controls are drawn, not real; fonts may fall back in Chrome.
