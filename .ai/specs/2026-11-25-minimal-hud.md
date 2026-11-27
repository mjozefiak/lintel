# Minimal HUD pills: dictation, meeting recording, meeting suggestions

> Status: **design. OD-1 to OD-13 and Q1 to Q5 decided by the owner (2026-11-26).** Phase 1 (`LintelPill`, the gallery scene `ui.pill`, the R2/R3 spike) is implemented; Phases 2 to 4 are not. OD-6 and OD-7 took the alternative (consent reminder only in the meeting's window; nothing about the speech model in the pill, the app says it after the recording); the other eleven took the recommendation. Q1 (a), Q2 (b), Q3 (a), Q4 (b), Q5 (a). Phase 4 is gated only on the recording panel (#255 step 4.3) being on `main`, and its OD-7 step on #346.
> Owner direction (2026-11-25): "te pastylki u konkurencji zawsze są mega minimalistyczne i też chcę, aby tak było w Lintel; obecnie jest tam za dużo zbędnych informacji, ograniczamy się do totalnego minimum."
> Sketch (before and after for every state, light and dark, en and pl, S/M/XL, Reduce Motion, Increase Contrast, hover): `.ai/specs/assets/minimal-hud/index.html`. It is a sketch for the decision only: after acceptance the SwiftUI gallery (#248) is the source of truth.
> Related: #233 (the meeting clock wraps when a notice adds a second button; this design removes that layout), #236 (its fix), #258 (new microphone states, merged 2026-11-25, mapped below), #266 (a dictation state for a lost microphone, not designed here), #333 (`LintelRing`, merged 2026-11-26, reused by the pill), #346 (OD-7: the app's text after a meeting the speech model could not transcribe).
> Inputs: the current HUD code (`Sources/DictationPlugin/HUDState.swift`, `DictationHUD.swift`, `Sources/MeetingsPlugin/UI/MeetingHUDState.swift`, `MeetingHUD.swift`, `Sources/MeetingsPlugin/Suggestions/SuggestionHUD.swift`, `SuggestionPrompt.swift`), the `--qa-hud` states in `docs/qa.md`, the new states of PR #258, the UX direction of PR #247 (the working ring, Verdigris only for live state) and the gallery spec of PR #248.

## 📝 TLDR

**Who:** everyone who dictates or records meetings. Office users who never read a HUD on purpose: the pill must be understood at a glance or not noticed at all.
**Today:** three different floating surfaces. Dictation is a 248 × 40 pt capsule with an icon, the word "Recording", level bars, a timer and a ✕. The meeting HUD is a 400 × 44–68 pt rounded rectangle with the time, two named level meters, a red "End recording" button and a second line of notices (up to 63 characters). The suggestion is a 440 × 78 pt card with a sentence and three buttons. PR #258 adds a two-line bubble above the dictation pill and more notices to the meeting HUD.
**Proposed:** **one pill family** (`LintelPill`): a capsule 32 pt high (28 at S, 35 at L, 38 at XL), glass, one line of text at most, at most one text button plus ✕. In the normal state the pill shows only what is live: dictation = the turning ring and the voice wave (88 pt wide); meeting = the ring with its dot, the time and a stop button (about 120 pt). Everything else (timer, ✕, meters, "End", "Don't ask again", processing details) appears **only on hover** and is always in the VoiceOver label. A problem appears **only while it exists**, as one short line with one action. Finished states are a ✓ or one word.

## ✅ Owner decisions (decided 2026-11-26)

| # | Question | Decision | Why it matters |
|---|---|---|---|
| OD-1 | Colour of "live" | **Verdigris ring** for both pills (#247: the ring is the brand signature, Verdigris marks live state) | The meeting pill is visible in screen sharing on purpose; a red dot would be understood by everyone on the call (risk R4). |
| OD-2 | Dictation: timer and ✕ | **Hover only**; Esc still cancels; the ✕ is always visible only when Esc could not be claimed | Wispr's bar shows only the wave. The timer tells an office user nothing while dictating. |
| OD-3 | After pasting | **✓ for 0.6 s**, then gone | Today "Pasted" stays 0.8 s. |
| OD-4 | "Pasted – partly cleaned up" | **Show nothing**; "Pasted without cleanup" (all raw) stays, without the "Raw version: …" hint | A partial fallback is invisible to most users; the hint names a menu path nobody reads in 3 s. |
| OD-5 | Meeting level meters | **Hover only**; problems come as notices (20 s system silence, 10 s microphone silence, lost device) | The notices already detect the failures the meters were for. |
| OD-6 | Consent reminder | **Only in the meeting's window**; the pill has no reminder line and no "Copy message" button. This spec reads "the meeting's window" as the recording panel of the main window (spec `2026-11-24-notes-explorer-main-window`), because the per-meeting `MeetingWindowController` is not open while a meeting records. When the main window is closed at the start, it opens on the recording panel (Q4 (b)) | It protects the user legally; the owner wants the pill to carry problems only. See "Consent reminder (OD-6)" below. |
| OD-7 | Model loading / model unavailable during recording | **Silent pill**, also on hover (no "Text after the meeting"). The audio is recorded anyway and the transcript and notes can be made later; the app says so **after the recording**, not in the pill | Recording already runs; the user can do nothing about it then. See "After the recording: what the app says (OD-7)" below. |
| OD-8 | A problem that lasts | **Line stays 10 s**, then the pill shrinks back and keeps an amber dot on the ring; hover and VoiceOver give the line again; a new problem expands it again | Long lines over a call window are the clutter the owner named. |
| OD-9 | After "End" (meeting) | **Closing ring only**; "Transcribing, 3 left" on hover; then "Saved · Open" 3 s | Processing can take minutes; the ring says "working" without words. |
| OD-10 | Suggestion pill | **One line + "Record" + ✕ (= Not now)**; "Don't ask again" on hover; end question: "End the recording?" + "End" + ✕ (= keep recording) | The mute choice is rare and stays one hover away. |
| OD-11 | Chosen microphone missing (#258) | **Name of the microphone used, 3 s (dictation) / 4 s (meeting)**, then an amber dot; hover shows it | Quality changes when the built-in mic replaces a headset. |
| OD-12 | Meter names | **"You" / "Others"** ("Ty" / "Rozmówcy") instead of "Me" / "System" | "System" is jargon for office users. |
| OD-13 | Size | **32 pt at M**, follows the app's text size (28 / 32 / 38 at S / M / XL; L is not named in the decision, this spec uses 35 pt, see "The pill family") | XL users get readable pills; today HUDs ignore text size. |

## ✅ Follow-up questions decided (2026-11-26)

| # | Question | Decision | What it means here |
|---|---|---|---|
| Q1 | The recording panel with the consent reminder (#255 step 4.3) may land after the meeting pill is ready. | **(a) The new meeting pill lands together with the recording panel** (#255 step 4.3). The dictation pill and the suggestion pill do not wait. | Phasing: Phase 2 (dictation) and Phase 3 (suggestion pill) go as soon as Phase 1 is in; Phase 4 (meeting pill) merges only when the recording panel is on `main` (same merge batch or right after it, never before). Today's meeting HUD, with its consent line, stays until then. |
| Q2 | "Copy message" (MEET-1.6) leaves the pill. | **(b) MEET-1.6 is retired.** No button that copies the consent sentence anywhere, the recording panel included. | See "Consent reminder (OD-6)", "Retiring Copy message (Q2)". Phase 4 removes the code path; the schema does not change. |
| Q3 | OD-7 in dictation: dictation keeps no audio, so a model that fails after the key is released cannot be "made later". | **(a)** The dictation pill is silent only while the model loads (`recording(loadingModel)`); "No speech model · Download" and "Speech model isn't working · Fix" stay as short lines. | The dictation table below is final for Phase 2; Q3 no longer blocks it. |
| Q4 | What does "the meeting's window" mean for a meeting started with ⌃⌥M, from the menu bar or from a suggestion while the main window is closed? With OD-6 read literally such a meeting gets no reminder at all, and that is the usual way to start a recording. | **(b)** When a recording starts (⌃⌥M, the menu bar or a suggestion) while the main window is closed and `plugins.meetings.consentReminder` is on, the main window opens on the recording panel (#255 step 4.3), which shows the consent reminder. With the setting off the window does not open. | The pill never carries the reminder: `Notice.consent`, `Recording.showsConsent`, the 8 s `consentDuration` timer and the `recording-consent` QA state go in Phase 4 (risk R6 decided). The main window is an activating window and may take the focus from the call app (risk R8): Phase 4 finds a way to open it without that, or reports to the owner. See "Consent reminder (OD-6)". |
| Q5 | Phase 4 removes the pill's only hint that the transcript comes later (OD-7). Until #346 lands, a meeting the speech model could not transcribe ends with the wrong banner "Recording was interrupted. The transcript may be missing its end." Does that part of Phase 4 wait for #346? | **(a)** Gated: the step that maps `.loadingModel` / `.modelUnavailable` to the plain pill (Phase 4 step 3) merges with or after #346. If Phase 4 is ready first, those two notices keep one interim line, "Text comes after the meeting" / „Tekst będzie po spotkaniu” (28 / 25 characters), until #346 is on `main`. | Only that step waits; the rest of Phase 4 does not. The interim line's lifetime is in the meeting table (risk R7 decided). |


## 📝 Problem Statement

1. **Too much in the normal state.** While dictating, the user sees an icon, a word, bars, a timer and a ✕ (five things) where they need one: "it is listening". The meeting HUD shows a clock, two labelled meters and a red button across 400 pt at the top of the call window.
2. **Notices are long and technical.** "Check the system audio recording permission", "No microphone audio – check the microphone permission and input", "Another speech model is in use – the text comes after the meeting" (63 characters). They wrap or get squeezed in Polish (#236, the #258 screenshots).
3. **Three shapes, three sizes.** Capsule, rounded rectangle and card; widths 248, 400 and 440 pt; buttons as links, bordered and prominent. PR #258 adds a fourth: a bubble above the capsule.
4. **States that the user cannot act on are shown** (model loading, partial cleanup, processing counts), and one reminder that is not a problem (the consent line in the first 8 s).

## 📝 Market

- **Wispr Flow** (research 2026-11-24, `research-competitors-ui.md` §1): "zero UI" with one small Flow Bar; the only change made after 700 critics answered was letting users move it. The brand lives in motion, not in text.
- **Granola**: no floating HUD while recording; the state lives in the notes window and the menu bar. Complaints are about silent empty recordings, i.e. missing problem signals (§4), which is why problems stay visible here.
- **Circleback**: "clean, distraction-free interface" is what users praise.
- Not verified on screenshots: exact sizes of the Flow Bar. The sketch takes the size from the owner's direction, not from a measurement.

## 📝 Proposed Solution

### The pill family

| Variant | Content | Width | Used by |
|---|---|---|---|
| `live` | glyph + live content (wave, or time) + hover content + optional trailing control | hugs the content (dictation 88 pt, meeting ≈ 120 pt) | dictation recording, meeting recording |
| `working` | the closing ring only (a 32 pt circle) | 32 pt | dictation finishing, meeting processing |
| `message` | glyph + one line + at most one text button + optional ✕ | hugs, max 380 pt (420 at L, 450 at XL) | problems, done states; also the notes explorer's `UndoToast` (spec `2026-11-24-notes-explorer-main-window`, component table and step 1.5: no ✕, one button "Undo", title shortened in the middle) |
| `prompt` | glyph + one line + one primary button + hover link + ✕ | hugs, max 380 pt (420 at L, 450 at XL) | suggestions, "Microphone denied, record others only" |

- Shape: capsule, height 28 / 32 / 35 / 38 pt (app text size S / M / L / XL; `TextSize` has four sizes, OD-13 names three: L follows `LintelRingMetrics.points`, which scales M by 1.1 at L and 1.1875 at XL, so L = 32 × 1.1 ≈ 35 pt and XL = 32 × 1.1875 = 38 pt), glass `.regular`, system shadow. Padding 10 pt leading, 12 pt trailing, 8 pt spacing.
- Text: 12 / 13 / 14 / 15 pt medium (S / M / L / XL), **one line, never wraps**. Copy budget: 40 characters in both languages (a test checks every pill string in `Localizable.xcstrings`), and the pixel width limit above (checked by the gallery snapshots at XL).
- Glyphs (16 / 16 / 17.6 / 19 pt, S / M / L / XL): **live** = the cut ring turning slowly; the meeting ring has the breathing centre dot, the dictation ring has none (the same meaning as the note-type ring in #247). **working** = the ring closing. **problem** = amber triangle (`statusAttention`). **failed** = red triangle (`statusError`). **done** = ✓ in the live colour. Microphone problems use `mic.slash` in amber. The ring is the existing `LintelRing` (`Sources/LintelUI/Components/LintelRing.swift`, #333, on `main`): live = `.listening`, the amber dot of OD-8 / OD-11 = `.warning` (a dictation ring gets the dot too), working = `.processing(progress:)`, mark `.meeting` / `.dictation`; sizes already follow `LintelRingMetrics` (16 / 16 / 17.6 / 19 pt). The pill does not draw a ring of its own; under Reduce Motion it shows what `LintelRingAppearance` gives (`LintelRingMotion.reduced`): no turning, no breathing, and the working ring as a static part ring with its track, no spinner.
- Buttons: one text button (`act`, neutral fill, the live colour only for a prompt's primary), ✕ 22 pt (hit area 24 pt), the meeting's stop button is a 22 pt circle with a square.
- Positions do not change: dictation bottom centre, 48 pt above the visible frame; meeting and suggestion top centre under the menu bar. The distances are measured to the **pill's** edge, not the panel's: the transparent panel is placed (56 − pill height) / 2 pt lower (dictation) or higher (meeting, suggestion) than today's origin (`DictationHUD.swift` `minY + 48`), so the pill sits where today's HUD sits. A pill is at most 380 pt wide at S and M, 420 pt at L and 450 pt at XL, plus 120 pt while hovered (hover content must never truncate the main line). Measured in the sketch, every state in en and pl fits without truncation: widest normal pill 376 pt (M, pl) and 415 pt (XL, pl), "Mikrofon nie nagrywa · Spróbuj ponownie"; widest hovered 442 pt (M, pl) and 489 pt (XL, pl), the suggestion pill (re-measured 2026-11-26 in headless Chrome after OD-6 and OD-7 removed the consent and model lines: unchanged, neither was the widest). The panel is a fixed transparent window larger than the widest pill (580 × 56 pt), the pill centred in it, so expanding never moves or resizes the window. The transparent area must stay click-through (risk R2).
- The meeting pill stays visible in screen sharing; the suggestion pill stays hidden from it (`sharingType = .none`), as today.

### Hover

- 300 ms after the pointer enters the pill (movement inside it does not restart the timer) it expands (spring 0.2 s; instant under Reduce Motion) and shows its hover content. It collapses 500 ms after the pointer leaves. Keyboard focus on a button inside the pill counts as hover.
- Hover content is a shortcut to things that exist elsewhere: cancel (Esc), End (⌃⌥M, the menu bar and the stop button that is always in the meeting pill), "Don't ask again" (Settings → Meetings). The one exception is the level meters: after OD-5 they exist **only** on hover (the meeting window has neither meters nor an End button) and VoiceOver has no level value; what they were for reaches every user as a problem line ("Can't hear the others", "Can't hear your microphone"). Hover never adds a model or reminder line (OD-6, OD-7); the only exception is the interim Q5 line until #346.
- The panels stay non-activating and never take focus.

### Dictation states (bottom centre)

| Today (`HUDState`) | After | Stays | Goes |
|---|---|---|---|
| `recording` | `live`: ring + wave. Hover: `0:12` + ✕ | the ring, the wave | "Recording", red dot, timer, ✕ (OD-2) |
| `recording`, Esc not claimed | ring + wave + ✕ always | ✕ | "✕ cancels" |
| `recording(loadingModel)` | same as recording, also on hover | — | "Loading model…", blinking caret (OD-7) |
| `recording(secondsLeft)` | ring + wave + amber `9` | the seconds | "Stops in 9 s" |
| `recording(fallback)` (#258) | ring with amber dot + wave + "Using MacBook Pro Microphone" for 3 s, then the collapsed pill with the amber dot; hover shows the line again (see "Microphone line (OD-11)") | — | the two-line bubble (OD-11) |
| `allowMicrophone` | message: "Allow the microphone in the dialog" | | |
| `finishing` | `working` ring | | "Finishing…" |
| `pasted` | ✓ for 0.6 s (OD-3) | | "Pasted" |
| `pastedUnformatted(all: true)` | ⚠ "Pasted without cleanup", 3 s | | "Raw version: Dictation → Paste raw version" |
| `pastedUnformatted(all: false)` | nothing (OD-4) | | |
| `copied(.noAccessibility)` | ⚠ "Copied, paste with ⌘V" · **Allow** | | |
| `copied` | ⚠ "Copied, paste with ⌘V" | | |
| `problem(.modelMissing)` | red ⚠ "No speech model" · **Download** | | "in Settings" |
| `problem(.modelUnavailable / .modelFailedToLoad)` | red ⚠ "Speech model isn't working" · **Fix** | | two texts merge |
| `problem(.speechModelBusy)` | ⚠ "Dictation is back after the meeting" | | jargon |
| `problem(.microphoneDenied)` | mic ⚠ "No microphone access" · **Allow** | | "Open Settings" |
| `problem(.noMicrophone)` | mic ⚠ "No microphone found" | | |
| `problem(.nothingHeard)` | ⚠ "Nothing heard" | | |
| `problem(.nothingToPaste)` | ⚠ "Nothing to paste yet" | | |

OD-7 in dictation covers the model loading while the user speaks (`recording(loadingModel)`). The model problems above come when the key is pressed or after it is released, when there is no dictation or it is lost (dictation keeps no audio, so nothing can be made later), so they stay one line in the pill (owner decision Q3 (a)).

`recording(secondsLeft)` is not a problem line: the amber seconds replace nothing and never collapse (OD-8 does not apply to it). With Esc not claimed, the ✕ stays visible in every recording variant (fallback and countdown included).

### Microphone line (OD-11)

Both pills show the same text, built from `InputFallback` (`Sources/LintelSpeech/InputDeviceResolution.swift`):

| `InputFallback` | Line (en / pl) |
|---|---|
| `usingName` known | "Using %@" / „Mikrofon: %@” with the name Core Audio gives (e.g. "Using MacBook Pro Microphone") |
| `usingName` nil (the default input has no name) | "Using the default mic" / „Domyślny mikrofon” |

- The requested device's name (the one that is missing) is not in the line; it is in the VoiceOver label ("USB Microphone unavailable, using MacBook Pro Microphone"), as in today's `InputFallback.message`.
- A long name is shortened in the **middle** by the pill so the line stays within the width limit; the 40-character budget is checked with a 20-character placeholder name, and the full name is in the VoiceOver label and the hover line.
- The new strings live where today's does: a new `InputFallback.pillLine` in `LintelSpeech`, next to `message`, so both HUDs keep one key per text (comment prefix `HUD pill:`). `message` is removed with its last use (the meeting HUD, Phase 4).

### Meeting recording (top centre)

While a problem line is shown, the clock steps aside (ring · line · action · stop) and comes back when the line goes; the time stays in the VoiceOver label. This keeps every line within the width budget and puts the one thing that matters first. The pill shows no line that is not a problem: the consent reminder is in the recording panel of the main window, which opens at the start when it was closed (OD-6, Q4 (b)), and the speech model is not mentioned while recording (OD-7; until #346 lands, the interim line of Q5 (a)).

| Today (`MeetingHUDState`) | After | Goes |
|---|---|---|
| `recording` | `live`: ring with dot + `12:34` + stop. Hover: You ▂ · Others ▂ · **End** | "Recording a meeting" (not visible, it is in the VoiceOver label), two named meters, red "End recording" (OD-1, OD-5, OD-12) |
| `recording`, system track off (`recordsSystem == false`, QA `recording-microphone-only`) | as `recording`; hover shows only You ▂ · **End** (no "Others" meter); VoiceOver "Recording a meeting, your microphone only, 12:34" | the "System" meter |
| notice `.consent` (first 8 s) | the plain recording pill, however the recording started (OD-6, Q4 (b)): no line, no button. The reminder is in the recording panel; the main window opens on it at the start when it was closed and the setting is on | the line, "Copy message" (Q2), the long sentence; the notice itself (Phase 4) |
| notice `.loadingModel`, `.modelUnavailable` | plain recording pill, hover unchanged (OD-7); the app says it after the recording (#346). **Interim (Q5 (a)), only while #346 is not on `main`:** the line "Text comes after the meeting" for 10 s, then the plain pill **without** an amber dot (it is not a problem the user can act on, and OD-7 wants the pill silent); while the notice lasts, hover shows the line again and the VoiceOver label carries it | the notice's text |
| notice `.limitCountdown` | ring + amber "Ends in 4:59" + stop; it is a clock, not a problem line, so it never collapses (OD-8 does not apply); if a collapsed problem is also active, the ring carries the amber dot next to the amber clock | separate line |
| notice `.noSystemAudio` | ring · ⚠ "Can't hear the others" · **Fix** · stop | jargon |
| notice `.noMicrophoneAudio` | ring · mic "Can't hear your microphone" · **Fix** · stop | |
| notice `.deviceDisconnected` | ring · mic "Microphone disconnected" · **Try again** · stop | |
| notice `.microphoneNotRecorded` (#258) | ring · mic "Your mic isn't recording" · **Try again** · stop | squeezed meters |
| notice `.retryingMicrophone` (#258) | ring · working ring "Reconnecting the mic…" · stop: the line's glyph is `PillGlyph.working(dot: false)`, a second `LintelRing` in `.processing` (the static part ring with its track under Reduce Motion); there is no separate spinner | |
| notice `.microphoneFallback` (#258) | "Using MacBook Pro Microphone" 4 s, then amber dot (OD-11, "Microphone line (OD-11)") | both device names |
| notice `.systemAudioLost` | ring · ⚠ "Others' audio stopped" · **Fix** · stop (new: today this notice has only Stop) | |
| notice `.lowDisk` | ring · ⚠ "Low disk, ends soon" · stop | |
| notice `.writeProblem` | ring · ⚠ "Saving problem, fix it later" · stop | |
| any problem line after 10 s (every notice above except `.limitCountdown`, `.microphoneFallback`, whose line lasts 4 s (OD-11), and the interim Q5 line, which collapses without the dot) | plain pill with an amber dot on the ring (OD-8) | the line |
| `finishing`, `processing(.closing)` | `working` ring with dot; hover "Saving the meeting" | "Processing…" |
| `processing(.transcribing)`, `processing(.recognisingSpeakers)` | `working` ring with dot; hover "Transcribing, 3 left" / "Recognising speakers" (OD-9) | "Processing: transcribing (3 left)" |
| `saved` | ✓ "Saved" · **Open**, 3 s | |
| `savedIncomplete` | ⚠ "Saved, incomplete" · **Open**, 6 s | "not complete" |

"Fix" opens the place that fixes it: the system audio and microphone privacy panes (today's `openSettings` / `openMicrophoneSettings` actions). "Try again" is #258's `retryMicrophone`. "Open" is new: it opens the saved meeting in the meeting window (`MeetingWindowController`), see Architecture.

### Consent reminder (OD-6)

What the code has today:

- The reminder is the HUD's second line only: `MeetingController` sets `Recording.showsConsent` from `plugins.meetings.consentReminder` (default on, Settings → Meetings "Remind me to say I am recording") and clears it after `consentDuration` (8 s); `MeetingHUDState.Notice.consent` with the actions `copyConsentText` and `stop`. "Copy message" puts `MeetingConsentText.sentence` on the pasteboard and `MeetingsStore.markConsentTextCopied` stores the time (MEET-1.6, migration `v2-consent`, column `consent_text_copied_at`).
- The per-meeting window (`MeetingWindowController`, opened from the library with ⌘O) shows no reminder. After the fact its header has one line, "Message copied at 10:02" (`MeetingWindowView.consentLine`), only when the sentence was copied.
- No window is opened when a recording starts. The meeting's place while it records is the recording panel of the main window (notes explorer spec `2026-11-24-notes-explorer-main-window`, merged with #255: component `RecordingPanel`, step 4.3, flow step 1: "the consent reminder 'Remember to tell people you are recording.' (while `plugins.meetings.consentReminder` is on)"). That panel is not built yet (`Sources/NotesPlugin/UI/Recording/` does not exist on `main` 2026-11-26).

What this spec does:

- **Pill (Phase 4):** removes the "Copy message" button and `Action.copyConsentText` (Q2) and the consent line for every start (OD-6, Q4 (b)): `Notice.consent`, `Recording.showsConsent`, the 8 s `consentDuration` timer and the `recording-consent` QA state go.
- **Window (Q4 (b), decided):** when a recording starts with ⌃⌥M, from the menu bar or from a suggestion while the main window is closed and `plugins.meetings.consentReminder` is on, the main window opens on the recording panel. With the setting off it does not open. The reminder's place, text and look are the notes-explorer spec's `RecordingPanel` (main window, not designed here): one line, no button (Q2), shown from the start of the recording while the setting is on. The setting keeps its key and type; it now switches the panel's reminder and this opening.
- **How a start is known:** the notes-explorer spec's `MeetingsLiveRecorder` (#255 step 2.3, not on `main` yet) calls the same path as `meetings.record` (its component table: "`start`/`stop` call the same paths as `meetings.record`"), so `MeetingController` cannot tell the panel's Record button from ⌃⌥M today. Phase 4 (or #255 step 2.3, whichever lands first) adds an internal start source in `MeetingsPlugin` (the command and the menu, a suggestion, the live recorder; no contract), and the window is opened only for a start that did not come from the main window's Record button.
- **How the window opens:** through the existing route if it can be done without a new `LintelKit` contract: `PluginContext.openNote` with the live meeting's `NoteKey`, which `MainWindowRouter.open` routes to the Notes section, provided #255 step 4.3 makes the note of a recording meeting show the recording panel. If the panel needs a route of its own, that is a new `PluginContext` value (a protected contract) and a question for the owner before Phase 4, not a decision of this spec.
- **Focus (risk R8):** the main window is an activating window; every other Lintel panel during a call is non-activating on purpose. Opening it over the call app may take the focus while the user is talking or presenting. Phase 4 investigates opening it without taking the focus (for example `orderFront` without activating the app, or opening it only after 8 s or at the first mouse move) and, if none works, reports to the owner. That is a question about how, not a change of the decision.
- **Order (Q1 (a), decided):** the meeting pill (Phase 4) lands together with the recording panel (#255 step 4.3): it merges only when the panel is on `main`, so no build is without a reminder while the setting is on. Until then today's meeting HUD stays, consent line and "Copy message" included. The dictation pill (Phase 2) and the suggestion pill (Phase 3) do not wait.

#### Retiring Copy message (Q2 (b), decided)

MEET-1.6 is retired: no surface copies the consent sentence, the recording panel included. Phase 4 cleans up the code path; **the schema does not change** (`BACKWARD_COMPATIBILITY.md`: migrations are additive only).

| Part | Today | After Phase 4 |
|---|---|---|
| `MeetingHUDState.Action.copyConsentText`, the "Copy message" button and its string | the consent line's button | removed |
| `MeetingConsentText` (`Sources/MeetingsPlugin/Recording/MeetingConsentText.swift`, the sentence to paste for the participants) and its strings | copied by the button | removed with its last use (the panel's reminder is its own, shorter text from the notes-explorer spec) |
| `MeetingsStore.markConsentTextCopied` and the controller code that calls it | writes `consent_text_copied_at` on the first copy | removed |
| Migration `v2-consent`, column `meeting.consent_text_copied_at` | written by the copy | **stay** (a registered migration is never removed); the column is no longer written; old rows keep their values |
| `MeetingDocument.consentTextCopiedAt` and `MeetingWindowView.consentLine` ("Message copied at 10:02" in the per-meeting window header) | read for meetings where the sentence was copied | removed: a line about a feature that no longer exists would only show on old meetings. The column stays unread |
| Tests (`ConsentCopyTests`, the copy cases in `ControllerTests`, `HUDStateTests`, `StoreTests`) | cover MEET-1.6 | removed or changed with the code; the `v2-consent` migration test stays |

### After the recording: what the app says (OD-7)

What the code does today when the speech model is loading or unavailable during a meeting:

- **Loading** (`MeetingSession` yields `.loadingModel`, then `.modelLoaded`): the audio goes on into the encrypted spool; segments that could not be transcribed live are replayed after "End" while the state is `processing` (`MeetingSession.replayDeferred`). The meeting ends `ready` as usual. **Nothing needs saying**: the only visible effect is a longer `processing` (the closing ring, "Transcribing, N left" on hover, OD-9).
- **Busy or failed during the meeting** (`.modelUnavailable(busy:)`, `SpeechEngineLease` busy or a load error): the same, the replay tries the model once more after "End". If it is free then, the meeting ends `ready`: nothing needs saying.
- **Still unavailable after "End"** (`replayDeferred` cannot take the lease, `replayUnavailable`): the meeting ends `incomplete` with the whole spool kept. Today the pill shows `savedIncomplete` ("Saved, incomplete" · **Open**, 6 s, stays in this spec), the library row the badge "Incomplete" and the "Needs Attention" filter, and the meeting window the banner **"Recording was interrupted. The transcript may be missing its end."** with **Finish** (`MeetingWindowModel.Banner.incomplete(canFinish: true)`, `MeetingWindowView` line 405), which transcribes the spool (`MeetingsLibrary.finish`). Notes wait for a transcript (`NotesService` queues a meeting only when it becomes `ready`).

Verdict: the existing states **do not suffice for the third case**. The capability is there (audio kept, Finish makes the transcript, notes follow), but the text is wrong: the recording was not interrupted, and nothing says the transcript and notes can still be made. The reason is not stored (no column says why a meeting is `incomplete`), so the window cannot choose a text today. This needs:

1. A stored or derivable reason "speech model unavailable" for an `incomplete` meeting (Meetings data; additive, if a column: a migration in `MeetingsStore`).
2. A text for the meeting window and for the main window's meeting row and preview (domain of the main window, notes-explorer spec; not designed here). Proposal for the owner to accept or reword, not a look: en "The speech model wasn't free, so there's no transcript yet. The recording is kept: Finish makes the transcript and notes." / pl "Model mowy był zajęty, więc nie ma jeszcze transkrypcji. Nagranie jest zachowane: Dokończ zrobi transkrypcję i notatki."

Filed as issue #346 (related: #338, a meeting whose stored model was removed). It is not part of this spec's phases. The meeting pill's OD-7 step waits for it (Q5 (a), decided; the interim line until then is in the meeting table); Phase 4 checks it in QA.

### Meeting: start and end messages

| Today | After |
|---|---|
| `problem(.microphoneDenied(offersSystemOnly: true))` | `prompt`: mic "No microphone access" · **Record others only** · hover: "Allow" · ✕ (20 s, as today) |
| `problem(.microphoneDenied(false))` | mic "No microphone access" · **Allow** |
| `problem(.modelMissing / .modelUnavailable)` | red "No speech model" / "Speech model isn't working" · **Download** / **Fix** |
| `problem(.libraryUnavailable)` | red "Meetings can't be saved now" · **Fix** |
| `problem(.lowDiskAtStart)` | red "Not enough disk space" |
| `problem(.stillProcessing)` | ⚠ "Previous meeting still saving" |
| `problem(.modelBeingRemoved)` | ⚠ "Model is being removed, try soon" |
| `problem(.noAudioInput)` | mic "No audio could be recorded" |
| `problem(.nothingHeard)` | ⚠ "Nothing heard" |
| `problem(.couldNotStart)` | red "Recording didn't start" |
| `problem(.failed)` | red "The meeting couldn't be saved" |
| `allowMicrophone` | mic "Allow the microphone in the dialog" (no ✕: the system prompt decides). This **removes** today's Cancel (`.dismiss` → `MeetingController.cancelPreparation`); ⌃⌥M and the menu bar still cancel the preparation, and the system prompt's own buttons end it |

### Meeting suggestions (top centre, hidden from screen sharing)

| Today | After |
|---|---|
| `.meeting`: "Looks like a meeting in Google Chrome" + Record / Not now / Don't ask for this app | person glyph · "Meeting in Google Chrome" · **Record** (primary) · hover: "Don't ask again" · ✕ = Not now (OD-10) |
| `.endRecording`: "End the recording?" + End recording / Keep recording | ring with dot · "End the recording?" · **End** (primary) · ✕ = Keep recording |

Lifetime (15 s), no key claims and the click-only start stay as today.

### Copy (en / pl)

Every visible string, with its budget. Existing keys whose text changes get new keys (the old keys are removed with their last use, `StringCatalogTests` keeps both languages complete). Removed with no replacement in the pill: "Copy message" and the consent sentence `MeetingConsentText` (Q2), the long consent line (OD-6, Q4 (b)), "Loading the speech model – recording continues" and "… the text comes after the meeting" (OD-7; until #346 the interim line below, Q5 (a)). Every key below carries the comment prefix `HUD pill:` so the budget test (`PillCopyBudgetTests`, Phase 1) finds it. A text only VoiceOver hears (the hover link's "Don't ask again for %@" / „Nie pytaj więcej dla %@”, a full device name, the pill's label) carries the prefix `HUD pill, VoiceOver:` instead and is outside the budget. The Polish texts follow the owner's quotes in OD-9 („Transkrybuję, zostały 3”) and OD-10 („Nagraj”).

| Key (en) | pl |
|---|---|
| Allow the microphone in the dialog | Zezwól na mikrofon w oknie systemu |
| Using %@ *(device name, shortened in the middle)* | Mikrofon: %@ |
| Using the default mic | Domyślny mikrofon |
| Pasted without cleanup | Wklejono bez poprawek |
| Copied, paste with ⌘V | Skopiowano, wklej ⌘V |
| No speech model | Brak modelu mowy |
| Speech model isn't working | Model mowy nie działa |
| Dictation is back after the meeting | Dyktowanie wróci po spotkaniu |
| No microphone access | Brak dostępu do mikrofonu |
| No microphone found | Nie znaleziono mikrofonu |
| Nothing heard | Nic nie usłyszano |
| Nothing to paste yet | Nie ma jeszcze nic do wklejenia |
| Ends in %@ | Koniec za %@ |
| Can't hear the others | Nie słychać rozmówców |
| Can't hear your microphone | Nie słychać Twojego mikrofonu |
| Microphone disconnected | Mikrofon odłączony |
| Your mic isn't recording | Mikrofon nie nagrywa |
| Reconnecting the mic… | Łączenie z mikrofonem… |
| Others' audio stopped | Dźwięk rozmówców przerwany |
| Low disk, ends soon | Mało miejsca, zaraz koniec |
| Saving problem, fix it later | Błąd zapisu, dokończysz później |
| Transcribing, %lld left | Transkrybuję, zostały %lld *(plural variants: został 1 / zostały 2–4 / zostało 5+)* |
| Recognising speakers | Rozpoznawanie mówców |
| Saving the meeting | Zapisywanie spotkania |
| Saved / Saved, incomplete | Zapisano / Zapisano, niepełne |
| Meetings can't be saved now | Spotkań nie da się teraz zapisać |
| Not enough disk space | Za mało miejsca na dysku |
| Previous meeting still saving | Poprzednie spotkanie wciąż się zapisuje |
| Model is being removed, try soon | Usuwanie modelu, spróbuj za chwilę |
| No audio could be recorded | Nie da się nagrać dźwięku |
| Recording didn't start | Nagrywanie się nie zaczęło |
| The meeting couldn't be saved | Nie udało się zapisać spotkania |
| Meeting in %@ | Spotkanie w %@ |
| End the recording? | Zakończyć nagrywanie? |
| Don't ask again | Nie pytaj więcej |
| You / Others | Ty / Rozmówcy |
| *Interim until #346 (Q5 (a)):* Text comes after the meeting | Tekst będzie po spotkaniu |
| Buttons: Allow, Download, Fix, Try again, Open, End, Record, Record others only | Zezwól, Pobierz, Napraw, Spróbuj ponownie, Otwórz, Zakończ, Nagraj, Nagraj tylko rozmówców |

The suggestion's "Record" button gets a new key with „Nagraj” (OD-10); today's `Record` key („Nagrywaj”, comment "Meeting suggestion HUD button that starts a recording") is used only by the suggestion and is removed in Phase 3. Every row is within 40 characters in both languages (longest: „Poprzednie spotkanie wciąż się zapisuje”, 39; „Transkrybuję, zostały %lld” is 25 with a three-digit number).

"Meeting in %@" takes the app's display name; a name that would break the budget is shortened by the pill (tail truncation) and the full name is in the VoiceOver label. The hover link "Don't ask again" has the VoiceOver label "Don't ask again for %@" („Nie pytaj więcej dla %@”, comment prefix `HUD pill, VoiceOver:`, outside the 40-character budget).

### Accessibility

- **VoiceOver:** each pill is one element whose label carries everything, including hover-only content: "Dictation, recording, 0:12. Esc cancels." / "Recording a meeting, 12:34. Can't hear the others." / "Meeting in Google Chrome". Its buttons (also the hover-only ones) are exposed as named accessibility actions, so nothing depends on the pointer. Announcements stay as today (start, stop, done, each new problem once; no ticks), with the new texts.
- **Contrast:** text is primary label colour on glass (no coloured text except the amber countdown, which uses the text-grade `statusAttention` and is checked at 4.5:1 on the light and dark glass in the gallery). Increase Contrast adds the 1 pt border used today.
- **Reduce Motion:** the ring does not turn, the dot does not breathe, the wave bars stay flat at the current level (as today), expand and collapse are instant, the working ring is the static part ring with its track that `LintelRingAppearance` draws for `.processing` under `LintelRingMotion.reduced` (no spinner, nothing moves).
- **Large text:** height and font follow the app text size (OD-13, all four sizes); at XL every Polish string fits in 450 pt (checked in the sketch; L, between M and XL, is checked by the gallery snapshots).
- **Pointer-free use:** Esc cancels dictation, the menu bar and the meeting shortcut end a meeting, as today.

## 📝 Architecture

- **`LintelPill`** (Phase 1, `Sources/LintelUI/Components/LintelPill.swift`): a SwiftUI view over a pure `PillContent` value (`PillContent.swift`), as built:
  - `glyph: PillGlyph` = `.live(dot:)`, `.working(dot:)`, `.attention`, `.error`, `.microphone`, `.done`, `.person`; the two ring glyphs are the existing `LintelRing` (#333), not a second ring.
  - `badge: Bool`: the amber dot; only a live ring carries it (`LintelRingState.warning`), any other glyph ignores it.
  - `live: [PillLive]` (`.wave(level:)`, `.clock(String, amber: Bool)`): an array rather than one value, because the dictation countdown is the wave plus the amber seconds.
  - `lineGlyph: PillGlyph?`: the small glyph of a line that stands beside the live ring (the meeting pill's ⚠, the microphone, the working ring of "Reconnecting the mic…").
  - `text: String?`, `truncation: PillTruncation` (`.tail` / `.middle`), `action: PillAction?`.
  - Hover content: `hoverText`, `hoverLevels: [PillLevel]` (the You / Others meters, OD-5), `hoverActions: [PillAction]`.
  - `stop: PillAction?` (the meeting's stop button, always last) and `close: PillClose?` (`visibility` `.always` / `.onHover`, so OD-2's hover-only ✕ and the "Esc not claimed" ✕ are one field; this replaces the earlier `closes: Bool`).
  - `accessibilityLabel`; derived: `variant` (`live`, `working`, `message`, `prompt`) and `accessibilityActions` (every button, hover-only ones included, so the pill is one element and nothing depends on the pointer).
  - `PillAction` has an `id` (the consumer's name, passed back on a press), a `title`, an `accessibilityName` and a `Style` (`.button` neutral fill, `.primary` live colour, `.link`, `.stop`). `PillMetrics` holds the sizes (28 / 32 / 35 / 38 pt, 12–15 pt text, the 16 / 16 / 17.6 / 19 pt glyph, 380 / 420 / 450 pt plus 120 pt while hovered, the 580 × 56 pt panel); `PillMotion` reads Reduce Motion from the ring's `lintelRingMotion` knob or the system; `lintelIncreasedContrast` lets the gallery draw the bordered look.
  - Consumers beyond the HUDs: the notes explorer's `UndoToast` (`message`, no ✕, one button, `.middle` truncation; its keys carry `HUD pill:` and join the budget test), so the API and the test scope keep that case working (gallery state `message-undo`).
- **Hover** (Phase 1, `PillHover.swift`): `PillHoverModel` (`@Observable`: expands 300 ms after the pointer enters the pill, collapses 500 ms after it leaves, keyboard focus on a button expands at once; the time is injected), `PillHoverRoot` (the pill centred in the fixed transparent 580 × 56 pt frame, 0.2 s spring, instant under Reduce Motion, reports the pill's frame) and `PillHoverHost` (`NSHostingView` subclass with an `NSTrackingArea` `[.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect]`; the pointer counts as on the pill only inside the pill's frame, never in the transparent rest of the panel). The panels are non-activating and Lintel is usually not the active app, so SwiftUI `.onHover` alone is not relied on; the Phase 1 spike result is under "Phase 1 result".
- **`LintelUI` depends on no plugin**; the plugins map their state to `PillContent`: `HUDState.pill` in `DictationPlugin`, `MeetingHUDState.pill` and `SuggestionPrompt.pill` in `MeetingsPlugin`. The state enums keep their cases (QA names, tests and controllers unchanged) except the consent ones, which go (`Notice.consent`, `Recording.showsConsent`, `Action.copyConsentText`; OD-6, Q2, Q4 (b)); only texts, actions and the view change. No `LintelKit` contract change (unless the window route of Q4 (b) needs one: then it is a question for the owner, see "Consent reminder (OD-6)"), no settings keys apart from the DEBUG QA keys `plugins.dictation.qaHUDHover` and `plugins.meetings.qaHUDHover` (Phases 2 and 3, not a contract), no data.
- **Panels:** the three `NSPanel`s keep their level, collection behaviour, sharing type and placement code; their content size becomes the fixed 580 × 56 pt transparent frame.
- **Behaviour changes** (everything else keeps today's actions):
  - New "Open" on `saved` / `savedIncomplete`: `MeetingHUDState.Action.openMeeting`, handled by the controller through the existing `MeetingWindowController` (opens the meeting that was just saved).
  - New "Allow" on dictation `copied(.noAccessibility)` (today no button): opens the Accessibility privacy pane, the same route as Settings → Permissions.
  - New "Fix" on the meeting notice `.systemAudioLost` (today only Stop): the existing `openSettings` action (system audio privacy pane).
  - Removed: the Cancel (✕) on the meeting `allowMicrophone` state (today `.dismiss` → `cancelPreparation`); ⌃⌥M and the menu bar still cancel.
  - Removed: "Copy message" / `Action.copyConsentText` (Q2).
  - New: the main window opens on the recording panel at a start outside it while `consentReminder` is on (Q4 (b)), through the internal start source and the existing route of "Consent reminder (OD-6)".
- **Timers:** the 10 s collapse of a lasting notice (OD-8) and the 3 / 4 s fallback line (OD-11) are owned by the HUD model (view-side), not by the controllers. The 8 s consent timer in `MeetingController` (`consentDuration`, `showsConsent`) is removed (Q4 (b)). The interim Q5 line's 10 s is the same HUD-model timer as OD-8's.
- **Removed from the HUD path:** `Action.copyConsentText` and the MEET-1.6 code listed in "Retiring Copy message (Q2)", and `Notice.consent`, `Recording.showsConsent` and the `recording-consent` QA state (Q4 (b)). `Notice.loadingModel` and `.modelUnavailable` stay as states (QA names `recording-loading-model`, `recording-model-unavailable`, tests) and map to the plain recording pill (OD-7), with the interim line until #346 (Q5 (a)).

## 📝 Edge Cases & Failure Scenarios

| Case | Behaviour |
|---|---|
| Two problems at once | The notice order of `Recording.notice` stays (low disk first); the pill shows one line; VoiceOver label lists the shown one. |
| Problem appears while hovered | The pill shows the problem line (hover content yields to the problem). |
| Pointer is on the pill during dictation | Hover expands it; it never takes focus, so typing continues into the app. |
| Pill under the pointer when it appears | No expansion until the pointer moves (avoids flashing details). |
| Very long app name in the suggestion | Tail truncation in the line; full name in VoiceOver. |
| Screen sharing | The meeting pill (with OD-1 colour) is what participants see; the suggestion pill never shows. |
| Reduce Motion toggled during a recording | Applied on the next state update (as today). |
| Consent reminder on, main window closed | Q4 (b): a recording started with ⌃⌥M, the menu bar or a suggestion opens the main window on the recording panel, which shows the reminder; the pill stays plain. With the setting off nothing opens. A start from the main window's Record button opens nothing new. |
| The main window opens during a call | Risk R8: it must not take the focus from the call app; Phase 4 checks how (see "Consent reminder (OD-6)"). |
| Speech model still busy after "End" | `savedIncomplete` in the pill ("Saved, incomplete · Open", 6 s); the explanation and Finish are in the app (issue #346). |
| Model loading for the whole meeting | Plain pill throughout; after "End" a longer closing ring while the spool is transcribed. |

## 📝 Risks & Impact Review

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Details hidden behind hover are missed (meters were the only visible sign that the other side is heard). With OD-6 and OD-7 the pill also says nothing about consent or the speech model, so every line it shows is a problem the user can act on | Medium | Problems still surface as lines; the measurement below compares first-minute detection. Model trouble is told after the recording in the app (issue #346). |
| R2 | The larger transparent panel blocks clicks in the area around the pill | Medium | Verified in the Phase 1 spike ("Phase 1 result"); the fallback, if it ever fails, is a panel that resizes with the pill (top/bottom edge fixed, as the meeting HUD does today). |
| R3 | Hover tracking in a non-activating panel of a background app | Medium | `NSTrackingArea` with `.activeAlways`, verified in the Phase 1 spike ("Phase 1 result"). |
| R4 | A Verdigris ring is not read as "recording" by call participants | Medium | OD-1; red dot is the fallback. |
| R5 | Polish strings over budget at XL | Low | Budget test over the catalog; the sketch's XL check. |
| R6 | With OD-6 read literally, the consent reminder is seen only when the main window is open during a recording; a meeting started with ⌃⌥M, the menu bar or a suggestion (the usual way) would show no reminder at all | Medium (legal comfort of the user) | **Decided (Q4 (b)):** such a start opens the main window on the recording panel while the setting is on. Phase 4 lands with the recording panel (Q1 (a)). |
| R7 | Until issue #346 is done, a meeting the model could not transcribe says "Recording was interrupted", which is wrong, and the pill no longer hints "text after the meeting" | Low | **Decided (Q5 (a)):** the OD-7 step waits for #346, with the interim pill line until then. Finish already works. |
| R8 | Q4 (b) opens an activating window over the call app at the start of a recording; it may take the focus while the user talks or presents (every other Lintel panel during a call is non-activating on purpose) | Medium | Phase 4 investigates opening it without taking the focus (`orderFront` without activating the app, or opening only after 8 s or at the first mouse move); if none works, the owner is asked how to proceed (a question about how, not a change of Q4). |

No protected contract, settings key, database or migration changes in this spec's phases (`BACKWARD_COMPATIBILITY.md`), unless the window route of Q4 (b) cannot use `PluginContext.openNote`: a new `PluginContext` value would then be a question for the owner before Phase 4. String keys change, which is not a protected surface. `plugins.meetings.consentReminder` keeps its key and type; it switches the recording panel's reminder and whether the main window opens on it at a start outside it (Q4 (b)). The column `consent_text_copied_at` stays in the schema, unwritten and unread (Q2). Issue #346 may add a migration; that is its own PR.

## 🧪 Validation

- **Riskiest belief:** users notice a problem (no system audio, mic not recording) as fast without the always-visible meters.
- **Smallest test:** the owner records three meetings with the Phase 4 build with one failure each (mute the call, unplug the mic, deny system audio) and says when they noticed. Pass: noticed within the notice's own delay (10–20 s) every time. Fail: OD-5 alternative (a combined wave stays visible).
- **Guardrail:** no new silent-recording reports (the Granola complaint).
- **QA without a real microphone or sound:** every phase is checked with the `--qa-hud` fixtures and the gallery, never with a real microphone, system audio or the speakers (owner rule 2026-11-26: no sound on the Mac's speakers). The owner's three validation recordings above are the only real-audio step and are the owner's.

## 📋 Phasing

Four `feat/` PRs. Phase 1 first; Phases 2 and 3 after it, in any order, without waiting for anything else; Phase 4 last and gated. Each one:

- has an **owner sheet**: a gallery or QA picture of every new look of that phase (light and dark, en and pl, S, M, L and XL, Reduce Motion, Increase Contrast, hover), posted on the PR for the owner's approval before `qa-approved` (new looks go to the owner's QA track);
- has **QA with screenshots of the running debug build** (`docs/qa.md`, `--qa-hud …`, `--qa-snapshot`, light and dark), with no real microphone, system audio or sound;
- passes the validation gate (`swift build`, `swift test`, `swift format lint --strict -r Sources Tests`).

1. **Phase 1 — `LintelPill` in the gallery.** The component over `LintelRing` (#333, on `main`; reused, not redrawn), gallery scene `ui.pill` (the brief called it `lintel.pill`; `LintelUI` scenes use the `ui.` prefix, like `ui.ring`), and the R2/R3 spike in the non-activating panel. The gallery mechanism of #248 is on `main` (`Sources/LintelUI/Gallery/`), so no fallback is needed. No HUD changes yet.
2. **Phase 2 — dictation pill.** `HUDState.pill`, the dictation panel on `LintelPill`. Not gated (Q1 (a) and Q3 (a) decided).
3. **Phase 3 — suggestion pill.** `SuggestionPrompt.pill`, the suggestion panel on `LintelPill` (OD-10). Not gated: the suggestion pill has nothing to do with the consent reminder or the recording panel (Q1 (a)).
4. **Phase 4 — meeting pill. Lands together with the recording panel (#255 step 4.3, Q1 (a)); its OD-7 step waits for #346 (Q5 (a)).** `MeetingHUDState.pill`, the #258 states (merged 2026-11-25, on `main`: `microphoneFallback`, `retryingMicrophone`, `microphoneNotRecorded`, `retryMicrophone`), the consent change of Q4 (b) (no line in the pill; the main window opens on the recording panel), the MEET-1.6 clean-up (Q2), `Action.openMeeting`, and the OD-7 mapping (its own step). The PR may be built and reviewed before the gates clear; it merges only when the recording panel is on `main`.

## 📋 Implementation Plan

### Phase 1 — Pill component

1. `LintelPill` + `PillContent` in `Sources/LintelUI/Components/`, with `LintelRing` as the glyph for live, warning and working (no second ring), sizes from `lintelTextSize` (28 / 32 / 35 / 38 pt at S / M / L / XL, the L and XL factors of `LintelRingMetrics.points`), colours from `LintelBrand`, `truncation` `.tail` / `.middle`.
2. `PillHoverHost` with the tracking area and the 300 / 500 ms delays; spike for R2 (click-through of the transparent 580 × 56 pt panel) and R3 (hover in a non-activating panel of a background app) recorded in the PR, with the fallback of R2 if click-through fails.
3. Gallery scene `ui.pill` with every variant (live wave, live clock, working, message, message without ✕ and with middle truncation as the `UndoToast` uses it, prompt, amber dot) in the full matrix; it is the owner sheet of the phase.
4. Tests: `PillContent` accessibility labels and actions, the 40-character copy budget test over `Localizable.xcstrings` (every key whose comment starts with `HUD pill:`, the notes explorer's `UndoToast` keys included; a `%@` placeholder counted as 20 characters and a number as 3; accessibility-only texts carry `HUD pill, VoiceOver:` and are outside the budget), ring use under Reduce Motion (through `LintelRingMotion.reduced`), gallery goldens.

#### Phase 1 result (2026-11-26)

Built as described in Architecture. The R2/R3 spike ran on the debug build (`--qa-pill-spike`, `docs/qa.md`) with a real non-activating 580 × 56 pt panel built like the HUD panels (borderless, `.nonactivatingPanel`, status-bar level, clear, shadow, `ignoresMouseEvents` left unset), the meeting suggestion pill in it, a window of **another process** under the panel as the frontmost app, and real mouse events posted through Quartz (no microphone, no sound), once in light and once in dark:

- **R2, click-through: passes.** Three clicks on transparent pixels of the panel (left of the pill, 6 pt above it, 6 pt below it) all reached the window below (3 of 3, both runs). A click on the pill body reached nobody below; a click on the pill's ✕ ran its action on the first click. The fallback (a panel that resizes with the pill) is not needed.
- **R3, hover in a background app: passes.** With the other app frontmost the whole time, the tracking area saw the pointer enter and leave; the pill expanded 312–333 ms after the pointer entered it (`pointerEntered`; light 318 / 312 / 320, dark 319 / 326 / 333; target 300 ms) and collapsed 501–552 ms after it left (light 513 / 533 / 501, dark 538 / 522 / 552; target 500 ms), including when the pointer left to the transparent part of the panel. Lintel never became the active app (no `didBecomeActive`), also not on the ✕ click. The 300 ms is counted from the pointer entering the pill, not from a rest: the earlier design text said "rests 300 ms"; the owner is asked to approve the as-built reading (PR #366).

### Phase 2 — Dictation

1. `HUDState.pill` mapping per the dictation table (final, Q3 (a)); new strings en + pl; remove the old ones (including "Loading model…", OD-7). `InputFallback.pillLine` in `LintelSpeech` ("Microphone line (OD-11)"); `InputFallback.message` stays for the meeting HUD until Phase 4.
2. `DictationHUDView` renders `LintelPill`; panel frame 580 × 56, placed so the pill keeps today's position; the #258 fallback bubble becomes the 3 s line (OD-11); "Allow" on `copied(.noAccessibility)`.
3. QA fixtures (`DictationHUDQA`, listed in `docs/qa.md`): the existing `recording-microphone-fallback`, plus new `recording-escape-unclaimed` (`escapeCancels = false`), `recording-microphone-fallback-unnamed` (`usingName == nil`), `recording-microphone-fallback-collapsed` (after the 3 s line: amber dot) and a DEBUG setting `plugins.dictation.qaHUDHover` that draws the pill in its hover state. A collapsed or hovered fixture sets the HUD model's state directly; it does not wait for a timer.
4. Tests: mapping per state (`DictationHUDQATests`), announcements unchanged except texts, hover-only actions exposed as accessibility actions, `recording(loadingModel)` maps to the same pill as `recording`, the fallback line's 3 s timer with `TestClock`.
5. Owner sheet: a gallery scene of the dictation states (or the `--qa-hud dictation:*` snapshots).
6. QA: every `--qa-hud dictation:*` state, light and dark, en and pl, S and XL, Reduce Motion; hover on the running app. No microphone is opened.

### Phase 3 — Suggestions

1. `SuggestionPrompt.pill` per "Meeting suggestions" (OD-10): "Record" (new key, „Nagraj”), hover "Don't ask again", ✕ = Not now; the end question with "End" and ✕ = Keep recording.
2. `SuggestionHUDView` renders `LintelPill`; panel 580 × 56; `sharingType = .none`, 15 s lifetime, no key claims, unchanged.
3. QA fixtures: the existing `suggestion-meeting` and `suggestion-end-recording`, plus a long app name (tail truncation) and the hover state (`plugins.meetings.qaHUDHover`, DEBUG); `docs/qa.md` updated.
4. Tests: suggestion actions unchanged (`Not now` on ✕, `muteApp` on the hover link), VoiceOver label with the full app name.
5. Owner sheet and QA as in Phase 2, `--qa-hud meeting:suggestion-*`.

### Phase 4 — Meeting pill (gated: recording panel on `main`; step 3 on #346)

1. `MeetingHUDState.pill`; the 10 s collapse and the fallback 4 s line in the HUD model; `Action.openMeeting`; "Fix" on `.systemAudioLost`; no ✕ on `allowMicrophone`; `processing(.closing)` / `finishing` hover "Saving the meeting"; `recording-microphone-only` hover with "You" only.
2. Q2: remove `Action.copyConsentText` and the MEET-1.6 code per "Retiring Copy message (Q2)"; the `v2-consent` migration and the column stay. Q4 (b): remove `Notice.consent`, `Recording.showsConsent`, the `consentDuration` timer and the `recording-consent` QA state; add the internal start source (unless #255 step 2.3 already did) and open the main window on the recording panel at a start outside it while `consentReminder` is on, through the existing route (`PluginContext.openNote` with the live meeting's key, `MainWindowRouter`) if #255 step 4.3 makes it land on the panel, else ask the owner about a new contract; check that it opens without taking the focus from the call app (R8), else report to the owner; update `docs/qa.md`.
3. OD-7 (gated on #346, Q5 (a)): `.loadingModel` and `.modelUnavailable` map to the plain recording pill with unchanged hover; remove their strings. Until #346 is on `main`, the interim line "Text comes after the meeting" (10 s, then the plain pill without the amber dot; hover and VoiceOver keep it while the notice lasts).
4. `MeetingHUDView` renders `LintelPill`; panel 580 × 56; screen-sharing behaviour unchanged. `InputFallback.message` is removed with this last use.
5. QA fixtures (`MeetingHUDQA`, listed in `docs/qa.md`): the existing #258 fixtures `recording-microphone-fallback` and `recording-microphone-retrying` stay; new `recording-microphone-fallback-unnamed`, `recording-microphone-fallback-collapsed` and `recording-no-system-audio-collapsed` (OD-8, amber dot), `recording-countdown` together with a collapsed problem, and the hover setting `plugins.meetings.qaHUDHover`.
6. Tests: mapping per state, collapse timer with `TestClock` (and that `limitCountdown` never collapses, `.microphoneFallback` collapses after 4 s, the interim Q5 line collapses without the dot), `openMeeting` routes to the window, no pill string mentions the speech model while recording (after #346), no pill path copies the consent sentence, a start outside the main window with `consentReminder` on asks to open it and with the setting off does not, a start from the panel's Record button does not.
7. Owner sheet: a gallery scene of the meeting states.
8. QA: every `--qa-hud meeting:*` state including the #258 states; `recording-loading-model` and `recording-model-unavailable` show the plain pill on hover too (or, before #346, the interim line); `saved-incomplete` shows "Saved, incomplete · Open" and Open opens the meeting; the main window's recording panel shows the consent reminder with no copy button while the setting is on, a ⌃⌥M start with the main window closed opens it on the panel (and the call app keeps the focus), and the pill has no consent line; once issue #346 is done, the app shows the model text for a fixture meeting the model could not transcribe (no recording). The owner's validation recordings above are separate.

## 📝 Not doing

- Moving or resizing pills by drag (Wispr's first change after feedback; later, if asked for).
- A menu-bar-only mode without a pill.
- New detection or new problems: the pill only shows what the controllers already report. When #266 (dictation: microphone lost during a recording) is decided, its state uses the `message` variant with the microphone glyph and "Microphone disconnected" ("Mikrofon odłączony"), the same line as the meeting pill.
- Window management HUDs (`WindowsPlugin`), which are an add-on and off by default.
