# Turning early users into feedback contributors (research, 2026-11-23)

Scope: how small OSS / indie Mac and dev-tool projects got early users to report, discuss and come back, and how to measure month 1 without analytics. Every source was accessed 2026-11-23 via web search. Labels: **FACT** (the source says it), **INFERENCE** (my conclusion), **UNVERIFIED** (only third-party or mirror sources).

## Starting point (checked with `gh` on 2026-11-23)

- FACT: `mjozefiak/lintel` has Issues on, **Discussions off**, 0 stars. Release `v0.1.0-beta.1` `Lintel.dmg` has 2 downloads. Issue forms `bug_report.yml` and `feature_request.yml` exist, `config.yml` has `blank_issues_enabled: true` and one security contact link. A `good first issue` label exists. CONTRIBUTING, CODE_OF_CONDUCT and SECURITY are present.

## 1. Where the conversation lives: Discussions vs Discord vs Slack

- FACT: Ghostty ran a private beta for nearly two years. The Discord was the waitlist, and active members were invited in waves (https://mitchellh.com/writing/ghostty-devlog-003, https://mitchellh.com/writing/ghostty-devlog-005). Testers could vouch for friends (https://mitchellh.com/writing/ghostty-devlog-004). The beta ended at about 5,000 users from a Discord of about 28,000, and Hashimoto credited testers for much of the polish (https://mitchellh.com/writing/ghostty-1-0-reflection).
- FACT: Ghostty now starts **all bugs and feature requests as GitHub Discussions**. An issue is opened only once the item is actionable, for example a bug with repro steps (https://ghostty.org/docs/help). UNVERIFIED (mirror of CONTRIBUTING.md): first-time contributors need a "Vouch Request" discussion, and newcomers are pointed to "contributor friendly" issues (https://www.mintlify.com/ghostty-org/ghostty/guides/contributing).
- FACT: Zed moved feature requests from Issues to Discussions. Its in-app "request feature" link points at Discussions, and its issue templates were consolidated into one "Report an issue" form (https://zed.dev/community-links, https://zed.dev/docs/feedback-and-support). Discord is for real-time help (https://zed.dev/support).
- FACT: Raycast opened a public Slack for users about six months after the company started using Slack internally. CEO Thomas Paul Mann says he reads feedback channels and replies himself (https://slack.com/customer-stories/raycast-story). The 2020 private beta ran with "a limited number of beta users" and a waitlist of thousands (https://www.raycast.com/blog/hello-world).
- FACT: Ice (menu bar manager, solo developer) uses only GitHub Issues + Discussions, with no chat server (https://github.com/jordanbaird/Ice/discussions).
- FACT: Hyprnote (now Char, YC S25, open-source meeting notes) links Discord from its README and offers a "20-min call" with the founders on its blog and docs (https://hyprnote.com/docs, https://hyprnote.com/blog/yc, https://char.com/blog/hyprnote-is-now-char).
- UNVERIFIED: VoiceInk's paid build includes "priority support via Discord and email" (seen only in a fork's README: https://github.com/nanmu42/VoiceInk). The main repo is https://github.com/Beingpax/VoiceInk.
- FACT (anecdotal): Discord Q&A is not indexed by search engines and is often lost (https://dev.to/bdbchgg/why-discord-sucks-for-developer-communities-2fg1). One maintainer had to ask people to re-file Discord reports as issues or they forgot them (https://www.datadab.com/blog/the-developer-community-growth-flywheel-discord-vs-slack-vs-github-discussions-when-to-use-each-and-how-to-avoid-the-graveyard/).

**INFERENCE for Lintel:** with 0 users, an empty Discord looks dead and splits one person's attention. Turn on **GitHub Discussions** now: it is free, searchable, and works the way Ghostty and Zed do it, with the same login as issues. Add Discord only when people ask for real-time chat. Slack's message-history limits on free plans make it a poor fit (INFERENCE, not researched here).

## 2. Lowering the cost of a report

- FACT: issue forms plus `config.yml` can hide blank issues (`blank_issues_enabled: false`) and send people elsewhere with `contact_links` (https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests/configuring-issue-templates-for-your-repository).
- FACT: a `.../issues/new?template=bug_report.yml&title=...&body=...` URL pre-fills an issue. Overly long URLs fail with HTTP 414 (https://docs.github.com/en/enterprise/2.16/user/github/managing-your-work-on-github/about-automation-for-issues-and-pull-requests-with-query-parameters).
- FACT: Zed's app opens Discussions for feature requests directly (https://zed.dev/docs/feedback-and-support).
- **INFERENCE:** add Help menu items "Report a Bug…", "Request a Feature…" and "Ask a Question / Discussions" that open pre-filled URLs. Fill only the app version, macOS version, chip and enabled features. Never include transcripts, clipboard or notes text: this matches the bug form's existing privacy note and the project rule against logging content. Opening a URL in the browser sends nothing by itself, so it stays local-first.

## 3. Talking to people directly

- FACT: Hyprnote/Char offers a 20-minute founder call as a standing link (https://hyprnote.com/docs).
- FACT (anecdotal): founders report that 15-minute calls surface things surveys miss. One sent ~1,600 survey emails and got 15 replies (https://www.indiehackers.com/post/i-asked-10-customers-to-describe-their-support-experience-from-their-perspective-heres-what-i-learned-aec2773d7a, https://www.indiehackers.com/post/how-to-get-user-feedback-when-user-outreach-isnt-working-613e5b3b23). Others report no-shows and people who prefer DMs (https://www.indiehackers.com/post/how-do-you-get-1-1-calls-during-validation-stage-8d6da6c114).
- **INFERENCE:** offer an optional "15 minutes with the developer" link (free scheduler or plain email) in the README, the release notes and the first-run or About window. Also accept async answers in a pinned Discussion for people who will not take a call.

## 4. "Founding user" / beta tester programs

- FACT: Ghostty's beta was invite-based, with vouching and a tester README (https://mitchellh.com/writing/ghostty-devlog-004). Raycast also ran a closed beta with a waitlist (https://www.raycast.com/blog/hello-world).
- **INFERENCE:** Lintel is already public, so gating adds nothing. A lighter version: a pinned Discussion "Beta testers: introduce yourself (Mac model, how you dictate, which meeting app)", a `beta-tester` label, and named credit in release notes. This gives the status of a founding group without a waitlist. No numbers on how well this works were found (UNVERIFIED as a tactic).

## 5. Fast first responses, Good First Issues, credit

- FACT: in a large GitHub study, how maintainers interact on a newcomer's first issue relates to retention more than the issue's own attributes. Clear, technical replies did better than emotional but empty positivity (https://arxiv.org/abs/2603.27136, preprint). A study of 72,635 projects found first responses mostly positive but often "less responsive" (https://arxiv.org/abs/2104.02933). No study found here isolates response *speed* (**UNVERIFIED** that speed alone matters).
- FACT: Good First Issues help onboarding, but in the sampled projects they were only ~1.5% of issues (https://repository.tudelft.nl/record/uuid:c5ad4296-6ab7-4a3a-8e4b-73216cf38012). Whether they lead to lasting contributors is unclear (https://arxiv.org/abs/2604.27532).
- FACT: the All Contributors bot credits non-code work, bug reports included, through a README table updated by PR (https://allcontributors.org/docs/bot/overview).
- **INFERENCE:** aim to reply to every new issue or discussion within 24 h in month 1, with a concrete next step (repro question, label, "fixed in X"). Thank reporters by @handle in release notes. Keep 3–5 truly small `good first issue` items (strings, Polish translation, docs, landing page).

## 6. Public roadmap and changelog cadence

- FACT: Appwrite runs a public roadmap as GitHub Projects boards per release (https://appwrite.io/blog/post/public-roadmap-announcement). GitHub publishes its own roadmap as a GitHub repo/project (https://github.blog/2020-07-28-announcing-the-github-public-roadmap/).
- UNVERIFIED: no source found that ties a specific changelog cadence (e.g. weekly) to better retention for indie Mac apps.
- **INFERENCE:** one public GitHub Project with "Now / Next / Later / Ideas" columns built from Discussions and issues. Ship a beta every 1–2 weeks in month 1 (Sparkle `appcast.xml` already exists), with a "Thanks to" section in each release.

## 7. Measuring month 1 without analytics

- FACT: the Traffic API (`/traffic/views`, `/traffic/clones`, `/traffic/popular/referrers`, `/traffic/popular/paths`) needs push access, covers only the **last 14 days**, and returns only the top 10 referrers (https://docs.github.com/en/rest/metrics/traffic).
- FACT: each release asset has a point-in-time `download_count`. Re-uploading an asset resets it, and source archives have no count (https://docs.github.com/en/rest/releases/assets).
- **INFERENCE:** history is lost after 14 days, so snapshot both into a file (a scheduled Action committing JSON, or a local `gh api` cron). Sparkle appcast fetches would show active installs, but only if the hosting logs them. GitHub release assets give no request logs, so this is not measurable today (INFERENCE).
- Proposed month-1 scorecard (targets are owner decisions, not research): DMG downloads across releases; unique visitors and top referrers from Traffic; stars; issues and discussions opened by people other than the owner; number of distinct external reporters; median time to first reply; calls held.

## Setup checklist for `mjozefiak/lintel`

1. [ ] Enable Discussions with categories: Announcements, Q&A, Ideas (feature requests), Beta testers (introductions), Show and tell.
2. [ ] Pin two Discussions: "Start here / beta tester introductions" and "What should Lintel do next?".
3. [ ] `config.yml`: set `blank_issues_enabled: false` and add `contact_links` to Discussions Q&A, Ideas and "Talk to the developer (15 min)". Keep the security link.
4. [ ] Change `feature_request.yml` to point to Discussions → Ideas, as Zed does (or keep the form but link Ideas at the top).
5. [ ] Help menu in the app: "Report a Bug…", "Request a Feature…", "Join Discussions", "Talk to the Developer". Pre-filled URLs carry only the version, OS, chip and enabled features, never user content. Needs a small spec.
6. [ ] README: a short "Feedback" section with the same four links, and a note that every report is credited in the release notes.
7. [ ] Labels: add `beta-tester`, `needs-repro`, `from-discussion`. Seed 3–5 `good first issue` items with a clear scope.
8. [ ] Install the All Contributors app (or keep a hand-written "Thanks" list) and credit bug reporters.
9. [ ] Public GitHub Project "Lintel roadmap" (Now / Next / Later / Ideas), linked from the README.
10. [ ] Release every 1–2 weeks with a "Thanks to @…" section. Never re-upload a DMG asset (it resets the count).
11. [ ] Scheduled GitHub Action (daily) that saves `traffic/views`, `traffic/clones`, `traffic/popular/referrers` and release `download_count` to a JSON file on a `metrics` branch. It needs a token with push access as a repo secret.
12. [ ] Personal rule for month 1: first reply within 24 h on every issue and discussion. Track the median in a weekly note.
