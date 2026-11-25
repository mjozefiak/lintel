# Proactive meeting actions: market scan — 2026-11-23

This builds on `2026-11-13-meeting-notes-market-B.md`. That file already covers basic action-item extraction, Claude Meetings, the leaked "Parka" recorder (action items with an `autoRunnable` flag routed to Cowork or Claude Code) and ChatGPT Record. This file looks only at what happens **after** an action item exists: does the tool propose or perform work in another system (tracker, calendar, mail, CRM, Slack), and how does the user approve it?

**Method.** Web searches only, all run on 2026-11-23. I could not open pages in full, so every claim rests on search-result excerpts of the cited URL. Labels: **FACT** = stated on the vendor's own page or help centre; **INFERENCE** = my reading; **UNVERIFIED** = third-party, marketing-only, or the sources conflict. Prices are quoted only where a source states them.

---

## 1. Per product

### Granola
- **Targets:** Slack, Notion, HubSpot, Attio, Affinity and Zapier on Business; Jira, Linear and Asana through Zapier. FACT: https://www.granola.ai/pricing , https://www.granola.ai/blog/meeting-action-items-to-task-manager (2026-11-23).
- **Mode:** a Zap runs **automatically** on new notes in a chosen folder, or the user pushes one note **by hand** from the share menu. FACT: https://linear.app/integrations/granola . There is no native suggestion inbox. Recipes are reusable prompts, and a checklist recipe gathers to-dos across meetings; they do not act anywhere else. UNVERIFIED (aggregator): https://createwith.com/tool/granola
- **Agents:** public API and an MCP server (`mcp.granola.ai/mcp`), so external agents do the acting. **Agent Briefs** (reported 2026-11-11) gives connected assistants an overnight digest of the user's priorities; Business/Enterprise only. UNVERIFIED (news aggregator): https://work-management.org/news/granola-agent-briefs-ai-context-review/
- **Price:** Basic $0, Business $14/user/month, Enterprise $35. FACT: https://www.granola.ai/pricing
- **INFERENCE:** Granola stays a notes layer and leaves acting to Zapier and other people's agents.

### Circleback
- **Targets:** native Linear (one issue per action item); Jira through an "Ask Circleback" custom connector, Zapier or Make; Asana and Todoist through Zapier; emails, Slack, HubSpot, Salesforce and Notion through automations. FACT: https://linear.app/integrations/circleback , https://circleback.ai/blog/circleback-automation-setup-guide
- **Mode:** a **rule-based auto-run** after every meeting, filtered by tag, title or participants. For email the user picks **send or draft**, and the audience: all, external only or internal only. FACT: https://circleback.ai/blog/circleback-automations-you-should-build . I found no per-item approval step for Linear issues. INFERENCE from the integration page.
- **Price:** Pro about $15–21/month; sources conflict. UNVERIFIED.

### Fireflies
- **Targets:** native Jira integration that "automatically turns your conversations into actionable Jira issues", with Integration Rules on Business and above; many more through Zapier, Make and Relay. FACT: https://guide.fireflies.ai/articles/6214483081-how-to-integrate-jira-with-fireflies
- **Talk to Fireflies** (2025-06-12, Perplexity web search, "Hey Fireflies") answers questions live in the meeting. I found no evidence that it acts in other systems. FACT: https://fireflies.ai/blog/talk-to-fireflies-perplexity/ , https://guide.fireflies.ai/articles/8186888414-talk-to-fireflies-in-live-meetings (updated 2026-09-28). "AI Skills" generate emails and reports: https://fireflies.ai/apps . I found nothing called "AI Apps"; UNVERIFIED.
- **Mode:** auto-push governed by rules. INFERENCE.

