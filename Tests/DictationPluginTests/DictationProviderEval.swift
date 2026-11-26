import AVFoundation
import Foundation
import LintelSpeech
import Synchronization
import Testing

@testable import DictationPlugin
@testable import LintelProviders

/// Phase 4 of the cleanup levels spec (`2026-11-25-dictation-cleanup-levels`): the measurement of the external provider
/// as a cleanup source, before any product code exists. Every chunk goes through `ProviderRunner.run` (the isolation
/// check of the argv, the consumer's authorization before the start, the FIFO `ProviderGate`), with the level's
/// `CleanupPrompt` and the same `FormatterGuard` the app uses. Nothing here is part of the product: the feature id,
/// the prompt serialisation and the replay of a session live in the tests until Phase 5 builds `ProviderFormatter`.
enum ProviderEval {
    /// The feature id Phase 5 adds to `LintelProviders` (`ProviderFeatureID.dictationCleanup`). The eval builds it
    /// from its raw value so `LintelProviders` stays unchanged.
    static let feature = ProviderFeatureID(rawValue: "dictation.cleanup")

    /// The speaking rate used when no recording gives an item's length: 150 words a minute.
    static let estimatedMillisecondsPerWord = 400

    /// The limit of one request in the eval. Generous on purpose: the eval measures the tail, it does not cut it; the
    /// release limits of the spec (Standard 2 s, Full 6 s) are applied by `provider_summary.py` afterwards.
    static let requestTimeout: Duration = .seconds(60)

    /// One chunk of a replayed session: its text, the end of the previous raw chunk as context (300 characters, as
    /// `DictationSession.startFormatting`), and when the session would hand it to the formatter.
    struct PlannedChunk: Sendable, Equatable {
        var text: String
        var context: String?
        /// Milliseconds from the start of speech.
        var submitMs: Int
        var endsParagraph: Bool
    }

    struct Plan: Sendable, Equatable {
        var chunks: [PlannedChunk]
        /// The key release: the end of the last speech segment, in milliseconds from the start of speech.
        var releaseMs: Int
    }

    /// The chunks of one dictation and the times a session would start cleaning them. The raw transcripts carry no
    /// pauses, so the words are spread evenly over the recording (`audioMs`): a chunk the segmenter closes while the
    /// user speaks (more than 60 words) starts when its last word was said; the chunks `Segmenter.flush` returns start
    /// at the release, which is what the session does with the rest of the text. The first is optimistic by one speech
    /// segment and its recognition; the last one, which decides the latency from the release, is what the app does.
    static func plan(raw: String, audioMs: Int) -> Plan {
        var segmenter = Segmenter()
        let early = segmenter.add(raw, pauseBefore: 0)
        let late = segmenter.flush()
        let total = max(1, FormatterGuard.words(in: raw))
        var said = 0
        var previous: String?
        var chunks: [PlannedChunk] = []
        for (chunk, atRelease) in early.map({ ($0, false) }) + late.map({ ($0, true) }) {
            said += FormatterGuard.words(in: chunk.text)
            let submit = atRelease ? audioMs : audioMs * min(said, total) / total
            chunks.append(
                PlannedChunk(
                    text: chunk.text, context: previous.map { String($0.suffix(300)) }, submitMs: submit,
                    endsParagraph: chunk.endsParagraph))
            previous = chunk.text
        }
        return Plan(chunks: chunks, releaseMs: audioMs)
    }

    /// The length of a dictation when no recording is given: `estimatedMillisecondsPerWord` a word.
    static func estimatedAudioMs(of raw: String) -> Int {
        max(1, FormatterGuard.words(in: raw)) * estimatedMillisecondsPerWord
    }

    /// The length of `<id>.wav` (or `.flac`, `.m4a`) in `folder`, or `nil`.
    static func audioMs(id: String, in folder: URL) -> Int? {
        for ext in ["wav", "flac", "m4a"] {
            let url = folder.appending(path: "\(id).\(ext)")
            guard let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 else { continue }
            return Int(Double(file.length) / file.fileFormat.sampleRate * 1000)
        }
        return nil
    }

    // MARK: one chunk

