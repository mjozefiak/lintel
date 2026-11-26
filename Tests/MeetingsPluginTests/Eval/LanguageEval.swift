import Foundation
import LintelSpeech
import Synchronization

@testable import MeetingsPlugin

/// The language part of a meeting evaluation (spec `2026-11-23-automatic-language-detection`, "Measurement gate"):
/// what every request was sent with, when the profile settled and what the repair did. Numbers and closed codes
/// only; the text is looked at, never kept here or printed.
enum LanguageEval {
    /// The phase a request belongs to: the recording (and its replays), or the repair in `beforeReady`.
    enum Phase: Sendable { case live, repair }

    /// The closed key of one request's options: `none`, `script:<latin|cyrillic|greek>`, `whisper:pinned:<code>`,
    /// `whisper:detect`, and both joined with `+` when a request carries both (the app's options always do, the
    /// engine reads the half it needs).
    static func key(_ options: SpeechRequestOptions) -> String {
        var parts: [String] = []
        if let hint = options.scriptHint { parts.append("script:\(hint.rawValue)") }
        switch options.whisperLanguage {
        case .pinned(let code): parts.append("whisper:pinned:\(code)")
        case .detect: parts.append("whisper:detect")
        case nil: break
        }
        return parts.isEmpty ? "none" : parts.joined(separator: "+")
    }

    /// The key that matters for the engine that decoded the request: the script hint for Parakeet, the language
    /// choice for Whisper.
    static func key(_ options: SpeechRequestOptions, whisper: Bool) -> String {
        whisper
            ? key(SpeechRequestOptions(whisperLanguage: options.whisperLanguage))
            : key(SpeechRequestOptions(scriptHint: options.scriptHint))
    }

    /// The profile of a transcript replayed in the order its segments were sent (by start), as `MeetingLanguage`
    /// builds it while recording: the same identifier, hints and thresholds. `settledAtMs` is the end (audio time)
    /// of the segment that settled it, `nil` when it never did.
    static func settle(
        _ segments: [StoredSegment], identifier: any TextLanguageIdentifier, hints: [String]
    ) -> (settledAtMs: Int?, profile: LanguageProfile) {
        var profile = LanguageProfile()
        var settledAt: Int?
        for segment in segments.sorted(by: { ($0.startMs, $0.id) < ($1.startMs, $1.id) }) {
            profile.add(
                ProfileSegment(text: segment.text, duration: segment.duration), identifier: identifier, hints: hints)
            if settledAt == nil, profile.isSettled { settledAt = segment.endMs }
        }
        return (settledAt, profile)
    }

    /// The ids whose text the repair changed (the texts before and after `beforeReady`).
    static func changedIDs(before: [StoredSegment], after: [StoredSegment]) -> Set<Int64> {
        let old = Dictionary(before.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first })
        return Set(after.filter { segment in old[segment.id].map { $0 != segment.text } ?? false }.map(\.id))
    }

    /// The block of the result, from the parts the run collected.
    static func block(
        settle: (settledAtMs: Int?, profile: LanguageProfile), languages: [String], tally: RequestTally,
        repair: RepairRun?
    ) -> EvalResult.Language {
        EvalResult.Language(
            languages: languages, profileSettledAtMs: settle.settledAtMs,
            profileConfidentSeconds: settle.profile.confidentSeconds, shares: settle.profile.shares,
            requests: tally.counts(.live),
            repair: repair.map { run in
                EvalResult.Language.Repair(
                    engine: run.engine, suspect: run.report.suspect, redecoded: run.report.replaced + run.report.kept,
                    replaced: run.report.replaced, kept: run.report.kept, skipped: run.report.skipped,
                    stop: run.report.stop.rawValue, seconds: run.seconds, beforeReadySeconds: run.beforeReadySeconds,
                    peakFootprintMB: run.peakFootprintMB, requests: tally.counts(.repair),
                    changedSegments: run.changed.count)
            })
    }

    /// What the `beforeReady` hook of an evaluation saw. The segments are kept in memory for the settle replay.
    struct RepairRun: Sendable {
        var engine: String
        var report: LanguageRepairReport
        var seconds: Double
        var beforeReadySeconds: Double
        var peakFootprintMB: Double
        var before: [StoredSegment]
        var changed: Set<Int64>
    }
}

/// Counts the requests per phase and options key. No text, no audio.
final class RequestTally: Sendable {
    private struct State {
        var phase = LanguageEval.Phase.live
        var counts: [LanguageEval.Phase: [String: Int]] = [:]
    }

    private let state = Mutex(State())

    /// From now on every request counts as the repair's (the lease may hand the repair the session's engine).
    func enterRepair() { state.withLock { $0.phase = .repair } }

    func record(_ key: String) {
        state.withLock { state in state.counts[state.phase, default: [:]][key, default: 0] += 1 }
    }

    func counts(_ phase: LanguageEval.Phase) -> [String: Int] { state.withLock { $0.counts[phase] ?? [:] } }
}

/// Forwards every request to the real engine with the caller's options and counts them by key.
struct CountingEngine: SpeechEngine {
    let base: any SpeechEngine
    let tally: RequestTally
    /// Whisper reads the language choice, Parakeet the script hint.
    let isWhisper: Bool

    var isLoaded: Bool { get async { await base.isLoaded } }
    func load(modelFolder: URL) async throws { try await base.load(modelFolder: modelFolder) }
    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        try await transcribe(samples, options: .none)
    }
    func transcribe(_ samples: [Float], options: SpeechRequestOptions) async throws -> TranscriptSegment {
        tally.record(LanguageEval.key(options, whisper: isWhisper))
        return try await base.transcribe(samples, options: options)
    }
    func unload() async { await base.unload() }
}
