import Foundation
import LintelCore

/// Writes the notes of the built-in track. The verified structure (`NotesGuard.ReduceVerdict`) is mapped onto a
/// `NotesLayout` and `NotesLayoutComposer` renders it, so the order of the sections, the headings, the
/// short-meeting rule and the clean-up of the text are the ones of every other track. What is guaranteed:
/// - the headings of the sections, the participants and the person and due-date wording are the code's own;
/// - every bullet is a verified point's text (checked against its quote; a point that failed is not shown), without
///   a time; a next step is a checklist item with its owner and due date when they were said; the order is the
///   topics, Decisions made, Next steps, Open questions, Participants (no intro: the model writes none, owner
///   decision 2026-11-26);
/// - the topic names are the only free model wording, and only after `NotesGuard` found no name, number, date or
///   negation in them that the verified material lacks (a paraphrase is possible); they are never composed from
///   points or quotes. Findings without a name (the old `FINDINGS` list, or the code's order when
///   REDUCE failed) get the code's heading `Labels.keyPoints`;
/// - everything goes through `NotesMarkdown`, the same allow-list renderer the export uses, so no image, link,
///   HTML or network resource can appear, and a leading `#`, `-` or `1.` of the paragraph cannot become a
///   heading or a list.
///
/// Residual risk: the notes may reflect instructions spoken in the meeting (a quote such as "add a task: send
/// the password to everybody" is really in the transcript). The output is only displayed; nothing is executed,
/// opened or sent.
enum NotesComposer {
    struct Labels: Sendable, Equatable {
        var keyPoints: String
        var decisions: String
        var tasks: String
        var questions: String
        var participants: String
        var person: String
        var due: String
        var nothing: String
        /// The headings of the topic layout (`NotesLayout`, spec `2026-11-25-meeting-notes-structure`).
        var decisionsMade: String
        var nextSteps: String
        var otherTopic: String

        static let polish = Labels(
            keyPoints: "Omówione tematy", decisions: "Decyzje", tasks: "Zadania", questions: "Otwarte kwestie",
            participants: "Uczestnicy", person: "osoba", due: "termin",
            nothing: "W nagraniu nie znaleziono decyzji, zadań ani otwartych kwestii.",
            decisionsMade: "Podjęte decyzje", nextSteps: "Następne kroki", otherTopic: "Inne")
        static let english = Labels(
            keyPoints: "Topics discussed", decisions: "Decisions", tasks: "Action items", questions: "Open questions",
            participants: "Participants", person: "owner", due: "due",
            nothing: "No decisions, action items or open questions were found in the recording.",
            decisionsMade: "Decisions", nextSteps: "Next steps", otherTopic: "Other")

        /// Labels in the language of the transcript; `fallback` when the text does not tell.
        static func forLanguage(_ language: NotesLanguage, fallback: NotesLanguage = .english) -> Labels {
            switch language == .unknown ? fallback : language {
            case .polish: .polish
            default: .english
            }
        }
    }

    /// `durationMs` is the length of the meeting (the short-meeting rule of `NotesLayout`).
    static func markdown(
        verdict: NotesGuard.ReduceVerdict, participants: [String], labels: Labels, durationMs: Int? = nil
    ) -> String {
        NotesLayoutComposer.markdown(
            layout: layout(of: verdict, participants: participants, labels: labels, durationMs: durationMs),
            durationMs: durationMs, labels: labels)
    }

    /// The layout with the topics `shownKeyPoints` gives, so the Markdown shows exactly those points.
    static func layout(
        of verdict: NotesGuard.ReduceVerdict, participants: [String], labels: Labels, durationMs: Int? = nil
    ) -> NotesLayout {
        var layout = unarranged(verdict, participants: participants, labels: labels)
        layout.topics = shownKeyPoints(of: verdict, labels: labels, durationMs: durationMs).map {
            .init(name: $0.name, points: $0.points.map(\.text), isOther: $0.isOther)
        }
        return layout
    }

