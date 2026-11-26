import Foundation
import LintelCore

/// Writes the notes from a checked `NotesDraft` (the whole-transcript track): it maps the draft onto a
/// `NotesLayout` and `NotesLayoutComposer` renders it, so the section order, the headings (`NotesComposer.Labels`),
/// the short-meeting rule and the clean-up of the text are shared with every other track. The renderer is
/// `NotesMarkdown.render`, so no link, image or HTML can appear. No times and no marks of who wrote what (owner
/// decisions 3 and 4).
///
/// Order: the title (the highest heading), the intro without a heading, the topics, Decisions made, Next steps,
/// Open questions, Participants (real names only, composed by the code from the speaker labels).
enum NotesDraftComposer {
    static func markdown(
        draft: NotesDraft, participants: [String], labels: NotesComposer.Labels, durationMs: Int? = nil
    ) -> String {
        NotesLayoutComposer.markdown(
            layout: layout(of: draft, participants: participants), title: draft.title, durationMs: durationMs,
            labels: labels)
    }

    static func layout(of draft: NotesDraft, participants: [String]) -> NotesLayout {
        NotesLayout(
            intro: draft.summary,
            topics: draft.topics.map { .init(name: $0.name, points: $0.points, isOther: $0.isOther) },
            decisions: draft.decisions.map(\.text),
            nextSteps: draft.tasks.map { .init(text: $0.text, person: $0.person, due: $0.due) },
            openQuestions: draft.open, participants: participants)
    }

    /// A time in the notations of the transcript and of the answer ("[12:34]", "~12:34", and "(12:34)" at the end of
    /// a line) is removed wherever it stands; a clock hour in a sentence ("o 17:00") is a fact and stays.
    static func withoutTimes(_ text: String) -> String {
        text.replacing(/\s*\[~?\d{1,2}(?::\d{2}){1,2}\]/, with: "")
            .replacing(/\s*~\d{1,2}(?::\d{2}){1,2}(?!\d)/, with: "")
            .replacing(/\s*\(\d{1,2}(?::\d{2}){1,2}\)\s*$/, with: "")
    }
}
