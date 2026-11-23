# Lintel UX direction

> Status: **draft for the owner's decision**, 2026-11-23. Design-only (no Swift, no settings keys changed). The shared parts (personas, tone, glossary, settings IA, principles) are proposed as one package; the visual choice between the three sketched directions is the owner's. Sketches: `.ai/prototypes/lintel-direction/`.

## Status and handoff

**Done**
- Inputs read: `.uxproof/conventions.md`, the settings audit, the UI root-cause report, the Figma evaluation (session scratchpad reports, 2026-11-23), `.ai/specs/2026-11-04-lintel-main-window.md`, `.ai/prototypes/lintel-app` (CSS tokens, README), owner memory (audience shift 2026-11-23, Verdigris palette, SwiftUI gallery as source of truth).
- Every jargon-bearing string pulled from `Resources/Localizable.xcstrings` (1412 keys) to ground the glossary.
- Web research (findings and sources below).
- Shared direction written: personas, tone, glossary, settings IA, principles.
- Three clickable sketches built (A Quiet Native, B Paper & Ink, C Friendly Guide), each with the same three screens (onboarding step 4 "Try it", main window Home, Settings → Dictation), light and dark, English and Polish. Screenshots are in the PR body.
- Direction comparison, validation plan, open decisions and evidence limits (below).

**Next (after the owner picks)**
1. Owner picks A, B, C or a named mix, and answers the open decisions below.
2. The chosen direction becomes the SwiftUI gallery's tokens and the three design tracks (onboarding, main window, settings rebuild) each get their own spec that cites this doc.
3. Run the five-user preference and findability check described under Validation before the settings rebuild is specced.

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

## Design principles

These apply to every direction; the sketches follow all twelve.


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

## Three visual directions

