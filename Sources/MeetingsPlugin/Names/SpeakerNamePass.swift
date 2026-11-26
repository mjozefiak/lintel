import Foundation
import LintelSpeech

/// Asks the notes model which names were said in the conversation (spec `2026-11-25-meeting-speaker-names`,
/// Architecture → `SpeakerNamePass`, step 1.3). One request over the excerpts of `NameMentionExtractor`, through
/// the same generator the notes use (`NotesGenerating`: the built-in local model or the provider the user chose)
/// with the same `open()` / `release()` bookkeeping. The answer goes through `SpeakerNameParser` and
/// `NameEvidenceGuard`; only the evidence that passes the guard comes back.
///
/// The pass never throws and never blocks the notes: a failed request, the time limit (60 s), a cancellation or an
/// unusable answer all give no evidence, and the notes go on without names. It asks the model at all only when the
/// notes are on (`notesEnabled`), the user allows names from the conversation (`namesFromConversation`), the
/// meeting was diarized (`channels` keeps "Ja" / "Inni" tracks, not people) and the extractor found an excerpt.
///
/// Nothing here logs: the transcript, the names and the answer never leave this type except as `NameEvidence`, and
/// the counters of `Outcome` hold no text (for `NotesTrace`, step 1.4b).
struct SpeakerNamePass: Sendable {
    struct Conditions: Equatable, Sendable {
        /// Whether a notes job runs (`NotesService` passes `true`: the job loads the model anyway, also for a
        /// "Regenerate" with the notes switch off). Without a notes job Lintel does not load a model just for names.
        var notesEnabled: Bool
        /// `plugins.meetings.namesFromConversation` (step 1.4b adds the key; the pass only reads the value).
        var namesFromConversation: Bool
        /// A `channels` meeting has no people to name: the tracks are "Ja" and "Inni".
        var isChannelMeeting: Bool

        init(notesEnabled: Bool = true, namesFromConversation: Bool = true, isChannelMeeting: Bool = false) {
            self.notesEnabled = notesEnabled
            self.namesFromConversation = namesFromConversation
            self.isChannelMeeting = isChannelMeeting
        }
    }

    struct Configuration: Sendable {
        /// The whole request, load included: the spec's limit of the pass (spec: Risks → performance).
        var timeout: Duration = .seconds(60)
        /// The JSON answer of a whole pass, well under the model's context.
        var answerMaxTokens = 2000
        init() {}
    }

    struct Outcome: Equatable, Sendable {
        /// How the pass ended. Only `failed` says nothing about the transcript: the caller keeps the names it had.
        enum Status: String, Equatable, Sendable, Codable {
            /// The conditions keep the model out (notes off, names from the conversation off, a `channels` meeting).
            case notAsked
            /// The extractor found no excerpt: there is no name to look for, and the model was not asked.
            case noExcerpts
            /// The model answered (an empty or unusable answer included): the evidence is what passed the guard.
            case answered
            /// No answer: the writer could not be opened, the request failed, the time limit came first, the
            /// answer was cut by the token limit or the task was cancelled.
            case failed
        }

        var status: Status = .notAsked
        /// The time from the first request to its end, the open of the writer included; 0 when it was not asked.
        var elapsedMs = 0
        /// The evidence that passed the guard, `source = .transcript`.
        var accepted: [NameEvidence] = []
        /// How many excerpts went to the model (0 when it was not asked).
        var excerpts = 0
        /// How many excerpts the extractor's limit cut.
        var droppedExcerpts = 0
        /// How many name entries the answer held before the guard.
        var answers = 0
        /// The guard's refusals per reason.
        var rejections: [NameEvidenceGuard.Rejection: Int] = [:]
    }

    let generator: any NotesGenerating
    /// The names the platform or the calendar already knows; the extractor uses them to find candidates, and they
    /// never go to the model (spec: the participant list stays on this Mac).
    var knownNames: [String]
    var configuration: Configuration
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> ContinuousClock.Instant

    init(
        generator: any NotesGenerating, knownNames: [String] = [], configuration: Configuration = Configuration(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.generator = generator
        self.knownNames = knownNames
        self.configuration = configuration
        self.sleep = sleep
        self.now = now
    }

    /// The evidence found for the transcript, or none. Never throws.
    func run(segments: [NameSegment], conditions: Conditions) async -> Outcome {
        // One cleaning for the extractor, the model and the guard, so a quote the model copied from the excerpt is
        // the same text the guard looks for (the indices and the times stay as they were).
        let segments = segments.map { segment in
            NameSegment(
                speaker: SpeakerNamePrompt.sanitized(segment.speaker), startMs: segment.startMs,
                endMs: segment.endMs, text: SpeakerNamePrompt.sanitized(segment.text))
        }
        let extraction = NameMentionExtractor(knownNames: knownNames).excerpts(from: segments)
        var outcome = Outcome(droppedExcerpts: extraction.droppedExcerpts)
        guard conditions.notesEnabled, conditions.namesFromConversation, !conditions.isChannelMeeting else {
            return outcome
        }
        guard !extraction.excerpts.isEmpty else {
            outcome.status = .noExcerpts
            return outcome
        }
        outcome.excerpts = extraction.excerpts.count
        outcome.status = .failed

        let messages = SpeakerNamePrompt.messages(excerpts: extraction.excerpts)
        let generator = generator
        let maxTokens = configuration.answerMaxTokens
        let started = now()
        let answer: String?
        do {
            answer =
                try await NotesDeadline.run(limit: configuration.timeout, sleep: sleep) { report in
                    // The pass has no queue phase of its own: the whole request, the open of the writer (a model load,
                    // the wait for a busy model) included, counts against the limit.
                    report(.running)
                    // The operation releases what it opened on every path, also when the limit already gave up on it:
                    // a load that ignores cancellation still ends here and must not keep the model.
                    do {
                        try await generator.open()
                        try Task.checkCancellation()
                        let generated = try await generator.generateResult(
                            messages: messages, maxTokens: maxTokens, onPhase: nil)
                        await generator.release()
                        // An answer cut by the token limit is no JSON array: never trusted.
                        return generated.stoppedByTokenLimit ? nil : generated.text
                    } catch {
                        await generator.release()
                        throw error
                    }
                } ?? nil
        } catch {
            answer = nil
        }
        outcome.elapsedMs = Self.milliseconds(now() - started)
        guard let text = answer, !Task.isCancelled else { return outcome }
        outcome.status = .answered
        let proposals = SpeakerNameParser.proposals(from: text)
        outcome.answers = proposals.count
        let checked = NameEvidenceGuard(segments: segments).check(proposals)
        outcome.accepted = checked.accepted
        outcome.rejections = checked.rejections
        return outcome
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return max(0, Int(seconds) * 1000 + Int(attoseconds / 1_000_000_000_000_000))
    }
}
