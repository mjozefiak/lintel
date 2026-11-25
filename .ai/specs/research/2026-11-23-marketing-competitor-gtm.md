# Competitor go-to-market: Wispr Flow, Superwhisper, VoiceInk, Meetily / Hyprnote

Date: 2026-11-23. Purpose: learn how these products found their first users and what a solo, zero-budget OSS project (Lintel) can copy.
Labels: **FACT** = stated by a primary source or a public API at the date given. **INFERENCE** = my reading of facts. **UNVERIFIED** = only secondary sources, or sources disagree. All URLs were read on 2026-11-23.

## 1. Wispr Flow

### Timeline
- **FACT (founder account):** The company began as a wearable that turned silent speech into text. Work on the hardware stopped on 18 July 2024, and headcount went from about 40 to 5 in late July 2024. Sources: Kothari's post on Product Hunt, https://www.producthunt.com/p/wisprflow/how-wispr-flow-found-pmf-through-a-pivot, and Wispr's own copy, https://wisprflow.ai/post/pmf-through-pivot.
- **FACT (founder quote):** "We got millions of views and hit #1 on Product Hunt for the day and the week. Two months before that, we weren't even a consumer software company." https://nextplayso.substack.com/p/meet-the-startup-that-is-growing (2025-10-09).
- **UNVERIFIED:** The Mac launch on Product Hunt was on 30 Sep or 1 Oct 2024 and got about 2.1k upvotes and 527 comments, per hunted.space: https://hunted.space/product/wisprflow/launches/wispr-flow. Chris Messina was the hunter, per https://www.marketingmonk.so/p/wispr-flow-word-of-mouth-marketing-strategy (2026-05-10).
- **UNVERIFIED (secondary):** Windows shipped in March 2025, iOS in June 2025 together with a $30M Series A led by Menlo, and Android in February 2026. There was also a $25M extension at a $700M post-money valuation in November 2025. Sources: https://www.postbeam.ai/blog/how-wisprflow-grows (updated 2026-11-06). The iOS date is confirmed by TechCrunch: https://techcrunch.com/2025/06/03/wispr-flow-releases-ios-app-in-a-bid-to-make-dictation-feel-effortless, and the Android launch by https://techcrunch.com/2026/02/23/wispr-flow-launches-an-android-app-for-ai-powered-dictation.

### Early numbers
- **FACT (founder quote, same Next Play piece):** About 20% of users converted to paid, against a usual 3–4%. Organic growth was about 90% month over month in January and February 2025. Users made about 100 dictations a day.
- **UNVERIFIED:** Revenue grew 150x and users 200x in the year to May 2026, ARR was about $10M in October 2025, and 270+ Fortune 500 companies were customers. These come from postbeam (above) and founder tweets that I did not check against the tweets themselves.

### Channels in the first ~12 months
1. **One big Product Hunt launch, treated as a single shot.** A well-known hunter, a six-week sprint, and a full marketing push for launch day. Per marketingmonk (UNVERIFIED), the Windows launch got its own hunt from Product Hunt's CEO. **INFERENCE:** Each new platform was used as a fresh launch event (Mac, then Windows, iOS, Android).
2. **Seeding to a dense, influential network.** The first users were Silicon Valley VCs and founders, and the founder onboarded them personally. Later came public praise from Reid Hoffman ("voicepilled"), Marc Andreessen and Rahul Vohra. Postbeam says these endorsements were not paid, though some of the people are investors. UNVERIFIED; sources: postbeam, marketingmonk.
3. **Founder posts on X and LinkedIn.** Tanay Kothari (@tankots) posts metrics and product thinking publicly, and the founder says long user posts on LinkedIn and X drove the second wave of growth (FACT, Next Play quote). Postbeam reports that the paid LinkedIn spend mostly boosts the founder's own posts (UNVERIFIED).
4. **Referral program.** **FACT:** users get an invite link under Hub → Account → "Refer a friend" and earn free months of Pro for each person who signs up: https://docs.wisprflow.ai/articles/6496688316-how-to-find-your-referral-link. **UNVERIFIED:** an early version rewarded referrals in dictation words and was later simplified to "give a month, get a month" (postbeam).
5. **Affiliates.** **FACT:** creators earn 25% of each sale for one year on individual Pro referrals, run through Dub: https://partners.dub.co/flow.
6. **Gamified waitlist for Android.** A waitlist of 375k with a leaderboard, referral multipliers and merchandise for the top 100. UNVERIFIED (marketingmonk).
7. **Paid UGC and ads (after the first year, with VC money).** The founder claimed "500m views in 60 days" from a UGC program. Postbeam counts about 610 Meta ads, about 900 Google ads (mostly YouTube) and comparison SEO pages. UNVERIFIED.
8. **Podcasts and investor distribution.** Founder-audience podcasts, plus a Flight Fund (Steven Bartlett) investment said to include a content collaboration. UNVERIFIED (marketingmonk).

