import Foundation
import LintelSpeech
import os

/// The model the language repair decodes with.
struct RepairSpeech: Sendable {
    enum Kind: Sendable, Equatable {
        /// Pinned to the profile's dominant language; its `noSpeechProb` / `avgLogProb` are checked.
        case whisper
        /// With the script hint of the profile.
        case parakeet
    }

    let kind: Kind
    let modelID: String
    let folder: URL
    let engine: any SpeechEngine
}

/// What one repair did. Counts and a closed reason only: no text, no audio.
struct LanguageRepairReport: Equatable, Sendable {
    /// Why the stage stopped before every suspect segment was decoded again (`none` when it did not).
    enum Stop: String, Error, Sendable {
        case none
        /// The transcript, or every spool track with a suspect segment, could not be read.
        case unreadable
        /// Less than `LanguageProfile.minimumRepairSeconds` of confident speech: nothing is rewritten on a guess.
        case noProfile
        /// Neither the Whisper nor the Parakeet model is installed, or the model did not load.
        case noModel
        /// Parakeet only, and the profile's languages are written in more than one script: a decode without a
        /// hint would only repeat the live one.
        case noHint
        /// Another model held the lease for longer than `LanguageRepair.busyWait`.
        case busy
        case timeLimit
        case cancelled
    }

    var suspect = 0
    var replaced = 0
    /// Decoded again, and the new text was refused (or was the same).
    var kept = 0
    var stop = Stop.none

    /// Suspect segments that were not decoded again (busy, time limit, a `.spool` answer, unreadable audio).
    var skipped: Int { max(0, suspect - replaced - kept) }
}

/// The finalization repair of the spec (`2026-11-23-automatic-language-detection`, "Meetings, Parakeet" item 4):
/// short segments that are probably in the wrong language or script, or invented on noise, are decoded again from
/// the spool, and the new text replaces the old only when it passes every check of `SuspectSegmentPolicy` and, for
/// Whisper, the decoder's own confidence.
///
/// - The profile is rebuilt from the stored texts (no column holds it), on every path: the live meeting, a
///   meeting resumed after a crash and "Dokończ" alike.
/// - A segment longer than `SuspectSegmentPolicy.maximumSeconds` **and** `maximumWords` is never touched.
/// - One forward, decrypting pass over each track that has a suspect segment; a track without one is not read.
///   Every range is decoded as soon as its audio has passed, one at a time, so no track is held in memory.
/// - The lease is taken at `background` priority. A different model in use: wait up to `busyWait`, then skip the
///   whole stage. From the successful attempt on (loading the model included) the stage stops after `timeLimit`;
///   segments not reached keep their text.
/// - Never throws and never fails the meeting. Cancellation stops it between segments; the caller (the session)
///   then leaves the meeting `processing` with its spool, as for a cancelled diarization.
struct LanguageRepair: Sendable {
    /// How long the stage may hold the lease (tuned in step 2.5).
    static let timeLimit: Duration = .seconds(60)
    /// How long it waits for a lease that is busy with another model before it skips everything.
    static let busyWait: Duration = .seconds(60)
    /// How often it asks again while the lease is busy.
    static let busyPoll: Duration = .seconds(2)
    /// Audio added on each side of a suspect segment, cut at the neighbouring segment of the same track.
    static let padding: TimeInterval = 0.5
    /// Whisper's own "no speech" threshold (its default `no_speech_threshold`). Step 2.5 tunes it.
    static let maximumNoSpeechProb: Float = 0.6
    /// Whisper's own mean log-probability threshold (its default `logprob_threshold`). Step 2.5 tunes it.
    static let minimumAvgLogProb: Float = -1.0
    /// Nobody needs the repair's model afterwards; an idle model is replaced at once anyway.
    static let keepWarm: Duration = .seconds(30)

    let store: MeetingsStore
    /// `nil` when no usable speech model is installed.
    let speech: @Sendable () async -> RepairSpeech?
    let lease: SpeechEngineLease
    let identifier: any TextLanguageIdentifier
    /// The user's "Languages I speak", the identifier's prior when the profile is rebuilt.
    let hints: @Sendable () -> [String]
    let openTrack: @Sendable (UUID, AudioChannel) throws -> any AudioSampleSource
    let now: @Sendable () -> ContinuousClock.Instant
    let sleep: @Sendable (Duration) async throws -> Void
    /// Times the model load (real time even when a test makes `sleep` instant: the load is real concurrency).
    let loadTimer: @Sendable (Duration) async throws -> Void
    let timeLimit: Duration
    let busyWait: Duration
    let logger: Logger

