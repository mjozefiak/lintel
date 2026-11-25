import Foundation
import LintelCore

/// The shape of the notes of both tracks (spec `2026-11-25-meeting-notes-structure`): a short intro without a
/// heading, topics (a name and a few points each), the decisions, the next steps, open questions and the
/// participants. A pure value: it holds the text a track chose to show; `NotesLayoutComposer` writes the Markdown
/// and is the one place that knows the order of the sections, the short-meeting rule and the clean-up of the text.
struct NotesLayout: Equatable, Sendable {
    struct Topic: Equatable, Sendable {
        /// `nil`: points without a heading (the old `FINDINGS` list, a short meeting).
        var name: String?
        var points: [String]
        /// The topic that collects what has no topic of its own; the composer gives it the label "Other".
        var isOther = false
    }

    struct NextStep: Equatable, Sendable {
        var text: String
        var person: String?
        var due: String?
    }

    var intro: String?
    var topics: [Topic] = []
    var decisions: [String] = []
    var nextSteps: [NextStep] = []
    var openQuestions: [String] = []
    var participants: [String] = []

    static let maxPointsPerTopic = 6
    static let maxOpenQuestions = 5
    static let maxIntroSentences = 3
    static let maxIntroWords = 70
    /// A meeting shorter than this, or with fewer points, is one list without topic headings.
    static let shortMeetingMinutes = 10
    static let shortMeetingPoints = 6

    /// `min(10, max(2, minutes / 6))`: 24 min is 4 topics, 38 min is 6, 55 min is 9, an hour or more is 10. The code
    /// guards only this upper bound.
    static func maxTopics(durationMs: Int) -> Int {
        min(10, max(2, max(0, durationMs) / 60_000 / 6))
    }

    var pointCount: Int { topics.reduce(0) { $0 + $1.points.count } }

    /// Short: under ten minutes (when the length is known) or fewer than six points to show.
    func isShortMeeting(durationMs: Int?) -> Bool {
        if let durationMs, durationMs < Self.shortMeetingMinutes * 60_000 { return true }
        return pointCount < Self.shortMeetingPoints
    }

    /// The topics as they are shown. A short meeting is one list without a heading. Otherwise a named topic with
    /// one point joins the closing topic "Other" (when there are two such topics, or an "Other" already exists), and
    /// that topic holds at most six points. Points without a name come first, so they never read as part of a
    /// heading above them.
    func shownTopics(durationMs: Int?) -> [Topic] {
        let filled = topics.filter { !$0.points.isEmpty }
        if filled.isEmpty { return [] }
        if isShortMeeting(durationMs: durationMs) { return [Topic(name: nil, points: filled.flatMap(\.points))] }
        let unnamed = filled.filter { $0.name == nil && !$0.isOther }
        let named = filled.filter { $0.name != nil && !$0.isOther }
        var other = filled.filter(\.isOther).flatMap(\.points)
        let singles = named.filter { $0.points.count == 1 }
        let merge = singles.count >= 2 || (!singles.isEmpty && !other.isEmpty)
        var kept = merge ? named.filter { $0.points.count > 1 } : named
        if merge { other = singles.flatMap(\.points) + other }
        if !other.isEmpty {
            kept.append(Topic(name: nil, points: Array(other.prefix(Self.maxPointsPerTopic)), isOther: true))
        }
        return unnamed + kept
    }
}

/// Writes `NotesLayout` as Markdown through `NotesMarkdown.render`, the allow-list renderer: no link, image, HTML
/// or network resource can appear. Whatever the layout holds is cleaned again here: no transcript time, no
/// checklist marker of the model's, no leading character that would become a heading or a list.
///
/// Order: the title (tracks that have one), the intro paragraph, the topics (each a heading, siblings of the
/// sections below), Decisions made, Next steps (a checklist, the owner and due date only when they were said), Open
/// questions, Participants. A section without items is not written.
enum NotesLayoutComposer {
    static func markdown(
        layout: NotesLayout, title: String? = nil, durationMs: Int? = nil, labels: NotesComposer.Labels
    ) -> String {
        var lines: [String] = []
        func heading(_ level: Int, _ text: String) {
            if !lines.isEmpty { lines.append("") }
            lines.append(String(repeating: "#", count: level) + " " + text)
            lines.append("")
        }
        func paragraph(_ text: String) {
            if !lines.isEmpty, lines.last != "" { lines.append("") }
            lines.append(text)
        }
        var hasBody = false
        if let title = title.map(flat), !title.isEmpty { lines.append("# " + NotesComposer.inertParagraph(title)) }
        if let intro = layout.intro.map(flat).map(NotesComposer.inertParagraph), !intro.isEmpty {
            paragraph(intro)
            hasBody = true
        }
        for topic in layout.shownTopics(durationMs: durationMs) {
            let points = topic.points.map(item).filter { !$0.isEmpty }
            guard !points.isEmpty else { continue }
            hasBody = true
            let name = topic.isOther ? labels.otherTopic : topic.name.map(flat).map(NotesComposer.inertParagraph)
            if let name, !name.isEmpty {
                heading(2, name)
            } else if !lines.isEmpty, lines.last != "" {
                lines.append("")
            }
            lines.append(contentsOf: points.map { "- " + $0 })
        }
        let decisions = layout.decisions.map(item).filter { !$0.isEmpty }
        if !decisions.isEmpty {
            hasBody = true
            heading(2, labels.decisionsMade)
            lines.append(contentsOf: decisions.map { "- " + $0 })
        }
        let steps = layout.nextSteps.map { step(of: $0, labels: labels) }.filter { !$0.isEmpty }
        if !steps.isEmpty {
            hasBody = true
            heading(2, labels.nextSteps)
            lines.append(contentsOf: steps.map { "- [ ] " + $0 })
        }
        let questions = layout.openQuestions.prefix(NotesLayout.maxOpenQuestions).map(item).filter { !$0.isEmpty }
        if !questions.isEmpty {
            hasBody = true
            heading(2, labels.questions)
            lines.append(contentsOf: questions.map { "- " + $0 })
        }
        if !hasBody { paragraph(labels.nothing) }
        let names = layout.participants.map(flat).filter { !$0.isEmpty && !NotesGuard.isGenericLabel($0) }
        if !names.isEmpty {
            heading(2, labels.participants)
            lines.append(NotesComposer.inertParagraph(names.joined(separator: ", ")))
        }
        return NotesMarkdown.render(lines.joined(separator: "\n"))
    }

    /// "text — osoba: X, termin: Y"; each detail only when it was said (no "unassigned" caption).
    private static func step(of step: NotesLayout.NextStep, labels: NotesComposer.Labels) -> String {
        var details: [String] = []
        if let person = step.person.map(flat), !person.isEmpty { details.append("\(labels.person): \(person)") }
        if let due = step.due.map(flat), !due.isEmpty { details.append("\(labels.due): \(due)") }
        let text = item(step.text)
        guard !text.isEmpty else { return "" }
        return details.isEmpty ? text : text + " — " + details.joined(separator: ", ")
    }

    /// One line: no checklist marker, no time.
    private static func item(_ text: String) -> String {
        var result = Substring(flat(text))
        while let match = result.prefixMatch(of: /\[[ xX]\]\s*/) { result = result[match.range.upperBound...] }
        return String(result)
    }

    /// One line of text without the transcript's times.
    private static func flat(_ text: String) -> String {
        NotesDraftComposer.withoutTimes(MarkdownText.cleaned(text, keepNewlines: false))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
