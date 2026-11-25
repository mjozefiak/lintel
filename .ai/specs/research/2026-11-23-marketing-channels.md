# Zero-budget launch channels for Lintel (research, 2026-11-23)

Scope: where a solo developer can find the first real users of a free, MIT, local-first Mac app (dictation + meeting notes; launcher, clipboard, files and windows as add-ons) in month 1. Labels: **FACT** = stated by the cited source; **INFERENCE** = my conclusion; **UNVERIFIED** = I could not confirm it from a primary source. All sources were accessed on 2026-11-23. Only WebSearch was available, so many rule pages are known from third-party summaries. Re-read each sidebar or rules page on the day you post.

## Key context before any channel

- **The niche is crowded.** FACT: recent Show HN posts include OpenWhisper, Ghost Pepper, TongueType and Yap, all local dictation apps for macOS (hn.svelte.dev/item/47006248, /47666024, /48148106, /49073834). FACT: lists of open-source Wispr Flow alternatives name VoiceInk, Handy, OpenWhispr, Blurt, Voquill and OpenFlow (startuphub.ai/startups/wisprflow-ai/open-source-alternatives; openalternative.co/alternatives/wisprflow). FACT: local Granola-style meeting tools include Meetily, anarlog/Hyprnote, Yogurt, HushScribe (macOS 26+, MIT), Daisy and Humla (openalternative.co/alternatives/granola; hn.svelte.dev/item/44725306; github.com/drcursor/HushScribe).
  - INFERENCE: "local Whisper dictation for Mac" no longer stands out on its own. The pitch has to lead with what the others lack: dictation **and** meeting notes with speakers in one encrypted, on-device app, plus Polish as a first-class language. Benchmarks against named tools (latency, WER on one real meeting) will carry more weight than adjectives.
- **Signing friction.** The release is signed with a self-signed certificate, not notarized (AGENTS.md). INFERENCE: every channel will produce "macOS says it's damaged" comments. Before launch, write a first-run Gatekeeper guide in the README and on the site.
- **AI label.** FACT: r/opensource now excludes projects that "use AI, are made by AI, or are intended for AI" (techrepublic.com/article/news-reddit-opensource-ai-ban-developers/, Oct 2026). INFERENCE: other communities apply the same lens. Describe the app as on-device speech recognition and lead with that; mention the optional LLM cleanup second.

## 1. Show HN (Hacker News)

- **Rules.** FACT: Show HN is for "something you've made that other people can play with" (news.ycombinator.com/showhn.html). FACT: asking for votes, using multiple accounts or vote rings is prohibited (news.ycombinator.com/newsguidelines.html).
  - FACT (secondary): link straight to the thing, not a landing page, and avoid hype language (dev.to/iris1031/how-to-launch-on-hacker-news-the-show-hn-guide-real-data-461e).
- **Timing.** FACT: an analysis of about 188k posts found the best slot is Monday 00:00 UTC (Sunday 7 pm ET), with a 10.8% chance of 50+ points; Sunday 02:00 and Saturday 19:00 UTC come next. HN score explains only about 8% of the variance in GitHub stars (r = 0.29), and a post's half-life is about 24 h (danfking.github.io/blog/2026/04/23/show-hn-by-the-numbers/).
  - FACT: a Myriade analysis of about 157k posts found Sunday (11.75% breakout) and around 12:00 UTC best (via hn.jakechampion.name reader of myriade.ai).
  - INFERENCE: post Sunday evening or very early Monday UTC.
- **Titles that work.** FACT: the recent dictation posts follow one pattern: "Show HN: Name – plain description with the differentiator" (e.g. "Yap – OSS on-device voice dictation for macOS with no model to download", hn.svelte.dev/item/49073834). UNVERIFIED: claims that short titles or the words "open source" lift results (dev.to/howiprompt…).
  - Suggested title: *"Show HN: Lintel – on-device dictation and meeting notes for macOS (open source)"*.