### Otter
- **Meeting Agent** (voice in the call) schedules follow-up calls and drafts emails. FACT (press): https://www.engadget.com/ai/otterais-meeting-agent-can-schedule-calls-and-write-emails-for-you-130048189.html . The launch date is UNVERIFIED (I believe it was 2025). Business plan per Product Hunt, "all users" per UC Today; the two conflict, UNVERIFIED.
- **Jira AI Chat Connector** (blog, July 2026): pulls Jira context into a meeting and pushes outcomes to Jira "when a call ends". FACT (vendor blog): https://otter.ai/blog/ship-the-ticket-not-just-the-meeting-notes . Push to a Notion page or a **Gmail draft** the moment a call ends. FACT (vendor blog, April 2026, via search summary).
- **Approval UX:** not documented in anything I found. UNVERIFIED.
- **Trust incident:** in 2024 the auto-share setting emailed a full transcript to all attendees, including investors' private talk after a guest had left. FACT (press): https://fortune.com/2024/10/06/ai-assistants-ratting-out-for-badmouthing-coworkers/

### Read.ai
- **Ask Read actions** (January 2026): update a CRM deal, **send** an email, set up a meeting. The email flow is conversational: Ask Read drafts, the user revises, then types "Send it." FACT: https://support.read.ai/hc/en-us/articles/48863788829971-Using-Ask-Read-actions
- **Ada** (2026-02-26): an email-based "digital twin" for scheduling and questions. FACT (press): https://techcrunch.com/2026/02/26/read-ai-launches-an-email-based-digital-twin-to-help-you-with-schedules-and-answers/
- **Asana:** per item, the user edits title, description and assignee before sending; Premium only. FACT: https://read.ai/integrations/asana . Native Linear per the Read blog; UNVERIFIED.

### Fathom (now part of Superhuman)
- **Targets:** "Sync to Asana" button per action item, tasks go only to the user's own account. FACT: https://help.fathom.video/en/articles/7639617 . HubSpot auto-sync; Jira and other CRMs through Zapier; MCP for ChatGPT and Claude. FACT: https://www.fathom.ai/integrations-workflow-automation
- **Superhuman Go** "draft follow-up emails and recaps straight from your meeting notes" and "manage tasks across tools". FACT (marketing): https://superhuman.com/plans/go , https://blog.superhuman.com/superhuman-expands-go-unveils-personal-ai-assistant

### tl;dv
- **Targets:** CRM Update Agent (HubSpot, Salesforce), Slack, Notion; recurring AI reports by email on a **schedule**. FACT: https://tldv.io/ai-agents-for-meetings/ , https://tldv.io/blog/tldv-recurring-ai-reports/ . I found no native Jira integration. Approval UX not documented.

### Avoma
- **AI Tasks** detects commitments such as "I'll send the proposal by Friday" and turns them into tasks with owners; it fills CRM fields automatically; follow-up email drafts are **reviewed and sent by the rep**. FACT (vendor): https://www.avoma.com/blog/ai-tasks , https://www.avoma.com/ai-meeting-assistant/meeting-follow-up-software . The time-saving figures are vendor claims; I don't repeat them.

### Jamie
- Sends action items to Asana (Pro and up) and Notion (auto-sync); webhooks for Zapier and Make; an MCP server. A January 2026 changelog says integrations now push action items, not only notes. FACT: https://docs.meetjamie.ai/integrations/asana , https://www.meetjamie.ai/changelog . It pushes; it does not propose. INFERENCE.

### Notion AI Meeting Notes
- **Notion Agent** assigns tasks with owner, priority and due date, and updates project status after a meeting. FACT (marketing): https://www.notion.com/product/ai-meeting-notes . The template gallery has a "Meeting Notes Task Creator" agent, and a "Meeting Action Extractor" that **posts to Slack for approval before creating** tasks. FACT: https://www.notion.com/templates/collections/more-than-meeting-notes
- Business $20/member/month; AI credits $10 per 1,000. UNVERIFIED (undated pages).