    enum Outcome: Sendable, Equatable {
        case formatted
        /// The guard refused the answer; the reason as `FormatterGuard.Reason` prints it.
        case rejected(String)
        /// No usable answer from the provider: a `ProviderError` code (`failed.rateLimited`, `timedOut`, ...).
        case providerFailed(String)
    }

    struct Answer: Sendable, Equatable {
        var text: String
        var outcome: Outcome
        var exactModel: String?
    }

    /// The level's messages for a command-line provider: the system prompt goes to argv, the examples and the
    /// transcript to stdin, flattened with Meetings' `cli1` rule (`ProviderPromptSerializer`, copied here because a
    /// plugin's tests cannot import another plugin). Phase 5 decides the format of `ProviderFormatter`.
    static func messages(chunk: String, context: String?, level: DictationSettings.CleanupLevel) -> [ChatMessage] {
        let chat = CleanupPrompt.messages(transcript: chunk, context: context, level: level)
        let system = chat.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        let input = chat.filter { $0.role != "system" }.map { message -> String in
            let role = message.role == "assistant" ? "assistant" : "user"
            return "<\(role)>\n\(strippingBlockMarkers(message.content))\n</\(role)>"
        }.joined(separator: "\n")
        return [ChatMessage(role: "system", content: system), ChatMessage(role: "user", content: input)]
    }

    private static func strippingBlockMarkers(_ text: String) -> String {
        var result = text
        while true {
            let next = result.replacing(/(?i)<\s*\/?\s*(?:user|assistant)\b[^<>]*>/, with: "")
            if next == result { return result }
            result = next
        }
    }

    /// One chunk through the provider: the answer checked by the level's guard, or the raw chunk with the reason.
    /// Never throws: a provider failure is an outcome, counted apart from the guard's rejections.
    static func format(
        _ chunk: PlannedChunk, level: DictationSettings.CleanupLevel, model: String, runner: ProviderRunner,
        authorization: @escaping ProviderAuthorization = { .allowed }
    ) async -> Answer {
        let request = ProviderRequest(
            feature: feature, model: model,
            messages: messages(chunk: chunk.text, context: chunk.context, level: level), timeout: requestTimeout)
        let exact = Mutex<String?>(nil)
        do {
            let result = try await runner.run(request, authorization: authorization) { id in
                exact.withLock { $0 = id }
            }
            let model = exact.withLock { $0 }
            if result.stoppedByTokenLimit {
                return Answer(text: chunk.text, outcome: .providerFailed("truncated"), exactModel: model)
            }
            switch FormatterGuard.check(input: chunk.text, output: result.text, level: level) {
            case .accepted(let text):
                return Answer(text: text, outcome: .formatted, exactModel: model)
            case .rejected(let reason):
                return Answer(text: chunk.text, outcome: .rejected(String(describing: reason)), exactModel: model)
            }
        } catch {
            return Answer(text: chunk.text, outcome: .providerFailed(code(of: error)), exactModel: nil)
        }
    }

    /// A closed code for an error: the case name, with the provider's closed failure or denial after a dot.
    static func code(of error: any Error) -> String {
        switch error {
        case ProviderError.failed(let failure): "failed.\(failure.rawValue)"
        case ProviderError.notAuthorized(let denial): "notAuthorized.\(denial.rawValue)"
        case ProviderError.isolationProblem: "isolationProblem"
        case let error as ProviderError: String(describing: error)
        case is CancellationError: "cancelled"
        default: "other"
        }
    }

    // MARK: one dictation

    struct ChunkResult: Sendable, Equatable {
        var chunk: PlannedChunk
        var answer: Answer
        /// From the replay's start (the first chunk's submit time) to the hand-over and to the answer.
        var submitted: Duration
        var finished: Duration
    }

    struct ItemResult: Sendable, Equatable {
        var text: String
        var chunks: [ChunkResult]
        /// From the key release to the last chunk back: what the user waits for after letting go of the key.
        var fromRelease: Duration
        /// From the first chunk's hand-over to the last chunk back.
        var wall: Duration
    }