    init(
        store: MeetingsStore, speech: @escaping @Sendable () async -> RepairSpeech?, lease: SpeechEngineLease = .shared,
        identifier: any TextLanguageIdentifier = NaturalLanguageIdentifier(),
        hints: @escaping @Sendable () -> [String],
        openTrack: @escaping @Sendable (UUID, AudioChannel) throws -> any AudioSampleSource,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        loadTimer: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        timeLimit: Duration = Self.timeLimit, busyWait: Duration = Self.busyWait,
        logger: Logger = Logger(subsystem: "com.lintelapp", category: "meetings")
    ) {
        self.store = store
        self.speech = speech
        self.lease = lease
        self.identifier = identifier
        self.hints = hints
        self.openTrack = openTrack
        self.now = now
        self.sleep = sleep
        self.loadTimer = loadTimer
        self.timeLimit = timeLimit
        self.busyWait = busyWait
        self.logger = logger
    }

    /// Opens a track of the meeting's spool for one forward, decrypting pass.
    static func spoolOpener(spool: SpoolStorage, keys: MeetingKeys)
        -> @Sendable (UUID, AudioChannel) throws -> any AudioSampleSource
    {
        { uuid, channel in
            guard let track = SpoolTrack(rawValue: channel.rawValue) else { throw SpoolError.notASpoolFile }
            return try SpoolReader(file: spool.file(for: uuid, track: track), meeting: uuid, track: track, keys: keys)
        }
    }

    @discardableResult
    func run(meetingID: Int64, uuid: UUID) async -> LanguageRepairReport {
        let report = await repair(meetingID: meetingID, uuid: uuid)
        logger.notice(
            "languageRepair.suspect=\(report.suspect, privacy: .public) replaced=\(report.replaced, privacy: .public) kept=\(report.kept, privacy: .public) skipped=\(report.skipped, privacy: .public) stop=\(report.stop.rawValue, privacy: .public)"
        )
        return report
    }

    // MARK: Selection

    private func repair(meetingID: Int64, uuid: UUID) async -> LanguageRepairReport {
        var report = LanguageRepairReport()
        let segments: [StoredSegment]
        do {
            segments = try store.languageSegments(meetingID: meetingID)
        } catch {
            report.stop = .unreadable
            return report
        }
        let profile = LanguageProfile.rebuilt(
            from: segments.map { ProfileSegment(text: $0.text, duration: $0.duration) }, identifier: identifier,
            hints: hints())
        guard profile.isUsableForRepair, let dominant = profile.dominant else {
            report.stop = .noProfile
            return report
        }
        let policy = SuspectSegmentPolicy(identifier: identifier)
        let suspects = Set(
            segments.filter { policy.isSuspect(ProfileSegment(text: $0.text, duration: $0.duration), profile: profile) }
                .map(\.id))
        report.suspect = suspects.count
        guard !suspects.isEmpty else { return report }

        // The tracks are opened before the model is taken, so a spool that is gone never loads one for nothing.
        var passes: [(channel: AudioChannel, reader: any AudioSampleSource, targets: [Target])] = []
        for channel in [AudioChannel.mic, .system] {
            let targets = Self.targets(in: segments.filter { $0.channel == channel }, suspects: suspects)
            guard !targets.isEmpty else { continue }
            do {
                passes.append((channel, try openTrack(uuid, channel), targets))
            } catch {
                logger.error("languageRepair: the \(channel.rawValue, privacy: .public) spool could not be opened")
            }
        }
        guard !passes.isEmpty else {
            report.stop = .unreadable
            return report
        }

        guard let setup = await speech() else {
            report.stop = .noModel
            return report
        }
        let options: SpeechRequestOptions
        switch setup.kind {
        case .whisper:
            options = SpeechRequestOptions(whisperLanguage: .pinned(dominant))
        case .parakeet:
            guard let hint = ScriptHint.hint(for: profile.scripts()) else {
                report.stop = .noHint
                return report
            }
            options = SpeechRequestOptions(scriptHint: hint)
        }

        let handle: SpeechLease
        let started: ContinuousClock.Instant
        switch await acquire(setup) {
        case .success(let acquired): (handle, started) = (acquired.lease, acquired.started)
        case .failure(let stop):
            report.stop = stop
            return report
        }
        let context = Context(
            profile: profile, policy: policy, kind: setup.kind, options: options, handle: handle,
            started: started)
        for (channel, reader, targets) in passes {
            if let stop = await pass(channel, reader: reader, targets: targets, context: context, report: &report) {
                report.stop = stop
                break
            }
        }
        await handle.release()
        return report
    }

