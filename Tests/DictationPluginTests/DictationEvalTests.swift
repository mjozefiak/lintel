import Foundation
import Testing

@testable import DictationPlugin
@testable import LintelSpeech

/// Offline measurement of the dictation cleanup (`scripts/dictation-eval/`). Reads raw transcripts (one JSON
/// object per line: `id`, `output`), cleans each one with the code path the app uses (`Segmenter` →
/// `BuiltInFormatter` over a real GGUF → `CleanupPrompt` → `FormatterGuard`, chunks joined as
/// `DictationSession.assembleChunks` does) and writes the same format back, so the benchmark scorer reads it
/// like an app's result. `LINTEL_DICTATION_EVAL_LEVEL=light` runs `LightCleaner` alone (no model, so
/// `LINTEL_DICTATION_EVAL_MODEL` is not needed); the default, `standard`, and `full` are the model path above, with
/// the level's prompt and guard limits (`LINTEL_DICTATION_EVAL_VOCAB` names a JSON array of vocabulary words for the
/// term check). Off by default;
/// `LINTEL_DICTATION_EVAL_INPUT` turns it on. Never prints text.
@Suite struct DictationEvalTests {
    struct Line: Codable {
        var id: String
        var app: String
        var output: String
        var latencyMs: Int
        /// The same cleaning time in microseconds: Light takes far less than a millisecond.
        var latencyUs: Int
        var wallMs: Int
        var chunks: Int
        var fellBack: Int
        var rejections: [String]
        /// One entry per chunk the model's answer was used for: what the speaker said ("none", "minor", "correction")
        /// and the output/input word ratio, so the guard's length ranges can be set from data. Numbers only.
        var accepted: [ChunkStat]

        enum CodingKeys: String, CodingKey {
            case id, app, output, chunks, rejections, accepted
            case latencyMs = "latency_ms"
            case latencyUs = "latency_us"
            case wallMs = "wall_ms"
            case fellBack = "fell_back"
        }
    }

    struct ChunkStat: Codable, Equatable {
        var kind: String
        var inWords: Int
        var ratio: Double

        enum CodingKeys: String, CodingKey {
            case kind, ratio
            case inWords = "in_words"
        }
    }

    private static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["LINTEL_DICTATION_EVAL_INPUT"] != nil))
    func cleansRawTranscripts() async throws {
        let input = try #require(Self.environment["LINTEL_DICTATION_EVAL_INPUT"])
        let output = try #require(Self.environment["LINTEL_DICTATION_EVAL_OUT"])
        let level = Self.environment["LINTEL_DICTATION_EVAL_LEVEL"] ?? "standard"
        let isLight = level == "light"
        let cleanupLevel = try #require(DictationSettings.CleanupLevel(rawValue: level), "unknown level \(level)")
        let app =
            Self.environment["LINTEL_DICTATION_EVAL_APP"]
            ?? (isLight
                ? "lintel-offline-light"
                : "lintel-offline-\(cleanupLevel == .full ? "full-" : "")v\(CleanupPrompt.version(for: cleanupLevel))")

        // A user's vocabulary (terms and variants) for the guard's term check: a JSON array of strings.
        let vocabulary: [String] =
            try Self.environment["LINTEL_DICTATION_EVAL_VOCAB"].map {
                try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
            } ?? []
        let records = try Self.records(at: URL(fileURLWithPath: input))
        let formatter: any TextFormatter
        var runtime: KeepWarmRuntime?
        if isLight {
            formatter = LightCleaner()
        } else {
            let model = try #require(Self.environment["LINTEL_DICTATION_EVAL_MODEL"])
            let warm = KeepWarmRuntime(
                runtime: LlamaRuntime(), modelURL: URL(fileURLWithPath: model), keepWarm: { .seconds(3600) })
            runtime = warm
            formatter = BuiltInFormatter(runtime: warm, level: cleanupLevel, vocabulary: { vocabulary })
            // The app loads the model while the user speaks; the measured time is the cleaning only.
            try await warm.warmUp()
        }

        var lines: [Line] = []
        for (id, raw) in records {
            let started = ContinuousClock.now
            let result = try await Self.clean(raw, with: formatter)
            let elapsed = ContinuousClock.now - started
            let milliseconds = Int(elapsed / .milliseconds(1))
            lines.append(
                Line(
                    id: id, app: app, output: result.text, latencyMs: milliseconds,
                    latencyUs: Int(elapsed / .microseconds(1)), wallMs: milliseconds, chunks: result.chunks,
                    fellBack: result.rejections.count + result.otherFallbacks, rejections: result.rejections,
                    accepted: result.accepted))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try lines.map { try encoder.encode($0) }.reduce(into: Data()) {
            $0.append($1)
            $0.append(0x0A)
        }
        try data.write(to: URL(fileURLWithPath: output), options: .atomic)
        // Free the model before the process exits: ggml asserts at exit while a Metal residency set is alive.
        await runtime?.unload()
        print("[dictation-eval] \(lines.count) records, app \(app), fallbacks \(lines.map(\.fellBack).reduce(0, +))")
    }

    /// The transcript the way a session cleans it: chunks of at most 60 words, each with the end of the
    /// previous raw chunk as context, the pieces joined by a space or a paragraph break.
    static func clean(_ raw: String, with formatter: any TextFormatter) async throws -> (
        text: String, chunks: Int, otherFallbacks: Int, rejections: [String], accepted: [ChunkStat]
    ) {
        var segmenter = Segmenter()
        let chunks = segmenter.add(raw, pauseBefore: 0) + segmenter.flush()
        var text = ""
        var paragraphBreak = false
        var previous: String?
        var otherFallbacks = 0
        var rejections: [String] = []
        var accepted: [ChunkStat] = []
        for chunk in chunks {
            let context = previous.map { String($0.suffix(300)) }
            previous = chunk.text
            let result = try await formatter.format(chunk: chunk.text, previousContext: context)
            if case .fellBack(let reason) = result.outcome {
                if case .rejected(let why) = reason {
                    rejections.append(String(describing: why))
                } else {
                    otherFallbacks += 1
                }
            }
            let piece = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.outcome == .formatted, chunk.text != result.text {
                let inWords = max(1, SpokenNumbers.wordCount(in: chunk.text))
                let kind: String
                switch Removals.kind(of: chunk.text) {
                case .none: kind = "none"
                case .minor: kind = "minor"
                case .correction: kind = "correction"
                }
                accepted.append(
                    ChunkStat(
                        kind: kind, inWords: inWords,
                        ratio: Double(SpokenNumbers.wordCount(in: piece)) / Double(inWords)))
            }
            guard !piece.isEmpty else { continue }
            if !text.isEmpty { text += paragraphBreak ? "\n\n" : " " }
            text += piece
            paragraphBreak = chunk.endsParagraph
        }
        return (text, chunks.count, otherFallbacks, rejections, accepted)
    }

    private static func records(at url: URL) throws -> [(id: String, output: String)] {
        struct Row: Decodable {
            var id: String
            var output: String
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try text.split(whereSeparator: \.isNewline).filter { !$0.allSatisfy(\.isWhitespace) }.map {
            let row = try JSONDecoder().decode(Row.self, from: Data($0.utf8))
            return (row.id, row.output)
        }
    }
}