- **A. Quiet Native**: looks like a first-party Apple app (System Settings / Notes); neutral greys, accent only on selection and primary buttons. Lowest build cost; risk: the owner already called a similar look "bland" (2026-11-04).
- **B. Paper & Ink** (author's current lean): warm paper neutrals, New York serif for headings (`.fontDesign(.serif)`), hairlines instead of filled cards, the cut ring as the listening indicator. Signature without leaving native controls.
- **C. Friendly Guide**: rounded type and 14-16 pt corners, soft Verdigris tints, icon circles, an illustrated side panel in onboarding, section headings as questions ("How do you start?"). Warmest for non-technical users; highest build cost and furthest from native.

## Sketch content (fixed copy, en / pl)

Screens: (1) onboarding step 4 of 5 "Try it", (2) main window Home, (3) Settings → Dictation.

- Onboarding: "Say something. Lintel will type it." / "Powiedz coś. Lintel to napisze." · "Hold ⌥ Space, say a sentence, then let go." / "Przytrzymaj ⌥ Spację, powiedz zdanie i puść." · sample email To: Marta Nowak, Subject: Q4 budget / Temat: Budżet na IV kwartał · result "Hi Marta, I went through the Q4 numbers and they look good. Can we go over the travel budget on Thursday?" / "Cześć Marto, liczby za IV kwartał wyglądają dobrze. Czy możemy w czwartek omówić budżet na podróże?" · success "That's it. It works the same in Mail, Slack, Word and every other app." / "To wszystko. Tak samo działa w Mailu, Slacku, Wordzie i każdej innej aplikacji." · buttons Back / Skip for now / Continue (Wstecz / Pomiń na razie / Dalej) · footer "Your voice is turned into text on this Mac. Nothing is sent anywhere." / "Głos zamienia się w tekst na tym Macu. Nic nie jest nigdzie wysyłane." Steps: Welcome, Access, Shortcut, Try it, Meetings.
- Home: "Monday, 23 November" · "Good afternoon, Anna" / "Dzień dobry, Anno" · actions "Dictate in any app" and "Record a meeting" [Start Recording] · Recent: Client call: Nordlys Energy (Meeting · 42 min · Notes ready), Weekly sales sync (3 follow-ups), Email to Marta about the Q4 budget (Dictation · 118 words), Notes for the board update · "Finish setting up · 3 of 5 done" checklist.
- Settings → Dictation: status "Ready to dictate" · Shortcut: Dictate [⌥ Space] "Hold to talk. Or tap once to start and once to stop." · "Tidy up my text" (on) · "Languages I speak: English, Polish [Change…]" · Names and words: Dictionary "12 words Lintel always spells your way" [Open Dictionary] · History: "Keep my dictations [30 days]" "Older ones are deleted on their own." · More options: Microphone, "After pasting, put back what I had copied" · footer privacy sentence.

## Sketches

Files: `.ai/prototypes/lintel-direction/a-quiet-native.html`, `b-paper-and-ink.html`, `c-friendly-guide.html`. `shared.js` holds the copy (en/pl, identical in all three), the state and the interactions; `shared.css` only the switcher bar. Open a file directly in a browser, or serve the folder (`python3 -m http.server 8766 --bind 127.0.0.1`).

- Query: `?screen=onb|home|set&theme=light|dark&lang=en|pl&chrome=0&demo=done|listening&more=1`. The bar at the top switches screen, theme, language and direction; `chrome=0` hides it for screenshots.
- Clickable: on "Try it", hold the button (or ⌥ Space) to get the listening state, let go and the sample email types itself, then the success line and Continue appear ("Try again" resets). Continue goes to Home. On Home: Start Recording / Stop, Hide the checklist, Settings in the sidebar. In Settings: switches, More options, the sidebar, Home to go back.
- All names and data are fictional (Anna, Marta Nowak, Nordlys Energy). Motion respects Reduce Motion (typing is skipped, the listening mark stops).

## Direction comparison

| | A. Quiet Native | B. Paper & Ink | C. Friendly Guide |
|---|---|---|---|
| Feels like | System Settings, Notes | a well-set letter or notebook | a guided consumer app |
| Signature | accent on selection and primary buttons only | warm paper, serif headings, hairline rules, cut ring as the listening mark | Verdigris tints, icon circles, illustration, questions as section headings |
| Onboarding | centred, dots, Mail-like compose box | numbered steps in the margin, the email as a ruled letter | illustrated side panel, progress bar, rounded email card |
| Settings | grouped inset boxes | ruled sections, no boxes | rounded cards with an icon per row |
| SwiftUI cost | lowest: stock `Form(.grouped)`, `List(.sidebar)` | low-medium: `.fontDesign(.serif)` on titles, custom section header and divider styles, own window background colour | highest: custom row and card views, `.fontDesign(.rounded)`, illustration assets in two themes |
| Risk | looks like every other Mac utility; the owner called a similar look "bland" (2026-11-04) | serif can read as "editorial" rather than "tool"; hairlines need care in dark mode and at XL text | furthest from native; icon circles everywhere add noise; Polish labels truncate first (see below) |
| Fit for the audience | trusted and familiar, but nothing says "this is Lintel" | calm and confident; signals "your words" without AI clichés | warmest and most explanatory; can feel childish to lawyers and managers |

What the sketches showed when built:
- **Polish length**: at the 960 pt window, A and C truncate two of four Recent titles in Polish ("Rozmowa z klientem: …", "Cotygodniowe spotkanie sp…" in A; "Rozmowa z klientem: Nordlys En…", "E-mail do Marty o budżecie na IV k…" in C) because the status chip sits beside the title (A) or icon circles take width (C). B fits all four: status ("Notatki gotowe") goes into the meta line as accent text. Checklist rows wrap to two or three lines in Polish in all three.
- **Hierarchy**: A needs the green status dot and the filled primary button to show what matters; B gets it from type size alone; C from colour fills, which compete with the accent on the primary button.
- **Contrast** (WCAG, computed from the sketch tokens): accent text 6.3-7.9:1 and secondary text 5.3-6.4:1 in all three, both themes; white on the light accent button 5.0:1. Placeholder text is 2.6-2.7:1 in A and C (placeholder only; real content never uses that colour).

**Author's recommendation: B. Paper & Ink**, with two things borrowed from C: the "Finish setting up" checklist with a progress bar, and the green tinted status line in Settings. Reasons: it carries the brand (warm neutrals, the cut ring as the listening indicator) without leaving native controls, it is the only direction where Polish fits without truncation and without extra icons, it costs little more than A in SwiftUI, and it reads as calm and serious to all three personas. A is the fallback if build time is the constraint. This is a recommendation; nothing is decided until the owner picks.

## Validation

Before the decision (cheap, no build):
- **Five-second and preference test**: show the three Home screenshots (light, in the person's language) to five non-technical office workers, at least two Polish speakers. Ask what the app does, what they would click first, and which they would trust with a client memo. Pass: at least 4 of 5 can say "it types what I say and writes meeting notes" for the chosen direction.
- **Findability**: in the chosen Settings sketch, ask "where do you change how long dictations are kept?" and "where do you make Lintel spell a client's name right?". Pass: found in under 15 s by 4 of 5 without using search.

After the decision (in the design tracks' own PRs):
- SwiftUI gallery snapshots of the three screens in light and dark, S and XL text, English and Polish (conventions "Done means").
- Onboarding: time from first launch to first successful dictation, measured in QA runs with the `--qa` launcher; target under 3 minutes for a first-time user (persona Kasia).
- VoiceOver walk of onboarding and Settings; Reduce Motion on and off.

## Open decisions (owner)

1. **Direction**: A, B, C, or B with the two C borrowings recommended above.
2. **Default dictation shortcut**: keep ⌥ Space, or move to a single key like Wispr Flow's Fn. Fn is not a normal hot key on macOS and needs a feasibility check before it is promised.
3. **Dictionary as a top-level pane** (proposed in the IA and shown in the sketches) vs. keeping vocabulary inside Dictation.
4. **"Finish setting up" checklist on Home** (Linear-style, can be hidden, disappears when done): keep or drop.
5. **"Coming up" meetings on Home**: needs calendar access, which belongs to the later proactive-agent work; the sketches leave it out.
6. **Glossary adoption**: rename the visible strings in the settings rebuild (keys unchanged), e.g. "Tidy up my text", "AI on this Mac", "More options" instead of "Advanced". The conventions' archetype still says "Advanced disclosure"; the chosen wording should update `.uxproof/conventions.md` in the same PR as the rebuild.

## Evidence limits

- Personas are assumptions (no telemetry, no interviews). No user has seen the sketches.
- The research is desk research from public help pages and reviews (sources linked above); no App Store reviews quoting onboarding and no reviews from lawyers or sales teams were found.
- Sketches are HTML, not SwiftUI. Controls are drawn to look native but are not the real ones. Headless Chrome may not render New York (B) or SF Pro Rounded (C) and falls back to another serif or to SF Pro; the SwiftUI build would use `.fontDesign(.serif)` / `.fontDesign(.rounded)`.
- Screenshots cover light and dark, English and Polish, at the default text size only. XL text, VoiceOver and Increase Contrast were not checked.
- Only three screens per direction; other screens (notes reading view, HUD, permissions, empty and error states) are not sketched and may change the comparison.
- The research findings about Raycast's new first-run flow were not verified screen by screen.
