# User-added integrations for post-meeting actions — how others do it and keep writes safe (2026-11-23)

Scope: Lintel will propose actions after a meeting (Jira task, calendar event, email draft) that the user approves. The owner wants users to add apps Lintel does not support out of the box. This file covers the extension mechanisms other products use, their write-approval UX and their security record. It does not repeat the macOS channel table (EventKit, mailto, Gmail scopes, Jira/Linear tokens, Shortcuts basics) in `2026-11-23-proactive-agents-market.md` §5 or the approval-UX patterns in `2026-11-23-proactive-meeting-actions-market.md` §3.

Method: web search plus a few full page reads (MCP blog on tool annotations, MCP elicitation spec, Anthropic MCPB docs and desktop-extensions post, arXiv 2611.02527 abstract page), 2026-11-23. Other claims come from search-engine summaries of vendor pages, which I did not open in full; read them as paraphrase. Labels: **FACT** (vendor/spec page I read, or several consistent sources), **INFERENCE** (my reading), **UNVERIFIED** (single weak source, conflicting sources, or not checked). Policy context from `AGENTS.md`: "There is **no runtime loading** of code (no bundles, dylibs, scripts or extension stores)"; plugins are compile-time; Lintel ships as a notarized DMG, not through the Mac App Store.

## 1. MCP client in desktop apps

### 1.1 Config UX by product