### Zoom AI Companion 3.0 / ZoomMate
- A Post-Meeting Follow-Up template generates tasks and **drafts** emails. The **Tasks** tab detects action items in summaries, chat and email, and can complete some (schedule a follow-up, generate a document). FACT: https://investors.zoom.us/news-releases/news-release-details/zoom-launches-ai-companion-30-agentic-workflows-transforming
- Custom AI Companion ($12/user/month add-on) can create and update Jira tickets during the meeting. FACT: https://investors.zoom.us/news-releases/news-release-details/zoom-rolls-out-new-agentic-ai-offerings-save-time-and-drive . **ZoomMate** (June 2026) "takes action": schedules follow-ups, updates records. FACT (marketing): https://www.zoom.com/en/blog/zoom-ai-companion-zoommate/
- **Complaint:** AI Companion assigned an action item to someone who was not in the meeting. FACT (user post): https://community.zoom.com/ai-companion-21/ai-companion-and-hallucinations-75452

### Microsoft Teams Facilitator
- Captures tasks **live**. The user clicks **"Accept to sync"** under Follow-up tasks to send them to Planner. Participants can also ask in chat to create, edit or assign tasks. FACT: https://support.microsoft.com/office/facilitator-in-microsoft-teams-meetings-37657f91-39b5-40eb-9421-45141e3ce9f6
- Since MC1392571 (2026-06-15, updated 2026-08-10) a meeting can be linked to an existing Planner plan. FACT: https://mc.merill.net/message/MC1392571 . Needs a Microsoft 365 Copilot licence.

### Google Meet (Gemini)
- "Suggested next steps" can be reviewed, edited and assigned (2025). FACT: https://workspaceupdates.googleblog.com/2025/02/google-meet-take-notes-for-me-next-steps.html
- **2026-10-12:** the post-meeting screen offers routine next steps: **draft a follow-up email** and **add action items to Google Tasks**, turned on with one tap, for one meeting or **all meetings**. Enterprise Standard/Plus. FACT: https://workspaceupdates.googleblog.com/2026/10/find-your-routine-next-steps-on-post-meeting-screen-in-Google-Meet.html
- **INFERENCE:** this is the most polished "propose once, then make it a rule" design in the market, but it only reaches Google's own products.

### Claude Meetings + Cowork
- Claude Meetings has action items and nothing more (see file B). Cowork does the acting through connectors, with **per-tool permission**: "Needs approval" or "Always allow". In Auto mode Claude may approve on its own. UNVERIFIED (third-party docs): https://tactiq.io/learn/claude-cowork-connectors
- Users build a "meeting → Asana subtasks" skill themselves. FACT (user post): https://forum.asana.com/t/how-we-use-a-custom-claude-cowork-skill-to-keep-asana-current-after-every-meeting/1145498 . Scheduled tasks in Cowork: https://claude.com/resources/tutorials/delegating-and-scheduling-tasks-in-claude-cowork
- **INFERENCE:** if Parka ships, Anthropic gets bot-less capture plus an agent hand-off, still in the cloud.

### ChatGPT Meetings plugin (successor to Record)
- macOS app, Pro and Business plans, beta. It "suggests follow-up action items, such as drafting an email or updating a project plan". The user can "review and edit each suggested action item, then start it with one click". FACT: https://help.openai.com/en/articles/20001546-the-meetings-plugin-in-chatgpt
- **INFERENCE:** the closest match to the owner's idea (suggest → edit → one click to run), but in the cloud, with no rules and no local option.

### Proactive challengers
- **Coworker.ai:** drafts CRM updates, Jira tickets and emails; "nothing is sent or saved until the user clicks Execute", with editable fields. Auto-run can be switched on **per integration**. FACT (vendor help): https://intercom.help/coworker-ai/en/articles/14742523-understanding-draft-actions-for-write-operations
- **Shadow 2.0** (Mac, bot-less): "Skills" run when the call ends (email draft, CRM, scheduling; Gmail, Calendar and Notion first). The maker says users can review, edit, reject or approve before anything is sent. UNVERIFIED (vendor comment and one review): https://theaiagentindex.com/agents/shadow . Transcription is on-device per the vendor; the LLM location is unknown.

