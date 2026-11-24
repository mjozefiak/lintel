# Lintel UX direction: revision 2 (PR #247)

Adopted plan for the 2026-11-24 revision round of PR #247 (the PR had no run plan). Goal from the owner's feedback of 2026-11-24 and three research reports (`~/.lintel-agents/2026-11-24/research-competitors-ui.md`, `research-foolproof-ui.md`, `research-settings-ia.md`).

## Goal

Replace the three visual directions with one, "A with the warmth of C", whose brand signature is the working ring. Make the notes explorer the main window, rebuild settings per the IA research, redesign onboarding, run the 19-item foolproof checklist on every sketched screen, and update the direction doc and the PR body.

## Non-goals

- No Swift, no settings keys, no `Localizable.xcstrings` changes (design-only PR).
- No change to plugin defaults in code (the inversion of add-on defaults is a follow-up PR with a BACKWARD_COMPATIBILITY review).
- No chat over notes and no post-meeting actions (prototype-first with the owner, separate track).
- No update of `.uxproof/conventions.md` before the owner accepts the direction.

## Assumptions

- Mine vs AI is shown as tabs (Notes / My notes / Transcript), not as per-line authorship marks, which the owner dropped on 2026-11-19.
- The settings sidebar is the research's 7 items; Dictionary lives in the main window.

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Sketch

- [ ] 1.1 One-direction sketch: main window (explorer, empty, note, recording, dictionary), settings (7 pages + search), onboarding (5 steps); drop A, B, C files

### Phase 2: Doc and evidence

- [ ] 2.1 Direction doc revision 2 (principles, glossary, IA, brand signature, onboarding, checklist results, tree test)
- [ ] 2.2 Screenshots on the evidence branch, foolproof table and PR body
