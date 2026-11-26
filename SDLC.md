# Software delivery process

## Purpose

This file documents how work flows from ticket to merged PR in this repository. The agent skills configured in `.ai/agentic.config.json` enforce the process; humans read it here. PRs target `main`; issues and PRs live in GitHub (tracker `github`), with every tracker operation the skills run defined in `.ai/trackers/github.md` (edit that file to extend or override tracker behavior).

The skills themselves are Open Mercato's `open-mercato/skills`, installed unmodified in `.agents/skills/` (with relative symlinks in `.claude/skills/`) and pinned by `skills-lock.json`. This repository does not override them: there are no files under `.ai/skills/` and no edits to a skill. Repository rules live in `.ai/agentic.config.json`, in the Conventions of the tracker descriptor `.ai/trackers/github.md` and in this document. To update the skills run `npx skills update -p`, then `/om-apply-upgrade-notes`, and commit both.

Work enters through two paths: a free-form task brief handed to an agent, or a filed ticket. Both converge on the same review loop, the same validation gate, and the same merge gates.

Before intake, the work is shaped: `om-brainstorm` turns a single idea or question into a routing decision and a brief, and the spec skills (`om-spec-writing`, `om-auto-write-spec`) turn a feature into a design document before anything is built. Those steps feed the table below; they are not the ticket flow itself.

## Roles

Lintel is built by one owner with agents. Three roles, no more:

- **Author agent** — writes the change (`om-auto-create-pr`, `om-auto-implement-spec`, `om-fix`, …) and owns it from claim to a merge-ready PR, including the QA evidence (debug build, `--qa` launch arguments, screenshots in light and dark mode).
- **Reviewer agent** — reads the diff with `om-auto-review-pr` / `om-code-review`, preferably on a different model than the author. It is also the "second review" a `risk-high` change needs (the evidence table below still applies).
- **Owner** — queues PRs for `automerge` (approving the triage list in one move), applies `qa-approved` on the human QA lane, decides open questions (`state:needs-decision`) and design decisions, and maintains the label taxonomy, the config, this document and the tracker descriptor. Referenced by role, never by handle.

## Ticket lifecycle

