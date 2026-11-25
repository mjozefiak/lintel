import Foundation
import Testing

@testable import MeetingsPlugin

/// The whole-transcript track in the topic layout (prompt `whole2`, spec `2026-11-25-meeting-notes-structure`, F1).
@Suite struct WholeNotesLayoutTests {
    private static let utterances: [NotesUtterance] = (0..<30).map {
        NotesUtterance(
            startMs: $0 * 60_000, speaker: $0.isMultiple(of: 2) ? "Anna" : "Marek",
            text: "Omawiamy budżet i harmonogram projektu w tym kwartale, punkt \($0).")
    }

    private func check(_ answer: String, durationMs: Int? = 30 * 60_000) -> (
        draft: NotesDraft, report: NotesFactGuard.Report
    ) {
        NotesFactGuard(utterances: Self.utterances, durationMs: durationMs).check(NotesDraftParser.parse(answer).draft)
    }

    // MARK: Parser

    @Test func theParserReadsIntroAndTheOlderSummary() {
        #expect(NotesDraftParser.parse("INTRO: Wstęp.\nPOINT | A.").draft.summary == "Wstęp.")
        #expect(NotesDraftParser.parse("SUMMARY: Stary wstęp.\nPOINT | A.").draft.summary == "Stary wstęp.")
        #expect(NotesDraftParser.parse("INTRO: Pierwszy.\nSUMMARY: Drugi.").draft.summary == "Pierwszy.")
        #expect(NotesDraftParser.parse("INTRO:").lastLineMalformed)
        #expect(NotesDraftParser.parse("INTRO: Tylko wstęp.").isUsable)
        let draft = NotesDraftParser.parse("INTRO: I.\nTOPIC: X\nPOINT | P.\nOPEN | O?").draft
        #expect(draft.lines.hasPrefix("INTRO: I."))
        #expect(NotesDraftParser.parse(draft.lines).draft == draft)
    }

    // MARK: Limits

    @Test func theLimitsOfTheLayoutHold() {
        let decisions = (1...12).map { "DECISION | ~00:10 | Decyzja numer \($0) o budżecie." }
        let tasks = (1...18).map { "TASK | ~00:10 | - | - | Zadanie numer \($0) o budżecie." }
        let points = (1...9).map { "POINT | Punkt numer \($0) o harmonogramie." }
        let answer = (decisions + tasks + ["TOPIC: Harmonogram"] + points).joined(separator: "\n")
        let checked = check(answer)
        #expect(checked.draft.decisions.count == NotesFactGuard.maxDecisions && NotesFactGuard.maxDecisions == 10)
        #expect(checked.draft.tasks.count == NotesFactGuard.maxTasks && NotesFactGuard.maxTasks == 15)
        #expect(checked.draft.topics.first?.points.count == NotesFactGuard.maxPointsPerTopic)
        #expect(NotesFactGuard.maxPointsPerTopic == 6 && NotesFactGuard.maxSummarySentences == 3)
        #expect(checked.report.cutToLimit == 2 + 3 + 3)
        #expect(checked.report.dropped == 0)
    }

    @Test func theNumberOfTopicsFollowsTheMeetingLength() {
        let topics = (1...12).flatMap {
            ["TOPIC: Temat \($0)", "POINT | Punkt A \($0) o budżecie.", "POINT | Punkt B \($0) o budżecie."]
        }
        let answer = topics.joined(separator: "\n")
        #expect(check(answer, durationMs: 24 * 60_000).draft.topics.count == 4)
        #expect(check(answer, durationMs: 55 * 60_000).draft.topics.count == 9)
        #expect(check(answer, durationMs: 90 * 60_000).draft.topics.count == 10)
        #expect(check(answer, durationMs: 90 * 60_000).report.cutToLimit == 2)
        #expect(NotesFactGuard(utterances: Self.utterances, durationMs: 38 * 60_000).maxTopics == 6)
    }

    @Test func theIntroHasAtMostThreeSentencesAndSeventyWords() {
        let sentences =
            "INTRO: Pierwsze zdanie o budżecie. Drugie zdanie o budżecie. Trzecie zdanie o budżecie. Czwarte zdanie o budżecie."
        let three = check(sentences).draft.summary
        #expect(three == "Pierwsze zdanie o budżecie. Drugie zdanie o budżecie. Trzecie zdanie o budżecie.")
        let long = (1...40).map { _ in "budżet" }.joined(separator: " ")
        let wordy = check("INTRO: Zaczynamy \(long). Potem \(long). I jeszcze coś o budżecie.\nPOINT | A.").draft
            .summary
        #expect((wordy ?? "").split(separator: " ").count <= NotesFactGuard.maxSummaryWords)
        let huge = (1...100).map { _ in "budżet" }.joined(separator: " ")
        let cut = check("INTRO: \(huge).\nPOINT | A.").draft.summary
        #expect((cut ?? "").split(separator: " ").count == NotesFactGuard.maxSummaryWords)
    }