    /// Takes the lease; a different model in use is asked again every `busyPoll` until `busyWait` is over.
    /// `started` is read right before the attempt that succeeds, so the time limit includes loading the model:
    /// the stage holds the lease for at most `timeLimit` in all.
    private func acquire(_ setup: RepairSpeech) async
        -> Result<(lease: SpeechLease, started: ContinuousClock.Instant), LanguageRepairReport.Stop>
    {
        var waited: Duration = .zero
        while true {
            if Task.isCancelled { return .failure(.cancelled) }
            let started = now()
            do {
                guard let acquired = try await boundedAcquire(setup) else { return .failure(.timeLimit) }
                return .success((acquired, started))
            } catch ModelLeaseError.busy {
                guard waited < busyWait else { return .failure(.busy) }
                do {
                    try await sleep(Self.busyPoll)
                } catch {
                    return .failure(.cancelled)
                }
                waited += Self.busyPoll
            } catch is CancellationError {
                return .failure(.cancelled)
            } catch {
                return .failure(.noModel)
            }
        }
    }

    /// Takes the lease but gives up after `timeLimit`: a model load cannot be interrupted (the first Whisper load
    /// took 143 s in the step 2.5 measurement), and `ready` must not wait for it. The load goes on in the
    /// background and the lease it ends with is released at once, so nothing stays held. `nil` = gave up.
    /// A refusal (`busy`, no model) is thrown as it is.
    private func boundedAcquire(_ setup: RepairSpeech) async throws -> SpeechLease? {
        let state = AcquireRace()
        let lease = self.lease
        let timerSleep = loadTimer
        let limit = timeLimit
        let (outcomes, continuation) = AsyncStream<AcquireRace.Outcome>.makeStream()
        let loading = Task {
            do {
                let acquired = try await lease.acquire(
                    modelID: setup.modelID, folder: setup.folder, engine: setup.engine, priority: .background,
                    keepWarm: { Self.keepWarm })
                if state.deliver() {
                    continuation.yield(.acquired(acquired))
                } else {
                    await acquired.release()
                }
            } catch {
                if state.deliver() { continuation.yield(.failed(error)) }
            }
            continuation.finish()
        }
        let timer = Task {
            try? await timerSleep(limit)
            if state.expire() { continuation.yield(.timedOut) }
            continuation.finish()
        }
        defer { timer.cancel() }
        let first: AcquireRace.Outcome? = await withTaskCancellationHandler {
            var iterator = outcomes.makeAsyncIterator()
            return await iterator.next()
        } onCancel: {
            _ = state.expire()  // a lease that arrives later is released, never delivered
            loading.cancel()
            continuation.finish()
        }
        switch first {
        case .acquired(let acquired): return acquired
        case .failed(let error): throw error
        case .timedOut: return nil
        case nil: throw CancellationError()
        }
    }

    /// Decides which of "the lease arrived" and "the time ran out" wins; the loser is dropped.
    private final class AcquireRace: @unchecked Sendable {
        enum Outcome: @unchecked Sendable {
            case acquired(SpeechLease)
            case failed(any Error)
            case timedOut
        }
        private let lock = NSLock()
        private var decided = false

        /// `true` when the caller's result is the first one.
        func deliver() -> Bool { decide() }
        func expire() -> Bool { decide() }

