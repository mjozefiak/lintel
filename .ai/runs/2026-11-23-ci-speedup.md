# Execution plan: ci-speedup

Source doc: `~/.lintel-agents/2026-11-23/report-dev-flow.md` section 7 (points 7.1 to 7.3; not in the repository)

## Goal

Make `.github/workflows/ci.yml` faster without removing any test from CI and without changing the required
status check `Build, test and lint` (ruleset `main`).

## Scope

- `.github/workflows/ci.yml`: one Thread Sanitizer step instead of seven; `actions/cache` for `.build` and for the
  sanitizer's own scratch path; docs-only pull requests skip the Thread Sanitizer step.
- `scripts/ci-docs-only.sh` (new) + `scripts/tests/test_ci_docs_only.zsh` (new): the docs-only classifier and its tests.
- `Tests/LintelCoreTests/CIWorkflowTests.swift` (new): the TSan step still names every suite the seven steps named,
  keeps the watchdog, and the job name stays the required check.
- `AGENTS.md`: one sentence on what docs-only PRs skip.

## Non-goals

- No change to `release.yml`, `pages.yml`, the watchdog script, the validation gate or any test.
- No new job name, no branch protection or ruleset change.
- Report items 7.4 to 7.6 (test map, QA snapshots, batching pushes).

## Decision recorded

The brief suggested `paths-ignore` plus a stub job for docs-only PRs. Tests read the docs: `RepositoryNamesTests`
and `NoHomePathsInRepositoryTests` scan every tracked text file, `ChangelogTests` and `test_changelog.zsh` read
`CHANGELOG.md`, `LandingPageTests` reads `docs/index.html`, two suites read `BACKWARD_COMPATIBILITY.md`. A stub would
drop exactly the tests a docs PR can break, which the brief forbids ("must not drop any test from CI"). So docs-only
PRs keep the job, the build, the plain `swift test`, the script tests and the lint, and skip only the Thread
Sanitizer run: every TSan test also runs in the plain `swift test`, and a docs change cannot add a data race. The
required check always runs, so no stub is needed.

## Implementation Plan

### Phase 1: Workflow

- 1.1 Combine the seven TSan steps into one `swift test --sanitize=thread` with the union of the filters, under the
  watchdog, in its own scratch path `.build-tsan`.
- 1.2 Cache `.build` and `.build-tsan` with `actions/cache` (pinned by commit), keyed on the toolchain
  (`xcodebuild -version` + `swift --version`) and `Package.resolved`.
- 1.3 Docs-only classifier script with script tests; the TSan step and its cache skip on docs-only PRs.

### Phase 2: Guard and docs

- 2.1 `CIWorkflowTests` (Swift) on the text of `ci.yml`.
- 2.2 AGENTS.md sentence.

### Phase 3: Measure

- 3.1 Before/after job times from `gh run list` / `gh run view` (cold and warm cache) in the PR body.

## Risks

- Tests from different suites now run in one TSan process at the same time: a timing-sensitive test could flake.
  Mitigation: run the combined filter locally under TSan before pushing, and watch the PR runs.
- Cache size (`.build` is about 2.7 GB locally): download time can eat the gain; measured in 3.1, reported as is.
- A docs-only PR whose change only matters under TSan: impossible for the classified paths (docs, `.ai/`, Markdown
  outside `Sources/`, `Tests/`, `Packages/`, `Resources/`, `scripts/`); pushes to `main` always run everything.

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Workflow

- [x] 1.1 One TSan step with the combined filter — ebebc365
- [x] 1.2 Cache .build and .build-tsan — ebebc365
- [x] 1.3 Docs-only classifier and TSan skip — ebebc365

### Phase 2: Guard and docs

- [x] 2.1 CIWorkflowTests — 6861fa66
- [x] 2.2 AGENTS.md sentence — 6861fa66

### Phase 3: Measure

- [ ] 3.1 Before and after timings in the PR body