    // MARK: Topic names

    @Test func aTopicNameWithAnUnknownPersonMovesItsPointsToOther() {
        let answer = """
            TOPIC: Budżet według Zenona
            POINT | Budżet na ten kwartał omówiono.
            POINT | Harmonogram projektu omówiono.
            TOPIC: Harmonogram
            POINT | Harmonogram projektu w tym kwartale.
            POINT | Punkt 3 o budżecie.
            POINT | Punkt 4 o budżecie.
            POINT | Punkt 5 o budżecie.
            """
        let checked = check(answer)
        #expect(checked.report.topicNameRefused == 1)
        #expect(checked.report.dropped == 0, "a refused name is not a dropped line")
        #expect(checked.draft.topics.map(\.name) == ["Harmonogram", nil])
        let other = checked.draft.topics.last
        #expect(other?.isOther == true && other?.points.count == 2)
        let markdown = NotesDraftComposer.markdown(
            draft: checked.draft, participants: [], labels: .polish, durationMs: 40 * 60_000)
        #expect(markdown.contains("Inne\n") && markdown.contains("Harmonogram\n"))
        #expect(!markdown.contains("Zenon"))
    }

    @Test func aTopicNameIsCheckedStrictlyNotLikeATitle() {
        // A title that looks like a title may use capitalised words; a topic name may not.
        let checked = check(
            "TITLE: Plan Wielkiej Reorganizacji Firmy\nTOPIC: Plan Wielkiej Reorganizacji Firmy\nPOINT | Budżet omówiono."
        )
        #expect(checked.draft.title != nil)
        #expect(checked.report.topicNameRefused == 1)
    }

    // MARK: Prompt

    @Test func theCodeGivesTheNumberOfTopicsToThePrompt() {
        let text = WholeNotesPrompt.messages(transcript: "[00:01] Ala: Tekst.", maxTopics: 9).first?.content ?? ""
        #expect(text.contains("at most 9 TOPIC lines") && text.contains("2 to 6 POINT lines"))
        #expect(text.contains("INTRO:") && !text.contains("SUMMARY:"))
        let merge = WholeNotesPrompt.mergeMessages(drafts: ["INTRO: A."], maxTopics: 4).first?.content ?? ""
        #expect(merge.contains("at most 4 TOPIC lines"))
        #expect(WholeNotesPrompt.version == "whole2")
    }

    @Test func theExampleAnswerIsInTheNewFormatAndPassesTheParser() {
        let parsed = NotesDraftParser.parse(WholeNotesPrompt.exampleAnswer)
        #expect(parsed.isUsable && parsed.skippedLines == 0)
        #expect(parsed.draft.topics.count == 2 && parsed.draft.topics.allSatisfy { (2...6).contains($0.points.count) })
        #expect(WholeNotesPrompt.exampleAnswer.contains("INTRO:"))
    }

    // MARK: Pipeline

    @Test func aMeetingOfThirtyEightMinutesAsksForSixTopicsAndWritesTheLayout() async throws {
        let answer = """
            TITLE: Budżet
            INTRO: Omawiano budżet i harmonogram.
            TOPIC: Budżet
            POINT | Budżet na ten kwartał omówiono.
            POINT | Harmonogram projektu w tym kwartale.
            DECISION | ~00:10 | Budżet zostaje bez zmian.
            TASK | ~00:20 | Anna | - | Opisać harmonogram projektu.
            OPEN | Czy harmonogram się zmieni?
            """
        let generator = ScriptedGenerator.answering(answer)
        let result = try await WholeNotesPipeline(generator: generator).run(
            utterances: Self.utterances, durationMs: 38 * 60_000)
        #expect(generator.calls.first?.first?.content.contains("at most 6 TOPIC lines") == true)
        #expect(result.promptVersion == "whole2")
        let markdown = try #require(result.markdown)
        let headings = markdown.split(separator: "\n").filter { $0.hasPrefix("#") }.map {
            $0.drop { $0 == "#" || $0 == " " }
        }
        #expect(
            headings.map(String.init) == [
                "Budżet", "Podjęte decyzje", "Następne kroki", "Otwarte kwestie", "Uczestnicy",
            ])
        #expect(markdown.contains("Omawiano budżet i harmonogram."))
    }
}