- **Prepare.** The GitHub repo as the link. A first comment covering why you built it, the stack (Parakeet/WhisperKit, llama.cpp, SQLCipher), honest limits (macOS 26 only, not notarized) and what feedback you want. Two or three hours free to answer every comment.
- **Effort** medium (one day). **Risk** low if you never ask for votes; flagged if hype-y. **Week** 2, after Reddit has surfaced the first install bugs. You can repost later after a significant update (INFERENCE from common practice; UNVERIFIED as a rule).

## 2. Product Hunt

- FACT: launching is free and makers are advised to post their own product from a personal account (launchrepo.dev/blog/product-hunt-launch-checklist-solo-developers/; daily.dev/blog/product-hunt-launch-checklist-developer-tools/). The bottleneck is being *featured*: an unfeatured launch sits behind the "All" toggle, and vote manipulation gets a launch unfeatured (same sources).
- FACT (anecdotal): a solo maker of a free OSS project expected 50–200 upvotes (dev.to/raxxostudios/…). FACT: one comparison suggests OSS projects launch on Show HN first and DevHunt second, and treat PH as optional (setproduct.com/blog/where-to-launch-startup-2026).
  - INFERENCE: worth it in 2026 only as a backlink and listing, not as a user source.
- **Prepare** a gallery of 4–6 screenshots, a 30–60 s video, a maker comment, and a "Wispr Flow / Granola alternative" tagline.
- **Effort** medium-high. **Risk** low. **Week** 4 or later, once you have real screenshots, a few testimonials and a notarization story. Launch on DevHunt in week 3 (devhunt.org; rules UNVERIFIED).

## 3. Reddit

| Sub | Current rule | Fit |
|---|---|---|
| r/macapps | FACT (secondary): devs may post their own app about once per 30 days with disclosure, otherwise in the megathread; promoting in comments needs some sub karma (threadotter.com/subreddit-rules/macapps). FACT: first-person "I built…" posts that solve a real problem do well (upvote.net/blog/macapps-reddit-analysis). | **Best fit.** Week 1. |
| r/LocalLLaMA | FACT (secondary): "Limit Self-Promotion", about 10% of activity, disclose affiliation; karma minimum reported inconsistently (intoru.ai/subreddits/localllama; willitstay.com/r/localllama). | Good if the post is technical: Parakeet vs WhisperKit numbers, llama.cpp cleanup prompt, memory. Week 2. |
| r/selfhosted | FACT (secondary): projects under 3 months old go only in the weekly New Project Megathread (rule as of Oct 2026) (willitstay.com/r/selfhosted). | Megathread only, week 1. Low fit (desktop app). |
| r/opensource | FACT: promotion limited to projects with multiple contributors, 1+ year of maintenance and a community; AI projects excluded (techrepublic.com, Oct 2026). | **Do not post.** |
| r/MacOS | FACT (secondary): Sep 2025 mod note allows self-promotion only for Mac App Store apps; a domain whitelist auto-removes links (libreddit mirror). | **Do not post** a direct-download app. |
| r/productivity | UNVERIFIED (no rules found). | Read the sidebar; comment-only. |

- Also relevant (INFERENCE, rules UNVERIFIED): r/speechtech, r/transcription, r/ADHD (dictation threads; promotion-sensitive), r/sideproject, r/Polska / r/programowanie.
- **Prepare.** An account with genuine comment history in each sub **before** launch (start now). A post with a GIF and the text: what it does, why local, "I'm the developer", known limits, and a request for issues.
- **Risk** high: removal or shadow-ban for link-dropping or cross-posting the same text. Write a different post per sub, days apart.

## 4. X / Bluesky / Threads (build in public)