### Local / open source
- **Meetily:** fully local (Whisper or Parakeet + Ollama); action items only; no tracker integration found. FACT: https://github.com/Zackriya-Solutions/meetily
- **Anarlog (ex-Hyprnote):** local-first, with a local MCP server; acting is left to the agent that connects to it. FACT (file B).
- **HoldSpeak** (open source): turns decisions into proposals the user confirms before anything is created in GitHub, Jira, Slack or email. FACT (README): https://raw.githubusercontent.com/karolswdev/HoldSpeak/main/README.md . Tiny project; how much runs locally is UNVERIFIED.
- **Off Grid AI Desktop** (AGPL): a local model with Linear, Jira and Notion MCP; writes need approval; not a meeting recorder. UNVERIFIED (dev.to): https://dev.to/alichherawalla/how-to-connect-notion-linear-and-jira-to-a-local-ai-private-mcp-2f2h
- **Ghosty Notes:** on-device transcription + Ollama + its own MCP server; it does not create tickets. UNVERIFIED: https://mcpservers.org/servers/ghostynotes-app

---

## 2. Complaints about wrong or unwanted actions

- **Wrong owner:** Zoom assigned an action item to a non-attendee (Zoom Community, link above). A guide reports a Gemini user being assigned stories they never agreed to; the typical failure is assigning a task to whoever **mentioned** it rather than whoever **accepted** it. UNVERIFIED (blog): https://gotranscript.com/en/blog/red-flags-in-ai-summaries
- **A wrong item becomes the official record:** the Copilot complaint pattern is less "the AI is imperfect" and more that "a wrong action item starts to look like official record". UNVERIFIED (blog): https://venture-lab.org/2026/copilot-meeting-notes-wrong/amp/
- **Auto-send leaks:** Otter's automatic transcript emails (Fortune 2024, above). The consent class action (N.D. Cal. 25-cv-06911) is covered in file B.
- **Speaker mislabelling, decisions mixed into discussion, items that still need cleanup** recur in Reddit threads, according to one blog. UNVERIFIED (second-hand): https://www.lilachbullock.com/ai-meeting-notetaker-problem/
- I found **no** documented incident of a meeting tool auto-creating a wrong Jira ticket or calendar event. Nothing conclusive; it may just be under-reported.

## 3. What a trustworthy approval UX looks like (from the patterns above)

INFERENCE, built from the FACT rows:
1. **Draft by default, execute on click.** Teams "Accept to sync", ChatGPT "start it with one click", Coworker "Execute", Read's "Send it."
2. **Every field editable before execution.** Owner, due date, project, recipients (Read/Asana, Coworker).
3. **Risk tiers.** Internal and reversible actions (a task in my own list) can graduate to auto-run; external actions (email to a client, a calendar invite to others) always need a click. Coworker and Cowork both switch auto-run **per integration**; Circleback splits internal and external email audiences.
4. **Graduation from suggestion to rule.** Google's "apply this next step to all meetings" turns a repeated confirmation into a rule without a settings screen.
5. **Evidence attached.** Each proposal links to the transcript moment and the speaker who **accepted** the task, which addresses the wrong-owner complaints directly. INFERENCE: nobody shows this prominently today.
6. **No silent fan-out to attendees.** The Otter lesson.
7. **One review place after the meeting**, not pop-ups during it. Teams Follow-up tasks, Meet post-call screen, ChatGPT meeting page.

## 4. Is "local + proactive with approval" taken?

**Partly taken at the edges; the core is empty.** INFERENCE:
- The **approval pattern is crowded and converging**: Microsoft, Google, OpenAI, Coworker, Read and Notion templates all use draft → edit → one click. It is not a differentiator in itself.
- **Every proactive product is cloud.** The platforms (Zoom, Teams, Meet) only act inside their own suites. The independents (Circleback, Fireflies, Otter, Read, Avoma, tl;dv) mostly **auto-push by rule** rather than propose.
- **Local tools stop at action items or an MCP server**: Meetily, Anarlog, Ghosty. They hand acting to someone else's agent, which is usually cloud. HoldSpeak and Off Grid show the idea but are hobby-scale.
- **Closest threats:** Shadow (bot-less Mac, on-device STT, approval-gated Skills; LLM location unclear) and a shipped Parka (bot-less, `autoRunnable` agent hand-off, cloud).
- **Open slot for Lintel:** on-device transcription and LLM decide what to propose; an encrypted local queue of proposals with transcript evidence; then only the approved payload leaves the Mac to Jira, calendar or mail. I found no shipped product that does this end to end. Note: the execution step necessarily calls the target's cloud API, so "local" means the **reasoning and the data** stay local, not the action.