        private func decide() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if decided { return false }
            decided = true
            return true
        }
    }

    // MARK: Ranges

    /// A suspect segment and the audio it is decoded from, in samples.
    struct Target: Equatable, Sendable {
        let segment: StoredSegment
        let range: Range<Int>
    }

    /// The suspect segments of one track with their padded ranges, by the start of the range.
    static func targets(in track: [StoredSegment], suspects: Set<Int64>) -> [Target] {
        let ordered = track.sorted { ($0.startMs, $0.id) < ($1.startMs, $1.id) }
        var targets: [Target] = []
        var previousEnd = Int.min
        for (index, segment) in ordered.enumerated() {
            defer { previousEnd = max(previousEnd, segment.endMs) }
            guard suspects.contains(segment.id) else { continue }
            let next = index + 1 < ordered.count ? ordered[index + 1].startMs : nil
            targets.append(
                Target(segment: segment, range: paddedRange(segment, previousEnd: previousEnd, nextStart: next)))
        }
        return targets.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    /// Up to `padding` on each side, but only audio that belongs to no other segment of the track: the padding
    /// stops at the end of the one before and the start of the one after, so their words cannot enter the text.
    static func paddedRange(_ segment: StoredSegment, previousEnd: Int, nextStart: Int?) -> Range<Int> {
        let pad = Int(padding * 1_000)
        let lowerMs = min(segment.startMs, max(0, segment.startMs - pad, previousEnd))
        let upperMs = max(segment.endMs, min(segment.endMs + pad, nextStart ?? .max))
        return samples(lowerMs)..<max(samples(lowerMs), samples(upperMs))
    }

    private static func samples(_ milliseconds: Int) -> Int { milliseconds * AudioFormat.sampleRate / 1_000 }

    // MARK: Decoding

    private struct Context {
        let profile: LanguageProfile
        let policy: SuspectSegmentPolicy
        let kind: RepairSpeech.Kind
        let options: SpeechRequestOptions
        let handle: SpeechLease
        let started: ContinuousClock.Instant
    }

    /// One forward pass over a track. Returns a reason when the whole stage must stop.
    private func pass(
        _ channel: AudioChannel, reader: any AudioSampleSource, targets: [Target], context: Context,
        report: inout LanguageRepairReport
    ) async -> LanguageRepairReport.Stop? {
        var index = 0
        var position = 0
        var window: [Float] = []
        do {
            while index < targets.count, let chunk = try reader.nextChunk() {
                window += chunk
                position += chunk.count
                while index < targets.count, targets[index].range.upperBound <= position {
                    let windowStart = position - window.count
                    if let stop = await decode(
                        targets[index], window: window, windowStart: windowStart, context, &report)
                    {
                        return stop
                    }
                    index += 1
                }
                if index < targets.count {
                    let drop = min(max(0, targets[index].range.lowerBound - (position - window.count)), window.count)
                    window.removeFirst(drop)
                } else {
                    window = []
                }
            }
        } catch {
            logger.error("languageRepair: the \(channel.rawValue, privacy: .public) spool could not be read")
            return nil
        }
        // The stream ended before the last ranges did (a truncated tail): decode what exists.
        while index < targets.count {
            let windowStart = position - window.count
            if let stop = await decode(targets[index], window: window, windowStart: windowStart, context, &report) {
                return stop
            }
            index += 1
        }
        return nil
    }

    private func decode(
        _ target: Target, window: [Float], windowStart: Int, _ context: Context, _ report: inout LanguageRepairReport
    ) async -> LanguageRepairReport.Stop? {
        if Task.isCancelled { return .cancelled }
        if now() - context.started >= timeLimit { return .timeLimit }
        let from = max(0, target.range.lowerBound - windowStart)
        let to = min(window.count, target.range.upperBound - windowStart)
        guard from < to else { return nil }
        let decoded: TranscriptSegment
        do {
            switch try await context.handle.transcribe(Array(window[from..<to]), options: context.options) {
            case .transcript(let segment): decoded = segment
            case .spool: return nil
            }
        } catch is CancellationError {
            return .cancelled
        } catch {
            return nil
        }
        let text = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard accepts(text, decoded, for: target.segment, context) else {
            report.kept += 1
            return nil
        }
        do {
            try store.setSegmentText(target.segment.id, text: text)
            report.replaced += 1
        } catch {
            logger.error("languageRepair: a repaired segment could not be saved")
            report.kept += 1
        }
        return nil
    }

    /// The four conditions of the spec, and a last guard that a long segment is never rewritten.
    private func accepts(_ text: String, _ decoded: TranscriptSegment, for original: StoredSegment, _ context: Context)
        -> Bool
    {
        guard !text.isEmpty, text != original.text,
            SuspectSegmentPolicy.isShort(ProfileSegment(text: original.text, duration: original.duration))
        else { return false }
        if context.kind == .whisper {
            guard let noSpeech = decoded.noSpeechProb, let logProb = decoded.avgLogProb,
                noSpeech < Self.maximumNoSpeechProb, logProb >= Self.minimumAvgLogProb
            else { return false }
        }
        return context.policy.acceptsReplacement(text, profile: context.profile)
    }
}
