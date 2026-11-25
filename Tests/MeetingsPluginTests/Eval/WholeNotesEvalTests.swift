import Foundation
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// The provider track of the evaluation harness over a scripted generator: nothing is sent anywhere.
@Suite struct WholeNotesEvalTests {
    private final class Scripted: HarnessGenerator, @unchecked Sendable {
        let profile = NotesGeneratorProfile(
            strategy: .wholeTranscript, inputBudgetTokens: 100_000, promptFormat: "test")
        private let answer: String
        private let texts = Mutex<[String]>([])
        init(answer: String) { self.answer = answer }
        var allTexts: [String] { texts.withLock { $0 } }
        var lastText: String? { texts.withLock { $0.last } }
        var callCount: Int { texts.withLock { $0.count } }
        var inputTokens: Int { 10 }
        var outputTokens: Int { 5 }
        func open() async throws {}
        func release() async {}
        func generateResult(
            messages: [ChatMessage], maxTokens: Int, onPhase: (@Sendable (GenerationPhase) -> Void)?
        ) async throws -> GenerationResult {
            texts.withLock { $0.append(answer) }
            return GenerationResult(text: answer, stoppedByTokenLimit: false)
        }
    }

    private let rows = [
        EvalResult.Segment(
            track: "mic", startMs: 0, endMs: 9_000, text: "Zatwierdzamy ten budżet bez zmian.", speaker: "Anna"),
        EvalResult.Segment(
            track: "mic", startMs: 10_000, endMs: 19_000, text: "Marek wyśle ofertę do klienta w piątek.",
            speaker: "Marek"),
    ]

    private func result() -> EvalResult {
        EvalResult(
            recording: "demo", audioSeconds: 30,
            config: .init(engine: "e", language: "pl", codeVersion: "v"),
            asr: .init(processingSeconds: 1, rtf: 0.1, peakFootprintMB: 1, deferredSegments: 0, segments: rows))
    }

    /// One decision the recording backs and one task whose person and date it does not.
    private static let answer = """
        SUMMARY: Zespół omówił budżet.
        DECISION | ~00:00 | Zatwierdzono budżet bez zmian.
        DECISION | ~00:05 | Zatwierdzono premię 5000 zł dla zespołu.
        """

    @Test func runsTheTrackAndWritesTheNotesOfEveryGeneration() async throws {
        let directory = try TemporaryDirectory()
        var evaluated = result()
        try await WholeNotesEval.run(
            result: &evaluated, rows: rows, name: "demo", to: directory.url, generations: 2,
            generator: { (Scripted(answer: Self.answer), "scripted") })
        let notes = try #require(evaluated.notes)
        #expect(notes.model == "scripted" && notes.status == "ok" && !notes.markdown.isEmpty)
        #expect(notes.dropped == 1)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.url.path).sorted()
        #expect(files == ["demo.g2.notes.md", "demo.notes.md"])
        let mode =
            try FileManager.default.attributesOfItem(
                atPath: directory.url.appending(path: "demo.notes.md").path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
        #expect(
            try String(contentsOf: directory.url.appending(path: "demo.notes.md"), encoding: .utf8) == notes.markdown)
    }

    @Test func theDropReportListsTheRemovedLinesWithTheirSection() throws {
        let final = NotesDraft(
            summary: "Spotkanie.", decisions: [.init(timeMs: 0, text: "A"), .init(timeMs: 1, text: "B")],
            topics: [.init(name: nil, points: ["P", "Q"])], open: ["O"])
        var kept = final
        kept.decisions.removeFirst()
        kept.topics[0].points.removeLast()
        kept.summary = nil
        let removed = WholeNotesDropReport.removedLines(final: final, kept: kept)
        #expect(
            removed == [
                .init(section: "decision", text: "A"), .init(section: "point", text: "Q"),
                .init(section: "summary", text: "Spotkanie."),
            ])
        let directory = try TemporaryDirectory()
        let url = try EvalResultWriter.write(
            WholeNotesDropReport(
                recording: "demo", generation: 1, droppedByRule: ["names": 1], personReset: 0, dueRemoved: 0,
                timesOmitted: 0, shapeStripped: 0, cutToLimit: 0, removed: removed, answers: ["raw"]),
            to: directory.url)
        #expect(url.lastPathComponent == "demo.notes-whole.json")
        let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func aReplayedResultKeepsItsTranscriptAndNamesItsSource() throws {
        var replay = result()
        replay.config.transcriptSource = "demo.json"
        let data = try EvalResultWriter.data(for: replay)
        let decoded = try JSONDecoder().decode(EvalResult.self, from: data)
        #expect(decoded.config.transcriptSource == "demo.json" && decoded.asr.segments == rows)
        // A result without the field (every earlier one) decodes with none.
        let older = try EvalResultWriter.data(for: result())
        #expect(!String(decoding: older, as: UTF8.self).contains("transcriptSource"))
        #expect(try JSONDecoder().decode(EvalResult.self, from: older).config.transcriptSource == nil)
    }
}