### Positioning and copy
- **UNVERIFIED (postbeam):** The 2024–25 headline was "Think it, speak it, send it." with logos of companies using it. The 2026 headline is "Don't type, just speak."
- **FACT:** The site today reads "The voice-to-text AI that turns speech into clear, polished writing in every app" and "Talk 4x faster": https://wisprflow.ai/post/pmf-through-pivot. The site also has comparison pages against Apple Dictation and Gboard.
- **INFERENCE:** The message was always about one change in behaviour (speak instead of type, in the apps you already use), never about the model.

### Pricing
- **UNVERIFIED:** The launch introduced Free plus Pro at about $12 per month billed yearly, per https://usagepricing.com/blueprint/wisprflow. Later the free tier was 2,000 words a week on desktop and Pro was $15 a month, per postbeam. A student offer gives 3 months free and then $6 a month: https://wisprflow.ai/students. Numeric free limits were dropped in November 2026, per https://pricingsaas.com/news/article/wispr-flow-drops-numeric-free-plan-limits-makes-pro-meetings-unlimited.

### Feedback loop
- **FACT:** Users are pointed to support email for ideas (https://docs.wisprflow.ai/faqs/curious-questions), and there is a public changelog at https://roadmap.wisprflow.ai and https://wisprflow.ai/whats-new. Founders answer feature requests in Product Hunt comments (https://www.producthunt.com/p/wisprflow/wispr-flow).
- I found no public Discord. The team's motto is "Talk to users, every day if you can" (FACT, Next Play).

## 2. Superwhisper (bootstrapped, closed source)
- **FACT:** "Show HN: superwhisper – AI powered offline voice to text for macOS" was posted on 2023-08-21 and got 43 points and 48 comments: https://news.ycombinator.com/item?id=37204722. The post is written by the founder in first person ("built out of frustration with native dictation") and names whisper.cpp. The base models were free, while larger models and non-English languages were paid. It asks people to follow releases on X (@superwhisperapp) or join an email list. In the post he says he launched "one month ago", which fits the Product Hunt listing date of 24 July 2023 (https://www.producthunt.com/products/superwhisper/launches).
- **FACT:** The iOS app had its own Product Hunt launch on 2024-04-17: https://www.producthunt.com/products/superwhisper/launches/superwhisper-for-ios.
- **UNVERIFIED:** Superwhisper is bootstrapped with no outside money and reported "hundreds of thousands of weekly active users" by early 2026, per https://aiwiki.ai/wiki/superwhisper, which cites the Globe and Mail.
- **INFERENCE:** Growth came from shipping very often and posting release notes on X. A free local tier did the job of a trial. There was no paid launch machine.

## 3. VoiceInk (open source, Mac, solo developer)
- **FACT:** The repo is github.com/Beingpax/VoiceInk. It was created on 2024-10-20, has 7,190 stars, has Discussions turned on, and its homepage is tryvoiceink.com (GitHub API, 2026-11-23). The README says the developer built the app for 5 months before opening the source, that buying the app funds full-time work, and that pull requests are not accepted (only issues and ideas): https://raw.githubusercontent.com/Beingpax/VoiceInk/main/README.md.
- **FACT:** The model is free to build from source and $25 one-time for the signed build (https://tryvoiceink.com/walloflove). The developer announced the Product Hunt launch to existing buyers through Gumroad posts: https://beingpax.gumroad.com/p/voiceink-is-now-on-producthunt-needs-your-support.
- **FACT:** Hacker News posts got 2 points each, e.g. https://news.ycombinator.com/item?id=45210599 ("Open-Source Whispr Flow and SuperWhisper Alternative"). HN was not the channel that worked.
- **UNVERIFIED/INFERENCE:** The listings that keep sending traffic are open-source directories (openalternative.co, alternativeto.net), Homebrew and "alternative to X" framing. A public "wall of love" page serves as social proof. I could not reach Reddit (the API returned nothing), so r/macapps is UNVERIFIED.

## 4. OSS meeting notes: Meetily and Hyprnote
- **Meetily, FACT:** Zackriya-Solutions/meetily was created on 2024-12-26, is MIT-licensed, has 32,982 stars and has Discussions turned on (GitHub API). Its Show HN on 2025-02-22 got 4 points: https://news.ycombinator.com/item?id=43137186. The pitch was "Alt to Otter.ai", privacy, no SaaS fees, with a clear tech stack. **FACT:** the team publishes a long series of dev.to posts using SEO-style "Granola/Fireflies alternative" titles, e.g. https://dev.to/zackriya/meetily-the-best-free-open-source-self-hosted-ai-meeting-note-taker-a-granola-alternative-for-2c8e. **INFERENCE:** The stars came from steady content plus "free alternative to <paid brand>" positioning and GitHub Trending, not from a launch day. How fast it grew is UNVERIFIED, because the dated snapshots disagree.
- **Hyprnote, FACT:** A Show HN on 2025-04-20 got 18 points (https://news.ycombinator.com/item?id=43741559). The Launch HN after joining YC S25 on 2025-07-29 got 270 points and 180 comments: https://news.ycombinator.com/item?id=44725306. The pitch was "open-source Granola", fully on-device. The repo is now fastrepl/anarlog (MIT, 9,969 stars, "Open source Granola AI Alternative"). **UNVERIFIED:** a 70% Pro discount for Product Hunt visitors (https://www.producthunt.com/p/hyprnote/hyprnote-2), and a later rebrand to Char/Anarlog.
- **A relevant extra data point, FACT:** "Show HN: Free alternative to Wispr Flow, Superwhisper, and Monologue" (zachlatta/freeflow) was posted on 2026-02-16 and got 277 points and 132 comments: https://news.ycombinator.com/item?id=47040375. The repo now has 3,150 stars. **INFERENCE:** On HN, the title framing "free alternative to <known paid brands>" beats a product name nobody knows.

## 5. What this means for Lintel (INFERENCE)
- Wispr's real edge was **network density and the founder's personal onboarding**, not money. A solo developer can do a small version: hand-pick 10–20 heavy writers or note-takers (Polish dev and founder communities, accessibility/RSI users), install the app with them on a call, and ask them to file issues.
- For OSS, the pattern that worked is **"free, local, open-source alternative to Wispr Flow / Granola"** as the headline, plus directory listings, a Homebrew cask, a regular content cadence and visible release notes. A single launch day matters less than steady presence.
- HN results are bimodal: a plain product name got 2–43 points, while "Free alternative to …" and Launch HN got 270+. Write one well-framed Show HN rather than repeat posts.

## Copy / Skip

| Tactic | Who did it | Cost | Verdict for Lintel |
|---|---|---|---|
| Founder-written Show HN, first person, "free/open-source alternative to Wispr Flow/Granola" title | Superwhisper, Hyprnote, freeflow | 0 | **Copy**, once, well-timed |
| Product Hunt launch with a credible hunter, rally existing users/buyers | Wispr, Superwhisper, VoiceInk (Gumroad email) | 0 | **Copy**; treat each platform/major feature as a new launch |
| Founder posts on X/LinkedIn: release notes, metrics, demos | Wispr, Superwhisper | 0 (time) | **Copy** |
| Personally onboard a dense, influential first cohort | Wispr | 0 (time) | **Copy** at small scale (10–20 people, calls) |
| "Wall of love" / testimonial page from real users | VoiceInk, Wispr | 0 | **Copy** once quotes exist |
| OSS directories, Homebrew, "alternative to" pages, dev.to series | VoiceInk, Meetily | 0 | **Copy** |
| GitHub Discussions + issues as the public feedback channel, public changelog | VoiceInk, Meetily, Wispr (changelog) | 0 | **Copy** |
| Refer-a-friend for free Pro months | Wispr | needs a paid tier | **Skip** (nothing to give); revisit only if paid features appear |
| 25% affiliate program via Dub | Wispr | revenue share | **Skip** |
| Gamified waitlist with leaderboard and merch | Wispr (Android) | merch + tooling | **Skip** (app is already downloadable) |
| Paid UGC (500M views), Meta/Google ads, boosted founder posts | Wispr | high, VC-funded | **Skip** |
| Celebrity/VC endorsements, Head of Celebrity Partnerships | Wispr | network + staff | **Skip** |
| Investor-for-distribution deals (podcast host fund) | Wispr | VC round | **Skip** |
| Localized market push (Hinglish model, India pricing) | Wispr | team + pricing | **Partial copy**: Polish UI and Polish dictation quality as a free home-market angle |
