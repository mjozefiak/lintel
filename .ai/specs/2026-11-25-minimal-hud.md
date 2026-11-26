# Minimal HUD pills: dictation, meeting recording, meeting suggestions

> Status: **design, decided by the owner 2026-11-26 (OD-1 to OD-13).** Nothing here is implemented. OD-6 and OD-7 took the alternative (consent reminder only in the meeting's window; nothing about the speech model in the pill, the app says it after the recording); the other eleven took the recommendation.
> Owner direction (2026-11-25): "te pastylki u konkurencji zawsze są mega minimalistyczne i też chcę, aby tak było w Lintel; obecnie jest tam za dużo zbędnych informacji, ograniczamy się do totalnego minimum."
> Sketch (before and after for every state, light and dark, en and pl, S/M/XL, Reduce Motion, Increase Contrast, hover): `.ai/specs/assets/minimal-hud/index.html`. It is a sketch for the decision only: after acceptance the SwiftUI gallery (#248) is the source of truth.
> Related: #233 (the meeting clock wraps when a notice adds a second button; this design removes that layout), #236 (its fix), #258 (new microphone states, merged 2026-11-25, mapped below), #266 (a dictation state for a lost microphone, not designed here), #333 (`LintelRing`, merged 2026-11-26, reused by the pill), #346 (OD-7: the app's text after a meeting the speech model could not transcribe).
> Inputs: the current HUD code (`Sources/DictationPlugin/HUDState.swift`, `DictationHUD.swift`, `Sources/MeetingsPlugin/UI/MeetingHUDState.swift`, `MeetingHUD.swift`, `Sources/MeetingsPlugin/Suggestions/SuggestionHUD.swift`, `SuggestionPrompt.swift`), the `--qa-hud` states in `docs/qa.md`, the new states of PR #258, the UX direction of PR #247 (the working ring, Verdigris only for live state) and the gallery spec of PR #248.

## 📝 TLDR

**Who:** everyone who dictates or records meetings. Office users who never read a HUD on purpose: the pill must be understood at a glance or not noticed at all.
**Today:** three different floating surfaces. Dictation is a 248 × 40 pt capsule with an icon, the word "Recording", level bars, a timer and a ✕. The meeting HUD is a 400 × 44–68 pt rounded rectangle with the time, two named level meters, a red "End recording" button and a second line of notices (up to 63 characters). The suggestion is a 440 × 78 pt card with a sentence and three buttons. PR #258 adds a two-line bubble above the dictation pill and more notices to the meeting HUD.
**Proposed:** **one pill family** (`LintelPill`): a capsule 32 pt high (28 at S, 38 at XL), glass, one line of text at most, at most one text button plus ✕. In the normal state the pill shows only what is live: dictation = the turning ring and the voice wave (88 pt wide); meeting = the ring with its dot, the time and a stop button (about 120 pt). Everything else (timer, ✕, meters, "End", "Don't ask again", processing details) appears **only on hover** and is always in the VoiceOver label. A problem appears **only while it exists**, as one short line with one action. Finished states are a ✓ or one word.

## ✅ Owner decisions (decided 2026-11-26)

| # | Question | Decision | Why it matters |
|---|---|---|---|
| OD-1 | Colour of "live" | **Verdigris ring** for both pills (#247: the ring is the brand signature, Verdigris marks live state) | The meeting pill is visible in screen sharing on purpose; a red dot would be understood by everyone on the call (risk R4). |
| OD-2 | Dictation: timer and ✕ | **Hover only**; Esc still cancels; the ✕ is always visible only when Esc could not be claimed | Wispr's bar shows only the wave. The timer tells an office user nothing while dictating. |
| OD-3 | After pasting | **✓ for 0.6 s**, then gone | Today "Pasted" stays 0.8 s. |
| OD-4 | "Pasted – partly cleaned up" | **Show nothing**; "Pasted without cleanup" (all raw) stays, without the "Raw version: …" hint | A partial fallback is invisible to most users; the hint names a menu path nobody reads in 3 s. |
| OD-5 | Meeting level meters | **Hover only**; problems come as notices (20 s system silence, 10 s microphone silence, lost device) | The notices already detect the failures the meters were for. |
| OD-6 | Consent reminder | **Only in the meeting's window** (the recording panel of the main window, spec `2026-11-24-notes-explorer-main-window`); the pill has no reminder line and no "Copy message" button | It protects the user legally; the owner wants the pill to carry problems only. See "Consent reminder (OD-6)" below. |
| OD-7 | Model loading / model unavailable during recording | **Silent pill**, also on hover (no "Text after the meeting"). The audio is recorded anyway and the transcript and notes can be made later; the app says so **after the recording**, not in the pill | Recording already runs; the user can do nothing about it then. See "After the recording: what the app says (OD-7)" below. |
| OD-8 | A problem that lasts | **Line stays 10 s**, then the pill shrinks back and keeps an amber dot on the ring; hover and VoiceOver give the line again; a new problem expands it again | Long lines over a call window are the clutter the owner named. |
| OD-9 | After "End" (meeting) | **Closing ring only**; "Transcribing, 3 left" on hover; then "Saved · Open" 3 s | Processing can take minutes; the ring says "working" without words. |
| OD-10 | Suggestion pill | **One line + "Record" + ✕ (= Not now)**; "Don't ask again" on hover; end question: "End the recording?" + "End" + ✕ (= keep recording) | The mute choice is rare and stays one hover away. |
| OD-11 | Chosen microphone missing (#258) | **Name of the microphone used, 3 s (dictation) / 4 s (meeting)**, then an amber dot; hover shows it | Quality changes when the built-in mic replaces a headset. |
| OD-12 | Meter names | **"You" / "Others"** ("Ty" / "Rozmówcy") instead of "Me" / "System" | "System" is jargon for office users. |
| OD-13 | Size | **32 pt at M**, follows the app's text size (28 / 32 / 38 at S / M / XL) | XL users get readable pills; today HUDs ignore text size. |

## ❓ Open questions after the decisions (owner)

The decisions leave three smaller questions. Each has a recommendation; none blocks Phase 1 or Phase 2.

| # | Question | Options | Recommendation |
|---|---|---|---|
| Q1 | The recording panel with the consent reminder (#255 step 4.3) may land after Phase 3 is ready. | (a) Phase 3 waits for it; (b) Phase 3 merges first and there is no reminder anywhere until the panel lands; (c) Phase 3 keeps today's consent line until the panel lands | **(a)**: the reminder protects the user and the wait costs only Phase 3's merge date. |
| Q2 | "Copy message" (MEET-1.6) leaves the pill. | (a) the recording panel gets "Copy message" next to the reminder (the existing sentence and store call); (b) MEET-1.6 is retired: no copy button, the window's "Message copied at …" line goes too | **(a)**: one text button in the panel; it keeps the record that the participants were told. To be drawn on the panel's own sheet (main window). |
| Q3 | OD-7 in dictation: dictation keeps no audio, so a model that fails after the key is released cannot be "made later". | (a) the dictation pill stays silent while the model loads (OD-7) but still shows "Speech model isn't working · Fix" when the dictation is lost; (b) also silent then | **(a)**: the text is lost, the user must know at once; nothing in the app could tell them later. |

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
| `message` | glyph + one line + at most one text button + optional ✕ | hugs, max 380 pt (450 at XL) | problems, done states |
| `prompt` | glyph + one line + one primary button + hover link + ✕ | hugs, max 380 pt (450 at XL) | suggestions, "Microphone denied, record others only" |

- Shape: capsule, height 28 / 32 / 38 pt (app text size S / M / XL), glass `.regular`, system shadow. Padding 10 pt leading, 12 pt trailing, 8 pt spacing.
- Text: 12 / 13 / 15 pt medium, **one line, never wraps**. Copy budget: 40 characters in both languages (a test checks every pill string in `Localizable.xcstrings`), and the pixel width limit above (checked by the gallery snapshots at XL).
- Glyphs (16 / 16 / 19 pt): **live** = the cut ring turning slowly; the meeting ring has the breathing centre dot, the dictation ring has none (the same meaning as the note-type ring in #247). **working** = the ring closing. **problem** = amber triangle (`statusAttention`). **failed** = red triangle (`statusError`). **done** = ✓ in the live colour. Microphone problems use `mic.slash` in amber. The ring is the existing `LintelRing` (`Sources/LintelUI/Components/LintelRing.swift`, #333, on `main`): live = `.listening`, the amber dot of OD-8 / OD-11 = `.warning` (a dictation ring gets the dot too), working = `.processing(progress:)`, mark `.meeting` / `.dictation`; sizes already follow `LintelRingMetrics` (16 / 16 / 19 pt). The pill does not draw a ring of its own.
- Buttons: one text button (`act`, neutral fill, the live colour only for a prompt's primary), ✕ 22 pt (hit area 24 pt), the meeting's stop button is a 22 pt circle with a square.
- Positions do not change: dictation bottom centre, 48 pt above the visible frame; meeting and suggestion top centre under the menu bar. A pill is at most 380 pt wide at S and M and 450 pt at XL, plus 120 pt while hovered (hover content must never truncate the main line). Measured in the sketch, every state in en and pl fits without truncation: widest normal pill 376 pt (M, pl) and 415 pt (XL, pl), "Mikrofon nie nagrywa · Spróbuj ponownie"; widest hovered 442 pt (M, pl) and 489 pt (XL, pl), the suggestion pill (re-measured 2026-11-26 in headless Chrome after OD-6 and OD-7 removed the consent and model lines: unchanged, neither was the widest). The panel is a fixed transparent window larger than the widest pill (580 × 56 pt), the pill centred in it, so expanding never moves or resizes the window. The transparent area must stay click-through (risk R2).
- The meeting pill stays visible in screen sharing; the suggestion pill stays hidden from it (`sharingType = .none`), as today.

### Hover

- After the pointer rests on the pill for 300 ms it expands (spring 0.2 s; instant under Reduce Motion) and shows its hover content. It collapses 500 ms after the pointer leaves. Keyboard focus on a button inside the pill counts as hover.
- Hover content never contains something only available there except shortcuts to things that exist elsewhere: cancel (Esc), End (the menu bar and the meeting window), meters (the meeting window), "Don't ask again" (Settings → Meetings). Hover never adds a model or reminder line (OD-6, OD-7).
- The panels stay non-activating and never take focus.

### Dictation states (bottom centre)

| Today (`HUDState`) | After | Stays | Goes |
|---|---|---|---|
| `recording` | `live`: ring + wave. Hover: `0:12` + ✕ | the ring, the wave | "Recording", red dot, timer, ✕ (OD-2) |
| `recording`, Esc not claimed | ring + wave + ✕ always | ✕ | "✕ cancels" |
| `recording(loadingModel)` | same as recording, also on hover | — | "Loading model…", blinking caret (OD-7) |
| `recording(secondsLeft)` | ring + wave + amber `9` | the seconds | "Stops in 9 s" |
| `recording(fallback)` (#258) | ring with amber dot + wave + "Using MacBook Pro mic" for 3 s, then hover only | — | the two-line bubble (OD-11) |
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

OD-7 in dictation covers the model loading while the user speaks (`recording(loadingModel)`). The model problems above come when the key is pressed or after it is released, when there is no dictation or it is lost (dictation keeps no audio, so nothing can be made later), so they stay one line in the pill (open question Q3).

### Meeting recording (top centre)

While a problem line is shown, the clock steps aside (ring · line · action · stop) and comes back when the line goes; the time stays in the VoiceOver label. This keeps every line within the width budget and puts the one thing that matters first. The pill shows no line that is not a problem: the consent reminder is in the meeting's window (OD-6) and the speech model is never mentioned while recording (OD-7).

| Today (`MeetingHUDState`) | After | Goes |
|---|---|---|
| `recording` | `live`: ring with dot + `12:34` + stop. Hover: You ▂ · Others ▂ · **End** | "Recording a meeting" (not visible, it is in the VoiceOver label), two named meters, red "End recording" (OD-1, OD-5, OD-12) |
| notice `.consent` (first 8 s) | nothing: the plain recording pill (OD-6); the reminder is in the meeting's window | the line, "Copy message", the 8 s window |
| notice `.loadingModel`, `.modelUnavailable` | plain recording pill, hover unchanged (OD-7); the app says it after the recording | the notice |
| notice `.limitCountdown` | ring + amber "Ends in 4:59" + stop | separate line |
| notice `.noSystemAudio` | ring · ⚠ "Can't hear the others" · **Fix** · stop | jargon |
| notice `.noMicrophoneAudio` | ring · mic "Can't hear your microphone" · **Fix** · stop | |
| notice `.deviceDisconnected` | ring · mic "Microphone disconnected" · **Try again** · stop | |
| notice `.microphoneNotRecorded` (#258) | ring · mic "Your mic isn't recording" · **Try again** · stop | squeezed meters |
| notice `.retryingMicrophone` (#258) | ring · spinner "Reconnecting the mic…" · stop | |
| notice `.microphoneFallback` (#258) | "Using MacBook Pro mic" 4 s, then amber dot (OD-11) | both device names |
| notice `.systemAudioLost` | ring · ⚠ "Others' audio stopped" · **Fix** · stop | |
| notice `.lowDisk` | ring · ⚠ "Low disk, ends soon" · stop | |
| notice `.writeProblem` | ring · ⚠ "Saving problem, fix it later" · stop | |
| any lasting notice after 10 s | plain pill with an amber dot on the ring (OD-8) | the line |
| `finishing`, `processing(…)` | `working` ring with dot; hover "Transcribing, 3 left" / "Recognising speakers" (OD-9) | "Processing: transcribing (3 left)" |
| `saved` | ✓ "Saved" · **Open**, 3 s | |
| `savedIncomplete` | ⚠ "Saved, incomplete" · **Open**, 6 s | "not complete" |

"Fix" opens the place that fixes it: the system audio and microphone privacy panes (today's `openSettings` / `openMicrophoneSettings` actions). "Try again" is #258's `retryMicrophone`. "Open" is new: it opens the saved meeting in the meeting window (`MeetingWindowController`), see Architecture.

### Consent reminder (OD-6)

What the code has today:

- The reminder is the HUD's second line only: `MeetingController` sets `Recording.showsConsent` from `plugins.meetings.consentReminder` (default on, Settings → Meetings "Remind me to say I am recording") and clears it after `consentDuration` (8 s); `MeetingHUDState.Notice.consent` with the actions `copyConsentText` and `stop`. "Copy message" puts `MeetingConsentText.sentence` on the pasteboard and `MeetingsStore.markConsentTextCopied` stores the time (MEET-1.6, migration `v2-consent`, column `consent_text_copied_at`).
- The per-meeting window (`MeetingWindowController`, opened from the library with ⌘O) shows no reminder. After the fact its header has one line, "Message copied at 10:02" (`MeetingWindowView.consentLine`), only when the sentence was copied.
- No window is opened when a recording starts. The meeting's place while it records is the recording panel of the main window (notes explorer spec `2026-11-24-notes-explorer-main-window`, merged with #255: component `RecordingPanel`, step 4.3, flow step 1: "the consent reminder 'Remember to tell people you are recording.' (while `plugins.meetings.consentReminder` is on)"). That panel is not built yet (`Sources/NotesPlugin/UI/Recording/` does not exist on `main` 2026-11-26).

What this spec does:

- **Pill:** removes the line, the "Copy message" button, `Notice.consent`, `Recording.showsConsent`, `Action.copyConsentText` from the HUD path and the 8 s timer from `MeetingController` (Phase 3).
- **Window:** adds nothing of its own. The reminder's place, text and look are the notes-explorer spec's `RecordingPanel` (main window, not designed here). The setting keeps its key and meaning (it now switches the panel's reminder).
- **Order:** the Phase 3 PR does not merge before the recording panel with the reminder is on `main` (#255 step 4.3), so no build is without a reminder while the setting is on. If the owner wants Phase 3 sooner, see open question Q1.
- **"Copy message" (MEET-1.6):** the notes-explorer spec's panel lists the reminder sentence but not the copy action. Without it nothing writes `consent_text_copied_at` and the window's "Message copied at …" line never appears for new meetings. Needs the owner (Q2): the panel gets "Copy message" next to the reminder (recommended: one text button, the existing sentence and store call, `MeetingConsentText` and `markConsentTextCopied` move behind the panel's `LiveRecorder` call), or MEET-1.6 is retired. Minimal requirement for the panel, for the owner to approve with the panel's sheet, not a look: one line plus at most one button, shown from the start of the recording while the setting is on, never in the pill.

### After the recording: what the app says (OD-7)

What the code does today when the speech model is loading or unavailable during a meeting:

- **Loading** (`MeetingSession` yields `.loadingModel`, then `.modelLoaded`): the audio goes on into the encrypted spool; segments that could not be transcribed live are replayed after "End" while the state is `processing` (`MeetingSession.replayDeferred`). The meeting ends `ready` as usual. **Nothing needs saying**: the only visible effect is a longer `processing` (the closing ring, "Transcribing, N left" on hover, OD-9).
- **Busy or failed during the meeting** (`.modelUnavailable(busy:)`, `SpeechEngineLease` busy or a load error): the same, the replay tries the model once more after "End". If it is free then, the meeting ends `ready`: nothing needs saying.
- **Still unavailable after "End"** (`replayDeferred` cannot take the lease, `replayUnavailable`): the meeting ends `incomplete` with the whole spool kept. Today the pill shows `savedIncomplete` ("Saved, incomplete" · **Open**, 6 s, stays in this spec), the library row the badge "Incomplete" and the "Needs Attention" filter, and the meeting window the banner **"Recording was interrupted. The transcript may be missing its end."** with **Finish** (`MeetingWindowModel.Banner.incomplete(canFinish: true)`, `MeetingWindowView` line 405), which transcribes the spool (`MeetingsLibrary.finish`). Notes wait for a transcript (`NotesService` queues a meeting only when it becomes `ready`).

Verdict: the existing states **do not suffice for the third case**. The capability is there (audio kept, Finish makes the transcript, notes follow), but the text is wrong: the recording was not interrupted, and nothing says the transcript and notes can still be made. The reason is not stored (no column says why a meeting is `incomplete`), so the window cannot choose a text today. This needs:

1. A stored or derivable reason "speech model unavailable" for an `incomplete` meeting (Meetings data; additive, if a column: a migration in `MeetingsStore`).
2. A text for the meeting window and for the main window's meeting row and preview (domain of the main window, notes-explorer spec; not designed here). Proposal for the owner to accept or reword, not a look: en "The speech model wasn't free, so there's no transcript yet. The recording is kept: Finish makes the transcript and notes." / pl "Model mowy był zajęty, więc nie ma jeszcze transkrypcji. Nagranie jest zachowane: Dokończ zrobi transkrypcję i notatki."

Filed as issue #346 (related: #338, a meeting whose stored model was removed). It is not part of this spec's phases; Phase 3 only checks it in QA (see Phase 3).

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
| `allowMicrophone` | mic "Allow the microphone in the dialog" (no ✕: the system prompt decides) |

### Meeting suggestions (top centre, hidden from screen sharing)

| Today | After |
|---|---|
| `.meeting`: "Looks like a meeting in Google Chrome" + Record / Not now / Don't ask for this app | person glyph · "Meeting in Google Chrome" · **Record** (primary) · hover: "Don't ask again" · ✕ = Not now (OD-10) |
| `.endRecording`: "End the recording?" + End recording / Keep recording | ring with dot · "End the recording?" · **End** (primary) · ✕ = Keep recording |

Lifetime (15 s), no key claims and the click-only start stay as today.

### Copy (en / pl)

Every visible string, with its budget. Existing keys whose text changes get new keys (the old keys are removed with their last use, `StringCatalogTests` keeps both languages complete). Removed with no replacement in the pill: the consent line and "Copy message" (OD-6), "Loading the speech model – recording continues" and "… the text comes after the meeting" (OD-7). The consent sentence itself (`MeetingConsentText`) stays for the recording panel.

| Key (en) | pl |
|---|---|
| Allow the microphone in the dialog | Zezwól na mikrofon w oknie systemu |
| Using MacBook Pro mic *(placeholder: device name)* | Mikrofon: MacBook Pro |
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
| Transcribing, %lld left | Transkrypcja, zostały %lld |
| Recognising speakers | Rozpoznawanie mówców |
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
| Buttons: Allow, Download, Fix, Try again, Open, End, Record, Record others only | Zezwól, Pobierz, Napraw, Spróbuj ponownie, Otwórz, Zakończ, Nagrywaj, Nagraj tylko rozmówców |

"Meeting in %@" takes the app's display name; a name that would break the budget is shortened by the pill (tail truncation) and the full name is in the VoiceOver label. The hover link "Don't ask again" has the VoiceOver label "Don't ask again for %@" ("Nie pytaj więcej dla %@").

### Accessibility

- **VoiceOver:** each pill is one element whose label carries everything, including hover-only content: "Dictation, recording, 0:12. Esc cancels." / "Recording a meeting, 12:34. Can't hear the others." / "Meeting in Google Chrome". Its buttons (also the hover-only ones) are exposed as named accessibility actions, so nothing depends on the pointer. Announcements stay as today (start, stop, done, each new problem once; no ticks), with the new texts.
- **Contrast:** text is primary label colour on glass (no coloured text except the amber countdown, which uses the text-grade `statusAttention` and is checked at 4.5:1 on the light and dark glass in the gallery). Increase Contrast adds the 1 pt border used today.
- **Reduce Motion:** the ring does not turn, the dot does not breathe, the wave bars stay flat at the current level (as today), expand and collapse are instant, the closing ring is replaced by a static ring with a small spinner.
- **Large text:** height and font follow the app text size (OD-13); at XL every Polish string fits in 450 pt (checked in the sketch).
- **Pointer-free use:** Esc cancels dictation, the menu bar and the meeting shortcut end a meeting, as today.

## 📝 Architecture

- **`LintelPill`** (new, `Sources/LintelUI/Components/LintelPill.swift`): a SwiftUI view over a pure `PillContent` value (`glyph: PillGlyph` = `.live(dot:)`, `.working(dot:)`, `.attention`, `.error`, `.microphone`, `.done`, `.person`; `live: PillLive?` = `.wave(level:)` or `.clock(String, amber: Bool)`; `text: String?`; `action: PillAction?`; `hoverText`, `hoverActions`, `closes: Bool`, `badge: Bool`, `accessibilityLabel`). Plus `LintelRing` (the cut ring, shared later with the notes explorer of #255) and a `PillHoverHost` (`NSHostingView` subclass with an `NSTrackingArea` `[.activeAlways, .mouseEnteredAndExited, .inVisibleRect]`, because the panels are non-activating and Lintel is usually not the active app, so SwiftUI `.onHover` alone is not reliable there; spike in Phase 1).
- **`LintelUI` depends on no plugin**; the plugins map their state to `PillContent`: `HUDState.pill` in `DictationPlugin`, `MeetingHUDState.pill` and `SuggestionPrompt.pill` in `MeetingsPlugin`. The state enums keep their cases (QA names, tests and controllers unchanged) except the consent ones (OD-6, below); only texts, actions and the view change. No `LintelKit` contract change, no settings keys, no data.
- **Panels:** the three `NSPanel`s keep their level, collection behaviour, sharing type and placement code; their content size becomes the fixed 580 × 56 pt transparent frame.
- **New action "Open"** on `saved` / `savedIncomplete`: `MeetingHUDState.Action.openMeeting`, handled by the controller through the existing `MeetingWindowController` (opens the meeting that was just saved). It is the only behaviour added.
- **Timers:** the 10 s collapse of a lasting notice (OD-8) and the 3 / 4 s fallback line (OD-11) are owned by the HUD model (view-side), not by the controllers. The 8 s consent timer in `MeetingController` (`consentDuration`, `showsConsent`) is removed with the consent line (OD-6).
- **Removed from the HUD path (OD-6, OD-7):** `MeetingHUDState.Notice.consent`, `Recording.showsConsent`, `Action.copyConsentText` and the `recording-consent` QA state; `Notice.loadingModel` and `.modelUnavailable` stay as states (QA names `recording-loading-model`, `recording-model-unavailable`, tests) but map to the plain recording pill. `MeetingConsentText`, `markConsentTextCopied` and `consent_text_copied_at` stay (data, MEET-1.6) for the recording panel.

## 📝 Edge Cases & Failure Scenarios

| Case | Behaviour |
|---|---|
| Two problems at once | The notice order of `Recording.notice` stays (low disk first); the pill shows one line; VoiceOver label lists the shown one. |
| Problem appears while hovered | The pill shows the problem line (hover content yields to the problem). |
| Pointer rests on the pill during dictation | Hover expands it; it never takes focus, so typing continues into the app. |
| Pill under the pointer when it appears | No expansion until the pointer moves (avoids flashing details). |
| Very long app name in the suggestion | Tail truncation in the line; full name in VoiceOver. |
| Screen sharing | The meeting pill (with OD-1 colour) is what participants see; the suggestion pill never shows. |
| Reduce Motion toggled during a recording | Applied on the next state update (as today). |
| Consent reminder on, main window closed | The pill shows nothing (OD-6); the reminder is in the recording panel when the user opens the main window. Accepted by the owner with OD-6 (risk R6). |
| Speech model still busy after "End" | `savedIncomplete` in the pill ("Saved, incomplete · Open", 6 s); the explanation and Finish are in the app (issue #346). |
| Model loading for the whole meeting | Plain pill throughout; after "End" a longer closing ring while the spool is transcribed. |

## 📝 Risks & Impact Review

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Details hidden behind hover are missed (meters were the only visible sign that the other side is heard). With OD-6 and OD-7 the pill also says nothing about consent or the speech model, so every line it shows is a problem the user can act on | Medium | Problems still surface as lines; the measurement below compares first-minute detection. Model trouble is told after the recording in the app (issue #346). |
| R2 | The larger transparent panel blocks clicks in the area around the pill | Medium | Click-through of transparent pixels is verified in the Phase 1 spike; otherwise the panel resizes with the pill (top/bottom edge fixed, as the meeting HUD does today). |
| R3 | Hover tracking in a non-activating panel of a background app | Medium | `NSTrackingArea` with `.activeAlways`, spike in Phase 1. |
| R4 | A Verdigris ring is not read as "recording" by call participants | Medium | OD-1; red dot is the fallback. |
| R5 | Polish strings over budget at XL | Low | Budget test over the catalog; the sketch's XL check. |
| R6 | The consent reminder is seen only when the main window is open during a recording (a meeting started with ⌃⌥M or from a suggestion shows no reminder) | Medium (legal comfort of the user) | Owner decision OD-6. Phase 3 waits for the recording panel with the reminder (#255 step 4.3); the setting stays. Open question Q1. |
| R7 | Until issue #346 is done, a meeting the model could not transcribe says "Recording was interrupted", which is wrong, and the pill no longer hints "text after the meeting" | Low | Finish already works; the issue fixes the text. |

No protected contract, settings key, database or migration changes in this spec's phases (`BACKWARD_COMPATIBILITY.md`). String keys change, which is not a protected surface. `plugins.meetings.consentReminder` keeps its key and type; it switches the recording panel's reminder instead of the pill's line. Issue #346 may add a migration; that is its own PR.

## 🧪 Validation

- **Riskiest belief:** users notice a problem (no system audio, mic not recording) as fast without the always-visible meters.
- **Smallest test:** the owner records three meetings with the Phase 3 build with one failure each (mute the call, unplug the mic, deny system audio) and says when they noticed. Pass: noticed within the notice's own delay (10–20 s) every time. Fail: OD-5 alternative (a combined wave stays visible).
- **Guardrail:** no new silent-recording reports (the Granola complaint).
- **QA without a real microphone or sound:** every phase is checked with the `--qa-hud` fixtures and the gallery, never with a real microphone, system audio or the speakers (owner rule 2026-11-26: no sound on the Mac's speakers). The owner's three validation recordings above are the only real-audio step and are the owner's.

## 📋 Phasing

Three `feat/` PRs, in order. Each one:

- has an **owner sheet**: a gallery or QA picture of every new look of that phase (light and dark, en and pl, S and XL, Reduce Motion, Increase Contrast, hover), posted on the PR for the owner's approval before `qa-approved` (new looks go to the owner's QA track);
- has **QA with screenshots of the running debug build** (`docs/qa.md`, `--qa-hud …`, `--qa-snapshot`, light and dark), with no real microphone, system audio or sound;
- passes the validation gate (`swift build`, `swift test`, `swift format lint --strict -r Sources Tests`).

1. **Phase 1 — `LintelPill` in the gallery.** The component over `LintelRing` (#333, on `main`; reused, not redrawn), gallery scene `ui.pill` (the brief called it `lintel.pill`; `LintelUI` scenes use the `ui.` prefix, like `ui.ring`), and the R2/R3 spike in the non-activating panel. The gallery mechanism of #248 is on `main` (`Sources/LintelUI/Gallery/`), so no fallback is needed. No HUD changes yet.
2. **Phase 2 — dictation pill.** `HUDState.pill`, the dictation panel on `LintelPill`.
3. **Phase 3 — meeting pill and suggestion pill.** `MeetingHUDState.pill`, `SuggestionPrompt.pill`, the #258 states (merged 2026-11-25, on `main`: `microphoneFallback`, `retryingMicrophone`, `microphoneNotRecorded`, `retryMicrophone`), the OD-6 removal of the consent line (after the recording panel with the reminder is on `main`, #255 step 4.3) and `Action.openMeeting`.

## 📋 Implementation Plan

### Phase 1 — Pill component

1. `LintelPill` + `PillContent` in `Sources/LintelUI/Components/`, with `LintelRing` as the glyph for live, warning and working (no second ring), sizes from `lintelTextSize` (28 / 32 / 38 pt at S / M / XL), colours from `LintelBrand`.
2. `PillHoverHost` with the tracking area and the 300 / 500 ms delays; spike for R2 (click-through of the transparent 580 × 56 pt panel) and R3 (hover in a non-activating panel of a background app) recorded in the PR, with the fallback of R2 if click-through fails.
3. Gallery scene `ui.pill` with every variant (live wave, live clock, working, message, prompt, amber dot) in the full matrix; it is the owner sheet of the phase.
4. Tests: `PillContent` accessibility labels and actions, the 40-character copy budget test over `Localizable.xcstrings` (pill keys tagged by comment prefix `HUD pill:`), ring use under Reduce Motion (through `LintelRingMotion.reduced`), gallery goldens.

### Phase 2 — Dictation

1. `HUDState.pill` mapping per the dictation table; new strings en + pl; remove the old ones (including "Loading model…", OD-7).
2. `DictationHUDView` renders `LintelPill`; panel frame 580 × 56; the #258 fallback bubble becomes the 3 s line (OD-11).
3. Tests: mapping per state (`DictationHUDQATests`), announcements unchanged except texts, hover-only actions exposed as accessibility actions, `recording(loadingModel)` maps to the same pill as `recording`.
4. Owner sheet: a gallery scene of the dictation states (or the `--qa-hud dictation:*` snapshots).
5. QA: every `--qa-hud dictation:*` state, light and dark, en and pl, S and XL, Reduce Motion; hover on the running app. No microphone is opened.

### Phase 3 — Meetings and suggestions

1. `MeetingHUDState.pill` and `SuggestionPrompt.pill`; the 10 s collapse and the fallback 4 s line in the HUD model; `Action.openMeeting`.
2. OD-6: remove `Notice.consent`, `Recording.showsConsent`, `Action.copyConsentText`, the `consentDuration` timer and the `recording-consent` QA state (update `docs/qa.md`); keep `MeetingConsentText` and the store call for the recording panel. Merge only after the recording panel with the reminder is on `main`.
3. OD-7: `.loadingModel` and `.modelUnavailable` map to the plain recording pill with unchanged hover; remove their strings.
4. `MeetingHUDView` and `SuggestionHUDView` render `LintelPill`; panels 580 × 56; screen-sharing behaviour unchanged.
5. Tests: mapping per state, collapse timer with `TestClock`, `openMeeting` routes to the window, suggestion actions unchanged (`Not now` on ✕, `muteApp` on the hover link), no pill string mentions consent or the speech model while recording.
6. Owner sheet: a gallery scene of the meeting and suggestion states.
7. QA: every `--qa-hud meeting:*` state including the #258 and suggestion states; `recording-loading-model` and `recording-model-unavailable` show the plain pill on hover too; `saved-incomplete` shows "Saved, incomplete · Open" and Open opens the meeting; the main window's recording panel shows the consent reminder while the setting is on (the pill never does), and, once issue #346 is done, the app shows the model text for a fixture meeting the model could not transcribe (no recording). The owner's validation recordings above are separate.

## 📝 Not doing

- Moving or resizing pills by drag (Wispr's first change after feedback; later, if asked for).
- A menu-bar-only mode without a pill.
- New detection or new problems: the pill only shows what the controllers already report. When #266 (dictation: microphone lost during a recording) is decided, its state uses the `message` variant with the microphone glyph and "Microphone disconnected" ("Mikrofon odłączony"), the same line as the meeting pill.
- Window management HUDs (`WindowsPlugin`), which are an add-on and off by default.