- FACT: X still rewards reach and launches; Bluesky rewards replies and context, with about 10.4M MAU in June 2026 (down 27% YoY); Threads has about 147M DAU (daily.dev/blog/where-developer-twitter-went-x-bluesky-mastodon-2026/). Figures come from secondary reports.
- INFERENCE: with zero followers, reach comes from replies in other people's threads (Wispr Flow complaints, "local AI" posts), not from your own timeline. Post short screen recordings: dictation into Slack, a meeting transcript with speakers, a benchmark table. Cross-post to all three; Mastodon (mastodon.social / hachyderm) is OSS-friendly.
- **Effort** 20–30 min a day, continuous. **Risk** none. **Week** 0 onward; this is the support channel for every launch.

## 5. LinkedIn (EN and PL)

- No primary data found (UNVERIFIED). INFERENCE: this is the best channel for the meeting-notes use case (managers, consultants) and for a Polish professional network. Use a personal post, not a page: a native video of meeting notes on a Polish-language call, "free, no cloud, built in Poland". Put the link in the first comment.
- **Effort** low. **Risk** none. **Week** 1 (PL) and week 3 (EN).

## 6. YouTube and Mac reviewers

- FACT: TidBITS asks for a subject line starting "PITCH", with the app name and function and no adjectives, and asks pitchers to contribute to their community first (tidbits.com/2026/07/23/how-to-pitch-apps-to-tidbits-in-the-ai-era/). FACT: personalised pitches that cite the reviewer's prior coverage beat templates (indieappdevs.substack.com/p/indie-app-devs-3). FACT: creators respond to short, visual pitches with a video link (rc-revshare-system.pages.dev outreach guide).
- UNVERIFIED: which Mac YouTubers review free apps (no source found). INFERENCE: target small and mid-size channels that have already made "free Mac apps" or "Wispr Flow alternatives" videos. Find them by YouTube search and send 10 personal emails.
- **Prepare** a 60 s demo video, a press kit (icon, screenshots, one paragraph) and the Gatekeeper workaround.
- **Effort** medium. **Risk** none. **Week** 3–4 (pitch after HN, with social proof).

## 7. Newsletters, lists and directories

- **Homebrew cask.** FACT: notability requires 30 forks / 30 watchers / 75 stars, or **90 / 90 / 225 when the owner self-submits** (docs.brew.sh/Acceptable-Casks; docs.brew.sh/Package-Acceptance-Policy). UNVERIFIED (vendor blog only): Homebrew 5 audits for codesigned and notarized casks and removes failing ones by Sept 2026 (workbrew.com/blog/what-homebrew-5-0-0-means-for-your-mac-fleet).
  - INFERENCE: ship your own tap (`brew install --cask mjozefiak/tap/lintel`) now, and try the main repo only when notarized and above the bar, or when a user submits it.
- **awesome-mac (jaywcjlove).** FACT: accepts additions via issues and PRs, e.g. "Add DisplayBuddy (#1134)" (ecosyste.ms; github releases). Also open-source-mac-os-apps (serhii-londar) and awesome-mac-open-source (simonsruggi, auto-sorted by stars, refreshed weekly; github.com/simonsruggi/awesome-mac-open-source). One PR each in week 1. Risk: rejection only.
- **AlternativeTo.** FACT: it has an open-source filter on new releases (alternativeto.net/browse/new-apps/?license=opensource). Add Lintel as an alternative to Wispr Flow, Granola, Superwhisper, Raycast and Maccy in week 1; the submission flow is UNVERIFIED. **openalternative.co** lists Wispr Flow and Granola alternatives (FACT, URLs above); submit there too.
- **MacUpdate.** No current submission info found (UNVERIFIED). Low priority.
- **Console.dev.** FACT: features 2–3 developer tools a week, takes suggestions at hello@console.dev and publishes no sponsored reviews (console.dev/about; console.dev/selection-criteria). INFERENCE: it is dev-tool-focused, so pitch the launcher/clipboard angle or skip it. Low odds.
- **Changelog News.** Submission process UNVERIFIED. INFERENCE: send it after HN traction.

## 8. Polish channels

