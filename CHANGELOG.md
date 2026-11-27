# Changelog

All notable user-visible changes to Lintel are listed here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Each release has a `## [x.y.z] - YYYY-MM-DD`
section (pre-releases use `x.y.z-beta.N`).

## [Unreleased]

### Added

- Dictation: **Tidy up my text** replaces the "Clean up text" switch in Settings → Dictation with a choice of Off, Light and Standard. Light only removes filler words such as "yyy", "eee", "um" and "uh" and never changes your words; it runs on this Mac without a model, as fast as pasting the raw text. Standard is the cleanup you had before (Cleanup prompt v2). If you had "Clean up text" on, you stay on Standard; if you had it off, you stay on Off.

- Dictation: a **Full** level of Tidy up my text (email layout, paragraphs for a long dictation, smoother style) is built and tested but not offered yet; it appears in the popup when it passes its quality checks.

- Notes: when Lintel suggests a name for a speaker, the meeting's transcript asks once, under that speaker's first words ("Marek?" with Yes and No), and the answer goes to the meeting.

### Changed

- Meeting notes now follow a topic layout: topics, decisions made and next steps. Notes written by a provider (Claude) start with a short intro; notes written by the model on this Mac, since notes prompt 7, have no intro, so the model never adds a sentence of its own about the meeting. They also show more of the points it checked (up to six per topic instead of ten in all). Notes written earlier stay as they are.
- On a new install, Dictation and Meetings are on, and app search, file search and clipboard history are add-ons that you turn on in Settings → Features. If you used Lintel before this version, every switch stays as it was.
- The welcome screen starts with dictation and meeting notes. It asks for the launcher shortcut only when app search, file search or window management is on; the shortcut stays in Settings → General and works only while one of them is on.
- On a new install, Lintel writes notes after each meeting with the model on this Mac; nothing is sent anywhere. The welcome screen offers the notes model download (with its size, and with the space needed when the disk is too full). Until the model is downloaded, meetings are recorded and saved as before and say that their notes are written once the model is on this Mac; meetings recorded since Lintel started get their notes as soon as the download finishes. If you used Lintel before this version, the notes switch stays as it was.

### Fixed

- Notes: the transcript's speaker column is as wide as the longest name (up to a limit, then the name wraps), so a full name such as "Anna Kowalska" is no longer cut, also at the largest text size.
- A meeting that was waiting for the notes model is no longer forgotten when Lintel restarts: it still says that its notes need the model, and it gets its notes when the model is downloaded.
- A meeting that waits for the notes model no longer loses its notes when the model is downloaded while Lintel is saving that wait: they are written as soon as the download finishes.

## [0.1.0-beta.1] - 2026-11-22

The first public beta.

### Added

- Lintel is signed with an Apple Developer ID and notarized, so macOS opens it without the Gatekeeper block. If you ran an earlier test build, grant Microphone, Accessibility, Screen & System Audio Recording and Full Disk Access to Lintel once more.
- Launcher panel on a global shortcut (Command-Space, or Control-Option-Space when Spotlight holds it) with fast app search, fuzzy matching and frecency ranking.
- App suggestions on an empty query, based on how long each app has been in front.
- File search by name with its own index kept fresh through FSEvents, and path search for queries that start with `/` or `~`. Indexing starts after the Full Disk Access step.
- Clipboard history in an encrypted store, with a list and preview, paste into the previous app, and controls for ignored apps, retention and clearing.
- Dictation (off by default) with on-device speech recognition, a recording HUD, paste into the active app, an encrypted history, and optional cleanup of the text by a built-in local model or a local server.
- Meeting recording (off by default) with microphone and system audio, speaker labels and notes written by a local model. Audio and text stay on this Mac.
- Notes workspace that brings meeting notes, transcripts and dictations together, with search, history and restore.
- Window management (off by default).
- Main window, a Settings window with Permissions and Advanced panes (Reset Ranking), and an About window with third-party notices.
- Welcome screen that sets the shortcut and walks through the steps of the features you enable.
- English and Polish interface.
- Lintel offers to move itself to Applications (or to your home folder's Applications when the system one is not writable) when it starts from a disk image or Downloads. It never replaces a newer installed copy, and moves the original to the Trash after the new copy is checked.
- In-app updates. Lintel asks once, after the welcome screen, whether it may check for updates, and makes no update request before you answer. Settings → General → Updates has automatic checks, automatic downloads, beta versions (on by default in a beta) and Check Now. Updates are signed and checked before they are installed, and your permissions stay granted across them. An update that is ready waits until a recording or its processing ends before it restarts Lintel.

### Changed

- Meeting notes (prompt v6): a task is listed once and small-talk tasks are left out, questions that do not say what they ask about and reports of a problem without a cause or fix are left out, and when the final organising step fails the topics shown are spread over the whole meeting instead of the first ones.
- Pounce is now called Lintel, with a new icon and brand colors.
