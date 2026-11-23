# Lintel UX direction (WIP, checkpoint)

> Status: **work in progress**, checkpointed 2026-11-23 because the owner's computer is restarting. Design-only. Nothing here is accepted yet. Sketches in `.ai/prototypes/lintel-direction/` are **not written yet**.

## HANDOFF

**Done**
- Read: `.uxproof/conventions.md`, the settings audit, the UI root-cause report, the Figma evaluation (session scratchpad reports, 2026-11-23), `.ai/specs/2026-11-04-lintel-main-window.md`, `.ai/prototypes/lintel-app` (CSS tokens, README), owner memory (audience shift 2026-11-23, Verdigris palette, SwiftUI gallery as source of truth).
- Pulled every jargon-bearing string from `Resources/Localizable.xcstrings` (1412 keys) to ground the glossary below.
- Web research (findings and sources below).
- Decided the shared direction below (personas, tone, glossary, IA, principles) and the shape of the three sketches.

**Next steps**
1. Write the three sketches `.ai/prototypes/lintel-direction/{a-quiet-native,b-paper-and-ink,c-friendly-guide}.html` (one file each; light + dark; en + pl; same three screens; query `?screen=onb|home|set&theme=light|dark&lang=en|pl&chrome=0&demo=done` for screenshots). Content and copy are fixed in "Sketch content" below.
2. Fill the remaining doc sections (validation, open decisions, evidence limits) and finish the design principles text.
3. Render screenshots with headless Chrome (`/Applications/Google Chrome.app`), 3 directions × 3 screens × light/dark, plus one PL shot each; push them to an evidence branch (repo `mjozefiak/lintel` is public) and embed in the PR body.
4. Mark the PR ready, labels per current `SDLC.md` on main: `documentation`, `review`, `skip-qa`, `priority-medium`, `risk-low` (PR #245 is migrating to `type:*`/`area:*`/`state:*` labels but is not merged; if it is by then, use `type:chore`, `area:app`).
5. `hc send t19k '<PR url + one line per direction>'`.

**Open questions (for the owner, not blocking the sketches)**
- Default dictation shortcut for non-technical users: keep ⌥ Space or move to a single key like Wispr Flow's Fn (needs a feasibility check; Fn is not a normal hot key on macOS).
- A top-level **Dictionary** pane (proposed) vs. keeping vocabulary inside Dictation.
- Is a "Finish setting up" checklist on Home acceptable (Linear-style, disappears when done)?
- Home "Coming up" meetings needs calendar access, which is the later proactive-agent work; the sketches leave it out.

## Decision being made

One shared UX direction that the three later design tracks (first-run onboarding, friendlier main window, settings rebuilt from scratch) follow, so they do not each invent a look, a vocabulary and an IA. The visual choice between 2-3 directions is the owner's.

## Research findings (web, 2026-11-23)

- **Wispr Flow** (help center): Mac onboarding is privacy choice → permissions (Microphone + Accessibility) → microphone test → shortcut test → languages; a "skip" path keeps only those essentials. Default push-to-talk is Fn (Ctrl+Opt without an Apple Fn key); double-tap for hands-free. Reviewers say setup asks about writing style; a secondhand design note says practice happens in a sample email field rather than a video. Dictionary learns from corrections; Styles per app category (Personal, Work, Email). Settings expose no models or servers. Complaints: privacy (not fully on-device), resource use, support.
  Sources: [setup guide](https://docs.wisprflow.ai/articles/3152211871-setup-guide), [first dictation](https://docs.wisprflow.ai/articles/6409258247-starting-your-first-dictation), [product-aware onboarding](https://docs.wisprflow.ai/articles/5926242953-product-aware-onboarding-choosing-dictation-notetaker-or-both-macos), [Styles](https://docs.wisprflow.ai/articles/2368263928-how-to-setup-flow-styles), [unite.ai review](https://www.unite.ai/wispr-flow-review/), [Cult of Mac](https://www.cultofmac.com/reviews/wispr-flow-mac-speech-to-text-app-review), [Product Hunt reviews](https://producthunt.com/products/wisprflow/reviews).
- **Granola**: praised by non-technical reviewers for near-zero setup and "no bot in the call" (feels discreet with clients and board members). Home opens on "Coming up" (next meetings from the calendar). Permissions: microphone, screen & system audio, calendar.
  Sources: [Granola setup docs](https://docs.granola.ai/help-center/getting-started/setting-up-granola-for-the-first-time), [calendar setup](https://www.granola.ai/docs/docs/101/gettingstarted/calendarintegrations), [G2 reviews](https://www.g2.com/products/granola/reviews), [tl;dv review](https://tldv.io/blog/granola-review/).
- **Superhuman**: activation came from a guided 30-minute session that made the user do real work in their own inbox, later turned into a self-serve in-product flow. Lesson: practise on the user's real task, not a tour.
  Sources: [First Round: onboarding playbook](https://review.firstround.com/superhuman-onboarding-playbook/), [Heavybit](https://www.heavybit.com/library/blog/4-phases-of-building-an-enterprise-onboarding-process/).
- **Linear**: one thing per screen, calm visuals, no confetti, tours or tooltips; ends with a short "get familiar" checklist. Sources: [Candu teardown](https://www.candu.ai/blog/linear-onboarding-teardown), [growth.dives](https://growth-dives.kit.com/posts/growth-dives-inside-linear-s-onboarding-3-things-i-didn-t-expect).
- **Raycast**: new first-run flow in v0.59 (May 2026); screen detail not verified. [changelog](https://www.raycast.com/changelog/macos/0-59).
- **Things 3**: two Apple Design Awards; UI deliberately "invisible" so content leads. [App Store](https://apps.apple.com/us/app/id904237743).
- **Apple Notes / Voice Memos**: recording and transcript live inside the note; summary is an optional extra layer, not the headline. [Notes: record and transcribe](https://support.apple.com/guide/notes/apdb5106e334), [Voice Memos transcription](https://support.apple.com/guide/voice-memos/vm4a03609f0d). Apple HIG: onboarding fast, fun, optional. [HIG onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding).
- **Otter / Notion AI meeting notes**: setup called straightforward; friction from upsell before calendar connect (Otter) and plan gating/beta (Notion). [tl;dv on Notion](https://tldv.io/blog/notion-ai-meeting-notes-review/), [tl;dv on Otter](https://tldv.io/blog/otter-ai-review/).
- Not found: App Store reviews quoting onboarding of these apps; any review from lawyers or sales teams about settings.

## Personas (assumptions, not research; Lintel has no telemetry or interviews)

1. **Anna, sales manager** (8+ calls a day, writes follow-ups between calls). Wants notes and follow-up emails without typing. Fears: sounding robotic, a client noticing a bot. Success: the follow-up is sent before the next call.
2. **Piotr, lawyer / consultant** (confidential client work, dictates memos). Wants dictation that spells names and terms right and never leaves the Mac. Fears: data leaving the device, losing a recording. Success: he trusts it with a client memo.
3. **Kasia, recruiter / HR** (interviews, many short messages, Polish and English). Wants both languages without switching. Fears: setup she cannot finish alone. Success: she set it up in 3 minutes without help.

## Tone of voice

Calm, plain, second person, short sentences (about 15 words), verbs on buttons, no exclamation marks, no AI hype words ("magic", "supercharge", "AI-powered"), no technical nouns. Say what happens to the user's words, not how the machine works. Polish uses "Ty" forms with capital letters in direct address ("Twoje słowa"), never declines the name Lintel.

## Glossary (current UI term → plain words; "hidden" = never in Basics, at most behind More options)

| Current term | Plain English | Plain Polish | Where it may appear |
|---|---|---|---|
| speech model, Parakeet, Whisper, WhisperKit | voice pack (download) / "speech recognition" | pakiet głosu / rozpoznawanie mowy | AI on this Mac pane only; engine names hidden |
| LLM, built-in model, Qwen, Bielik, GGUF, notes model | writing assistant | asystent pisania | AI on this Mac pane; model names hidden |
| Clean up / formatting | Tidy up my text | Porządkuj mój tekst | Dictation |
| Run on: Built-in (Lintel) / My server, endpoint, address, localhost, port | hidden ("Use my own AI server" under More options in AI on this Mac) | ukryte | More options only |
| notesProvider "Claude" / This Mac | Meeting notes written by: This Mac / Claude (online) | Notatki pisze: ten Mac / Claude (online) | AI on this Mac |
| diarization, speaker model, speaker recognition | telling speakers apart (always on, no setting) | rozpoznawanie, kto mówi | hidden; only "Speakers" in a note |
| transcript | transcript (kept; understood by office users) | transkrypcja | Notes |
| retention, retentionDays, maximumEntries | Keep … for 30 days | Przechowuj przez 30 dni | Privacy & Data, history rows |
| Erase Data, Clear Library, Clear History | Delete all meetings… / Delete dictation history… | Usuń wszystkie spotkania… | Privacy & Data |
| bundle ID | hidden (pick an app from a list instead) | ukryte | More options |
| Full Disk Access | "Search everywhere on this Mac" (permission name shown only on the System Settings button) | Szukaj wszędzie na tym Macu | Search add-on |
| Accessibility (permission) | "Let Lintel type into other apps" | Pozwól Lintel pisać w innych aplikacjach | onboarding, Privacy & Data |
| System Audio Recording | "Hear the other people in a call" | Słysz innych uczestników rozmowy | onboarding, Meetings |
| Test System Audio, Capture diagnostics, Copy diagnostics | Check call audio / Send a problem report | Sprawdź dźwięk rozmowy / Zgłoś problem | More options |
| voice processing, echo suppression | hidden (always on) | ukryte | — |
| index, Rebuild Index, Reset Ranking | hidden; "Start over" under More options | ukryte | More options |
| launcher | Quick search | Szybkie wyszukiwanie | Add-ons |
| plugin, feature toggles pane | features are switched on in their own pane header | — | — |
| vocabulary | Dictionary ("words Lintel always spells your way") | Słownik | top-level pane (proposed) |
| spool, keep warm, VAD, tokens | hidden | ukryte | never |

## Settings IA (shared by every direction)

Core: General · Dictation · Meetings · Notes · Dictionary. Add-ons: Quick search · Clipboard history · Window layouts. Then: Privacy & Data · AI on this Mac. A "Search settings" field sits above the sidebar. Each pane: status line → 3-5 basic rows → "More options" (collapsed) → one footer sentence. Builds on the 2026-11-23 settings audit (rank 1-5) without changing settings keys in this PR.

## Design principles (draft, to finish)

1. Show the result, not the machinery (no model, server or engine names in Basics).
2. One obvious next step per screen; the primary button says what happens.
3. Practise on a real task in onboarding (dictate into a sample email), never a video or tour.
4. Ask for a permission only when its reason is on screen, in the user's words.
5. Privacy is stated where the data is, in one sentence ("Nothing is sent anywhere").
6. Defaults decide; options are for exceptions (More options, never "Advanced").
7. Every setting has one home and is findable by search.
8. Voice and notes first; add-ons never sit above them.
9. Native controls, signature in three places only (accent, mark, onboarding/HUD motion).
10. Calm over clever: no confetti, glow, sparkles, purple-blue gradients.
11. Bilingual by design: every layout tested with Polish, which runs ~30% longer.
12. Recoverable: every destructive action names what is deleted and how long it was kept.

## Native vs signature

Native: window chrome, sidebar, grouped forms, toggles, pop-ups, shortcut recorder, sheets, SF Symbols, Dynamic Type via `TextSize`, system status colours. Signature: Verdigris accent (#267C6C / dark #6BBDAB; text #036152), the cut-ring mark (also the "listening" indicator), warm ink/paper neutrals, onboarding and HUD motion (respects Reduce Motion).

## Three visual directions (to sketch)

- **A. Quiet Native**: looks like a first-party Apple app (System Settings / Notes); neutral greys, accent only on selection and primary buttons. Lowest build cost; risk: the owner already called a similar look "bland" (2026-11-04).
- **B. Paper & Ink** (author's current lean): warm paper neutrals, New York serif for headings (`.fontDesign(.serif)`), hairlines instead of filled cards, the cut ring as the listening indicator. Signature without leaving native controls.
- **C. Friendly Guide**: rounded type and 14-16 pt corners, soft Verdigris tints, icon circles, an illustrated side panel in onboarding, section headings as questions ("How do you start?"). Warmest for non-technical users; highest build cost and furthest from native.

## Sketch content (fixed copy, en / pl)

Screens: (1) onboarding step 4 of 5 "Try it", (2) main window Home, (3) Settings → Dictation.

- Onboarding: "Say something. Lintel will type it." / "Powiedz coś. Lintel to napisze." · "Hold ⌥ Space, say a sentence, then let go." / "Przytrzymaj ⌥ Spację, powiedz zdanie i puść." · sample email To: Marta Nowak, Subject: Q4 budget / Temat: Budżet na IV kwartał · result "Hi Marta, I went through the Q4 numbers and they look good. Can we go over the travel budget on Thursday?" / "Cześć Marto, liczby za IV kwartał wyglądają dobrze. Czy możemy w czwartek omówić budżet na podróże?" · success "That's it. It works the same in Mail, Slack, Word and every other app." / "To wszystko. Tak samo działa w Mailu, Slacku, Wordzie i każdej innej aplikacji." · buttons Back / Skip for now / Continue (Wstecz / Pomiń na razie / Dalej) · footer "Your voice is turned into text on this Mac. Nothing is sent anywhere." / "Głos zamienia się w tekst na tym Macu. Nic nie jest nigdzie wysyłane." Steps: Welcome, Access, Shortcut, Try it, Meetings.
- Home: "Monday, 23 November" · "Good afternoon, Anna" / "Dzień dobry, Anno" · actions "Dictate in any app" and "Record a meeting" [Start Recording] · Recent: Client call: Nordlys Energy (Meeting · 42 min · Notes ready), Weekly sales sync (3 follow-ups), Email to Marta about the Q4 budget (Dictation · 118 words), Notes for the board update · "Finish setting up · 3 of 5 done" checklist.
- Settings → Dictation: status "Ready to dictate" · Shortcut: Dictate [⌥ Space] "Hold to talk. Or tap once to start and once to stop." · "Tidy up my text" (on) · "Languages I speak: English, Polish [Change…]" · Names and words: Dictionary "12 words Lintel always spells your way" [Open Dictionary] · History: "Keep my dictations [30 days]" "Older ones are deleted on their own." · More options: Microphone, "After pasting, put back what I had copied" · footer privacy sentence.
