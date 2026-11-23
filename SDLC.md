# Software delivery process

## Purpose

This file documents how work flows from ticket to merged PR in this repository. The agent skills configured in `.ai/agentic.config.json` enforce the process; humans read it here. PRs target `main`; issues and PRs live in GitHub (tracker `github`), with every tracker operation the skills run defined in `.ai/trackers/github.md` (edit that file to extend or override tracker behavior).

Work enters through two paths: a free-form task brief handed to an agent, or a filed ticket. Both converge on the same review loop, the same validation gate, and the same merge gates.

Before intake, the work is shaped: `om-brainstorm` turns a single idea or question into a routing decision and a brief, and the spec skills (`om-spec-writing`, `om-auto-write-spec`) turn a feature into a design document before anything is built. Those steps feed the table below; they are not the ticket flow itself.

## Roles

Lintel is built by one owner with agents. Three roles, no more:

- **Author agent** — writes the change (`om-auto-create-pr`, `om-auto-implement-spec`, `om-fix`, …) and owns it from claim to a merge-ready PR, including the QA evidence (debug build, `--qa` launch arguments, screenshots in light and dark mode).
- **Reviewer agent** — reads the diff with `om-auto-review-pr` / `om-code-review`, preferably on a different model than the author. It is also the "second review" a `risk-high` change needs (the evidence table below still applies).
- **Owner** — the only person who applies `qa-approved`, merges or queues a PR for `automerge`, decides open questions (`state:needs-decision`), and maintains the label taxonomy, the config, this document and the repo-local skill overrides under `.ai/skills/`. Referenced by role, never by handle.

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
| QA | A PR carrying `needs-qa` waits for QA. The author agent runs the debug build with the `--qa` launch arguments and records the evidence in the PR's single QA comment; the owner looks at it (and the app) and applies `qa-approved`, or `qa-failed` to send it back. A flow worth keeping becomes `om-integration-tests` coverage. See the QA gate below. | Author agent (evidence), owner (verdict) | `qa-approved` applied by the owner; `qa-failed` routes it back |
| Merge | `om-merge-buddy` reports, read-only, which PRs can merge now and which are close but blocked. `om-approve-merge-pr` re-checks every gate, approves, and squash-merges. | `om-merge-buddy` + `om-approve-merge-pr`, or a human | PR squash-merged into `main` |
| Post-merge housekeeping | Close issues the merged PR fixes; comment on issues whose PRs were closed without merging. Only a real bug found along the way becomes a new issue; review nits are never filed (see "Review findings and follow-ups"). | `om-close-fixed-issues`, `om-followup-issue-from-pr` (real bugs only) | Tracker reconciled |

After merge, this process stops. Deployment, smoke tests, monitoring, and rollback belong to the repository's release process, not to this document: the owner drafts the changelog with `om-auto-update-changelog` and reconciles the tracker with `om-close-fixed-issues`, and `om-pipeline-retro` reads finished runs to rank what second passes cost. Merge is where this document ends; delivering the change to users is a separate process the team owns (for releases, the owner's runbook is `docs/releasing.md`).

## Labels

The taxonomy changed on 2026-11-23 (owner decision, full migration). Issues carry what the work is and where it stands; PRs carry only what a gate reads. The repository config (`.ai/agentic.config.json`, `labels`) holds the same lists; the tracker descriptor (`.ai/trackers/github.md`, `resolve_label`) maps every legacy name the installed skills still use.

| Group | Labels | On | Exclusivity | Meaning |
|---|---|---|---|---|
| Type | `type:bug`, `type:feature`, `type:chore` | issues and PRs | exactly one | What the work is. `type:chore` covers docs, refactors, CI, dependencies and tooling. |
| Area | `area:dictation`, `area:meetings`, `area:notes`, `area:app` | issues and PRs | one, two when it truly spans | Where it lives. `area:app` is the shell, launcher, Files/Apps/Clipboard, Windows, release, CI and QA tooling. |
| State | `state:idea`, `state:needs-decision`, `state:agent-ready`, `state:in-progress` | issues (`state:in-progress` on PRs too) | at most one | Where the issue stands. `state:in-progress` is the claim (below). |
| QA | `needs-qa`, `qa-approved`, `qa-failed` | PRs | additive | The QA gate. Only the owner applies `qa-approved`. |
| Risk | `risk-low`, `risk-medium`, `risk-high` | PRs | exactly one; unset = medium | Blast radius; `risk-high` triggers the evidence table. |
| Hard blocks | `blocked`, `do-not-merge` | PRs | set and cleared by the owner | Stop the flow wherever it is. |
| Merge queue | `automerge`, `automerge-blocked` | PRs | — | `automerge` is the owner queuing a PR for `om-auto-merge-buddy`; the buddy parks a PR it cannot finish with `automerge-blocked` until a human clears it. |
| Exceptions | `security`, `do-not-close` | issues and PRs | additive | `security` feeds `CODE_REVIEW.md` and automerge eligibility; `do-not-close` (humans only) keeps housekeeping skills from closing an issue. |

