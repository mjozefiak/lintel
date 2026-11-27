# Post-meeting actions: Circleback and Fireflies (2026-11-26)

Sources checked on 2026-11-26.

Method: pages fetched through a summarising fetch tool plus web search. "Verified" means a fetched page said it. "Inferred" is my reading. Neither product's UI was opened, so card layouts are not seen firsthand; that gap is stated below. Search-result snippets that I did not open as pages are labelled "search snippet". I found no Reddit threads. The "Super Summaries" feature appeared on no page I fetched, so nothing is claimed about it.

## Summary of the two models

- Circleback: rules-first. You configure an automation ahead of time (trigger, action, destination). It then runs after every matching meeting with no review step. Email is the exception: it is drafted and sent through an editor.
- Fireflies: two tracks. (a) Automatic routing of action items to Jira, Asana and similar tools, with filters and no per-item approval. (b) On-demand drafting through the AskFred assistant and the Email Assistant, which only ever saves drafts. The user sends them.

## Circleback (circleback.ai)

### 1. Where and when actions appear
- Verified: action items are "automatically captured, assigned, and organized after every meeting" and aggregated into one universal task list (home page testimonial) - https://circleback.ai/
- Verified: automations run "after each matching meeting" and only for future meetings, not past ones - https://circleback.ai/blog/circleback-automation-setup-guide and https://circleback.ai/docs/support/automations/integrations/integrate-with-linear
- Verified: actions go out to the destination tool: Slack channel, CRM record (Salesforce opportunity, HubSpot deal), Linear issues, Notion rows, Google Docs. Recap emails are configured in Settings > Emails (recipients: Myself or Everyone invited) - setup guide above.
- Verified: you can run an automation by hand later, otherwise it runs on its own - https://circleback.ai/blog/automatically-create-linear-issues-for-tasks-that-come-up-in-meetings
- Verified: Jira is not built in. Routes are a custom connector in Ask Circleback (on request), Zapier or Make - same blog post.
- Verified (home page, https://circleback.ai/): also Asana, Notion, Salesforce, HubSpot, plus Zapier, Make, MCP, API, CLI and webhooks.
- Verified: a "Draft and send emails" release says you ask Circleback to write an email and it uses context from meetings, past threads and calendar availability, looks up recipients, and can reply in an existing thread. The draft opens in an editor, you change it and press send - https://circleback.ai/releases/draft-and-send-emails. A search snippet dates this release 2026-07-31; I did not see the date on the page.
- Not found: a documented automation step that auto-drafts to attendees. A search snippet says a "Draft email action" is listed in related resources of the setup guide, but the page gave no detail. Treat as unconfirmed.

### 2. What one action looks like
- Linear issue: one issue per action item, with a link back to the meeting. If the item owner's email matches a Linear team member, the issue is assigned to them; otherwise unassigned. The page does not list title, description or priority fields - Linear blog post above.
- Action-item filters in the Linear step (verified): "assigned to a Linear team member" and "not assigned to a Linear team member / no assignee", both on by default - Linear docs page above. A 2025-04-14 release note adds "workspace members, people outside your workspace, or both" - https://circleback.ai/releases/choose-which-action-items-get-created-in-linear-and-monday-com
- Attio tasks: assigned automatically if the assignee is a workspace member (search snippet, https://circleback.ai/releases/create-tasks-in-attio).
- Email draft: opens in an editor; fields beyond the body are not documented.
- Not verified: the in-app action-item list UI (fields, evidence link, status). A third-party listing (ToolQuestor, search snippet only) says items can be edited, reassigned, marked done. Do not rely on it.

### 3. Approval model
- Automations: no review or approval step is documented; issues are created automatically (Linear blog post; setup guide "doesn't mention" review or test/preview).
- Control is up front: tags, name-pattern and attendee conditions combined with and/or; blank means all meetings (setup guide). An automation can be shared workspace-wide from its "..." menu.
- Email: review in the editor, then Send. This is the one human-in-the-loop path found.
- Undo: not documented.

### 4. Error and disconnected states
- Linear: "Connect" appears in the setup flow if the account is not linked. No error states are documented on the pages read.
- Email accounts are connected under Settings > Connected accounts; providers and OAuth are not described on the page.

### 5. Who said it / assignee
- Assignment is by matching the owner's email to a team member (Linear, Attio). The page does not explain how the owner is detected from speech. Marketing copy says it "identifies and assigns" follow-ups (search snippet).

### 6. Patterns and pitfalls
- Pattern: "trigger, action, destination" automation builder. Inferred: low risk because destinations are internal tools, and the quality bar is the extractor.
- Pattern: split action items by assignee type (team vs outsider) so external-owned tasks do not clutter the tracker.
- Pitfall: no per-item review means a wrong extraction lands in the tracker. I found no complaint specific to this.
- Complaints found (all secondhand, from competitor blogs and snippets): wrong speaker attribution, missed words in quiet audio, slow billing support. G2 reviews are few and mixed (one praises action items, one rates 0.5/5 over support) - https://www.g2.com/products/circleback-ai-inc-circleback/reviews. No complaints about broken automations found.

## Fireflies (fireflies.ai)

### 1. Where and when actions appear
- Verified: action items appear next to the transcript on each meeting, and also in the connected PM tool or CRM - https://fireflies.ai/blog/ai-action-items
- Verified: extraction and routing are automatic for meetings recorded after connecting; the task-creation toggle is off by default and routing needs a paid plan - same blog post; https://guide.fireflies.ai/hc/en-us/articles/28272049616529-How-to-integrate-Jira-with-Fireflies
- Verified: "Push Past Meetings" sends older meetings in bulk (last 7/14/30/60/90 days or custom range) - Jira guide above and https://guide.fireflies.ai/articles/1901313269-how-to-integrate-asana-with-fireflies
- Verified: action items in the notes that Fred can help with show a "Create" or "Draft" link; clicking it opens AskFred with that task ready. These use AI credits on Fred Pro - https://guide.fireflies.ai/articles/6556345325-askfred-ask-fred-questions-from-your-meetings-in-fireflies-and-get-answers
- Verified: AskFred opens in a side panel from the Feed widget or beside the transcript in the Meeting Notepad, and only after the meeting is processed - same page. It can write a follow-up email on request; "Follow-up emails" is also a built-in AI Skill.
- Verified: the Email Assistant puts drafts in your Gmail or Outlook inbox, in the same thread as the original conversation - https://guide.fireflies.ai/articles/9503760922-learn-about-the-fireflies-email-assistant-organize-your-inbox-and-draft-replies. Note this is inbox replies and no-reply follow-ups on sent mail, not a post-meeting recap draft; I did not verify the latter.
- Home page claims (marketing, verified on page, no detail): Fred "drafts replies and follow-ups" and turns action items into tasks in 15+ tools - https://fireflies.ai/

### 2. What one action looks like
- Jira issue (verified, Jira guide): owner (the participant assigned; the host for general items), mention time, link to the full recording, project and issue type from config (Task, Bug, Story or custom). Blog post adds description and due date when mentioned.
- Asana task: created in a chosen workspace, project and section; field list is not documented; assigned by owner email when auto-assign is on - Asana guide.
- Action item in the Fireflies notes: links to the matching moment in the recording (blog post). Edit behaviour is not documented there.
- The Create/Draft link card layout is not shown on the page; I did not see the UI.

### 3. Approval model
- Routing to Jira/Asana: automatic, filtered by rules (Business plan or higher): meeting title, host, participants, type, combined with AND/OR. A "create only tasks assigned to me" switch exists for Jira. A "Create sample tasks / sample issue" button tests the setup before saving.
- Per-item: the "Create"/"Draft" link on an item is a manual, on-demand route through AskFred. A Fireflies guide for manually sending specific tasks exists but I did not read it.
- Email: "Nothing is sent automatically. You always stay in control." You review, edit, rewrite or delete any draft and send it yourself; drafts learn from your edits (Email Assistant page).
- Undo: not documented. The Jira sync is one-way: editing an action item in Fireflies does not update the Jira issue (Jira guide).

### 4. Error and disconnected states
- Asana guide has a troubleshooting list: tasks not appearing (check toggle and project/section), unexpected disconnection (reconnect from Integrations), unassigned tasks (turn on Auto-Assign; stays unassigned if user lacks project access), permission errors, wrong project, missing dropdown entries.
- Email Assistant: disconnecting stops new labels, drafts and follow-ups; existing drafts stay. Running out of AI credits shows a paywall and pauses new drafts. Admin must enable it under Team Settings > AI Settings.
- Jira guide has no troubleshooting section.

### 5. Who said it / assignee
- Verified (blog post): speaker labels identify who made each commitment and the task goes to that person (example: "I'll have the report ready by Friday" goes to the speaker). Assignment to a tool user is by email (Asana guide); the host is the fallback owner for general items (Jira guide).

### 6. Patterns and pitfalls
- Pattern: connect via OAuth redirect (Asana: "read and write tasks"; Jira: review and accept permissions) then a default configuration (project, type, only-mine) with a sample-item test. Multiple configurations allowed.
- Pattern: rules by meeting title/host/participants/type rather than per-item choices.
- Pattern: explicit "never auto-sent" copy for email.
- Pitfalls from reviews (search snippets only, G2/Trustpilot/Capterra): inaccurate action items are the top dislike but described as manageable; one G2 reviewer wanted more control over which items get created and over epic selection in Jira; one Trustpilot reviewer (a legal user) reported wrong attribution of who said what - https://g2.com/products/fireflies-ai/reviews?page=2, https://www.lindy.ai/blog/fireflies-ai-review. Capterra reviewers mention name errors and manual corrections. Fireflies' own docs warn that Jira sync is one-way.

## Comparison

| Aspect | Circleback | Fireflies |
|---|---|---|
| When | Automatically after each matching meeting | Automatically (paid, toggle off by default) or on demand through AskFred |
| Where seen | Destination tools and Slack; central task list | Notes beside transcript; destination tools; AskFred side panel |
| Per-item approval | None documented for automations | None for auto-routing; manual Create/Draft link per item |
| Email | Drafted in an editor, user presses Send | Draft saved in inbox, user sends; "nothing sent automatically" |
| Jira | No native integration (connector, Zapier, Make) | Native OAuth integration |
| Linear / Asana | Linear native; Asana listed | Asana and Jira native; Linear not checked |
| Rules | Tags, name patterns, attendees; assignee-type filter | Title, host, participants, type; "assigned to me" |
| Evidence | Link to meeting on the issue | Mention time and recording link on the issue |
| Assignee | Owner email matched to team member | Speaker label to owner; email matching |
| Test before live | Not documented | "Create sample tasks/issue" |
| Undo | Not documented | Not documented; one-way sync |

## Implications for Lintel (patterns, not decisions)

- Both competitors mostly skip per-action approval for tracker items and rely on rules set in advance. The brief's model (list of ready-to-execute actions, each approved) is stricter than either's automation path. The closest analogues are Circleback's email editor and Fireflies' saved drafts.
- Drafts that are never sent without a click are the explicit trust pattern for email. Fireflies states it in plain words; consider doing the same.
- Show evidence on the card itself: owner, time in the meeting, and a link back to the recording. Fireflies puts mention time and recording link on the created Jira issue; Circleback links to the meeting. Neither is verified to show the quote on a pre-approval card.
- Assignee: match the speaker to a person and the person to a tool account by email, with an "unassigned" fallback. A mismatch (wrong owner) is the main complaint class, so show the owner as an editable field before approval.
- Offer a test or sample step when connecting an account (Fireflies' "Create sample task"), and a per-connection default config (project, issue type, "only mine").
- Document and surface disconnected states: Fireflies' guides list reconnect, permission and missing-project cases; neither product shows a verified in-app error card. A card needing a reconnect should say so and keep its draft.
- Filter by assignee type (mine, teammates, outsiders), as Circleback does, to avoid noise in the list.
- Make one-way sync visible: after an action is executed, edits in the app do not change the ticket, so the card should show the result as a link, not a live copy.