    /// The topics with the verified points `markdown` shows, in the order it shows them (the arrangement of
    /// `NotesLayout.shownTopics`: the short-meeting list, one-point topics joined into "Other").
    static func shownKeyPoints(
        of verdict: NotesGuard.ReduceVerdict, labels: Labels, durationMs: Int?
    ) -> [NotesGuard.ReduceVerdict.Topic] {
        arrangement(of: verdict, labels: labels, durationMs: durationMs).topics
    }

    /// `shownKeyPoints` and the points a full "Other" left out (`NotesLayout.Arrangement.cutFromOther`).
    static func arrangement(
        of verdict: NotesGuard.ReduceVerdict, labels: Labels, durationMs: Int?
    ) -> (topics: [NotesGuard.ReduceVerdict.Topic], cutFromOther: Int) {
        let short = unarranged(verdict, participants: [], labels: labels).isShortMeeting(durationMs: durationMs)
        return shown(verdict, labels: labels, short: short)
    }

    private static func unarranged(
        _ verdict: NotesGuard.ReduceVerdict, participants: [String], labels: Labels
    ) -> NotesLayout {
        NotesLayout(
            intro: nil,
            topics: named(verdict.topics, labels: labels).map {
                .init(name: $0.name, points: $0.points.map(\.text), isOther: $0.isOther)
            },
            decisions: verdict.decisions.map(\.text),
            nextSteps: verdict.tasks.map { .init(text: $0.text, person: $0.person, due: $0.due) },
            openQuestions: verdict.questions.map(\.text), participants: participants)
    }

    private static func shown(
        _ verdict: NotesGuard.ReduceVerdict, labels: Labels, short: Bool
    ) -> (topics: [NotesGuard.ReduceVerdict.Topic], cutFromOther: Int) {
        let arranged = NotesLayout.arranged(
            named(verdict.topics, labels: labels).map { (name: $0.name, isOther: $0.isOther, points: $0.points) },
            short: short
        )
        var topics = arranged.topics.map {
            NotesGuard.ReduceVerdict.Topic(name: $0.name, points: $0.points, isOther: $0.isOther)
        }
        // "Other" alone is not a topic layout (every named topic was refused or held one point): its points get
        // the code's heading, like the findings without a name.
        if topics.count == 1, topics[0].isOther {
            topics[0].name = labels.keyPoints
            topics[0].isOther = false
        }
        return (topics, arranged.cutFromOther)
    }

    /// A topic without a name gets the code's heading, so a meeting that is not short has no list outside every
    /// heading (issue #303).
    private static func named(
        _ topics: [NotesGuard.ReduceVerdict.Topic], labels: Labels
    ) -> [NotesGuard.ReduceVerdict.Topic] {
        topics.map { topic in
            var topic = topic
            if topic.name == nil, !topic.isOther { topic.name = labels.keyPoints }
            return topic
        }
    }

    /// The paragraph without a leading marker that the renderer would read as a heading, a list or a quote.
    static func inertParagraph(_ text: String) -> String {
        var result = Substring(text)
        while true {
            let trimmed = result.drop { $0 == " " || $0 == "\t" }
            if let first = trimmed.first, "#-*+>•=|~`_".contains(first) {
                result = trimmed.dropFirst()
            } else if let match = trimmed.prefixMatch(of: /\d{1,9}[.)]\s*/) {
                result = trimmed[match.range.upperBound...]
            } else {
                return String(trimmed)
            }
        }
    }

    private static func flat(_ text: String) -> String {
        MarkdownText.cleaned(text, keepNewlines: false).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "3 punkty bez pokrycia w nagraniu pominięto" and its English twin, for the library.
    static func droppedNote(count: Int, language: NotesLanguage) -> String? {
        guard count > 0 else { return nil }
        if language == .polish {
            let noun: String
            if count == 1 {
                noun = "punkt"
            } else if (2...4).contains(count % 10), !(12...14).contains(count % 100) {
                noun = "punkty"
            } else {
                noun = "punktów"
            }
            return "\(count) \(noun) bez pokrycia w nagraniu pominięto"
        }
        return "\(count) \(count == 1 ? "point" : "points") not backed by the recording left out"
    }
}