| Stage | What happens | Driven by | Done when |
|---|---|---|---|
| Discovery | An idea, question, or itch is talked through before any artifact exists: the problem is questioned, alternatives (including building nothing) are weighed, and the conversation ends in a routing decision — an answer, a filed ticket, a brief for a spec, or a direct change. | `om-brainstorm` or a human | Conversation routed; a brief written when the work continues |
| Intake | A ticket or task brief is filed in GitHub with enough detail to act on: what is wrong or wanted, for whom, and what done looks like. `om-prepare-issue` files it with one `type:*`, one `area:*`, at most one `state:*` and, once triaged, a milestone (see "Issues: labels and milestones"). | Anyone, `om-prepare-issue` | Ticket exists |
| Triage | Confirm the issue is real, still unfixed on `main`, and not already claimed or covered by an open PR. Read-only; stops the chain cleanly when there is nothing to do. | `om-verify-in-repo` or a human | Confirmed actionable, or closed as no-action |
| Claim | The author claims the ticket so concurrent agents back off. See the claim protocol below. | `om-fix` / `om-auto-create-pr`, or a human | Claim visible on the ticket |
| Design | For a user-facing change, the flow and its states are settled before the code exists: what the screen does when empty, loading, in error, and without permission, and what the change deliberately does not do. Detailed screens may be designed from the specification with repository components; only an accepted version becomes its `Prototype:` reference. A ticket that touches no UI skips this stage. | `om-ux-shape`, optionally `om-ux-design` when chosen, or a human designer | The flow and its states are decided, or the ticket is not user-facing |
| Implement | Locate the minimal change surface (`om-root-cause`, read-only), then implement the change with regression tests and run the validation gate. Task briefs without a ticket go through `om-auto-create-pr`, which plans, implements phase by phase in an isolated worktree, and runs the same gate. | `om-root-cause` + `om-fix`, `om-auto-create-pr`, or a human author | Change complete, validation gate green |
| PR | Commit, push, and open a PR against `main` with normalized labels. On a hand-worked branch, `om-check-and-commit` runs the gate, fixes obvious drift, and pushes when green. | `om-open-pr`, `om-auto-create-pr`, or `om-check-and-commit` | Open, labeled PR |
| Review loop | The reviewer reads the diff against the `om-code-review` checklist and approves or requests changes. Requested changes are addressed (`om-auto-continue-pr` resumes agent PRs from the tracking plan, and adopts a PR that has none by reconstructing the plan from the PR's own context) and the PR is re-reviewed until approved. A user-facing change also gets a design pass: `om-ux-review-pr` walks the changed screens and reports findings ranked by user impact. That pass is advisory — it informs the review, it does not hold the merge. | `om-auto-review-pr` (single PR), `om-review-prs` (sweep), `om-ux-review-pr` (design pass), or a human | Approving review submitted |
| QA | `om-auto-review-pr` triages every PR into a QA lane (none: `skip-qa`; auto: `needs-qa`; human: `needs-human-qa`). The author agent runs the debug build with the `--qa` launch arguments and records the evidence in the PR's single QA comment. On the auto lane an agent applies `qa-approved` when the three conditions in the QA gate below hold; on the human lane the owner looks at the evidence (and the app) and applies `qa-approved`, or `qa-failed` to send it back. A flow worth keeping becomes `om-integration-tests` coverage. See the QA gate below. | Author agent (evidence), reviewer agent (independent review), owner (human lane) | `qa-approved` applied under the rules of the QA gate; `qa-failed` routes it back |
| Merge | `om-auto-merge-triage` proposes the PRs that are ready for the queue, the owner approves the list in one move and the `automerge` label is applied to each. `om-auto-merge-buddy` (mode `prepare-and-merge`, scheduled) then works the queue until review, QA and CI hold on the current head and squash-merges with a head-SHA guard. `om-merge-buddy` reports read-only and `om-approve-merge-pr` merges one PR by number when the owner asks. | `om-auto-merge-triage` + owner, `om-auto-merge-buddy`, or `om-merge-buddy` + `om-approve-merge-pr` | PR squash-merged into `main` |
| Post-merge housekeeping | Close issues the merged PR fixes; comment on issues whose PRs were closed without merging. Only a real bug found along the way becomes a new issue; review nits are never filed (see "Review findings and follow-ups"). | `om-close-fixed-issues`, `om-followup-issue-from-pr` (real bugs only) | Tracker reconciled |

After merge, this process stops. Deployment, smoke tests, monitoring, and rollback belong to the repository's release process, not to this document: the owner drafts the changelog with `om-auto-update-changelog` and reconciles the tracker with `om-close-fixed-issues`, and `om-pipeline-retro` reads finished runs to rank what second passes cost. Merge is where this document ends; delivering the change to users is a separate process the team owns (for releases, the owner's runbook is `docs/releasing.md`).

## Labels

The taxonomy follows the Open Mercato pipeline (owner decision of 2026-11-26, which returned to the upstream pipeline labels that the 2026-11-23 migration had retired). The repository's own `type:*`, `area:*` and `state:*` labels stay: issues carry what the work is and where it stands, PRs carry what a gate reads. The repository config (`.ai/agentic.config.json`, `labels`) holds the same lists; the tracker descriptor (`.ai/trackers/github.md`, `ensure-label-taxonomy`) creates every label with its colour and description.

