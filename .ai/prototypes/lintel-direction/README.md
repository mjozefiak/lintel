# lintel-direction: three visual directions (draft, 2026-11-23)

Sketches for the shared UX direction in `.ai/specs/research/2026-11-23-lintel-ux-direction.md`. Nothing here is accepted; the owner picks one direction.

- Files: `a-quiet-native.html`, `b-paper-and-ink.html`, `c-friendly-guide.html`. Each shows the same three screens: onboarding step 4 "Try it", main window Home, Settings → Dictation. `shared.js` holds the copy (English and Polish), state and interactions; `shared.css` the switcher bar.
- Open: open a file in a browser, or `cd .ai/prototypes/lintel-direction && python3 -m http.server 8766 --bind 127.0.0.1`.
- Query: `?screen=onb|home|set&theme=light|dark&lang=en|pl&chrome=0&demo=done|listening&more=1`.
- Clickable: hold the button or ⌥ Space on "Try it" (listening, then the email types itself), Continue, Start Recording / Stop, Hide checklist, Settings sidebar, switches, More options.
- Data is fictional. Native controls are drawn, not real; fonts may fall back in Chrome (see the doc's Evidence limits).
