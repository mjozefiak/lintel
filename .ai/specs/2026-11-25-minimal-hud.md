# Minimal HUD pills: dictation, meeting recording, meeting suggestions

> Status: **design, waiting for the owner's decisions OD-1 to OD-13.** Nothing here is implemented. The recommendations below are proposals; none of them is an accepted default.
> Owner direction (2026-11-25): "te pastylki u konkurencji zawsze są mega minimalistyczne i też chcę, aby tak było w Lintel; obecnie jest tam za dużo zbędnych informacji, ograniczamy się do totalnego minimum."
> Sketch (before and after for every state, light and dark, en and pl, S/M/XL, Reduce Motion, Increase Contrast, hover): `.ai/specs/assets/minimal-hud/index.html`. It is a sketch for the decision only: after acceptance the SwiftUI gallery (#248) is the source of truth.
> Inputs: the current HUD code (`Sources/DictationPlugin/HUDState.swift`, `DictationHUD.swift`, `Sources/MeetingsPlugin/UI/MeetingHUDState.swift`, `MeetingHUD.swift`, `Sources/MeetingsPlugin/Suggestions/SuggestionHUD.swift`, `SuggestionPrompt.swift`), the `--qa-hud` states in `docs/qa.md`, the new states of PR #258, the UX direction of PR #247 (the working ring, Verdigris only for live state) and the gallery spec of PR #248.

## 📝 TLDR

**Who:** everyone who dictates or records meetings. Office users who never read a HUD on purpose: the pill must be understood at a glance or not noticed at all.
**Today:** three different floating surfaces. Dictation is a 248 × 40 pt capsule with an icon, the word "Recording", level bars, a timer and a ✕. The meeting HUD is a 400 × 44–68 pt rounded rectangle with the time, two named level meters, a red "End recording" button and a second line of notices (up to 63 characters). The suggestion is a 440 × 78 pt card with a sentence and three buttons. PR #258 adds a two-line bubble above the dictation pill and more notices to the meeting HUD.
**Proposed:** **one pill family** (`LintelPill`): a capsule 32 pt high (28 at S, 38 at XL), glass, one line of text at most, at most one text button plus ✕. In the normal state the pill shows only what is live: dictation = the turning ring and the voice wave (88 pt wide); meeting = the ring with its dot, the time and a stop button (about 120 pt). Everything else (timer, ✕, meters, "End", "Don't ask again", processing details) appears **only on hover** and is always in the VoiceOver label. A problem appears **only while it exists**, as one short line with one action. Finished states are a ✓ or one word.

## ✅ Owner decisions (open, recommendation first)

| # | Decision | Recommendation | Alternative | Why it matters |
|---|---|---|---|---|
| OD-1 | Colour of "live" | **Verdigris ring** (#247: the ring is the brand signature, Verdigris marks live state) for both pills | Red dot for the meeting pill only (universal "recording" sign for people on a shared screen) | The meeting pill is visible in screen sharing on purpose; a red dot is understood by everyone on the call. |
| OD-2 | Dictation: timer and ✕ | **Hover only**; Esc still cancels; ✕ always visible when Esc could not be claimed | Keep the ✕ always | Wispr's bar shows only the wave. The timer tells an office user nothing while dictating. |
| OD-3 | After pasting | **✓ for 0.6 s**, then gone | No pill at all (the text appearing is the confirmation) | Today "Pasted" stays 0.8 s. |
| OD-4 | "Pasted – partly cleaned up" | **Show nothing**; "Pasted without cleanup" (all raw) stays, without the "Raw version: …" hint | Keep both | A partial fallback is invisible to most users; the hint names a menu path nobody reads in 3 s. |
| OD-5 | Meeting level meters | **Hover only**; problems come as notices (20 s system silence, 10 s microphone silence, lost device) | Keep one combined wave visible | The notices already detect the failures the meters were for. |
| OD-6 | Consent reminder | **Keep**: one line "Tell people you're recording" + "Copy text" in the first 8 s, only while the setting is on | Move it to the meeting window only | It protects the user legally; it is the only non-problem line kept. |
| OD-7 | Model loading / model unavailable during recording | **Silent** (dictation: same pill; meeting: "Text after the meeting" on hover only) | Keep a notice | Recording already runs; the user can do nothing about it. |
| OD-8 | A problem that lasts | **Line stays 10 s**, then the pill shrinks back and keeps an amber dot on the ring; hover and VoiceOver give the line again; a new problem expands it again | Line stays as long as the problem | Long lines over a call window are the clutter the owner named. |
| OD-9 | After "End" (meeting) | **Closing ring only**; "Transcribing, 3 left" on hover; then "Saved · Open" 3 s | Ring + "Saving…" | Processing can take minutes; a word may reassure. |
| OD-10 | Suggestion pill | **One line + "Record" + ✕ (= Not now)**; "Don't ask again" on hover; end question: "End the recording?" + "End" + ✕ (= keep recording) | Keep three visible buttons | The mute choice is rare and stays one hover away. |
| OD-11 | Chosen microphone missing (#258) | **Name of the microphone used, 3 s (dictation) / 4 s (meeting)**, then amber dot, hover shows it | Silent | Quality changes when the built-in mic replaces a headset. |
| OD-12 | Meter names | **"You" / "Others"** ("Ty" / "Rozmówcy") instead of "Me" / "System" | Keep | "System" is jargon for office users. |
| OD-13 | Size | **32 pt at M**, follows the app's text size (28 / 32 / 38) | Fixed 32 | XL users get readable pills; today HUDs ignore text size. |

## 📝 Problem Statement

1. **Too much in the normal state.** While dictating, the user sees an icon, a word, bars, a timer and a ✕ (five things) where they need one: "it is listening". The meeting HUD shows a clock, two labelled meters and a red button across 400 pt at the top of the call window.
2. **Notices are long and technical.** "Check the system audio recording permission", "No microphone audio – check the microphone permission and input", "Another speech model is in use – the text comes after the meeting" (63 characters). They wrap or get squeezed in Polish (#236, the #258 screenshots).
3. **Three shapes, three sizes.** Capsule, rounded rectangle and card; widths 248, 400 and 440 pt; buttons as links, bordered and prominent. PR #258 adds a fourth: a bubble above the capsule.
4. **States that the user cannot act on are shown** (model loading, partial cleanup, processing counts).

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
- Glyphs (16 / 16 / 19 pt): **live** = the cut ring turning slowly; the meeting ring has the breathing centre dot, the dictation ring has none (the same meaning as the note-type ring in #247). **working** = the ring closing. **problem** = amber triangle (`statusAttention`). **failed** = red triangle (`statusError`). **done** = ✓ in the live colour. Microphone problems use `mic.slash` in amber.
- Buttons: one text button (`act`, neutral fill, the live colour only for a prompt's primary), ✕ 22 pt (hit area 24 pt), the meeting's stop button is a 22 pt circle with a square.
- Positions do not change: dictation bottom centre, 48 pt above the visible frame; meeting and suggestion top centre under the menu bar. A pill is at most 380 pt wide at S and M and 450 pt at XL, plus 120 pt while hovered (hover content must never truncate the main line). Measured in the sketch, every state in en and pl fits without truncation: widest normal pill 376 pt (M, pl), 415 pt (XL, pl); widest hovered 442 pt (M, pl), 489 pt (XL, pl). The panel is a fixed transparent window larger than the widest pill (580 × 56 pt), the pill centred in it, so expanding never moves or resizes the window. The transparent area must stay click-through (risk R2).
- The meeting pill stays visible in screen sharing; the suggestion pill stays hidden from it (`sharingType = .none`), as today.

### Hover

- After the pointer rests on the pill for 300 ms it expands (spring 0.2 s; instant under Reduce Motion) and shows its hover content. It collapses 500 ms after the pointer leaves. Keyboard focus on a button inside the pill counts as hover.
- Hover content never contains something only available there except shortcuts to things that exist elsewhere: cancel (Esc), End (the menu bar and the meeting window), meters (the meeting window), "Don't ask again" (Settings → Meetings).
- The panels stay non-activating and never take focus.

### Dictation states (bottom centre)

| Today (`HUDState`) | After | Stays | Goes |
|---|---|---|---|
| `recording` | `live`: ring + wave. Hover: `0:12` + ✕ | the ring, the wave | "Recording", red dot, timer, ✕ (OD-2) |
| `recording`, Esc not claimed | ring + wave + ✕ always | ✕ | "✕ cancels" |
| `recording(loadingModel)` | same as recording | — | "Loading model…", blinking caret (OD-7) |
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

### Meeting recording (top centre)

While a problem or reminder line is shown, the clock steps aside (ring · line · action · stop) and comes back when the line goes; the time stays in the VoiceOver label. This keeps every line within the width budget and puts the one thing that matters first.

| Today (`MeetingHUDState`) | After | Goes |
|---|---|---|
| `recording` | `live`: ring with dot + `12:34` + stop. Hover: You ▂ · Others ▂ · **End** | "Recording a meeting" (not visible, it is in the VoiceOver label), two named meters, red "End recording" (OD-1, OD-5, OD-12) |
| notice `.consent` (first 8 s) | ring · "Tell people you're recording" · **Copy text** · stop (OD-6) | second line, the clock while the line shows |
| notice `.loadingModel`, `.modelUnavailable` | plain recording pill; hover adds "Text after the meeting" (OD-7) | the notice |
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

Every visible string, with its budget. Existing keys whose text changes get new keys (the old keys are removed with their last use, `StringCatalogTests` keeps both languages complete).

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
| Tell people you're recording | Powiedz, że nagrywasz |
| Text after the meeting | Tekst po spotkaniu |
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
| Buttons: Allow, Download, Fix, Try again, Open, End, Record, Record others only, Copy text | Zezwól, Pobierz, Napraw, Spróbuj ponownie, Otwórz, Zakończ, Nagrywaj, Nagraj tylko rozmówców, Kopiuj tekst |

"Meeting in %@" takes the app's display name; a name that would break the budget is shortened by the pill (tail truncation) and the full name is in the VoiceOver label. The hover link "Don't ask again" has the VoiceOver label "Don't ask again for %@" ("Nie pytaj więcej dla %@").

### Accessibility

- **VoiceOver:** each pill is one element whose label carries everything, including hover-only content: "Dictation, recording, 0:12. Esc cancels." / "Recording a meeting, 12:34. Can't hear the others." / "Meeting in Google Chrome". Its buttons (also the hover-only ones) are exposed as named accessibility actions, so nothing depends on the pointer. Announcements stay as today (start, stop, done, each new problem once; no ticks), with the new texts.
- **Contrast:** text is primary label colour on glass (no coloured text except the amber countdown, which uses the text-grade `statusAttention` and is checked at 4.5:1 on the light and dark glass in the gallery). Increase Contrast adds the 1 pt border used today.
- **Reduce Motion:** the ring does not turn, the dot does not breathe, the wave bars stay flat at the current level (as today), expand and collapse are instant, the closing ring is replaced by a static ring with a small spinner.
- **Large text:** height and font follow the app text size (OD-13); at XL every Polish string fits in 450 pt (checked in the sketch).
- **Pointer-free use:** Esc cancels dictation, the menu bar and the meeting shortcut end a meeting, as today.

## 📝 Architecture

- **`LintelPill`** (new, `Sources/LintelUI/Components/LintelPill.swift`): a SwiftUI view over a pure `PillContent` value (`glyph: PillGlyph` = `.live(dot:)`, `.working(dot:)`, `.attention`, `.error`, `.microphone`, `.done`, `.person`; `live: PillLive?` = `.wave(level:)` or `.clock(String, amber: Bool)`; `text: String?`; `action: PillAction?`; `hoverText`, `hoverActions`, `closes: Bool`, `badge: Bool`, `accessibilityLabel`). Plus `LintelRing` (the cut ring, shared later with the notes explorer of #255) and a `PillHoverHost` (`NSHostingView` subclass with an `NSTrackingArea` `[.activeAlways, .mouseEnteredAndExited, .inVisibleRect]`, because the panels are non-activating and Lintel is usually not the active app, so SwiftUI `.onHover` alone is not reliable there; spike in Phase 1).
- **`LintelUI` depends on no plugin**; the plugins map their state to `PillContent`: `HUDState.pill` in `DictationPlugin`, `MeetingHUDState.pill` and `SuggestionPrompt.pill` in `MeetingsPlugin`. The state enums keep their cases (QA names, tests and controllers unchanged); only texts, actions and the view change. No `LintelKit` contract change, no settings keys, no data.
- **Panels:** the three `NSPanel`s keep their level, collection behaviour, sharing type and placement code; their content size becomes the fixed 580 × 56 pt transparent frame.
- **New action "Open"** on `saved` / `savedIncomplete`: `MeetingHUDState.Action.openMeeting`, handled by the controller through the existing `MeetingWindowController` (opens the meeting that was just saved). It is the only behaviour added.
- **Timers:** the 10 s collapse of a lasting notice (OD-8), the 3 / 4 s fallback line (OD-11) and the 8 s consent line are owned by the HUD model (view-side), not by the controllers, so they need no change in `MeetingController`; the consent end already exists there.

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
| #258 not merged when Phase 3 starts | Its states are mapped when it lands; Phase 3 then covers them in the same PR or #258 rebases on the pill. |

## 📝 Risks & Impact Review

| # | Risk | Severity | Mitigation |
|---|---|---|---|
| R1 | Details hidden behind hover are missed (meters were the only visible sign that the other side is heard) | Medium | Problems still surface as lines; the measurement below compares first-minute detection. |
| R2 | The larger transparent panel blocks clicks in the area around the pill | Medium | Click-through of transparent pixels is verified in the Phase 1 spike; otherwise the panel resizes with the pill (top/bottom edge fixed, as the meeting HUD does today). |
| R3 | Hover tracking in a non-activating panel of a background app | Medium | `NSTrackingArea` with `.activeAlways`, spike in Phase 1. |
| R4 | A Verdigris ring is not read as "recording" by call participants | Medium | OD-1; red dot is the fallback. |
| R5 | Polish strings over budget at XL | Low | Budget test over the catalog; the sketch's XL check. |

No protected contract, settings key, database or migration changes (`BACKWARD_COMPATIBILITY.md`). String keys change, which is not a protected surface.

## 🧪 Validation

- **Riskiest belief:** users notice a problem (no system audio, mic not recording) as fast without the always-visible meters.
- **Smallest test:** the owner records three meetings with the Phase 3 build with one failure each (mute the call, unplug the mic, deny system audio) and says when they noticed. Pass: noticed within the notice's own delay (10–20 s) every time. Fail: OD-5 alternative (a combined wave stays visible).
- **Guardrail:** no new silent-recording reports (the Granola complaint).

## 📋 Phasing

1. **Phase 1 — `LintelPill` in the SwiftUI gallery.** Depends on #248 Phase 1 (gallery mechanism). If #248 has not landed, the component ships with `--qa-hud`-style QA snapshots and moves into the gallery with #248 Phase 5.
2. **Phase 2 — dictation HUD on the pill.**
3. **Phase 3 — meeting HUD and suggestions on the pill** (including the #258 states).

Each phase is its own `feat/` PR with `needs-qa` and the QA comment (screenshots of the running debug build, light and dark, en and pl, S and XL).

## 📋 Implementation Plan

### Phase 1 — Pill component

1. `LintelRing` (live, working, static; dot on/off) and `LintelPill` + `PillContent` in `Sources/LintelUI/Components/`, sizes from `lintelTextSize`, colours from `LintelBrand`.
2. `PillHoverHost` with the tracking area and the 300 / 500 ms delays; spike for R2 and R3 recorded in the PR.
3. Gallery scene `lintel.pill` with every variant (live wave, live clock, working, message, prompt, badge) in the full matrix; or `--qa-pill <variant>` if #248 is not there yet.
4. Tests: `PillContent` accessibility labels and actions, the 40-character copy budget test over `Localizable.xcstrings` (pill keys tagged by comment prefix `HUD pill:`), ring rendering under Reduce Motion.

### Phase 2 — Dictation

1. `HUDState.pill` mapping per the dictation table; new strings en + pl; remove the old ones.
2. `DictationHUDView` renders `LintelPill`; panel frame 580 × 56; the #258 fallback bubble becomes the pill line.
3. Tests: mapping per state (`DictationHUDQATests`), announcements unchanged except texts, hover-only actions exposed as accessibility actions.
4. QA: every `--qa-hud dictation:*` state, light and dark, en and pl, S and XL, Reduce Motion; hover on the running app.

### Phase 3 — Meetings and suggestions

1. `MeetingHUDState.pill` and `SuggestionPrompt.pill`; the 10 s collapse, the consent 8 s line, the fallback 4 s line in the HUD model; `Action.openMeeting`.
2. `MeetingHUDView` and `SuggestionHUDView` render `LintelPill`; panels 580 × 56; screen-sharing behaviour unchanged.
3. Tests: mapping per state, collapse timer with a test clock, `openMeeting` routes to the window, suggestion actions unchanged (`Not now` on ✕, `muteApp` on the hover link).
4. QA: every `--qa-hud meeting:*` state including the #258 and suggestion states; the validation recordings above.

## 📝 Not doing

- Moving or resizing pills by drag (Wispr's first change after feedback; later, if asked for).
- A menu-bar-only mode without a pill.
- New detection or new problems: the pill only shows what the controllers already report.
- Window management HUDs (`WindowsPlugin`), which are an add-on and off by default.