| Group | Labels | On | Exclusivity | Meaning |
|---|---|---|---|---|
| Type | `type:bug`, `type:feature`, `type:chore` | issues and PRs | exactly one | The upstream "category" (`labels.category`). `type:chore` covers docs, refactors, CI, dependencies and tooling. The tracker descriptor maps the upstream names a skill uses (`bug`, `feature`, `refactor`, `documentation`, `dependencies`) onto these. |
| Area | `area:dictation`, `area:meetings`, `area:notes`, `area:app` | issues and PRs | one, two when it truly spans | Where it lives. `area:app` is the shell, launcher, Files/Apps/Clipboard, Windows, release, CI and QA tooling. |
| State | `state:idea`, `state:needs-decision`, `state:agent-ready` | issues | at most one | Where the issue stands. |
| Pipeline | `review`, `changes-requested`, `qa`, `qa-failed`, `merge-queue`, `blocked`, `do-not-merge` | PRs | at most one | Where the PR sits in the flow. Skills set `review`, `changes-requested` and `merge-queue`; only a tester sets `qa`; `blocked` and `do-not-merge` are the owner's hard blocks. |
| QA | `needs-qa`, `needs-human-qa`, `skip-qa`, `qa-approved`, `qa-self-verified` | PRs | `skip-qa` never with a QA request | The QA gate (below). `needs-human-qa` is `qaGateLabel`: the gate keys on it. |
| Claim | `in-progress`, `ci-monitoring`, `claim-reset` | issues and PRs | — | `in-progress` is the claim (protocol below); `ci-monitoring` is not a claim; `claim-reset` is the owner's recovery label. |
| Risk | `risk-low`, `risk-medium`, `risk-high` | PRs | exactly one; unset = medium | Blast radius; `risk-high` triggers the evidence table. |
| Merge queue | `automerge`, `automerge-now`, `automerge-force`, `automerge-prepare`, `automerge-blocked`, `automerge-signal-1-cr`, `automerge-signal-2-qa`, `automerge-signal-3-ci`, `automerge-signal-3-passes-local-ci-checks` | PRs | — | `automerge` is the owner's queue label for `om-auto-merge-buddy`; the signal labels are the buddy's record of review, QA and CI on the current head; `automerge-blocked` parks a PR the buddy cannot finish until a human clears it; `automerge-now` + `automerge-force` and `automerge-prepare` are the owner's per-PR overrides (see `om-auto-merge-buddy`). |
| Exceptions | `security`, `do-not-close`, `cez-autofix` | issues and PRs | additive | `security` feeds `CODE_REVIEW.md` and automerge eligibility; `do-not-close` (humans only) keeps housekeeping skills from closing an issue; `cez-autofix` (the upstream default `autofix.label`) marks an issue the owner confirmed for `om-auto-issue-triage`. |

Priority is the milestone, not a label: `priority-*` labels are never applied (the tracker guards turn them into a no-op) and the old `priority-low` and `priority-high` labels stay in the repository untouched. The old `state:in-progress` label is no longer a claim: it stays in the repository and means nothing; the owner removes it from open items that still carry it.

**No label-rationale prose.** Agents apply and change labels without a comment explaining why (the one exception is the machine-readable `<!-- qa-triage v1 -->` block of `om-auto-review-pr`, which the human QA lane reads); the run's summary comment may name the labels in one line. When risk signals conflict, pick the higher label and say why in the PR body.

### Issues: labels and milestones