- **Wykop.** FACT: the regulamin version in force from 11 May 2026 allows business use; the moderation standards cover flooding and spam; penalties go up to a permanent ban (wykop.pl/regulamin; wykop.pl/standardy-moderacji; android.com.pl/tech/753472-wykop-zaostrza-regulamin/). No explicit self-promotion clause found (UNVERIFIED).
  - INFERENCE: a Mikroblog post under #programowanie #apple #macos #opensource, written as "zrobiłem po godzinach", with a GIF, works better than a link "Znalezisko".
- **unknowNews.** FACT: a periodic Polish IT link digest at unknow.news / mrugalski.pl (wykop.pl/ludzie/imlmpe). The submission route is UNVERIFIED; INFERENCE: contact via the site or a reply to the newsletter email. High-value Polish developer reach.
- **4programmers.** UNVERIFIED (search found nothing). INFERENCE: check for a projects subforum and post there.
- **Facebook groups (Mac PL, productivity PL).** UNVERIFIED (no specific group found). FACT: Facebook's Polish ad reach is about 24.8M accounts (antyweb.pl/facebook-w-2026-roku…, NapoleonCat Aug 2026). INFERENCE: search "Mac Polska" and "macOS Polska", read the group rules and ask an admin first.
- **Polish podcasts and media.** iMagazine.pl and Spider's Web cover Mac software (FACT: both appear in Mac news results, e.g. imagazine.pl/?p=241858; spidersweb.pl/2026/02/…). INFERENCE: "polski deweloper, darmowa aplikacja, polski język, dane zostają na Macu" is a newsworthy local angle. Pitch by email in week 2.
- **Effort** low-medium. **Risk** Wykop downvotes or bans for spam. **Week** 1–2. Polish users are likely the most forgiving early testers.

## Month-1 sequence (INFERENCE)

- **Week 0 (now):** README with a GIF, Gatekeeper steps, issue templates and "Discussions" enabled; own Homebrew tap; start commenting in target subs; social accounts posting progress.
- **Week 1:** r/macapps, the r/selfhosted megathread, awesome lists, AlternativeTo / openalternative, Wykop, LinkedIn PL.
- **Week 2:** Show HN (Sunday evening UTC), r/LocalLLaMA technical post, Polish media and unknowNews.
- **Week 3:** DevHunt, LinkedIn EN, YouTuber pitches.
- **Week 4+:** Product Hunt (ideally after notarization), Console/Changelog, Homebrew main repo once eligible.

## Prioritised table

| # | Channel | Effort | Ban/spam risk | Prepare | Best week |
|---|---|---|---|---|---|
| 1 | r/macapps | Low | Medium (1 post/30 days, disclose) | GIF, "I built" post, karma | 1 |
| 2 | Show HN | Medium | Low (no vote asks) | Repo link, first comment, half a day free | 2 (Sun 23:00–Mon 02:00 UTC) |
| 3 | Awesome lists + AlternativeTo + openalternative | Low | None | One-line description, icon | 1 |
| 4 | Polish: Wykop, unknowNews, iMagazine/Spider's Web, LinkedIn PL | Low-medium | Low-medium | Polish demo, PL-language angle | 1–2 |
| 5 | r/LocalLLaMA | Medium | Medium-high | Benchmarks, technical write-up | 2 |
| 6 | X / Bluesky / Threads / Mastodon | Continuous | None | 15–30 s clips | 0 onward |
| 7 | Own Homebrew tap | Low | None | Tap repo, cask | 0 |
| 8 | YouTube / Mac writers (TidBITS) | Medium | None | 60 s video, press kit | 3–4 |
| 9 | DevHunt, then Product Hunt | Medium-high | Low | Gallery, video, maker comment | 3 / 4+ |
| 10 | LinkedIn EN | Low | None | Meeting-notes video | 3 |
| 11 | Console.dev, Changelog, MacUpdate | Low | None | Email pitch | 4+ |
| — | Homebrew main repo | Low | Rejection | 225 stars (self) or 75 (other submitter) + notarization | After eligible |
| — | r/opensource, r/MacOS | — | High (rules exclude) | Do not post | — |
