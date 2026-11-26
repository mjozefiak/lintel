# Meeting window Accessibility recon (spec step 0.2)

Spec: `.ai/specs/2026-11-25-meeting-speaker-names.md` (F0, step 0.2). Date: 2026-11-26. macOS 27.0.1 (Darwin 27.0.0),
Chrome 158.0.8127.88. Tool: `scripts/ax-recon`. **This note is partial: it answers the Chrome plumbing questions on
a fictional page and cannot answer the gate (a)–(d) for any real app. See "What the owner has to check".**

## What was done

No real meeting was used. A separate Chrome instance with a throwaway profile (`--user-data-dir` in a temp folder,
removed afterwards; the owner's Chrome was never queried) loaded a local page (`http://127.0.0.1` and `file://`) that
mimics a participant list: a `role=list` named "Participants", three fictional participants (Ala Testowa, Bob
Przykładowy, Celina Fikcyjna) and a per-participant `role=img` whose `aria-label` flips between "Speaking" and
"Not speaking" every second. Teams and Zoom are **not installed** on this Mac, so nothing was measured for them.

## Findings (Chrome 158, macOS 27, fictional page)

| Question | Result |
|---|---|
| Does Chrome expose the page tree to an AX client? | **Yes, without any flag.** A fresh instance whose first AX query was `AXWebArea` search / tree walk returned the page: `AXWebArea` → `AXList` ("Participants") → one `AXGroup` per participant (title and description = the name) → `AXStaticText` (the name) and `AXImage` (description "Speaking" / "Not speaking"). |
| `AXManualAccessibility` on the application element | **Cannot be set**: `AXUIElementSetAttributeValue` returns `-25205` (`kAXErrorAttributeUnsupported`) and the attribute reads back as unset. `AXEnhancedUserInterface` returns `-25208` (`kAXErrorNotImplemented`). The tree was complete anyway, so on this Chrome version the `chromeAXRestore` mechanism in the spec (Edge Cases) is not needed; it should be re-checked on the Chrome version the owner uses and on older Chrome versions before it is dropped from F2. |
| Which tabs are readable? | **Only the active tab.** With 10 tabs open, exactly one `AXWebArea` exists (the selected tab); background tabs have none. A Meet tab in a background window/tab is invisible to the reader. Recommendation: the reader returns nothing (state "meeting tab not in front") instead of switching tabs. |
| Finding the Meet tab by address (criterion d, first half) | **Works**: `AXWebArea` has `AXURL`; host extracted (`127.0.0.1`; `file://` has no host). A `meet.google.com` match needs only the host, no titles or page text. |
| Tab titles are visible in the tree | Yes (`AXTabButton` title) — real tab titles of the owner's other tabs would be readable by a careless walker. The reader must go straight to the `AXWebArea` and never walk the toolbar/tab strip (spec already says so); `ax-recon webareas` demonstrates that path. |
| Tree stability | The `AXImage` "Speaking" nodes appeared in the first walk only partly (one walk showed the participant but not the image, a later walk showed it): the first query after launch triggers building the tree, so a reader needs a short retry (about 1–3 s) at start. |
| Cost, whole-app walk at 1 Hz (410 nodes, trivial page) | Reader process: 0.24 s CPU in 20 s = **1.2% CPU**; one walk 74–78 ms median, 111–176 ms max. Chrome main process while being walked: 3.6–4.9% CPU (vs 0.1–1.8% idle, noisy baseline that included page load). **Not representative:** real Meet has thousands of nodes, video, and a different build; the numbers above are a lower bound. Scoping the walk to the active `AXWebArea` (not the whole application incl. its 290 menu items) is the first optimisation. |

## What this does and does not say about the gate

- (d) second half (`AXManualAccessibility` CPU +5 pp with 10 tabs, window-move budget, restore after `kill -9`): **moot on this Chrome**, because the attribute is not needed or settable; the cost of a client reading the tree remains to be measured on real Meet. Not measured: the Lintel window-management budget with a Chrome that has an AX client attached.
- (a), (b): **unknown for real Google Meet, Teams and Zoom.** A fictional page with hand-written `aria-label`s proves the transport, not that Meet's DOM (tiles, `aria-label`s, the speaking indicator is typically a CSS animation, not a label) carries names and a speaking flag, in gallery, speaker and screen-sharing views. I will not claim it from memory.
- (c): only the lower bound above.

## What the owner has to check (needs a real meeting with ≥ 4 people, or fictional-name test accounts)

1. Meet in Chrome: run `ax-recon webareas <chrome pid>` (host must be `meet.google.com`), then `ax-recon tree <pid> --window-index 0 --depth 30 --show-text` in a **test** meeting with fictional names, in gallery, speaker and screen-sharing views, without opening the participant panel. Look for the names and a changing node when somebody speaks.
2. Teams (new) and Zoom: install, same `tree` run; Zoom may need its own Accessibility setting.
3. `ax-recon sample <pid> 600 --hz 1` for ≥ 10 min in the meeting for (c); Activity Monitor average for the meeting app with and without sampling.
4. Check on the owner's Chrome version whether `ax-recon manual <pid> on` still returns `failed(-25205)`.

## Recommendation for F1–F3

- **F1 (names from conversation) does not depend on this recon** and can start now: it needs no Accessibility.
- **F2 (meeting window): conditional.** Plan the reader as "active-tab, `AXWebArea`-scoped, host-matched, no flag", keep `chromeAXRestore` as a contingency (implement only if the owner's Chrome needs the flag), and do not commit F2 for any app until step 1–3 above give (a)–(c) numbers on real Meet/Teams/Zoom. Until then F2's `supportedBundleIDs` stays empty by design (the port default).
- Reader must tolerate "Meet is not the active tab" as a normal state (no names, no error).
- **F3 (calendar) is independent** of this recon.
- The spec's open item "reader samples at 1 Hz" fits the measured cost for a scoped walk; a whole-app walk is not necessary.