Retired, never applied again: `review`, `changes-requested`, `qa`, `merge-queue` (a PR's review state is GitHub's review decision plus the reviewer's summary comment), `skip-qa` (no `needs-qa` means no QA), `qa-self-verified` (there is no self-QA), `ci-monitoring` (an owed CI follow-up is said in the summary comment), `in-progress` (now `state:in-progress`), `priority-*` (now milestones), `bug`, `feature`, `enhancement`, `refactor`, `documentation`, `dependencies` (now `type:*`), `question` (now `state:needs-decision`), `help wanted` and `good first issue` (now `state:agent-ready`), `accessibility` (now `type:bug` with "a11y" in the title), `wontfix`, `duplicate`, `invalid` (close with the reason in a comment).

**No label-rationale comments.** Agents apply and change labels without a comment explaining why; the run's summary comment may name the labels in one line. When risk signals conflict, pick the higher label and say why in the PR body.

### Issues: labels and milestones

- Every open issue has one `type:*` and one `area:*`. A triaged issue has a milestone: `beta.2` (needed for the next beta) or `later`. The milestone is the priority; there are no priority labels.
- `state:idea` — not decided whether to build it. `state:needs-decision` — waits for the owner, with the options and a recommendation in the issue. `state:agent-ready` — specified enough for an agent to pick up. `state:in-progress` — claimed.
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

The one hard rule of this process: **a PR carrying `needs-qa` must not merge until it also carries `qa-approved`, even when every other check is green.** `om-merge-buddy` classifies such a PR as blocked; `om-approve-merge-pr` refuses to merge it.

- Apply `needs-qa` to UI changes, new features, and other user-facing behavior that needs manual exercise. A docs-only, dependency-only, CI-only or test-only PR simply does not carry it.
- For a UI change, QA covers more than "it works": the state matrix (default, empty, loading, error, no-permission, long content, narrow viewport) is part of the pass/fail, and so is conformance to the accepted prototype and the design contract in `.uxproof/` when the repository has one. A missing state fails QA. `om-ux-review-pr` remains the advisory design review; its objective checks are the ones QA runs.
- `qa-failed`, `do-not-merge`, and `blocked` are hard blocks regardless of every other signal.
- **`qa-approved` is the owner's alone.** No agent and no skill applies it: not an authoring, review, QA or merge skill, and not `om-auto-qa-pr --self-qa-signoff` (there is no self-QA exception in this repository, whatever the risk label). The author agent's job is the evidence; the owner's is the verdict.
- **One QA comment per PR, edited in place.** The author agent keeps all QA evidence in a single PR comment: the scenarios exercised, the screenshots (light and dark, plus the relevant states), the negative cases tried, and the `QA head: <sha>` line for the tested head. Each new QA round rewrites that comment (tracker operation **update-comment**) instead of posting another one, and says which round it is.
- **How QA runs in this repository.** Lintel is a native macOS app, not a web app, so the browser provider (`agent-browser`, `.ai/browsers/agent-browser.md`) is used for the GitHub Pages landing page only. The native app is QA'd by building and running it locally (`CONFIGURATION=debug scripts/make-app.sh`, `--qa…` launch arguments, `docs/qa.md`) and attaching screenshots of the running app (light and dark mode, plus the relevant states from the spec: indexing, no results, clipboard access denied, paste disabled, recording paused, Keychain locked, feature unavailable for a plugin in `failed`) as PR evidence. Tests that need Accessibility or Full Disk Access, UI tests and performance benchmarks cannot run on GitHub runners (no TCC grants, noisy shared VMs); they run locally and their results go into the PR body.
- **`qa-approved` is pinned to a commit.** The QA comment carries the line `QA head: <sha>` for the head the owner approved. A push after that line leaves the label in place but stales it: `om-merge-buddy` reports "QA evidence older than head", and `om-approve-merge-pr` asks for confirmation before merging. The way back is the owner approving the new head.
- **Exception for test-only commits and `main` merges (owner rule of 2026-11-20).** The owner's `qa-approved` stays valid after a new commit only when all three hold: (1) the commit changes only tests (`Tests/**`) or is a mechanical merge of `main` — no file in `Sources/`, `Resources/`, workflows, scripts or `Package.swift`; (2) proof that the app code is identical to the approved head (a matching `git patch-id`, or an empty diff of `Sources/`, `Resources/`, `.github/workflows/` and `scripts/`) is posted on the PR; (3) an independent Opus reviewer confirms (1) and (2) and the required CI check is green. A commit that removes, disables or weakens a test (instead of repairing it) always goes back to the owner. Any other commit after approval needs the owner's `qa-approved` again.
- **`risk-high` gets no shortcuts.** A PR labeled `risk-high`, or one whose diff touches auth, sessions, data scoping, money, schema migrations, or shared contracts (the `risk-high` inference above), carries the evidence from the table above before the owner's QA; `om-code-review` blocks without it unless the owner waives it on the PR.

## The claim protocol

Before mutating an issue or PR, an agent claims it with the `state:in-progress` label. That label is the claim; the assignee and the `🤖` claim comment the skills add alongside it are optional signals, never required. Any agent that finds a live claim backs off instead of colliding, and the merge tooling skips a PR carrying `state:in-progress`. Installed skills still say `in-progress`: the tracker descriptor's guards apply `state:in-progress` for them, and a skill reading labels treats `state:in-progress` as that claim.

The claim is released when the work finishes — on success and on failure alike — and a finished run never leaves a label behind to say it is still watching CI (there is no `ci-monitoring`). A stale `state:in-progress` with no recent activity may be cleared by the owner.

### Reporting is decoupled from CI

Agents apply labels, submit reviews, and post comments **as soon as their work is done**, without waiting for CI to go green. A review submitted while checks are still running says so in its body: branch protection plus the QA-approval gate hold the actual merge, and the approval covers the code, not a green run. When the agent follows up, the CI outcome is added to its existing summary comment (edited in place), which also states if the result changes the verdict.

The wait for that outcome is bounded by `ci.maxWaitMinutes` (default 40). When it expires with checks still running, the agent stops waiting, runs the local validation gate as its own evidence, records that together with the still-pending check names and an explicit statement that no further follow-up is coming, and finishes.

A red signal does not short-circuit the review either. A failing required check or a conflicted head is collected as a **blocker finding** and reported together with the full code review, never instead of it: one review cycle gives the author the failing check, the conflict, and every code finding at once, rather than the cheapest red flag first and another cycle to discover the rest. Such a verdict is still `changes-requested` — completeness changed, the gate did not.

None of this touches the merge gates. Reporting early is safe; merging early is not — required checks still gate every merge, and the merge tooling refuses until they are genuinely green.

## Review findings and follow-ups

- **A nit or non-blocking finding is fixed in the same PR or dropped.** It is never filed as a new issue, never parked in a "follow-up" list and never turned into a tech-debt ticket. The summary comment lists what was dropped in one line, so the owner can object.
- **Only a real bug becomes a new issue** (`type:bug`, an `area:*`, a milestone once triaged): a defect a user could hit that is out of the PR's scope. One issue per bug, written so an agent can act on it.
- **A flaky test goes into the "Flaky tests" umbrella issue (#240)** as a checklist line with the test name, the CI run and what is known, not into a new issue.
- Skills that would file follow-ups for nits (`om-auto-fix-pr`, `om-approve-merge-pr`, `om-followup-issue-from-pr`) apply these rules; the tracker descriptor states them as repository process rules.

## The automation contract

The `om-auto-*` skills run this process unattended and are chainable: each accepts the artifact the previous one produced (an issue id, a spec path, or a PR number from the `PR: #<number> (link: <url>)` reference line every PR-producing skill emits), and each detects work already started — an open PR referencing the issue or plan — and continues on it rather than opening a duplicate. A completed autonomous run leaves a **ready** (non-draft) PR labeled with one `type:*`, its `area:*`, one risk label and `needs-qa` when user-facing — no priority label, no pipeline label and no label-rationale comment — with one run-summary comment and, for user-facing changes, the single QA comment with screenshots from the working app. Draft PRs are reserved for explicitly incomplete states: spec-only design PRs, interrupted hand-offs, or autonomous defaults flagged for human confirmation. No skill applies `qa-approved`.

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

Per-skill deviations — extra review rules, a different PR body template, an added gate step — belong in a repo-local skill of the same name at `.ai/skills/<skill-name>/SKILL.md`, which takes precedence over the installed skill (and can `@`-import or reference it to extend rather than replace it); local rules win, but a repo-local skill cannot grant what the installed skill's safety rules forbid.