| App | How a user adds a server | Local stdio / remote | Source |
|---|---|---|---|
| **Claude Desktop** | Two paths. (a) Remote "custom connector" by URL, OAuth handled by the app. (b) Local servers as `.mcpb` bundles: double-click, drag into the window, or Settings > Extensions > Install Extension; every route opens a screen to review details and permissions, set options and grant permissions. A `user_config` block in the manifest generates the settings UI; sensitive values stay in the OS keychain. | Both. Local runs over stdio on the user's machine, bundled Node.js runtime, no OAuth. | FACT https://claude.com/docs/connectors/building/mcpb ; https://www.anthropic.com/engineering/desktop-extensions |
| **Claude directory status** | Directory listings for desktop extensions are deprecated and the directory no longer accepts MCPB submissions; local servers ship inside a "plugin" instead. Older help pages still describe a reviewed directory with an Install button. | n/a | FACT (newer docs, same MCPB page); the older page conflict is noted, change date UNVERIFIED (https://support.claude.com/en/articles/10949351-getting-started-with-local-mcp-servers-on-claude-desktop) |
| **Claude enterprise controls** | Team/Enterprise owners can enable or disable public extensions, upload custom ones, blocklist extensions or publishers, push via MDM, disable the directory. | n/a | FACT https://www.anthropic.com/engineering/desktop-extensions ; https://support.claude.com/en/articles/10949351 |
| **ChatGPT (apps / developer mode)** | Developer mode gives full MCP client support for read and write tools; apps by connector URL. Business/Enterprise admins can restrict which actions an app may take before publishing, and some risky actions are blocked instead of offered for approval. Eligibility by plan is described inconsistently across OpenAI pages. | Remote only (as far as the pages say). | FACT for behaviour, UNVERIFIED for plan eligibility (https://developers.openai.com/api/docs/guides/developer-mode ; https://help.openai.com/en/articles/12584461-developer-mode-and-mcp-connectors) |
| **Raycast** | "Install MCP Server" command: a form; Raycast saves the config, starts the connection and loads the tool list. Also a `raycast://mcp/install` deeplink with percent-encoded JSON config, and a store extension "MCP Registry" for discovery. Local servers need Node.js or uv on the machine. | Both. | FACT (https://manual.raycast.com/model-context-protocol ; https://www.raycast.com/raycast/model-context-protocol-registry.md). Deeplink safeguards not found, UNVERIFIED. |
| **Cursor** | `mcp.json` (JSON file); one-click install links exist. | Both. | The format is FACT via LM Studio ("follows Cursor's mcp.json notation"); one-click links UNVERIFIED here. |
| **LM Studio** | Edit `mcp.json` (Cursor notation), or an "Add to LM Studio" button. MCP host since 0.3.17. | Both (remote doc exists). | FACT https://lmstudio.ai/docs/app/mcp ; https://www.infoq.com/news/2025/07/lm-studio-mcp |
| **Zed** | Settings > AI > MCP Servers > Add Server, or install from Zed extensions (context-servers filter); stored under `context_servers` in `settings.json`. | Both. | FACT https://zed.dev/docs/ai/mcp.html |
| **BoltAI (Mac)** | Runs any MCP server from v1.34; import from Cursor or Claude config, or via the Smithery CLI; config at `~/.boltai/mcp.json`. Mobile app: remote URL only. | Both on Mac. | FACT https://docs.boltai.com/docs/plugins/mcp-servers |
| **Msty Studio** | "Toolbox": STDIO/JSON for local servers, HTTP for remote; SSE not supported (use `mcp-remote` proxy). | Both. | FACT https://docs.msty.ai/studio/toolbox/tools |

INFERENCE: three UX tiers exist. (1) Paste JSON (Cursor, LM Studio, BoltAI, Zed): developer-grade, the user is asked to trust a command line. (2) A form plus a URL (Raycast, Claude connectors, ChatGPT): fits a non-developer for remote servers. (3) A signed/packaged bundle with a manifest and permission screen (MCPB): the only tier where the app shows what a local server is, but the MCPB docs I read mention no signing, sandboxing or process isolation of the server (the desktop-extensions post is silent on both) — UNVERIFIED that none exists.

### 1.2 Per-tool permission UX

- **Claude connectors:** tools are grouped as read-only vs write/delete; per tool or per group choose Always allow, Needs approval or Blocked. Custom-connector tools start at "Ask each time" in the Claude Science docs; a new Enterprise role defaults to "Needs approval". Anthropic advises "Allow always" only for trusted servers. Source-system permissions still apply. FACT (https://support.claude.com/en/articles/11176164 ; https://claude.com/docs/claude-science/custom-connectors). User reports that "Always allow" does not persist on Pro, UNVERIFIED (https://github.com/anthropics/claude-code/issues/56757).
- **ChatGPT:** write actions require confirmation by default; the app reads the MCP `readOnlyHint` and treats tools **without the hint as write**; approval can be remembered per tool and "new conversations will prompt for confirmation again". FACT (same OpenAI pages). INFERENCE: this is the most conservative read of the annotation defaults.
- **Raycast:** read-only tools are approved automatically by default, others ask; "Confirm Always" and a reset of allowed tools exist. FACT (Raycast manual above). Which signal Raycast uses for "read-only" is UNVERIFIED.
- **LM Studio:** every tool call opens a dialog showing the arguments, **editable**, with allow once / always. FACT (https://lmstudio.ai/docs/app/mcp). INFERENCE: the closest existing thing to an editable action card, but it edits raw arguments, not typed fields.
- **Zed:** `agent.tool_permissions.default` = `confirm` (default), `allow` or `deny`; per-tool regex rules `always_allow` / `always_deny` / `always_confirm`; deny wins. For MCP tools the docs say only the tool-level option is supported (key like `mcp:github:create_issue`). FACT with a caveat on regex scope (https://zed.dev/docs/ai/tool-permissions).
- **Cursor:** after CVE-2025-54136 ("MCPoison"), approval is required again every time an entry in the MCP config file changes (fixed in 1.3). FACT (https://research.checkpoint.com/2025/cursor-vulnerability-mcpoison/).

### 1.3 How write tools are surfaced

The MCP project itself says no major client surfaces annotations in approval prompts yet. FACT (https://blog.modelcontextprotocol.io/posts/2026-03-16-tool-annotations/, read in full). Defaults when annotations are missing: `readOnlyHint` false, `destructiveHint` true, `idempotentHint` false, `openWorldHint` true. Clients "must treat them as untrusted unless they come from a trusted server"; a server may claim read-only and still destroy data. Recommended client behaviour: skip confirmation only for read-only tools from trusted servers, warn before destructive ones and show what will change, scrutinise output of open-world tools, consider "tainting" the session after reading untrusted content and tightening later approvals. FACT (same post).

Measured state: arXiv 2611.02527 (submitted 2026-11-02) reports about 90% of destructive tools in a 1,000-repo sample of the official registry have no server-side confirmation; 32 of 41 popular open-source hosts and SDKs (16 of 25 applications) have no approval step by default; 60.7% of server-host pairs lack enforced human approval; four of five low-cost models ran an injected deletion in 479 of 960 runs. If hosts prompted for every tool not marked read-only/non-destructive, the unapproved share would drop to 5.4%, whereas universal elicitation support would only reduce it to 56.7%. The authors conclude applications should configure approval themselves. FACT (abstract page read: https://arxiv.org/abs/2611.02527). Peer review status UNVERIFIED.

### 1.4 Sandboxing of stdio servers

A stdio server is a child process with the user's rights. The MCPB docs describe it as running "on the user's machine" with access to local files and tools (FACT). I found no vendor documenting an OS sandbox around such servers in Claude Desktop, Raycast, Zed, LM Studio, Msty or BoltAI; MCP's own post says hard safety needs "network controls, sandboxing, or other deterministic mechanisms" (FACT). Not found is not proof of absence — UNVERIFIED.

### 1.5 MCP spec state relevant to Lintel

- **Versions:** 2025-11-25 release, with later revisions referenced as 2026-07-28 and a draft on modelcontextprotocol.io. FACT (https://modelcontextprotocol.io/specification/2025-11-25/changelog ; pages under /specification/latest/).
- **Authorization:** 2025-11-25 added OpenID Connect discovery, incremental scope consent via `WWW-Authenticate`, and OAuth Client ID Metadata Documents (CIMD) as the preferred client registration. Registration priority: pre-registration, then CIMD, then Dynamic Client Registration, then manual. Sources disagree on whether DCR is formally deprecated. FACT for the first part (https://auth0.com/blog/mcp-november-2025-specification-update/ ; https://modelcontextprotocol.io/specification/latest/basic/authorization/client-registration); UNVERIFIED for deprecation. INFERENCE: a native app has no stable HTTPS client-id URL of its own, so for a DMG app CIMD needs a hosted metadata document (a Lintel-owned URL); how a loopback redirect fits was not covered by my sources.
- **Elicitation** (read in full): form mode uses a restricted JSON Schema, **flat objects with primitive properties only** (string with `format` email/uri/date/date-time, number/integer, boolean, single/multi enum with titles, `default`). Clients "MUST" show which server asks, give decline/cancel, and for form mode **let users review and modify responses before sending**; servers MUST NOT ask for passwords or API keys in form mode. URL mode (new in 2025-11-25) sends the user to a URL for auth or payment out of band; clients MUST show the full URL, get consent and not pre-fetch. FACT (https://modelcontextprotocol.io/specification/latest/client/elicitation).
- **Registry:** official registry in preview since 2025-09-08 (Anthropic, GitHub, PulseMCP, Microsoft), API frozen at v0.1 2025-10-24; publishers prove namespace via GitHub, DNS or HTTP; for MCPB artifacts `fileSha256` is required, the registry does not validate it but clients do; security scanning is left to downstream aggregators. FACT (https://modelcontextprotocol.io/registry/about ; https://modelcontextprotocol.io/registry/package-types). INFERENCE: it is a metadata index, not a vetting service.
- **Real remote servers for Lintel's three targets:** Linear's remote server `https://mcp.linear.app/mcp` uses OAuth 2.1 with dynamic client registration, supports a bearer token or API key, and offers a **read-only endpoint** (`/mcp/readonly`). Atlassian's Rovo MCP server recommends OAuth 2.1 for interactive use; API-token auth is optional and must be enabled by an org admin; endpoint paths (`/v1/mcp` vs `/v2/mcp`) conflict across pages; whether Jira issue creation is among the exposed tools was not confirmed. FACT for Linear (https://linear.app/docs/mcp), mixed for Atlassian (https://developer.atlassian.com/cloud/rovo-mcp/guides/authentication-and-authorization/ ; https://support.atlassian.com/atlassian-rovo-mcp-server/docs/configuring-authentication-via-api-token).

## 2. Other extension models

### 2.1 Raycast extensions (store)

Extensions are TypeScript/React packages, archived, uploaded to the Store and published after a registered account submits them; Raycast's developer security page says more automated static analysis in CI is "planned". FACT (https://developers.raycast.com/information/security). The review process itself and any permission model were not described in what I found — UNVERIFIED. Who builds: developers. Non-developer setup: install from the store (easy); building: hard. Fits no-runtime-loading policy: **no**, it is a code store.

### 2.2 Alfred workflows

Gallery workflows go through automatic and manual security checks and are signed; Alfred installs or updates only with a valid signature; the terms place responsibility on the user; Alfred runs at user level; Gallery access can be disabled by a defaults command. FACT (https://alfred.app/security-and-privacy/ ; https://alfred.app/terms/). Workflows are arbitrary scripts. Fits policy: **no**. Not an integration target for Lintel (Lintel would be the host, not Alfred).

### 2.3 Apple Shortcuts / App Intents as "user builds the integration"

`shortcuts run "<name>"` takes input and returns output on the command line; exits 0 or 1; if a shortcut asks for input the command line process pauses. Privacy prompts on first access to data offer allow once / always / deny. Apple says it cannot verify the authenticity or behaviour of privately shared shortcuts. FACT (https://support.apple.com/guide/shortcuts-mac/apd455c82f02/mac ; https://support.apple.com/guide/shortcuts-mac/apd961a4fc65/mac). Developer-forum reports: the `shortcuts` CLI silently failed when Terminal lost Full Disk Access, and one macOS 14.7.5 report says the binary lost an entitlement — UNVERIFIED community threads (https://developer.apple.com/forums/thread/780790 ; https://discussions.apple.com/thread/255210852). Who builds: the user, visually, with Shortcuts' own connectors (Calendar, Mail, Reminders, "Get Contents of URL", app actions from App Intents). Setup for a non-developer: moderate (build once, name it). Security: the shortcut has the user's rights; the user, not Lintel, reviews its steps. Policy fit: INFERENCE — Lintel does not load or execute its own plugin code; it invokes a user-owned system feature. Letter of "scripts" in `AGENTS.md` is ambiguous, so this is an owner decision. Limitation: a shortcut has no declared input schema that Lintel can read, so any approval card shows Lintel's own fields (or a text blob) and Lintel cannot preview what the shortcut will do — INFERENCE.

### 2.4 Zapier / Make / n8n webhooks

- **Zapier MCP:** you choose which actions to enable on your server; admins get an audit log. Approval ("Human in the Loop", "Approval Studio") is described as a step inside a Zap, not a gate on every MCP tool call. A third-party guide advises a local approval step before calling the Zapier MCP action. FACT for the docs surface (https://docs.zapier.com/mcp/overview/how-tools-work ; https://zapier.com/mcp/human-in-the-loop); the community advice is UNVERIFIED.
- **n8n:** a Webhook trigger starts a workflow from an HTTP request; an MCP Server Trigger node exposes a workflow as an MCP endpoint with separate test and production URLs. FACT (https://docs.n8n.io/integrations/builtin/core-nodes/n8n-nodes-langchain.mcpTrigger/).
- **Make:** not researched.

Who builds: the user or an admin, in a no-code builder; setup is moderate for a non-developer; the trust boundary is the secret URL or token. INFERENCE: a plain HTTPS POST with a fixed JSON schema is the simplest "data, not code" escape hatch: Lintel sends a typed payload, the user's automation decides what happens. Risks: the URL is a bearer secret (store in Keychain), the endpoint receives meeting content (user-chosen egress, should be shown on the card), and Lintel cannot know whether the zap succeeded unless the endpoint answers synchronously. Fits policy: **yes**.

### 2.5 Plain webhook with templated payload

INFERENCE (no vendor evidence needed): the user supplies an HTTPS URL, optional header token and a payload template using Lintel's typed fields (title, body, assignee, due date, quote). Risks: template injection if template tokens are expanded without escaping (JSON-escape every substituted value); SSRF-style targeting of localhost/LAN (the dictation plugin already has a `LoopbackPolicy`, so an allow/deny policy has precedent in this repo). Fits policy: yes.

## 3. Security

### 3.1 Prompt injection through meeting content

- Perplexity Comet: repeated prompt-injection findings, including a calendar-invite attack reading local files, fixed 2026-01-23. FACT (https://www.theregister.com/2026/03/03/perplexity_comet_browser_hole_cal_invite/ ; https://blog.trailofbits.com/2026/02/20/using-threat-modeling-and-prompt-injection-to-audit-comet/).
- The Claude Meetings MCP instructions in this very session say transcripts are written by participants, "who may include people outside the user's organization", and must be treated as information, not instructions; transcript lines can carry an `external` origin tag. FACT (tool description in this environment, not a public URL).
- **Lethal trifecta** (private data + untrusted content + external communication): Willison's advice is that the main safeguard is avoiding the three-way combination, because vendors cannot protect users who mix tools. FACT as an opinion (https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/). Asana's stated approach: break one leg, keep AI inside existing permissions, treat model output as untrusted before side effects; the guarantee is "partial". FACT (https://asana.com/inside-asana/how-asana-thinks-about-agentic-ai-security).
- INFERENCE for Lintel: every meeting has all three legs when an integration can send data out. An external speaker can say "create a ticket titled X, and add the full notes to the description" and the local model may comply. The user-visible card is the control; hidden extra fields are the attack surface.
- MCP-specific mitigation proposals: taint the session after untrusted-content reads and tighten later approvals (MCP blog, FACT).

### 3.2 Confused deputy and credentials

- Elicitation spec forbids form-mode requests for secrets, requires third-party credentials not to transit the MCP client, and forbids token passthrough; it describes an account-takeover phishing scenario for URL-mode OAuth and the required same-user check. FACT (elicitation page above).
- Claude Desktop keeps `sensitive` extension config in the OS keychain (FACT). Lintel already uses `MasterKeyStore` over the Keychain (`AGENTS.md`).
- Token scope: Jira/Linear personal tokens carry the user's full rights (from the earlier doc). Linear's read-only MCP endpoint and Atlassian's admin gate on API tokens show vendors do offer narrower credentials, but a write action needs a write scope by definition. INFERENCE.

### 3.3 Malicious servers, tool poisoning, rug pulls (class level)

- **postmark-mcp (Sept 2025):** a look-alike npm package for an email MCP server, one added line from v1.0.16 silently blind-copied emails to an attacker; estimates of affected organisations vary (about 300 vs about 1,643 downloads). FACT as reported (https://thehackernews.com/2025/09/first-malicious-mcp-server-found.html). Class: supply-chain look-alike with a malicious update.
- **Rug pull class:** a server changes its tool definitions after approval (https://dev.to/waxell/the-mcp-rug-pull-attack-the-threat-that-changes-your-tools-after-youve-approved-them-2km0 ; UNVERIFIED blog). **MCPoison:** trust bound to a config key name, command swapped later, fixed by re-approval on any change. FACT (Check Point link above).
- **Deadbugz (2026):** a malicious MCP server distributed through unsolicited GitHub pull requests, payload gated behind a call counter so it behaves for a while. Reported by Pillar Security and summarised in CSA research notes dated 2026-08-30 and 2026-09-02. FACT that CSA published, details UNVERIFIED (https://labs.cloudsecurityalliance.org/wp-content/uploads/2026/09/CSA_research_note_deadbugz_mcp_metadata_poisoning_20260902-csa-styled.pdf).
- **Metadata poisoning scale:** Island's July 2026 analysis reports clear instruction or output-manipulation signals in about 3.3% of 33,563 MCP server builds and recommends rescanning after each update. UNVERIFIED (secondary summary via the CSA/Socket search result; https://socket.dev/glossary/mcp-security).
- **Registry limits:** namespace proof only; no payload scanning (FACT, registry docs).

### 3.4 Mitigations vendors document

| Mitigation | Who | Evidence |
|---|---|---|
| Default-confirm writes, remember approval per tool, reset on new conversation | ChatGPT | FACT |
| Read-only auto, write asks; "Confirm Always"; reset allowed tools | Raycast | FACT |
| Editable arguments in the approval dialog | LM Studio | FACT |
| Deny rules that cannot be overridden, per-tool confirm | Zed | FACT |
| Re-approve on any config-entry change | Cursor | FACT |
| Admin allow/blocklists, MDM, private directories | Claude Desktop | FACT |
| Admin RBAC and blocked actions | ChatGPT Business/Enterprise | FACT |
| Read-only endpoint | Linear | FACT |
| Hash check of MCPB at install | MCP clients (registry docs) | FACT |
| Bundle review by vendor | Anthropic directory (now deprecated for MCPB) | FACT / see 1.1 |

## 4. Typed actions vs free tool calls

- **No product found that maps arbitrary integrations into a reviewable typed card.** In every MCP host above, the approval prompt shows the tool name plus raw arguments (LM Studio's editable arguments are the best case). INFERENCE from search results; I could not inspect each app's UI, so UNVERIFIED for individual products. The MCP blog says no major client puts annotations into approval prompts.
- **Elicitation as a form engine:** its restricted schema (flat primitives, enums with titles, defaults, formats) is exactly enough for a Jira summary, project enum, due date, and an email subject/body, and the client MUST let the user review and modify the response. FACT for the schema and the review rule; INFERENCE that the same renderer can be driven from a **tool `inputSchema`** (JSON Schema) if Lintel limits itself to the flat subset and falls back to "unsupported field, edit as text" for nested objects. Nested/array-of-object inputs (Jira custom fields, attendee lists with roles) do not fit the subset.
- **Typed-first design (INFERENCE):** Lintel owns three action types (`task`, `event`, `message`) with fixed fields and renders cards itself. A user-added integration is a **target adapter** that declares "I accept `task`" and maps fields (Linear/Jira MCP tool, webhook, Shortcut). The card shows Lintel's fields plus the target and the mapped tool name; the model never picks the tool. This keeps the model's output a data record, matching the "proposals must be data" conclusion in the earlier doc.
- **Free tool calls** (the model picks any tool from any server) maximise reach but make the card unpredictable, bring tool-description poisoning into the model's context and force a generic approval screen. INFERENCE.

## 5. App Store, notarization and process spawning

- **Lintel is outside the MAS (DMG, `AGENTS.md`).** Apple forum replies: App Sandbox is required only for Mac App Store apps; independent distribution may enable it but is not required to; hardened runtime is required for notarization. FACT as DTS/forum answers (https://developer.apple.com/forums/thread/734801 ; https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution.md). INFERENCE: spawning a user-configured executable from a notarized, non-sandboxed, hardened-runtime app is technically allowed; hardened runtime constrains Lintel's own process (library validation, JIT, DYLD env), not an arbitrary child's code.
- **Child behaviour:** one forum thread reports a child process needing extra hardened-runtime entitlements failing to launch, and that the child does not inherit them; the sandbox "and the hardened runtime to a lesser extent" change the environment of children. UNVERIFIED single thread (https://developer.apple.com/forums/thread/120647). Quarantine is not removed by signing or notarization (FACT, forum), but a binary the user installed with a package manager is not a quarantined download — INFERENCE, not tested.
- **If Lintel ever went to the MAS:** sandboxed apps' children inherit the static sandbox and can run only executables available to it; tools must work under the sandbox. FACT as DTS answers (https://developer.apple.com/forums/thread/749725 ; https://developer.apple.com/forums/thread/746478). INFERENCE: arbitrary user-chosen stdio servers (`npx`, `uvx`) are effectively impossible there. Apple's quoted position that MAS apps may host plug-ins "enabled with mechanisms other than the App Store" (forum, UNVERIFIED) is not a guarantee.
- **Runtime availability, not just permission:** Claude Desktop bundles Node.js so MCPB users need none; Raycast's local servers need Node.js or uv on the machine (FACT, both pages). INFERENCE: for a non-developer, stdio MCP in Lintel would either need a bundled runtime (size, update duty, a second code-signing surface) or a prerequisite the user cannot satisfy.
- **TCC and Automation:** running Shortcuts or Mail AppleScript triggers per-app TCC prompts (covered in the earlier doc §5). The `shortcuts` CLI has reported failures when its parent lacks Full Disk Access (UNVERIFIED forum). Lintel already ships with Apple Events usage text only if it adds Mail scripting; no entitlement change is needed for Shortcuts — INFERENCE, untested.
- **The "no runtime loading" policy:** a stdio server is not loaded into Lintel's process, but it is user-supplied code Lintel launches. Whether that violates the policy's intent (no extension stores, no code from third parties inside the process boundary) is for the owner.

## 6. Comparison table

| Mechanism | Who builds | Setup effort (non-developer) | Write-approval UX seen in market | Security risks | Fits no-runtime-loading policy? | Effort for Lintel (INFERENCE) |
|---|---|---|---|---|---|---|
| Built-in adapters (EventKit, mailto/Mail draft, Jira, Linear) | Lintel | Low (grant permission or paste token) | Typed card, edit, one click | Token scope; Lintel owns bugs | Yes | Medium per adapter; already planned |
| Shortcuts run by name | User (visual builder) | Medium (build, name it, grant prompts) | None built in; a shortcut may prompt and block the CLI | Runs with user's rights, opaque steps, unverified shared shortcuts | Ambiguous (invokes user-owned automation, not Lintel code) | Low (Process + stdin/stdout, name picker via `shortcuts list`) |
| HTTPS webhook (Zapier/Make/n8n/custom) | User or admin | Medium (create hook, paste URL) | Zapier: approval is a Zap step; none at the client | Secret URL, content egress, template injection, SSRF to LAN | Yes | Low-medium (typed JSON payload, Keychain, URL policy) |
| MCP client, remote HTTP only | Vendors (Linear, Atlassian, others); user pastes URL | Low-medium (URL + OAuth in browser) | ChatGPT/Claude/Raycast: confirm writes, remember per tool; annotations rarely shown | Tool poisoning from a remote server, OAuth/CIMD registration, annotations untrusted | Yes (data over HTTPS) | High (OAuth 2.1 + CIMD/DCR, discovery, schema form, session handling) |
| MCP client, local stdio | User; .mcpb or JSON | High as JSON; medium as a vetted bundle | Same as above | Arbitrary code with user's rights, supply chain (postmark-mcp class), rug pulls, needs a runtime | No by letter, arguably by intent | Very high (process lifecycle, runtime, sandboxing, update pinning) |
| Raycast-style extension store | Developers | Low to install, impossible to build | Per-extension | Code store, review quality unknown | No | Not applicable under policy |
| Alfred workflows | Users/developers | Medium | None | Arbitrary scripts | No | Not applicable |

## 7. Options for Lintel (INFERENCE)

**A. Built-ins only + Shortcuts.** Three typed actions to four built-in targets (Calendar, Mail draft, Jira, Linear) and a "Run Shortcut" target for everything else.
- Pros: smallest attack surface; no secrets for Shortcuts targets; user already owns the integration; the card stays typed; no runtime code in Lintel.
- Cons: no schema discovery, no result feedback, opaque to the card; only as capable as the user's Shortcuts skill; macOS-only; CLI reliability reports (UNVERIFIED).

**B. A + typed webhook target.** Adds an HTTPS POST target with a JSON payload of Lintel's typed fields and a Keychain-held secret.
- Pros: covers Zapier/Make/n8n and any internal tool in one afternoon-sized feature; schema is Lintel's, so the card is reviewable; easy to test; fits policy cleanly.
- Cons: the user needs an automation tool; sync result is limited; egress of meeting text to a URL the user typed must be shown prominently; LAN/localhost policy needed.

**C. B + MCP client, remote HTTP only, typed mapping.** Lintel connects to remote servers (Linear, Atlassian Rovo, others), the user maps "task" to a chosen tool, Lintel renders the card from Lintel's fields and the tool's `inputSchema` for extras, prefers read-only endpoints for lookups, requires approval for every write regardless of annotations.
- Pros: reaches many apps without Lintel adapters; no local code execution; matches market direction; remote vendors maintain servers.
- Cons: OAuth 2.1 with CIMD/DCR is the hardest part (a hosted client-metadata URL is needed); tool descriptions are an injection channel to the on-device LLM unless the model never sees them; `inputSchema` may not fit the flat form subset; ongoing spec churn (versions 2025-11-25 to 2026-07-28 visible); each server needs its own review of what a "write" is.

**D. C + local stdio MCP (JSON or .mcpb).**
- Pros: maximum reach, offline servers, access to LAN and internal tools, parity with Claude Desktop and Raycast.
- Cons: breaks the letter of the no-runtime-loading policy; user-supplied code with full user rights; supply-chain class incidents (postmark-mcp, Deadbugz); needs a bundled runtime or developer prerequisite; no vendor-documented sandbox to copy; incompatible with a future MAS build; heaviest QA load.

INFERENCE on ordering: A, B and C are additive with rising cost; D is a separate policy decision, not a larger C.

## 8. Decisions for the owner

1. **Is "user adds an integration" worth shipping in v1 of actions at all?** Options: (a) built-ins only, revisit after real usage; (b) Shortcuts target; (c) webhook target; (d) MCP. Evidence: all three built-ins are already scoped in the earlier doc; Shortcuts and webhook each need little work; MCP needs OAuth and spec tracking.
2. **Shortcuts as an official escape hatch?** It invokes user-owned automation rather than Lintel code, but `AGENTS.md` bans "scripts" at runtime. Options: allow by amending the policy wording, allow only a fixed pre-shipped Shortcut set, or disallow. Evidence: Apple warns shared shortcuts are unverified; `shortcuts run` blocks on prompts and has forum-reported TCC failures.
3. **Webhook target: yes or no, and what egress rules?** Options: any HTTPS URL; HTTPS to public hosts only (blocking localhost/LAN, reusing the idea of `LoopbackPolicy`); allow LAN only after an explicit per-target toggle. Include whether the card must always show the destination host and the exact JSON body.
4. **MCP client: remote-only, local-and-remote, or none?** Evidence: arXiv 2611.02527 says hosts should set approval themselves; MCP's own post says annotations are untrusted; Claude Desktop deprecated MCPB directory submissions; no vendor documents stdio sandboxing. If stdio is chosen, is the policy exception acceptable and is a bundled runtime acceptable?
5. **Approval rule for user-added targets.** Options: every write always needs a click (ChatGPT-style default plus per-tool memory is the market norm); allow "always allow" per tool after the user has approved N cards (graduation, as in the earlier doc §3); never allow auto-run for external-facing actions. Evidence: Raycast "Confirm Always", ChatGPT "remember per tool, reset on new conversation", Claude per-tool Always allow/Needs approval/Blocked.
6. **Typed card or generic tool call?** Option 1: Lintel's three action types with fixed fields, targets are adapters; Option 2: render a form from the target tool's `inputSchema` (flat subset), with a text fallback; Option 3: raw tool name and JSON arguments like LM Studio. Evidence: no product found with typed cards over arbitrary integrations; MCP elicitation requires the client to let users edit before sending.
7. **Does the on-device or Claude model ever see tool descriptions from user-added servers?** Options: never (Lintel maps typed fields to a chosen tool without model involvement); only descriptions from servers on a Lintel-maintained list; any server. Evidence: tool-poisoning/rug-pull class incidents; Island's 3.3% figure (UNVERIFIED).
8. **Trust and pinning of a user-added server.** Options: trust-on-first-use with re-approval whenever the config, tool list or tool descriptions change (the post-MCPoison Cursor fix); pin to a hash for bundles; curated list of known servers only (Linear, Atlassian). Include whether Lintel stores the OAuth token in Keychain per server and whether write scope is requested only when the first write is approved (incremental consent, supported by 2025-11-25).
9. **Meeting-origin guard.** Whether actions proposed from segments by **external speakers** are marked and restricted: for example, cannot set recipients or add attachments, or require an extra confirmation. Evidence: Claude Meetings tags external lines; Comet's calendar-invite attack; the trifecta advice to break one leg.