- Every open issue has one `type:*` and one `area:*`. A triaged issue has a milestone: `beta.2` (needed for the next beta) or `later`. The milestone is the priority; there are no priority labels.
- `state:idea` — not decided whether to build it. `state:needs-decision` — waits for the owner, with the options and a recommendation in the issue. `state:agent-ready` — specified enough for an agent to pick up.
- Umbrella issues collect small related work as a checklist instead of one issue each. A flaky test is a new line in the open "Flaky tests" umbrella issue (#240), not a new issue, unless it already has a known cause and a fix plan.

### Risk

When no risk label is set, infer one:

- `risk-high` — authentication and login sessions, data scoping, money, schema migrations, shared contract surfaces, or broad cross-cutting edits. In Lintel that means in particular: the plugin contract in `LintelKit` (`LintelPlugin` and everything it exposes), the target dependency graph in `Package.swift`, the on-disk formats (`ranking.sqlite`, `Plugins/clipboard/clipboard.sqlite`, `Plugins/files/index.snapshot`), their migrations, the `Plugins/<id>/` paths and the `<plugin id>:<key>` item keys, anything touching clipboard encryption, the Keychain key or TCC permissions, and the code-signing identity or release workflow.
- `risk-medium` — an ordinary single-area change that ships with tests (also the default reading of unset).
- `risk-low` — docs-only, test-only, typo, or isolated cosmetic changes.

A `risk-high` PR is not merely advised to get more scrutiny; it triggers gates:

| Area behind `risk-high` | What the PR must carry |
|---|---|
| Auth, sessions, permissions | an integration test for the denied path and the wrong-scope read; a second review by the reviewer agent |
| Data scoping | an isolation test proving one scope cannot read another |
| Money | tests for the failure, retry, and idempotency paths; a second review by the reviewer agent |
| Schema migrations | a migration test up and down, and a rollback plan in the PR body |
| Shared contract surfaces | the consuming side exercised, per `BACKWARD_COMPATIBILITY.md` |
| Plugin contract (`LintelKit`: `LintelPlugin`, `SearchSource`, `ResultAction`, `PluginContext`, …; `PluginRegistry` / `PluginHost`) | every in-tree plugin still compiles and passes its tests; `PluginHost` tests pass under `--sanitize=thread`; the change is additive or follows the exception path in `BACKWARD_COMPATIBILITY.md` §1 |
| Clipboard storage, encryption keys, Keychain | tests for every Keychain error path (locked, denied, not found) and for "the key is never lost silently"; a second review by the reviewer agent |
| Code signing identity, entitlements, TCC permissions | proof that two consecutive builds keep the same designated requirement (`codesign -dr -`), and a manual check that Accessibility / Full Disk Access survive an update |
| Any `risk-high` | `needs-qa` when user-facing; `om-code-review` blocks without the evidence above unless the owner waives it on the PR |

## The QA gate

The one hard rule of this process: **a PR carrying the gate label (`needs-human-qa`, or `needs-qa` while no narrower label is set) must not merge until it also carries `qa-approved`, even when every other check is green.** `om-merge-buddy` classifies such a PR as blocked; `om-approve-merge-pr` refuses to merge it.

- **Lanes (set by `om-auto-review-pr` triage on every review).** *None*: `skip-qa`, nothing user-visible to exercise (docs, tests, CI configuration, tooling, a runtime change with tests and no visible effect). *Auto*: `needs-qa`, a user-visible change an agent can exercise and judge. *Human*: `needs-human-qa` (and `needs-qa` until the owner answers), which the owner alone clears. The configuration that sets the human lane is `humanQaPolicy` and `automerge.humanOnlyLabels` in `.ai/agentic.config.json`: any PR labelled `risk-high` or `state:needs-decision`; any PR that changes a file in the high-risk set (`Package.swift`, `Package.resolved`, `Packages/`, the plugin contract in `Sources/LintelKit/`, `Sources/LintelPersistence/`, `PluginRegistry.swift`, `Sources/ClipboardPlugin/`, `Info.plist`, the entitlements and the signing and release scripts and workflows); and, from the built-in triage rules, a new screen, flow or visible layout change without a design approved in a spec already merged to `main` (a design decision belongs to the owner), a change that lowers a safety control or takes data away, and anything triage is unsure about (`whenUnsure: human`).
- Apply `needs-qa` to UI changes, new features, and other user-facing behavior that needs manual exercise. A docs-only, dependency-only, CI-only or test-only PR simply does not carry it.
- For a UI change, QA covers more than "it works": the state matrix (default, empty, loading, error, no-permission, long content, narrow viewport) is part of the pass/fail, and so is conformance to the accepted prototype and the design contract in `.uxproof/` when the repository has one. A missing state fails QA. `om-ux-review-pr` remains the advisory design review; its objective checks are the ones QA runs.
- `qa-failed`, `do-not-merge`, and `blocked` are hard blocks regardless of every other signal. `qa-failed` is set by the owner (or by `om-auto-qa-pr --apply-failure`) and cleared only by the owner, normally together with the `qa-approved` for the fixed head; no skill clears it.
- **Who applies `qa-approved` (owner decision of 2026-11-26).** On the auto lane an agent may apply it when all three hold on the final head: (1) an independent `om-auto-review-pr` review, run in a fresh context on an Opus-class model, is approved; (2) the agent's own QA with screenshots in light and dark mode on that head is recorded in the PR's single QA comment, with the `QA head:` line and a list of what was not exercised (a real microphone, a real meeting); (3) CI is green. On the human lane, and for every PR that carries a design decision, a `risk-high` label or `state:needs-decision`, only the owner applies it. The tracker descriptor no longer refuses the label; the rule above is the guard.
- **What cannot be written in configuration.** `om-auto-qa-pr` and the QA stage of `om-auto-merge-buddy` drive a browser provider, and Lintel is a native app, so they cannot exercise it. "Opus in a fresh context" and "screenshots of the running native app" are therefore rules for the author agent and the reviewer, not something a setting enforces. The buddy's QA signal forms for a native change only from a pinned `qa-approved` (the `QA head:` line); a PR that has none stays out of the merge until someone provides it, and the buddy parks it with `automerge-blocked` after its attempts. The agent that opens a UI PR does the native QA and the labels before the PR is queued.
- **One QA comment per PR, edited in place.** The author agent keeps all QA evidence in a single PR comment: the scenarios exercised, the screenshots (light and dark, plus the relevant states), the negative cases tried, and the `QA head: <sha>` line for the tested head. Each new QA round rewrites that comment (tracker operation **update-comment**) instead of posting another one, and says which round it is.
- **How QA runs in this repository.** Lintel is a native macOS app, not a web app, so the browser provider (`agent-browser`, `.ai/browsers/agent-browser.md`) is used for the GitHub Pages landing page only. The native app is QA'd by building and running it locally (`CONFIGURATION=debug scripts/make-app.sh`, `--qa…` launch arguments, `docs/qa.md`) and attaching screenshots of the running app (light and dark mode, plus the relevant states from the spec: indexing, no results, clipboard access denied, paste disabled, recording paused, Keychain locked, feature unavailable for a plugin in `failed`) as PR evidence. Tests that need Accessibility or Full Disk Access, UI tests and performance benchmarks cannot run on GitHub runners (no TCC grants, noisy shared VMs); they run locally and their results go into the PR body.
- **`qa-approved` is pinned to a commit.** The QA comment carries the line `QA head: <sha>` for the head that was approved. A push after that line leaves the label in place but stales it: `om-merge-buddy` reports "QA evidence older than head", and `om-approve-merge-pr` asks for confirmation before merging. The way back is a new QA round on the new head under the rules above.
- **Exception for test-only commits and `main` merges (owner rule of 2026-11-20).** An existing `qa-approved` stays valid after a new commit only when all three hold: (1) the commit changes only tests (`Tests/**`) or is a mechanical merge of `main` — no file in `Sources/`, `Resources/`, workflows, scripts or `Package.swift`; (2) proof that the app code is identical to the approved head (a matching `git patch-id`, or an empty diff of `Sources/`, `Resources/`, `.github/workflows/` and `scripts/`) is posted on the PR; (3) an independent Opus reviewer confirms (1) and (2) and the required CI check is green. A commit that removes, disables or weakens a test (instead of repairing it) always goes back to the owner. Any other commit after approval needs a new `qa-approved` under the rules above.
- **`risk-high` gets no shortcuts.** A PR labeled `risk-high`, or one whose diff touches auth, sessions, data scoping, money, schema migrations, or shared contracts (the `risk-high` inference above), carries the evidence from the table above and goes to the owner's human lane; `om-code-review` blocks without the evidence unless the owner waives it on the PR. `om-auto-qa-pr --self-qa-signoff` is never used on such a PR.

## The claim protocol

Before mutating an issue or PR, an agent claims it. GitHub ownership is the create-only ref `refs/om-locks/{kind}-{number}` (tracker operations **get-lock**, **acquire-lock**, **release-lock**): the run that creates it proceeds, the others back off, and a run releases it last, after the guarded `in-progress` label and the `🤖` claim comment are cleaned up. The `in-progress` label is the mandatory second check; the claim comment carries `Claim-Run`, `Claim-Actor`, `Claim-State`, `Claim-Lock` and `Claim-Lock-SHA`. Lintel has one GitHub account for the owner and the agents, so the claim tells runs apart by run id and lock, never by login. Any agent that finds a live claim backs off instead of colliding, and the merge tooling skips an item that carries `in-progress`.

`in-progress` means **actively working**. A run that finished its work and reported it, but still owes the CI-result follow-up, swaps `in-progress` for `ci-monitoring`; that label is not a claim and blocks nobody. Both are released when the work ends, on success and on failure alike.

**Recovery.** A stalled claim is retired by stopping the runner and adding the human-only `claim-reset` label in GitHub: the next run audits that event and competes for a new lock. Removing `in-progress` alone does not clear a lock. The `refs/om-locks/*` refs are created and deleted with the owner's account through git over HTTPS (`gh auth git-credential` with the Lintel `gh` configuration); a stalled lock may also be deleted by the owner with `git push origin :refs/om-locks/<kind>-<number>`.

### Reporting is decoupled from CI

Agents apply labels, submit reviews, and post comments **as soon as their work is done**, without waiting for CI to go green. A review submitted while checks are still running says so in its body: branch protection plus the QA-approval gate hold the actual merge, and the approval covers the code, not a green run. When the agent follows up, the CI outcome is added to its existing summary comment (edited in place), which also states if the result changes the verdict.

The wait for that outcome is bounded by `ci.maxWaitMinutes` (default 40), and the agent holds `ci-monitoring` while it waits. When it expires with checks still running, the agent stops waiting, runs the local validation gate as its own evidence, records that together with the still-pending check names and an explicit statement that no further follow-up is coming, and finishes.

A red signal does not short-circuit the review either. A failing required check or a conflicted head is collected as a **blocker finding** and reported together with the full code review, never instead of it: one review cycle gives the author the failing check, the conflict, and every code finding at once, rather than the cheapest red flag first and another cycle to discover the rest. Such a verdict is still `changes-requested` — completeness changed, the gate did not.

None of this touches the merge gates. Reporting early is safe; merging early is not — required checks still gate every merge, and the merge tooling refuses until they are genuinely green.

## Review findings and follow-ups

- **A nit or non-blocking finding is fixed in the same PR or dropped.** It is never filed as a new issue, never parked in a "follow-up" list and never turned into a tech-debt ticket. The summary comment lists what was dropped in one line, so the owner can object.
- **Only a real bug becomes a new issue** (`type:bug`, an `area:*`, a milestone once triaged): a defect a user could hit that is out of the PR's scope. One issue per bug, written so an agent can act on it.
- **A flaky test goes into the "Flaky tests" umbrella issue (#240)** as a checklist line with the test name, the CI run and what is known, not into a new issue.
- Skills that would file follow-ups for nits (`om-auto-fix-pr`, `om-approve-merge-pr`, `om-followup-issue-from-pr`) apply these rules; the tracker descriptor states them as repository process rules.

## The automation contract

The `om-auto-*` skills run this process unattended and are chainable: each accepts the artifact the previous one produced (an issue id, a spec path, or a PR number from the `PR: #<number> (link: <url>)` reference line every PR-producing skill emits), and each detects work already started — an open PR referencing the issue or plan — and continues on it rather than opening a duplicate. A completed autonomous run leaves a **ready** (non-draft) PR labeled with the `review` pipeline label, one `type:*`, its `area:*`, one risk label and the QA label of its lane when user-facing — no priority label (the issue's milestone is the priority) and no label-rationale prose — with one run-summary comment and, for user-facing changes, the single QA comment with screenshots from the working app. Draft PRs are reserved for explicitly incomplete states: spec-only design PRs, interrupted hand-offs, or autonomous defaults flagged for human confirmation. `qa-approved` follows the rules of the QA gate: no authoring skill applies it on its own.

## Validation gate

Every PR passes the full validation gate before review sign-off, in this order:

1. `swift build`
2. `swift test`
3. `swift format lint --strict -r Sources Tests`

> **Live since Phase 0** (`feat/scaffold`). The gate applies to every PR that touches Swift code, `Package.swift`, `Package.resolved` or `Packages/`. Docs-only PRs (process docs, specs, `.ai/` config) record "validation gate not applicable: docs-only" in the PR body instead of a gate result.
>
> CI (`.github/workflows/ci.yml`) runs `swift build`, `swift test`, the `PluginHost` tests under `--sanitize=thread` and `swift format lint --strict -r Sources Tests` on every PR; `.github/workflows/release.yml` additionally builds and signs the DMG for PRs that touch the app. The implementing skills still run the gate locally before a PR is opened.

Any non-zero exit fails the gate and blocks the PR. The implementing skills run the gate before opening a PR, and `om-check-and-commit` runs it before pushing a hand-worked branch. The command list lives in `.ai/agentic.config.json`; when it changes, update it there and in this section together.

## Amending this process

This document and `.ai/agentic.config.json` describe the same process: change them together, and re-run the `om-setup-agent-pipeline` skill when the toolchain or label taxonomy changes.

The design contract the Design and Review stages read is set up once: `om-ux-setup` extracts it from the repository and is re-run when the design system changes.

Per-skill deviations are **not** made in this repository: the skills stay as installed (see Purpose), so an upstream update never has to be merged into a local copy. A rule the installed skills must follow goes into the configuration (`.ai/agentic.config.json`), into the Conventions of `.ai/trackers/github.md` or into this document. The repository's `main` is protected by the ruleset "main" (a PR is required, squash only, the check "Build, test and lint" must pass, no approving review is required and nobody can bypass it), not by classic branch protection.
