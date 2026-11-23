# Execution plan: label taxonomy migration (solo SDLC)

Goal: move the repository's process docs and agent config to the owner's new label taxonomy (decision 2026-11-23, full migration): issues use `type:*` / `area:*` / `state:*` plus the `beta.2` / `later` milestones; the claim label is `state:in-progress`; no label-rationale comments; review nits are fixed in the same PR or dropped; one QA comment edited in place.

Source docs: owner triage proposal ("Nowy zestaw etykiet" and its mapping) and the dev-flow report, section 6 "SDLC solo" (local scratch files, not committed).

## Scope

- `.ai/agentic.config.json` (label groups), `.ai/trackers/github.md` (label guards with a legacy-name alias map, claim convention, milestone operation, process conventions), `SDLC.md`, `CODE_REVIEW.md`, `AGENTS.md` (process row), `.github/dependabot.yml`, `.github/ISSUE_TEMPLATE/*.yml`.
- Before removing a PR-side label from the config, check how the installed `om-*` skills read it; keep every label a skill needs.

Non-goals: deleting or renaming labels on GitHub (post-merge commands go in the PR body), retagging existing issues, editing installed skills, CI changes, archiving skills.

## Risks

- Skills hard-code legacy names (`in-progress`, `priority-*`, `ci-monitoring`, `review`): handled by an alias map inside the descriptor's label guards, so a skill that applies an old name lands the new one or a logged no-op.
- `jq '.labels.priority // [defaults]'` falls back to the old names when the key is missing: the config keeps `"priority": []` explicitly.

## Progress

> Convention: `- [ ]` pending, `- [x]` done. Append ` — <commit sha>` when a step lands. Do not rename step titles.

### Phase 1: Config and tracker descriptor

- [ ] 1.1 Update label groups in agentic.config.json
- [ ] 1.2 Add label alias map, claim and milestone conventions to the GitHub tracker descriptor

### Phase 2: Process docs

- [ ] 2.1 Rewrite the SDLC label, claim, QA comment and follow-up rules
- [ ] 2.2 Update CODE_REVIEW.md, AGENTS.md, dependabot and issue templates
