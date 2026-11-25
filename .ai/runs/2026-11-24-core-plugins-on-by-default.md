# Execution plan: core plugins on by default

Owner decision 2026-11-24: notes and dictation are the core, the launcher, file search, clipboard history and window
management are add-ons, off by default. Evidence: `research-foolproof-ui.md` (violation 1) and
`research-settings-ia.md` (recommendation 1) in the owner's 2026-11-24 research folder.

## Goal

A new install gets Dictation and Meetings on and Apps, Files, Clipboard and Windows off; every existing install keeps
exactly the plugins it had.

## Scope

- `defaultEnabled`: `DictationPlugin` and `MeetingsPlugin` `true`; `AppsPlugin`, `FilesPlugin`, `ClipboardPlugin`
  `false` (they relied on the contract default `true`). `WindowsPlugin` stays `false`. `NotesPlugin` has no toggle
  (`canBeDisabled: false`), nothing to change.
- `PluginDefaultsMigration` in `LintelApp/Migration/`: runs once before the host reads `plugins.<id>.enabled`. On an
  existing install (the data root already holds `ranking.sqlite`, or the welcome screen was already answered) it
  writes the old effective value for every flipped plugin that has no stored value. A fresh install writes nothing
  but the marker. The marker `app.pluginDefaultsMigrated` makes it run once, so a fresh install's second launch is
  not mistaken for an old one.
- Runs in `AppEnvironment.live` and `.qa`, before `openRanking` creates the ranking file.
- Welcome screen: the first page's text leads with the core (en + pl). The Full Disk Access step already appears only
  while Files is enabled (steps come from active plugins); the Dictation and Meetings steps now appear on a fresh
  install. Tests for both.
- `BACKWARD_COMPATIBILITY.md` §3 (the new marker key, the changed defaults and the migration) and `AGENTS.md`.

## Non-goals

- `plugins.meetings.notesEnabled` (AI notes after a meeting) stays `false`: turning it on by default sends
  transcripts to a notes provider, a privacy default that needs its own owner decision.
- No Settings reorganisation (sidebar, Add-ons page) from `research-settings-ia.md`.
- No change to the default main shortcut or to the panel.
- `LintelKit`'s `PluginManifest` default (`defaultEnabled = true`) stays: changing a contract default is out of scope.

## Implementation Plan

### Phase 1: Defaults and migration

1.1 `PluginDefaultsMigration` with tests (fresh install, existing install without values, existing install with
stored values, runs once, a fresh install's second launch).
1.2 Flip the manifests and update the manifest tests.
1.3 Run the migration at launch (live and QA) before the ranking file is created, with a test.

### Phase 2: Welcome screen

2.1 First-page text leads with the core (String Catalog en + pl) and welcome-flow tests for the new defaults.

### Phase 3: Docs and QA

3.1 `BACKWARD_COMPATIBILITY.md` §3 and `AGENTS.md`.
3.2 Manual QA: debug app with `--qa…`, first launch for a fresh and an existing profile, light and dark.

## Risks

- Found in QA: with the add-ons off the main shortcut opens a panel that finds nothing, so the welcome screen skips the
  Shortcut page (and the final page does not name the shortcut) while no active plugin has search sources. Whether the
  main shortcut should be registered at all in that state is left to the owner.

- `risk-high`: a protected settings contract (`plugins.<id>.enabled`). Mitigation: the migration is tested on every
  path and runs before any read; existing installs are detected by two independent signals.
- A user who installed but never launched past the very first moment (no `ranking.sqlite`) counts as new. Acceptable:
  `ranking.sqlite` is created on every launch since v0.1.

## Progress

PR: #251

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Defaults and migration

- [x] 1.1 PluginDefaultsMigration with tests — 6aa2a152
- [x] 1.2 Flip the manifests and update the manifest tests — 6aa2a152, d78d05e2
- [x] 1.3 Run the migration at launch before the ranking file is created — 6aa2a152

### Phase 2: Welcome screen

- [x] 2.1 First-page text and welcome-flow tests for the new defaults — 654bf669, c66a6484

### Phase 3: Docs and QA

- [x] 3.1 BACKWARD_COMPATIBILITY.md and AGENTS.md — 86d7be57
- [x] 3.2 Manual QA with screenshots — evidence branch `qa-evidence-pr-251`

### Phase 4: Owner decision 1 (main shortcut only while a plugin searches)

- [x] 4.1 Register the main shortcut only while an active plugin has search sources, with tests — c7223070
- [x] 4.2 Docs (AGENTS.md, docs/qa.md, BACKWARD_COMPATIBILITY.md §5, CHANGELOG) — c7223070, 7f916a1a
- [x] 4.3 QA screenshots of the changed behaviour — evidence branch `qa-evidence-pr-251`, folder `pr-251/r2/`
