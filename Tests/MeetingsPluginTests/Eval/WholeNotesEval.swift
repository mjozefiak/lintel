import Foundation
import Synchronization
import Testing

@testable import MeetingsPlugin

/// What the fact guard did to one generation of the provider track (`LINTEL_MEETING_EVAL_DUMP_REJECTIONS=1`): the
/// raw answers and the lines it removed, with their text, in the output folder only (0600). Counts are in the
/// printed output. The only file of the provider track that holds notes text besides `<name>.notes.md`.
struct WholeNotesDropReport: Codable, Equatable {
    struct Removed: Codable, Equatable {
        /// `decision`, `task`, `open`, `point` or `summary`.
        var section: String
        var text: String
    }

    var schema = 1
    var recording: String
    var generation: Int
    var droppedByRule: [String: Int]
    var personReset: Int
    var dueRemoved: Int
    var timesOmitted: Int
    var shapeStripped: Int
    var cutToLimit: Int
    var removed: [Removed]
    var answers: [String]

    /// The lines of `final` that are not in `kept`, and the summary when the guard changed it.
    static func removedLines(final: NotesDraft, kept: NotesDraft) -> [Removed] {
        var removed: [Removed] = []
        func missing(_ section: String, _ all: [String], _ keep: [String]) {
            var remaining = keep
            for text in all {
                if let index = remaining.firstIndex(of: text) {
                    remaining.remove(at: index)
                } else {
                    removed.append(Removed(section: section, text: text))
                }
            }
        }
        missing("decision", final.decisions.map(\.text), kept.decisions.map(\.text))
        missing("task", final.tasks.map(\.text), kept.tasks.map(\.text))
        missing("open", final.open, kept.open)
        missing("point", final.topics.flatMap(\.points), kept.topics.flatMap(\.points))
        if kept.summary != final.summary { removed.append(Removed(section: "summary", text: final.summary ?? "")) }
        return removed
    }
}

/// The provider track of `MeetingEvalTests` (`LINTEL_MEETING_EVAL_NOTES_PIPELINE=whole`): the saved or fresh
/// transcript goes through `WholeNotesPipeline` with the Claude Code CLI or a loopback `llama-server`.
enum WholeNotesEval {
    private static let environment = ProcessInfo.processInfo.environment

    private static func value(_ key: String) -> String? {
        let value = environment["LINTEL_MEETING_EVAL_\(key)"]
        return (value?.isEmpty ?? true) ? nil : value
    }

    private static func ms(_ value: Double) -> String { String(format: "%.1f", value) }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    static func makeGenerator() -> (generator: any HarnessGenerator, label: String)? {
        if let url = value("LLAMA_URL") {
            guard let base = URL(string: url), base.host == "127.0.0.1" else { return nil }
            let budget = Int(value("LLAMA_BUDGET") ?? "") ?? 24_000
            return (LlamaServerGenerator(base: base, inputBudgetTokens: budget), "llama-server")
        }
        let model = value("PROVIDER_MODEL") ?? "sonnet"
        return (ClaudeCLIGenerator(model: model), "claude:\(model)")
    }

    /// Runs the track `GENERATIONS` times over `rows`. The first generation fills `result.notes`.
    static func run(
        result: inout EvalResult, rows: [EvalResult.Segment], name: String, to directory: URL,
        generations: Int? = nil,
        generator makeOne: () -> (generator: any HarnessGenerator, label: String)? = { WholeNotesEval.makeGenerator() }
    ) async throws {
        let generations = max(1, generations ?? Int(value("GENERATIONS") ?? "") ?? 1)
        let utterances = rows.map { NotesUtterance(startMs: $0.startMs, speaker: $0.speaker ?? "?", text: $0.text) }
        let durationMs = Int(result.audioSeconds * 1000)
        let clock = ContinuousClock()
        for generation in 1...generations {
            guard let made = makeOne() else {
                Issue.record("LINTEL_MEETING_EVAL_LLAMA_URL must be a loopback address (127.0.0.1)")
                return
            }
            let generator = made.generator
            let footprint = FootprintSampler()
            footprint.start()
            let started = clock.now
            let notes: NotesResult
            do {
                notes = try await WholeNotesPipeline(generator: generator).run(
                    utterances: utterances, durationMs: durationMs)
            } catch {
                _ = await footprint.stop()
                throw error
            }
            let elapsed = seconds(clock.now - started)
            let peak = await footprint.stop()
            let final = generator.lastText.map { NotesDraftParser.parse($0).draft } ?? NotesDraft()
            let checked = NotesFactGuard(utterances: utterances, durationMs: durationMs).check(final)
            let draft = checked.draft
            let lines =
                draft.decisions.count + draft.tasks.count + draft.open.count
                + draft.topics.reduce(0) { $0 + $1.points.count }
            let markdown = notes.markdown ?? ""
            try EvalResultWriter.writeNotes(markdown, named: name, generation: generation, to: directory)
            if generation == 1 {
                result.notes = .init(
                    model: made.label, seconds: elapsed, peakFootprintMB: peak, status: notes.status.rawValue,
                    chunkCount: notes.chunkCount, verifiedPoints: lines, dropped: notes.droppedCount,
                    failedChunks: 0, reduceFailed: false, markdown: markdown)
            }
            let report = checked.report
            let byRule = report.droppedByRule.map { "\($0.key.rawValue):\($0.value)" }.sorted().joined(separator: ",")
            print(
                "MEETING-EVAL whole generation=\(generation) provider=\(made.label) status=\(notes.status.rawValue)"
                    + " parts=\(notes.chunkCount) calls=\(generator.callCount) lines=\(lines)"
                    + " decisions=\(draft.decisions.count) tasks=\(draft.tasks.count) topics=\(draft.topics.count)"
                    + " open=\(draft.open.count) dropped=\(report.dropped) byRule=\(byRule)"
                    + " personReset=\(report.personReset) dueRemoved=\(report.dueRemoved)"
                    + " cut=\(report.cutToLimit) notesWords=\(markdown.split(whereSeparator: \.isWhitespace).count)"
                    + " inTok=\(generator.inputTokens) outTok=\(generator.outputTokens) seconds=\(ms(elapsed))"
                    + " peakMB=\(ms(peak))")
            if value("DUMP_REJECTIONS") == "1" {
                let dump = WholeNotesDropReport(
                    recording: name, generation: generation,
                    droppedByRule: Dictionary(
                        uniqueKeysWithValues: report.droppedByRule.map { ($0.key.rawValue, $0.value) }),
                    personReset: report.personReset, dueRemoved: report.dueRemoved, timesOmitted: report.timesOmitted,
                    shapeStripped: report.shapeStripped, cutToLimit: report.cutToLimit,
                    removed: WholeNotesDropReport.removedLines(final: final, kept: draft), answers: generator.allTexts)
                let url = try EvalResultWriter.write(dump, to: directory)
                print("MEETING-EVAL whole-removed lines=\(dump.removed.count)")
                print("MEETING-EVAL wrote \(url.path)")
            }
        }
    }
}