    /// Replays a session on `clock`: every chunk is handed to `format` at its time (relative to the first one, so
    /// the eval does not wait through the speech before the first chunk), the requests run concurrently as the
    /// session's tasks do and queue in the provider's gate, and the pieces are joined as `assembleChunks` does.
    static func replay<C: Clock>(
        _ plan: Plan, clock: C, format: @escaping @Sendable (PlannedChunk) async -> Answer
    ) async -> ItemResult where C.Duration == Duration {
        guard let first = plan.chunks.first?.submitMs else {
            return ItemResult(text: "", chunks: [], fromRelease: .zero, wall: .zero)
        }
        let origin = clock.now
        let results = await withTaskGroup(of: (Int, ChunkResult).self) { group in
            for (index, chunk) in plan.chunks.enumerated() {
                group.addTask {
                    try? await clock.sleep(
                        until: origin.advanced(by: .milliseconds(chunk.submitMs - first)), tolerance: nil)
                    let submitted = origin.duration(to: clock.now)
                    let answer = await format(chunk)
                    return (
                        index,
                        ChunkResult(
                            chunk: chunk, answer: answer, submitted: submitted, finished: origin.duration(to: clock.now)
                        )
                    )
                }
            }
            var collected: [(Int, ChunkResult)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        var text = ""
        var paragraphBreak = false
        for result in results {
            let piece = result.answer.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !piece.isEmpty else { continue }
            if !text.isEmpty { text += paragraphBreak ? "\n\n" : " " }
            text += piece
            paragraphBreak = result.chunk.endsParagraph
        }
        let wall = results.map(\.finished).max() ?? .zero
        let release = Duration.milliseconds(plan.releaseMs - first)
        return ItemResult(text: text, chunks: results, fromRelease: max(.zero, wall - release), wall: wall)
    }
}

extension Duration {
    var wholeMilliseconds: Int { Int((self / .milliseconds(1)).rounded()) }
}

/// The live measurement (`scripts/dictation-eval/run.sh --source provider`). Off by default: it needs
/// `LINTEL_DICTATION_EVAL_INPUT`, `LINTEL_DICTATION_EVAL_SOURCE=provider` and `LINTEL_DICTATION_EVAL_PROVIDER=claude-code`,
/// and it starts the real Claude Code CLI, which sends every chunk to Anthropic. Feed it public text only (FLEURS):
/// the owner's corpus needs the owner's explicit consent (spec A14). Never prints text: counts only.
@Suite struct DictationProviderEvalRun {
    struct Line: Codable {
        var id: String
        var app: String
        var output: String
        /// The latency from the key release (the same as `releaseMs`): the number the benchmark scorer reads.
        var latencyMs: Int
        var releaseMs: Int
        var wallMs: Int
        var audioMs: Int
        var audioEstimated: Bool
        var chunks: Int
        /// The time of each chunk's request, from its hand-over (queue in the gate included) to the answer.
        var chunkMs: [Int]
        var fellBack: Int
        var rejections: [String]
        var providerFailures: [String]
        var accepted: [DictationEvalTests.ChunkStat]
        var source: String
        var level: String
        var promptVersion: Int
        var providerModel: String
        var exactModel: String?

        enum CodingKeys: String, CodingKey {
            case id, app, output, chunks, rejections, accepted, source, level
            case latencyMs = "latency_ms"
            case releaseMs = "release_ms"
            case wallMs = "wall_ms"
            case audioMs = "audio_ms"
            case audioEstimated = "audio_estimated"
            case chunkMs = "chunk_ms"
            case fellBack = "fell_back"
            case providerFailures = "provider_failures"
            case promptVersion = "prompt_version"
            case providerModel = "provider_model"
            case exactModel = "exact_model"
        }
    }

    private static let environment = ProcessInfo.processInfo.environment

    /// Stop after this many dictations in a row whose every chunk failed at the provider: a run without a login or
    /// over the limit should not spend the account on the rest of the set.
    static let consecutiveFailureLimit = 5

    @Test(
        .enabled(
            if: environment["LINTEL_DICTATION_EVAL_INPUT"] != nil
                && environment["LINTEL_DICTATION_EVAL_SOURCE"] == "provider"
                && environment["LINTEL_DICTATION_EVAL_PROVIDER"] == ProviderID.claudeCode.rawValue))
    func cleansWithProvider() async throws {
        let input = try #require(Self.environment["LINTEL_DICTATION_EVAL_INPUT"])
        let output = try #require(Self.environment["LINTEL_DICTATION_EVAL_OUT"])
        let model = try #require(Self.environment["LINTEL_DICTATION_EVAL_PROVIDER_MODEL"], "set the provider model")
        try #require(ProviderDescriptor.isValidModelID(model), "not a model id")
        let levelName = Self.environment["LINTEL_DICTATION_EVAL_LEVEL"] ?? "standard"
        let level = try #require(DictationSettings.CleanupLevel(rawValue: levelName), "unknown level \(levelName)")
        try #require(level == .standard || level == .full, "only Standard and Full use a source")
        let version = CleanupPrompt.version(for: level)
        let app = Self.environment["LINTEL_DICTATION_EVAL_APP"] ?? "lintel-provider-\(model)-\(levelName)-v\(version)"
        let audioFolder = Self.environment["LINTEL_DICTATION_EVAL_AUDIO_DIR"].map { URL(fileURLWithPath: $0) }

        let caches = FileManager.default.temporaryDirectory.appending(path: "dictation-provider-eval-\(UUID())")
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: caches) }
        let runner = ProviderRunner(
            system: .live(homeDirectory: FileManager.default.homeDirectoryForCurrentUser), cachesDirectory: caches,
            gate: ProviderGate())
        // Content-free probes first: a CLI that is missing or not signed in fails here, before any text leaves.
        let status = await runner.report(of: .claudeCode)
        try #require(status.status == .ready, "provider status \(status.status.rawValue)")

        let records = try DictationEvalTests.records(at: URL(fileURLWithPath: input))
        var lines: [Line] = []
        var failedInARow = 0
        for (id, raw) in records {
            let measured = audioFolder.flatMap { ProviderEval.audioMs(id: id, in: $0) }
            let audioMs = measured ?? ProviderEval.estimatedAudioMs(of: raw)
            let plan = ProviderEval.plan(raw: raw, audioMs: audioMs)
            let item = await ProviderEval.replay(plan, clock: ContinuousClock()) { chunk in
                await ProviderEval.format(chunk, level: level, model: model, runner: runner)
            }
            lines.append(
                Self.line(
                    id: id, app: app, item: item, audioMs: audioMs, estimated: measured == nil, level: levelName,
                    version: version, model: model))
            let allFailed =
                !item.chunks.isEmpty
                && item.chunks.allSatisfy { if case .providerFailed = $0.answer.outcome { true } else { false } }
            failedInARow = allFailed ? failedInARow + 1 : 0
            if failedInARow >= Self.consecutiveFailureLimit {
                Issue.record("\(failedInARow) dictations in a row failed at the provider; stopped after \(lines.count)")
                break
            }
        }

        try DictationEvalTests.write(lines, to: URL(fileURLWithPath: output))
        let failures = lines.map(\.providerFailures.count).reduce(0, +)
        let rejections = lines.map(\.rejections.count).reduce(0, +)
        print(
            "[dictation-eval] \(lines.count) records, app \(app), provider failures \(failures), rejections \(rejections)"
        )
    }

