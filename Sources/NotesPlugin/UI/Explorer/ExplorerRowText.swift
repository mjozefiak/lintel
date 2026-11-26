import Foundation
import LintelKit
import LintelUI

/// What one explorer row says (spec `2026-11-24-notes-explorer-main-window`, "Layout" and "The working ring"): the word
/// for the kind ("Meeting", "Dictation", "Note", never the ring's shape alone), the meta line, the time, and the state
/// the ring and a line of words show together. Pure and localized through the main bundle; a title is other people's
/// words and is never built here.
struct ExplorerRowText: Sendable {
    var presentation: NoteRowPresentation

    init(presentation: NoteRowPresentation) {
        self.presentation = presentation
    }

    // MARK: Kind

    /// "Meeting", "Dictation" or "Note".
    static func kindWord(_ summary: NoteSummary) -> String {
        if NoteCollection.dictations.contains(key: summary.id, kind: summary.kind) {
            return String(localized: "Dictation", comment: "Spoken name of the idle ring of a dictation")
        }
        if NoteCollection.meetings.contains(key: summary.id, kind: summary.kind) {
            return String(localized: "Meeting", comment: "Spoken name of the idle ring of a meeting")
        }
        return String(localized: "Note", comment: "Explorer row: the word for a note you wrote yourself")
    }

    /// The type mark of the row's ring: a meeting has the centre dot, a dictation and a note do not.
    static func mark(_ summary: NoteSummary) -> LintelRingMark {
        NoteCollection.meetings.contains(key: summary.id, kind: summary.kind) ? .meeting : .dictation
    }

    // MARK: Meta line

    /// "Meeting · 42 min · 3 tasks", "Dictation · 118 words". A part the source does not know is left out.
    func meta(_ summary: NoteSummary) -> String {
        var parts = [Self.kindWord(summary)]
        let isDictation = NoteCollection.dictations.contains(key: summary.id, kind: summary.kind)
        if isDictation {
            if let words = summary.wordCount {
                parts.append(String(localized: "\(words) words", comment: "Explorer row: the length of a dictation"))
            }
        } else {
            if let ms = summary.durationMs, ms > 0 {
                parts.append(presentation.duration(milliseconds: ms, kind: summary.kind))
            }
            if let tasks = summary.taskCount, tasks > 0 {
                parts.append(String(localized: "\(tasks) tasks", comment: "Explorer row: how many tasks the notes carry"))
            }
        }
        return parts.joined(separator: " · ")
    }

    /// The time of day, shown at the right of the row (the group heading says which day).
    func time(_ summary: NoteSummary) -> String { presentation.time(summary.startedAt) }

    // MARK: State

    /// What a row's ring and state line show for a note's badge.
    struct State: Equatable {
        var ring: LintelRingState
        /// The words beside the ring; `nil` for a finished note.
        var text: String?
        var level: NoteStateLevel
    }

    func state(_ badge: NoteBadge?) -> State {
        guard let badge else { return State(ring: .idle, text: nil, level: .quiet) }
        let level = NoteRowPresentation.level(badge)
        switch badge {
        case .recording:
            return State(
                ring: .listening, text: String(localized: "Now", comment: "Explorer row: the meeting being recorded"),
                level: level)
        case .processing:
            return State(
                ring: .processing(progress: nil),
                text: String(localized: "Processing…", comment: "Explorer row: the recording is being turned into text"),
                level: level)
        case .writing(let done, let of):
            return State(
                ring: .processing(progress: of > 0 ? Double(done) / Double(of) : nil),
                text: String(localized: "Writing notes…", comment: "Explorer row: the notes are being written"),
                level: level)
        case .failed:
            return State(
                ring: .error,
                text: String(localized: "Notes not written", comment: "Explorer row: the notes could not be written"),
                level: level)
        case .needsModel:
            return State(
                ring: .idle,
                text: String(
                    localized: "Waiting for a download", comment: "Explorer row: the notes need something to download first"),
                level: level)
        default:
            return State(ring: .idle, text: NoteRowPresentation.stateText(badge), level: level)
        }
    }

    // MARK: Accessibility

    /// "Meeting, Client call: Nordlys Energy, 11:30, 42 min · 3 tasks, Writing notes…".
    func accessibilityLabel(_ row: NoteRow, snippet: String?, title: String) -> String {
        var parts = [Self.kindWord(row.summary), title, time(row.summary)]
        let facts = meta(row.summary).split(separator: "·").dropFirst().map { $0.trimmingCharacters(in: .whitespaces) }
        parts.append(contentsOf: facts)
        if let snippet { parts.append(snippet) }
        if let text = state(row.badge).text { parts.append(text) }
        return parts.joined(separator: ", ")
    }

    // MARK: Group titles

    /// The heading of a day group: "Today", "Yesterday", the weekday within the last week, else the date.
    func title(of key: NoteGroupKey, now: Date) -> String {
        switch key {
        case .today: return String(localized: "Today", comment: "Explorer: group of today's notes")
        case .yesterday: return String(localized: "Yesterday", comment: "Explorer: group of yesterday's notes")
        case .day(let day):
            let days = presentation.calendar.dateComponents(
                [.day], from: day, to: presentation.calendar.startOfDay(for: now)
            ).day ?? 0
            let style = Date.FormatStyle(
                locale: presentation.locale, calendar: presentation.calendar, timeZone: presentation.calendar.timeZone)
            if days < 7 { return day.formatted(style.weekday(.wide)).capitalizedFirst(locale: presentation.locale) }
            let sameYear = presentation.calendar.isDate(day, equalTo: now, toGranularity: .year)
            return day.formatted(sameYear ? style.day().month(.wide) : style.day().month(.wide).year())
        default: return ""
        }
    }
}

extension String {
    /// Upper-cases the first character only ("środa" → "Środa"); a day name starts a heading.
    func capitalizedFirst(locale: Locale) -> String {
        guard let first else { return self }
        return String(first).uppercased(with: locale) + dropFirst()
    }
}