---

## 5. Comparison table

P = proposes and waits; A = auto-executes by rule; D = drafts only (user sends). "?" = not found.

| Product | Targets (native unless noted) | Mode | Approval UX | When | Where it runs | Price (source quality) |
|---|---|---|---|---|---|---|
| Granola | Slack, Notion, HubSpot, Attio; Jira/Linear/Asana via Zapier; MCP, API | A (Zap) or manual push | None native | After meeting | Cloud | Business $14/user (FACT) |
| Circleback | Linear; Jira via connector/Zapier; email, Slack, CRM | A by rule; email send or D | Rule filters, internal/external split | After every matching meeting | Cloud | ~$15–21 (UNVERIFIED) |
| Fireflies | Jira native; much via Zapier/Make | A with Integration Rules | Rules (Business+) | After meeting; live Q&A only | Cloud | ? |
| Otter | Jira connector, Gmail draft, Notion; Meeting Agent schedules | A / D | Not documented | Live (voice) + after | Cloud | Business (conflicting) |
| Read.ai | CRM, email send, meetings, Asana, Linear | P (chat) | Draft → revise → "Send it"; Asana per-item edit | On request + after | Cloud | Premium (FACT for Asana) |
| Fathom / Superhuman Go | Asana button, HubSpot auto, email drafts | P (button) / A (HubSpot) / D | Per-item button | After meeting | Cloud | ? |
| tl;dv | HubSpot, Salesforce, Slack, Notion | A | ? | After + scheduled reports | Cloud (EU storage) | ? |
| Avoma | CRM fields, tasks, email drafts | A (CRM) / D (email) | Rep reviews email | After meeting | Cloud | ? |
| Jamie | Asana, Notion, webhooks, MCP | A / manual share | Per-integration toggles | After meeting | Cloud (EU) | Pro+ for Asana (FACT) |
| Notion AI Meeting Notes | Notion tasks/projects; Slack via template | A or P (template) | Slack approval template | After meeting | Cloud | $20/member (UNVERIFIED) |
| Zoom AI Companion / ZoomMate | Zoom Tasks, email drafts, Jira (Custom AI) | P / D; "takes action" (ZoomMate) | Tasks tab | Live + after | Cloud | Custom AI $12/user add-on (FACT) |
| Teams Facilitator | Planner, Loop/Word docs | P | "Accept to sync" | Live capture, review after | Cloud | M365 Copilot licence |
| Google Meet Gemini | Google Tasks, Gmail draft | P → rule | One tap; "apply to all meetings" | After meeting | Cloud | Enterprise Std/Plus (FACT) |
| Claude Meetings + Cowork | Any Cowork connector | P or auto per tool | "Needs approval" / "Always allow" | After / scheduled | Cloud | Team/Enterprise |
| ChatGPT Meetings | ChatGPT Work + connected apps | P | Edit item → one-click start | After meeting | Cloud (Mac app) | Pro, Business (FACT) |
| Coworker.ai | CRM, Jira, Gmail | P (auto per integration optional) | Review card → Execute | After meeting | Cloud | ? |
| Shadow 2.0 | Gmail, Calendar, Notion, CRM | P (claimed) | Review/edit/reject (claimed) | When the call ends | On-device STT; LLM ? | Plus $8/mo (file B) |
| Meetily | None (action items only) | — | — | After | **Local** | Free / Pro $10 |
| Anarlog (ex-Hyprnote) | Local MCP server (external agent acts) | — | Depends on the agent | After | **Local-first** | OSS + Pro |
| HoldSpeak | GitHub, Jira, Slack, email | P | Confirm proposals | After | Local? (UNVERIFIED) | OSS |
| **Lintel (target)** | Jira, calendar, mail (planned) | P → optional rule | Inbox with transcript evidence | After meeting | **On-device reasoning, encrypted** | — |
