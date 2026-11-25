# Chat over meeting notes: UX patterns — 2026-11-23

Builds on `2026-11-13-meeting-notes-market-B.md` (which products have cross-meeting chat at all) and `2026-11-23-proactive-meeting-actions-market.md` (actions after a meeting). This file does not repeat their product lists or action-item tables. It looks at how the chat is built: scope, grounding, editing, entry points, hand-off to actions, local/private angle and complaints.

**Method.** Web searches and page fetches run on 2026-11-23. Several pages could not be opened (Otter help centre 403, Read.ai help centre 403, ChatGPT/Claude app screens not seen), so some rows rest on search-result excerpts. Labels: **FACT** = stated on the vendor's own page or help centre; **INFERENCE** = my reading; **UNVERIFIED** = third-party, marketing-only, a single anecdote, or the sources conflict. Nobody here used the products hands-on, so "what it looks like" is only what the docs say.

**Big caveat on complaints.** I found no Reddit thread about chat over notes. Searches returned review blogs (several written by competitors), G2/Trustpilot excerpts and one HN thread about AI notetakers in general. Section 5 is therefore mostly second-hand. No measured error rate for cross-meeting chat was found for any product.

---

## 1. Per product

### Granola (the reference)
- **Scope.** Three places to start: home (all notes), one meeting, a folder, a People/Companies page (desktop only), or a hand-picked set of meetings via checkboxes. "Granola Chat automatically searches the meetings in your current view"; the doc describes no separate scope badge. FACT: https://docs.granola.ai/help-center/getting-more-from-your-notes/chatting-with-your-meetings
- **Default depth.** On home or in a folder the default is note summaries of the 40 most recent meetings; the user can switch to all meetings in view, or to full transcripts limited to the 25 most recent. FACT (search excerpt of the help article; the page I fetched did not repeat it, so the docs may be inconsistent): https://help.granola.ai/article/chatting-with-your-meetings
- **Retrieval design.** April 2026 rebuild: chat is "agentic", tells quick questions from deep ones, and passes only matching chunks into context rather than whole transcripts (a one-hour meeting is 60,000–80,000 characters). The team chose "100 meetings at a high level over 10 in detail"; pattern "search, shortlist, read, repeat". FACT: https://www.granola.ai/blog/granola-chat-just-got-smarter , https://www.granola.ai/blog/how-granola-thinks-about-designing-agents , https://www.granola.ai/blog/how-we-help-your-agent-find-what-its-looking-for (excerpt)
- **Citations.** Inline citations link to the meeting note where a statement was made; chat "flags which notes it is referring to so you can redirect it to other notes"; the design post says "Chat shows what it looked at" ("Coverage Notes"). The 2025 launch post said hovering a reference shows the meeting it comes from (via a review excerpt, UNVERIFIED). FACT for note-level links; I found no evidence of links to a **transcript moment**.
- **Trust stance.** "An answer that sounds certain while being wrong can break trust quickly." FACT (design post).
- **Editing notes.** Desktop only (Mac, Windows). Words such as "rewrite" in the prompt let chat change a note: make it more or less detailed, fix names, reassign action items, translate; highlight a passage before opening chat to target it. FACT (help article). First announced 2025-07-24 ("You can now ask Granola on Mac or Windows to make edits to your notes"). FACT: https://www.granola.ai/updates/edit-notes-just-by-asking . I found **no documentation of diff, accept/reject or undo** for these edits. Nothing conclusive.
- **Recipes.** Saved, static prompt templates (no variables), opened with `/` in the chat bar or from the sidebar. Each recipe is either single-meeting or multi-meeting, never both, and appears in matching contexts only. Shareable as private, workspace or link; "Remix" makes an editable copy; a Discover tab lists community recipes. FACT: https://docs.granola.ai/help-center/getting-more-from-your-notes/recipes
- **Entry points.** Chat bar at the bottom of the window (desktop and mobile); Android home "Ask anything" bar once there are 3 notes. No suggested-question list in the doc, only use-case examples (before, during, after, across meetings). FACT.
- **History/privacy.** Chat history is private even when a note is shared. Chat sees only notes, transcripts and files added to folders. Model: Basic uses Auto; Business/Enterprise can pick a model; the provider is not named on the page. FACT.
- **Plan limit.** Basic searches the last 30 days; Business/Enterprise have full history. Price: Basic $0, Business $14, Enterprise $35 per user/month (FACT: https://www.granola.ai/pricing , from file B).
- **Local/cloud.** Cloud.

### Otter AI Chat
- **Scope.** Chat inside one conversation, and a global chat that searches "all meetings the user has access to". FACT (launch coverage, 2024: https://techcrunch.com/2024/02/13/otter-brings-genai-to-your-meetings-with-ai-summaries-ai-chat-and-more ; Business Wire). Folder scoping: not confirmed.
- **Citations.** A "View sources" control opens a list of every conversation behind an answer; the sources panel may show more than the answer text names. A newer overview says sources are visible for every response and clicking one opens it. FACT (search excerpts of help.otter.ai: https://help.otter.ai/hc/en-us/articles/19890167963159-Otter-AI-Chat , https://help.otter.ai/hc/en-us/articles/19682180167575-Otter-AI-Chat-Overview ; pages returned 403 when fetched). Link granularity (whole conversation vs transcript moment) not confirmed. The older in-conversation chat answered "solely based on the provided meeting transcript" (FACT, older article, may be outdated).
- **Editing.** Not found.
- **Other.** Free tier had a per-meeting question cap at launch (2023, may be outdated). A hands-on review measured about 30 s per answer, no invented facts in a misleading-question test, but wrong task owner and misread deadline (UNVERIFIED: https://www.unite.ai/otter-ai-review/ via search excerpt).
- **Local/cloud.** Cloud. Plans and prices: see file B (secondary).

### Fireflies, Global AskFred
- **Scope.** Defaults to your meetings; Web Search is off until turned on. Narrow with `@` or the `+` menu to a meeting, a teammate or a user group. Connectors (Gmail, Slack, HubSpot, Notion, Drive, Jira, custom MCP) work only if enabled. FACT: https://guide.fireflies.ai/articles/1512776728-learn-about-global-askfred
- **Citations.** The help article does not describe them; marketing says answers show where the information came from. UNVERIFIED for format and granularity.
- **Entry points.** Left nav item, Home chat bar, top Search bar ("Try AskFred"), and **Ctrl/Cmd+J from anywhere in the app**. Per answer: Copy, rate, view AI credits, **Save as Skill**, Share. Chats are saved, searchable and grouped by time. FACT.
- **Privacy catch.** Shared answer links are public to anyone with the link; admins cannot see or disable members' links. FACT.
- **Cost.** Every request uses AI credits; model selector defaults to Auto. FACT.
- **Local/cloud.** Cloud.

### Read.ai (Ask Read / Search Copilot)
- **Scope.** Searches "what you can see": your meetings and connected apps, using Read's own models with retrieval; it does not reach other people's content unless shared. The paid-plan model picker (OpenAI or Anthropic) applies to web search only, not to your meetings. FACT (search excerpt of https://support.read.ai/hc/en-us/articles/39009378777875 ; page returned 403).
- **Citations.** Product pages say answers include links to sources. Granularity not confirmed.
- **Actions.** Covered in the actions file: draft, revise, type "Send it"; the user also gets a copy of the email. CRM update confirmation is not documented. Scheduled workflows re-run a search on a cadence and email the result. FACT (search excerpt): https://support.read.ai/hc/en-us/articles/48863788829971
- **Price.** Support page says Ask Read is free to all Read users; free-tier meeting limits conflict (5 vs 10 per month). UNVERIFIED.

### Fathom (Ask Fathom)
- **Scope.** Per recording page, per Deal View, per folder (Team plan, panel on the right), and **Account-Wide**, where Team plans get a dropdown: My Calls, Team Calls, All Calls. Free/Premium users search My Calls only and see no dropdown. FACT: https://help.fathom.video/en/articles/3239425 , https://help.fathom.video/en/articles/10390017
- **Retrieval.** Account-wide uses keyword search over titles, participants and transcripts for specific questions and call summaries for broad themes (October 2026 change). It excludes deal data, scorecards and AI Search/Trackers. FACT.
- **Citations.** Not described on either help page. Nothing conclusive.
- **History.** "Currently, Ask Fathom's history is not saved"; results are lost when you leave the call view. FACT.
- **Access.** Premium and Team only. Cloud.

### Jamie
- **Scope follows location.** "Inside a meeting, it answers about that meeting. In the meetings list, it searches across all of them." Filter by tag (project, client, team) first to narrow. FACT: https://docs.meetjamie.ai/getting-started/ask-ai
- **Citations.** Lists the meetings it used under each answer; reads transcripts when it needs exact wording. Timestamp links not documented. FACT/UNVERIFIED as noted.
- **Editing.** Can rewrite summaries; **changes appear live and an Undo button restores "the previous version"**. FACT (same page).
- **Actions.** Creates and assigns tasks, updates Salesforce, HubSpot, SharePoint, etc. The doc warns "Ask Jamie makes changes in your connected tools straight away"; to review first the user must ask for a draft. Web search can be switched off by admins. FACT. This is **act first, review only on request**.
- **Cloud**, EU data residency per file B.

### Circleback (Ask Circleback)
- **Scope.** "Every meeting you have access to", plus email if connected; a single call can be targeted. FACT: https://circleback.ai/docs/support/ask-circleback/ask-circleback
- **Citations.** "Answers that draw on your conversations include sources. Hover over a source to see specific references, or select it for full context." FACT: the hover-to-preview pattern is a useful reference.
- **Editing/actions.** Chat can edit notes, rename meetings, create/edit/assign/complete/**delete** action items, manage tags, folders and sharing, and create/update issues, CRM records and pages in connected apps. **The page describes no approval step.** FACT/INFERENCE.
- **Entry points.** Dedicated Ask page, right-hand panel on a meeting, mobile, Slack, search modal (`/` key) with history. No saved prompts mentioned.

### Fellow (Ask Fellow)
- **Scope pill.** Focus comes from the page you open it on (a meeting, a channel, a filtered list). An `@` pill beside the message box shows it, hover reveals filters, focus is set by the first message and stays for that chat; **click the X on the pill to search all meetings**. FACT: https://help.fellow.ai/en/articles/9077100-ask-fellow-your-ai-powered-meeting-assistant . This is the clearest "visible, removable scope" design found.
- **Citations.** Web answers link their sources; meeting-answer citations are claimed in marketing (UNVERIFIED).
- **Editing.** Only notes the user can already edit; reads the agenda first; works best when you name the section. Applying a template **replaces** the agenda. Drafts (email, docs) can be revised repeatedly before sending; clip creation shows a **transcript preview for approval**. FACT.
- **Entry points.** Meeting page, channel, All/My meetings, main chat; "Try it" example prompts per capability. No hotkey documented.

### Notion AI
- **Editing pages.** Select text or blocks, then "Edit with AI"; changes are not applied automatically: "accept or discard" or retry. FACT: https://www.notion.com/help/notion-ai-faqs
- **Agent approval modes.** Always ask (nothing happens until approved); **Review for me** (default; the agent self-reviews and pauses only on what it flags; "won't always flag the same things you would"); Skip all approvals (admins can disable). Reads need no approval. Mode switch sits at the top of the chat. FACT: https://www.notion.com/help/choose-how-notion-agent-asks-for-your-approval
- **Undo.** Ask the agent to reverse; page history restores earlier versions (retention 7 days Free, 30 Plus, 90 Business, unlimited Enterprise); sent email or Slack messages must be fixed in that app; no single "undo last AI edit" button found. FACT: same page, https://www.notion.com/help/duplicate-delete-and-restore-content (excerpt).
- **Meeting notes Q&A.** Meeting notes are "searchable with Notion AI"; no dedicated meeting Q&A feature described. Scope respects workspace permissions. Third-party review says no speaker ID or timestamps (UNVERIFIED).
- **Cloud**, Business $20/member/month (file B).

### Wispr Flow Notetaker ("Ask Wispr", newcomer, Mac August 2026)
Worth reading closely: its help page is the most explicit about chat behaviour found.
- **Scope.** Meeting "Ask anything" field = one meeting; Notetaker hub bar = all meetings; pasting a shared-meeting link adds a shared note (owner-only privacy respected). For long ranges "narrow the question". FACT: https://docs.wisprflow.ai/articles/5694642921-ask-wispr-chat-with-your-meetings-and-notes-beta
- **Grounding.** "Cites only meetings it actually read, flags uncertain speaker attribution, and says what it couldn't find." If an answer draws on another meeting, the **first line names and links it**. When nothing matches it says so and suggests adding a title, person or time. FACT. Citation chips show only when a valid link exists; the meeting chat drawer shows no chips (copied answers keep source labels). FACT: https://docs.wisprflow.ai/articles/4251565280-troubleshooting-notetaker-transcripts-summaries-and-the-hub-beta (excerpt)
- **Editing.** "Questions never overwrite your notes. Edits happen only when you explicitly ask", target sections, **save automatically with no confirmation step**, reviewed under "My thoughts"; the AI summary is separate and cannot be blanked; read-only notes cannot be edited. FACT.
- **Actions.** Email or page creation produce an editable **draft card**; an outside-the-organization recipient triggers a notice; it will not re-send something already sent. FACT.
- **Capture.** Bot-less local audio recording; chat in the cloud. FACT (Computerworld, 9to5Mac in search results).

### ChatGPT Meetings plugin
- Chat over meetings, including earlier ones ("our last meeting"); you can add your own notes next to the generated summary; suggested action items are edited and then started with one click; pages private by default; audio deleted from Mac and OpenAI servers once notes are ready. Citation behaviour not documented; shared pages give no transcript access. FACT: https://help.openai.com/en/articles/20001546-the-meetings-plugin-in-chatgpt . Mac beta, Pro and Business. Cloud. The file-B complaint about meeting content mixing with chat memory stays UNVERIFIED.

### Claude Meetings (follow-up Q&A)
- The meeting page holds the live transcript and a chat with Claude; the chat is internal (guests cannot see it); in a regular Claude chat you can ask about past meetings you have access to (third-party guide, UNVERIFIED): https://fellow.ai/blog/claude-meetings/ . Citation behaviour not confirmed. Answers during the call are written to the Meet chat. Team/Enterprise only (file B).

### Apple Notes / Apple Intelligence
- Recording in Notes offers a transcript and a Summary button; I found no question-answering over transcripts or notes, and nothing on macOS 27 chat. FACT (absence in search): https://support.apple.com/guide/mac-help/mchl2102c2ae/mac . File B: Polish is not supported.

### Local / open source
- **Meetily.** "Chat with Meetings" is listed as "coming soon"; summaries use Ollama or a built-in model; local SQLite. FACT (README via search): https://github.com/Zackriya-Solutions/meetily . No shipped local chat.
- **Anarlog (ex-Hyprnote).** Chat can answer about one meeting or several; transcription and the summary/chat model are configured separately; providers include Ollama and LM Studio so chat can stay on the machine; in-note prompts like "action items" or "rewrite in simpler language" appear in older README text. UNVERIFIED (README-level and one untested third-party review): https://github.com/fastrepl/anarlog , https://www.promptquorum.com/power-local-llm/anarlog-review . I could not find how its chat shows sources or edits notes.

---

## 2. Comparison table

"?" = not documented in anything I could open. "Provider choice" means the user can pick the model/provider.

| Product | Scope (how picked, shown) | Citations | Edits notes via chat | Entry point | Action approval | Where it runs | Price (source) |
|---|---|---|---|---|---|---|---|
| Granola | Home, meeting, folder, People/Company, hand-picked set; follows current view; no badge | Inline links to the note; "shows what it looked at"; no transcript-moment link found | Yes, desktop; highlight to target; diff/undo ? | Chat bar; `/` Recipes | None native (Zapier) | Cloud; model pick on paid plans | Free / $14 / $35 (FACT) |
| Otter | One conversation or all | "View sources" list | ? | Chat in conversation + global | ? (file actions doc) | Cloud | secondary |
| Fireflies | Default all; `@` meeting/person/group; web off by default | Claimed, format ? | ? | Nav, Home bar, Search, Cmd/Ctrl+J | Connectors, enabled per app | Cloud | AI credits per request (FACT) |
| Read.ai | What you can see | Source links claimed | ? | Ask Read page | Draft, then "Send it" | Cloud | Free to Read users (FACT, limits conflict) |
| Fathom | Call, deal, folder, account-wide with My/Team/All dropdown (Team) | Not documented | ? | Right panel | Per-item button (actions file) | Cloud | Premium/Team only |
| Jamie | By location; tag filter | Lists meetings used | Yes, live, **Undo** | Chat in meeting / list | **Acts immediately** unless asked for a draft | Cloud (EU) | secondary |
| Circleback | All you can access; one call targetable | Hover to preview, click for context | Yes (notes, action items incl. delete) | Ask page, meeting panel, Slack, `/` search | **None described** | Cloud | secondary |
| Fellow | Page-derived, removable `@` pill | Web sources linked; meetings claimed | Yes, only editable notes; template replaces agenda | Meeting, channel, lists | Drafts revisable; clip preview approval | Cloud | ? |
| Notion AI | Workspace permissions | "with citations" (marketing) | Select, accept/discard; agent edits with approval modes; page history | Side panel / Edit with AI | Always ask / Review for me (default) / Skip | Cloud | $20/member (file B) |
| Wispr Notetaker | One meeting vs hub (all) vs shared link | Cites only what it read; first line names other meetings | Yes, only on explicit request, auto-save, no confirm, "My thoughts" section | Meeting field, hub bar | Editable draft card; external-recipient notice | Local capture, cloud chat | ? |
| ChatGPT Meetings | Meetings, incl. earlier | ? | Add own notes | Mac app | Edit, then one click | Cloud | Pro/Business (FACT) |
| Claude Meetings | Meeting page chat; past meetings in normal chat | ? | ? | Meeting page, Claude chat | Per-tool in Cowork (actions file) | Cloud | Team/Enterprise (file B) |
| Apple Notes | n/a | n/a | n/a | n/a | n/a | On-device transcript | Free |
| Meetily | Chat "coming soon" | n/a | n/a | n/a | n/a | Local | Free / Pro $10 |
| Anarlog | One or several meetings | ? | In-note prompts (older README) | In-note chat | n/a | Local-first, provider choice | OSS + Pro |

---

## 3. Patterns that build trust (INFERENCE built on the FACT rows)

1. **Scope follows where you are, and is visible and removable.** Jamie, Granola, Fathom and Wispr tie the scope to the screen. Fellow shows it as a pill you can clear with one click. Nobody I found tells you in the answer how much was *not* searched (Granola's 40-summaries / 25-transcripts default is documented but not shown in the answer).
2. **Say what was read.** Wispr "cites only meetings it actually read", names a second meeting on the first line, flags uncertain speaker attribution and says what it could not find. Granola's "Coverage Notes" and Otter's "View sources" are weaker forms. This is the closest the market gets to an explicit "I don't know" behaviour.
3. **Hover to preview, click for context** (Circleback) beats a bare link. Granola and Jamie link to the meeting; nobody documents a jump to the exact transcript moment with speaker and time. That is the open grounding slot.
4. **Questions never edit; edits only on explicit request** (Wispr, Granola via "rewrite" wording). Notion separates reading (no approval) from changing (approval).
5. **Edits should be reversible without a mental model.** Jamie's Undo button and Notion's page history are the only documented reversal paths. Granola, Wispr and Circleback document edits with no diff, accept/reject or undo (Wispr: auto-save, no confirmation).
6. **Keep the AI's text and the user's text apart.** Wispr keeps the summary separate from "My thoughts"; ChatGPT keeps your notes beside the generated summary; Granola's core idea is typed notes plus transcript. Chat edits that overwrite human-written text are the risk.
7. **Approval scales with blast radius.** Notion's three modes and its default "Review for me" show the market accepting self-review, with the admission that it "won't always flag the same things you would". External recipients trigger extra confirmation (Wispr). Jamie's "acts straight away" and Circleback's undocumented approval are the opposite end.
8. **Privacy of the chat itself.** Granola: chat history is private even when the note is shared. Fireflies: public share links admins cannot see. Wispr: shared-note chats stored only on the device and deleted if access is revoked.
9. **Reading is free, writing is gated.** The same split appears in the actions file.

## 4. Context-window strategy as publicly described

- Granola: default to summaries of the 40 most recent meetings; opt-in full transcripts for 25; agentic search, shortlist, read, repeat; chunk retrieval instead of whole transcripts. FACT.
- Fathom: keyword search for specifics, summaries for themes. FACT.
- Wispr: starts from the most recent discussion in a meeting and can go back on request; asks the user to narrow busy ranges. FACT.
- Read.ai: "retrieval-augmented generation" (RAG). FACT (excerpt).
- Nobody publishes a recall figure. INFERENCE: the common shape is "summaries first, transcript on demand", which fits a local LLM with a small context window better than "load everything".
- Local angle: only Anarlog (provider choice including Ollama/LM Studio; UNVERIFIED depth) and Meetily (planned) have anything; both lack documented citations. Read.ai's provider picker applies to web search only, not to meeting data (FACT, excerpt), so even "choose your model" does not mean "your meetings stay with your provider".

## 5. Complaints (second-hand; see caveat at top)

- **Confident wrong summaries that become the record.** HN thread on AI notetakers: "they fabricate things that were never said (but always kind of close to something that was said)"; a coherent summary "may be accepted as fact"; "AI meeting notes are not transcripts"; "they can't be cross examined"; "the proof is the recording". FACT that these comments exist: https://news.ycombinator.com/item?id=48093043 . They are about summaries, not chat, but chat inherits them.
- **Dropped qualifiers.** A blog says summaries flatten "yes, as long as" into "yes" and tools do not know what was decided in earlier meetings. UNVERIFIED: https://theanalystedge.substack.com/p/ai-summarised-the-meeting-it-missed
- **Granola specifics.** One six-month reviewer estimates it invents content about twice a month, including a quote assigned to the wrong person and "not committing to Q4" turned into "committed to Q4 launch" (UNVERIFIED, single anecdote: https://undercorrect.com/reviews/granola). Another found $312,000 logged as $312.1M with no audio to check (UNVERIFIED: via file B and happyscribe). A review says Ask Granola questions and answers vanish when you leave and re-enter a meeting (UNVERIFIED; Granola's docs say chat threads can be deleted from a list, so history may have since been added).
- **Generic or slow cross-meeting answers.** A competitor (Jamie) blog says Granola chat is sometimes generic, slow and may hallucinate on large datasets. UNVERIFIED, competitor source: https://www.meetjamie.ai/blog/jamie-vs-granola
- **Otter.** About 30 seconds per answer and a wrong task owner/deadline in one review; G2 reviewers say answers are less astute than other AI models. UNVERIFIED (reviews, secondary).
- **Wrong owner of an action.** Zoom assigning a task to a non-attendee and "assigned to whoever mentioned it, not whoever accepted it" are in the actions file; same failure applies to chat that reassigns action items.
- **Public share links and auto-share.** Fireflies' public answer links (FACT), Otter's 2024 auto-share (actions file).
- **Mixing memory across meetings.** The ChatGPT complaint in file B (meeting content mixing with chat memory) is from a competitor review and is UNVERIFIED. I found no first-hand report of Granola/Otter answers pulling from the wrong meeting. Nothing conclusive.
- **Privacy.** Consent and training disputes (Otter, Granola, Fireflies) are in file B; I found no complaint specific to chat data retention.
- **What is missing.** No evidence on how often users actually click a citation, nor any measured "I don't know" rate.

---

## 6. Open slots for Lintel (INFERENCE)

1. **Citations to the exact transcript moment, with speaker, time and playable encrypted audio.** The market links to meetings or notes; I found no product documenting a jump to the sentence. Lintel keeps encrypted audio (file B), so "click the claim, hear the person" is possible and cloud competitors that delete audio cannot offer it.
2. **A visible scope pill, plus a "what was searched" line** (Fellow's removable pill; Wispr's "what I read / couldn't find"; Granola's depth settings made visible). Cheap for a local index because Lintel knows exactly which meetings and how much of each it retrieved.
3. **Edits as proposals by default.** The market splits between silent in-place edits (Wispr, Granola docs silent on review) and Notion's accept/discard. A per-change accept/reject with Undo (Jamie) on an encrypted local library is an open design: no competitor documents per-change diffs on meeting notes.
4. **Keep human-typed text and AI text separate** so chat never overwrites the user's own notes.
5. **Chat on-device, retrieval over a local index.** Nobody ships local chat with citations; Meetily lists it as planned, Anarlog's is unverified. Summaries-first retrieval fits a small local model.
6. **Polish questions over Polish meetings.** No vendor documents Polish quality for chat over notes (file B found no independent benchmark for Polish transcription either). A measured claim is open ground; so is saying so honestly when the model's Polish is weaker.
7. **A global shortcut that opens chat from the launcher** (Fireflies has Cmd/Ctrl+J inside its own app; nobody ties chat into a system launcher). Lintel already has the launcher shell (Pounce lineage); an OS-level "ask my meetings" is unclaimed.
8. **Chat to action hand-off stays in the existing approval inbox** from the actions file, so the chat does not become a second, ungated path (the Jamie/Circleback risk).

---

## 7. Product/UX questions for the owner (options with the market evidence; not decided here)

**Q1. What is the default scope when the chat opens?**
- A. Follows the screen: in a meeting = that meeting, in the library = all, in a folder/tag = that set (Jamie, Granola, Fathom, Wispr).
- B. Always global, with the user adding `@` filters (Fireflies).
- C. Follows the screen but shown as a removable pill (Fellow).
Evidence: A is the market norm; only Fellow documents making the scope visible and removable. Granola's docs show a risk of silently searching only recent summaries.

**Q2. Must every answer name its sources and what was searched, and how deep do citations go?**
- A. Meeting-level links (Granola, Jamie, Otter).
- B. Hover preview plus link (Circleback).
- C. Transcript-moment links with speaker/time and audio playback (nobody documented).
- D. Also an explicit "searched N meetings, found nothing for X" line (Wispr).
Evidence: all documented products stop at A or B; Wispr alone documents D. Hallucination complaints (HN, Granola reviews) all end in "the proof is the recording".

**Q3. When the model cannot answer, what should it do?**
- A. Say nothing found and suggest a narrower query (Wispr).
- B. Fall back to a general answer without sources.
- C. Offer to widen the scope.
Evidence: only Wispr documents the behaviour; none document a general-knowledge fallback inside meeting chat, and Fireflies/Jamie make web search a separate opt-in source.

**Q4. How does chat edit a note?**
- A. In place, on explicit request, with auto-save (Wispr, Granola docs).
- B. As a proposal with accept/discard per change (Notion "Edit with AI").
- C. In place with a visible Undo and version history (Jamie, Notion page history).
- D. Never in place: it appends to a separate "chat edits" block or creates a new version.
Evidence: no vendor documents per-change diffs on meeting notes; the safest documented separations are Wispr's separate summary and ChatGPT's "your notes beside the summary".

**Q5. May chat change the user's own typed text, or only AI-generated sections?**
- A. Only AI sections.
- B. Anything the user selects (Granola's highlight-to-rewrite).
- C. Anything, with confirmation.
Evidence: Granola and Wispr target sections or highlights; Fellow only edits notes the user can already edit. No evidence on how often users want AI to touch their own words.

**Q6. Where does the chat live?**
- A. Side panel in the note/meeting (Fathom, Circleback, Granola bar).
- B. A dedicated screen with history (Circleback Ask page, Fireflies, Wispr hub).
- C. Both, with a global shortcut from the launcher (Fireflies Cmd/Ctrl+J is the nearest).
Evidence: side panel and bar are most common; only Fireflies documents a global in-app shortcut; Fathom does not save history, Granola and Wispr do.

**Q7. Saved prompts and starter questions?**
- A. None at first.
- B. Granola-style slash recipes (single- vs multi-meeting, private/shared).
- C. Fellow-style "try it" examples per capability.
- D. Fireflies-style "Save as Skill" from a good answer.
Evidence: Granola recipes and Fireflies Skills are the two documented patterns; Fathom and Circleback have none documented. Recipes are static, no variables.

**Q8. Chat to action: does chat create tasks/emails, and with what approval?**
- A. Chat only proposes into the existing approval inbox (no direct execution).
- B. Draft card in chat, edit, then send (Wispr, Read "Send it", ChatGPT one click).
- C. Notion-style selectable mode: always ask / review for me / skip.
- D. Act immediately (Jamie default, Circleback undocumented).
Evidence: B and A are the trusted patterns; D has no documented incident but is the one the actions file flags as risky. Notion's default "Review for me" is self-review, which the vendor admits misses things.

**Q9. Local or cloud model for chat?**
- A. Local only (nothing leaves the Mac).
- B. Local default, optional user-chosen provider/key (Anarlog).
- C. User picks a cloud model per chat (Granola paid plans, Fireflies selector).
Evidence: every shipped product with citations is cloud; the local ones lack documented citations. Read.ai's picker applies to web search only, so "choose a model" can still leave meeting data with one provider. Context size: Granola's documented default is summaries of 40 meetings, transcripts for 25.

**Q10. Persistence of chats.**
- A. Saved, private, deletable (Granola, Fireflies, Wispr).
- B. Not saved (Fathom).
- C. Saved per meeting inside the encrypted library.
Evidence: loss of history is a reported annoyance (Granola review, UNVERIFIED); Granola keeps chat private when the note is shared; Fireflies' share links leak.

---

## Not done / gaps

- Could not open Otter and Read.ai help pages (403); both rest on search excerpts.
- Granola's edit feature: no documentation of diff or undo found; may exist in the app.
- ChatGPT Meetings and Claude Meetings: citation behaviour not documented in what I could open.
- No Reddit threads found for any product; user-sentiment rows are review blogs, G2/Trustpilot excerpts and one HN thread.
- No hands-on testing of any product; "what it looks like" is documentation only.
- Notion's meeting Q&A and citation format not documented beyond marketing.
