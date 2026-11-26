# Minimal HUD sketch (revision 1, 2026-11-25)

Before-and-after sketch for the owner's decision on the minimal HUD pills. Spec: `.ai/specs/2026-11-25-minimal-hud.md`. Brief: the owner's direction of 2026-11-25 (pills as minimal as Wispr Flow / Granola; problems only when they occur, one line).

**This is a sketch, not the source of truth.** After acceptance the SwiftUI gallery (#248) holds the look; this file is not updated afterwards.

## Open it

Open `index.html` in a browser (no server, no network). The header switches language (EN/PL), text size (S/M/XL), Reduce Motion, Increase Contrast and "Show hover details" (Always = every pill drawn in its hover state). Hover or tab into a pill to see what appears only on hover. Reload to reset.

## What is in it

- **Before:** the real HUD views from the debug build (`--qa-hud <plugin>:<state> --qa-appearance light --qa-snapshot`, en and pl). Only light: a snapshot cannot draw the dark glass (`docs/qa.md`). The #258 states (`recording-microphone-*`, `suggestion-*`, `dictation-recording-microphone-fallback`) are that PR's own screenshots (pl only), because #258 was not on `main` when revision 1 was drawn (it merged on 2026-11-25). States without a QA fixture say so.
- **After:** the proposed pill drawn in HTML on a sample desktop gradient, light and dark side by side. The glass is approximated with a CSS blur; the real material is judged in the app.
- Every state lists what stays, what goes and the owner decisions (OD-n) it depends on.

## Assumptions

- [ASSUMPTION A1] Sizes (32 pt at M, 88 / 120 / 360 pt widths) are proposals taken from the owner's direction, not measured from Wispr Flow. Check: owner review of the sketch and the Phase 1 gallery scene.
- [ASSUMPTION A2] Hover expansion works in a non-activating panel of a background app (spec R3). Check: Phase 1 spike.
- [ASSUMPTION A3] Users notice failures without the meters (spec Validation).
- All data (times, app names, device names) is fictitious.

## Known limits of the "before" images

- The light snapshot draws the red record symbol as a white circle (a `cacheDisplay` limit with multicolor symbols); the running app shows it red, as in the #258 screenshots.
- The meeting clock wrapping as "12:3 / 4" in some snapshots is the real bug fixed by the open PR #236.

## Verification: incomplete

- Static review passed: no external URL, script, font, storage or network; all images local; all data fictitious.
- Rendered from `file://` in headless Chrome for every combination of en/pl × S/M/XL × hover on/off, plus Reduce Motion and Increase Contrast; screenshots in `evidence/` (`en-m-*`, `pl-xl-hover-*`, `pl-s-reduce-motion-contrast-meeting`).
- Measured in the page: no pill line truncates in any combination; widest normal pill 376 pt (M, pl) / 415 pt (XL, pl), widest hovered 442 pt (M, pl) / 489 pt (XL, pl).
- Not done: an interactive keyboard and pointer walk through a browser provider (the Chrome DevTools session was in use by another agent) and a real phone-width check (headless Chrome does not render below 500 px). Query parameters (`?lang=pl&size=xl&hover=on&motion=on&contrast=on&only=<section>`) reproduce every screenshot.

## Revision 2 (2026-11-26): owner decisions

The owner decided OD-1 to OD-13 (spec, "Owner decisions"). Only two states of this sketch changed, as annotations, not a redraw: "First 8 s: consent reminder" now draws the plain recording pill (OD-6: the reminder is only in the meeting's window), and "Model loading / unavailable" has no hover line (OD-7: the app says it after the recording). The widths were measured again in headless Chrome: unchanged (widest normal 376 / 415 pt, widest hovered 442 / 489 pt, M / XL, pl). The `evidence/` images are from revision 1 and do not show these two states.

## Revision 3 (2026-11-26): review of PR #273

Text fixes only, no redraw and no new measurement: the Polish microphone-denied line now reads „Brak dostępu do mikrofonu” (as in the spec), the processing hover „Transkrybuję, zostały 3” (OD-9) and the suggestion button „Nagraj” (OD-10). `prototype.json` carries revision 3 and the current sha256 of `README.md` and `index.html`. The `evidence/` images are still from revision 1.