    static func line(
        id: String, app: String, item: ProviderEval.ItemResult, audioMs: Int, estimated: Bool, level: String,
        version: Int, model: String
    ) -> Line {
        var rejections: [String] = []
        var failures: [String] = []
        var accepted: [DictationEvalTests.ChunkStat] = []
        for result in item.chunks {
            switch result.answer.outcome {
            case .rejected(let reason): rejections.append(reason)
            case .providerFailed(let code): failures.append(code)
            case .formatted:
                guard result.chunk.text != result.answer.text else { break }
                accepted.append(DictationEvalTests.stat(chunk: result.chunk.text, piece: result.answer.text))
            }
        }
        let release = item.fromRelease.wholeMilliseconds
        return Line(
            id: id, app: app, output: item.text, latencyMs: release, releaseMs: release,
            wallMs: item.wall.wholeMilliseconds, audioMs: audioMs, audioEstimated: estimated, chunks: item.chunks.count,
            chunkMs: item.chunks.map { ($0.finished - $0.submitted).wholeMilliseconds },
            fellBack: rejections.count + failures.count, rejections: rejections, providerFailures: failures,
            accepted: accepted, source: "provider", level: level, promptVersion: version, providerModel: model,
            exactModel: item.chunks.compactMap(\.answer.exactModel).first)
    }
}
