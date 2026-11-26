import Foundation
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

// Every text here is an invented placeholder or a generic phrase from the policy's lists; no real speech.

/// `count` invented words tagged `tag`: long enough for the profile when the segment is long too.
private func words(_ tag: String, _ count: Int = 12) -> String {
    (1...count).map { "\(tag)w\($0)" }.joined(separator: " ")
}

private let polish = LanguageGuess(code: "pl", confidence: 0.95)

/// A track whose sample `i` has the value `i`, so the engine can tell exactly which audio it was given.
private final class IndexedTrack: AudioSampleSource {
    private let total: Int
    private let position = Mutex(0)
    let sampleRate = AudioFormat.sampleRate
    var endState: AudioEndState? { position.withLock { $0 >= total } ? .complete : nil }

    init(seconds: Int) { total = seconds * AudioFormat.sampleRate }

    func nextChunk() throws -> [Float]? {
        position.withLock { position -> [Float]? in
            guard position < total else { return nil }
            let end = min(total, position + 2 * AudioFormat.sampleRate)
            defer { position = end }
            return (position..<end).map(Float.init)
        }
    }
}

/// The spool tracks the stage opened.
private final class ChannelLog: Sendable {
    private let items = Mutex<[AudioChannel]>([])
    func append(_ channel: AudioChannel) { items.withLock { $0.append(channel) } }
    var channels: [AudioChannel] { items.withLock { $0 } }
}

/// A clock the test moves by hand.
private final class RepairClock: Sendable {
    private let instant = Mutex(ContinuousClock.now)
    private let reads = Mutex(0)
    private let onRead: @Sendable (Int) -> Void

    init(onRead: @escaping @Sendable (Int) -> Void = { _ in }) { self.onRead = onRead }

    func now() -> ContinuousClock.Instant {
        let count = reads.withLock { value -> Int in
            value += 1
            return value
        }
        onRead(count)
        return instant.withLock { $0 }
    }

    func advance(_ duration: Duration) { instant.withLock { $0 = $0.advanced(by: duration) } }
}

/// The repair's speech engine: records the sample range and options of every call and answers by call number.
/// A call longer than `parkAbove` samples waits at `gate` (a transcription of someone else's on the same model).
private final class RepairEngine: SpeechEngine {
    struct Call: Equatable {
        let range: Range<Int>
        let options: SpeechRequestOptions
    }

    private let state = Mutex<(calls: [Call], loaded: Bool, parked: Bool)>(([], false, false))
    private let reply: @Sendable (Int) -> TranscriptSegment
    private let onCall: @Sendable (Int) async -> Void
    let gate = Gate()
    let parkAbove: Int

    init(
        parkAbove: Int = .max,
        reply: @escaping @Sendable (Int) -> TranscriptSegment = { index in
            TranscriptSegment(text: "naprawione u\(index)", noSpeechProb: 0.1, avgLogProb: -0.2)
        }, onCall: @escaping @Sendable (Int) async -> Void = { _ in }
    ) {
        self.parkAbove = parkAbove
        self.reply = reply
        self.onCall = onCall
    }

    var calls: [Call] { state.withLock { $0.calls } }
    var parked: Bool { state.withLock { $0.parked } }
    var isLoaded: Bool { state.withLock { $0.loaded } }

    func load(modelFolder: URL) async throws { state.withLock { $0.loaded = true } }

    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        try await transcribe(samples, options: .none)
    }

    func transcribe(_ samples: [Float], options: SpeechRequestOptions) async throws -> TranscriptSegment {
        if samples.count > parkAbove {
            state.withLock { $0.parked = true }
            await gate.pass()
            return TranscriptSegment(text: "parked")
        }
        let first = Int(samples.first ?? 0)
        let index = state.withLock { state -> Int in
            state.calls.append(Call(range: first..<(first + samples.count), options: options))
            return state.calls.count - 1
        }
        await onCall(index)
        return reply(index)
    }

    func unload() async { state.withLock { $0.loaded = false } }
}

/// A meeting in a store with a real spool (for the diarizer), segments as given and fakes for the repair.
private final class RepairRig: Sendable {
    let directory: TemporaryDirectory
    let keys: MeetingKeys
    let store: MeetingsStore
    let spool: SpoolStorage
    let uuid = UUID()
    let meetingID: Int64
    let ids: [Int64]
    let lease = SpeechEngineLease(sleep: { _ in })
    let opened = ChannelLog()

    /// Two long Polish segments (12 s of confident speech in all) are added by default, so the profile is usable.
    init(_ segments: [(AudioChannel, Int, Int, String)], identifier extra: [String: LanguageGuess] = [:]) throws {
        directory = try TemporaryDirectory()
        keys = try testKeys()
        store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: keys)
        spool = SpoolStorage(pluginDirectory: directory.url.appending(path: "meetings"))
        meetingID = try store.insertMeeting(
            uuid: SpoolStorage.name(of: uuid), startedAt: Date(), speechModelID: "test", status: .processing)
        var ids: [Int64] = []
        for (channel, start, end, text) in segments {
            ids.append(
                try store.insertSegment(meetingID: meetingID, channel: channel, startMs: start, endMs: end, text: text))
        }
        self.ids = ids
        let pair = try SpoolWriter.createPair(in: spool, meeting: uuid, keys: keys, freeSpace: { _ in .max })
        let audio = [Int16](repeating: 1_000, count: 24 * SpoolFormat.sampleRate)
        try pair.mic.append(audio)
        try pair.mic.close()
        try pair.system.append(audio)
        try pair.system.close()
        self.extra = extra
    }

    private let extra: [String: LanguageGuess]

    /// Long segments `a…` and `b…` are Polish; everything else is unknown unless the test says otherwise.
    func identifier() -> TableIdentifier {
        var answers = extra
        for tag in ["a", "b", "c"] { answers[words(tag)] = polish }
        return TableIdentifier(answers)
    }

    func text(_ index: Int) throws -> String {
        try store.languageSegments(meetingID: meetingID).first { $0.id == ids[index] }?.text ?? ""
    }

    func repair(
        engine: RepairEngine, kind: RepairSpeech.Kind = .whisper, modelInstalled: Bool = true,
        identifier: TableIdentifier? = nil, clock: RepairClock = RepairClock(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { _ in }
    ) -> LanguageRepair {
        let folder = directory.url.appending(path: "model")
        let opened = opened
        return LanguageRepair(
            store: store,
            speech: {
                modelInstalled
                    ? RepairSpeech(kind: kind, modelID: "\(kind)", folder: folder, engine: engine) : nil
            }, lease: lease, identifier: identifier ?? self.identifier(), hints: { ["pl", "en"] },
            openTrack: { _, channel in
                opened.append(channel)
                return IndexedTrack(seconds: 24)
            }, now: { clock.now() }, sleep: sleep)
    }

    func finalizer(enabled: Bool, folder: URL?, diarizer: ScriptedDiarizer, repair: LanguageRepair)
        -> MeetingFinalizer
    {
        MeetingFinalizer(
            store: store, keys: keys, spool: spool, isEnabled: { enabled }, modelFolder: { folder },
            makeDiarizer: { _ in diarizer }, languageRepair: repair)
    }
}

private func samples(_ milliseconds: Int) -> Int { milliseconds * AudioFormat.sampleRate / 1_000 }

/// Spec step 2.4: the language repair of `MeetingFinalizer`.
@Suite struct LanguageRepairTests {
    // MARK: Selection and replacement

    @Test func aSuspectSegmentIsReplacedAndLongSegmentsAndOtherTracksAreNotTouched() async throws {
        // 3 s and 4 words, confidently English: outside the profile, but too long to be suspect.
        let english = "u1 u2 u3 u4"
        let rig = try RepairRig(
            [
                (.mic, 0, 6_200, words("a")),
                (.system, 6_000, 9_000, english),
                (.mic, 6_500, 7_500, "Thank you."),
                (.mic, 7_800, 13_800, words("b")),
            ], identifier: [english: LanguageGuess(code: "en", confidence: 0.99)])
        let engine = RepairEngine()
        let report = await rig.repair(engine: engine).run(meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: 1, replaced: 1, kept: 0, stop: .none))
        #expect(try rig.text(2) == "naprawione u0")
        #expect(try rig.text(0) == words("a"))
        #expect(try rig.text(1) == english)
        #expect(try rig.text(3) == words("b"))
        // Whisper pinned to the dominant language; the padding stops at both neighbours of the microphone track
        // (6.2 s and 7.8 s), and the system segment in between does not cut it.
        #expect(
            engine.calls == [
                .init(range: samples(6_200)..<samples(7_800), options: .init(whisperLanguage: .pinned("pl")))
            ])
        // The system track has no suspect segment: it is not read.
        #expect(rig.opened.channels == [.mic])
        // The new text is what search finds.
        #expect(try !rig.store.searchSegments("naprawione", limit: 5).isEmpty)
    }

    @Test func paddingIsHalfASecondEachSideAndCutAtNeighboursAndZero() {
        let segment = StoredSegment(id: 1, channel: .mic, startMs: 5_000, endMs: 6_000, text: "x")
        #expect(
            LanguageRepair.paddedRange(segment, previousEnd: 1_000, nextStart: 9_000)
                == samples(4_500)..<samples(6_500))
        #expect(
            LanguageRepair.paddedRange(segment, previousEnd: 4_800, nextStart: 6_100)
                == samples(4_800)..<samples(6_100))
        // A neighbour that overlaps gets no padding on that side.
        #expect(
            LanguageRepair.paddedRange(segment, previousEnd: 5_200, nextStart: 5_900)
                == samples(5_000)..<samples(6_000))
        let first = StoredSegment(id: 2, channel: .mic, startMs: 200, endMs: 900, text: "x")
        #expect(LanguageRepair.paddedRange(first, previousEnd: .min, nextStart: nil) == 0..<samples(1_400))
    }

    @Test func parakeetGetsTheProfilesScriptHint() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 6_500, 7_000, "yeah"), (.mic, 8_000, 14_000, words("b")),
        ])
        // Parakeet reports no confidences; that check is Whisper's only.
        let engine = RepairEngine(reply: { _ in TranscriptSegment(text: "naprawione") })
        let report = await rig.repair(engine: engine, kind: .parakeet).run(meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(report.replaced == 1)
        #expect(engine.calls.map(\.options) == [SpeechRequestOptions(scriptHint: .latin)])
        #expect(try rig.text(1) == "naprawione")
    }

    @Test func parakeetWithAMixedScriptProfileRewritesNothing() async throws {
        let rig = try RepairRig(
            [(.mic, 0, 6_000, words("a")), (.mic, 6_500, 7_000, "Thank you."), (.mic, 8_000, 14_000, words("u"))],
            identifier: [words("u"): LanguageGuess(code: "uk", confidence: 0.95)])
        let engine = RepairEngine()
        let report = await rig.repair(engine: engine, kind: .parakeet).run(meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(report.stop == .noHint)
        #expect(engine.calls.isEmpty)
        #expect(try rig.text(1) == "Thank you.")
    }

    @Test func withoutTenSecondsOfConfidentSpeechNothingIsReadOrLoaded() async throws {
        let rig = try RepairRig([(.mic, 0, 8_000, words("a")), (.mic, 8_500, 9_000, "Thank you.")])
        let engine = RepairEngine()
        let report = await rig.repair(engine: engine).run(meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(report == LanguageRepairReport(suspect: 0, replaced: 0, kept: 0, stop: .noProfile))
        #expect(rig.opened.channels.isEmpty)
        #expect(await rig.lease.residentKey == nil)
        #expect(try rig.text(1) == "Thank you.")
    }

    @Test func withoutAModelNothingIsRewritten() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 6_500, 7_000, "Thank you."), (.mic, 8_000, 14_000, words("b")),
        ])
        let report = await rig.repair(engine: RepairEngine(), modelInstalled: false).run(
            meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(report.stop == .noModel)
        #expect(report.skipped == 1)
        #expect(try rig.text(1) == "Thank you.")
    }

    // MARK: Acceptance

    @Test func refusedReDecodesKeepTheOriginalText() async throws {
        // One suspect per refusal reason, each 0.5 s long with a 0.5 s gap.
        let replies: [TranscriptSegment] = [
            // On a hallucination list.
            TranscriptSegment(text: "Thanks for watching!", noSpeechProb: 0.1, avgLogProb: -0.2),
            // A back-channel phrase of the dominant language itself.
            TranscriptSegment(text: "Dziękuję.", noSpeechProb: 0.1, avgLogProb: -0.2),
            // Whisper says there is no speech.
            TranscriptSegment(text: "naprawione", noSpeechProb: 0.9, avgLogProb: -0.2),
            // Whisper is unsure of its words.
            TranscriptSegment(text: "naprawione", noSpeechProb: 0.1, avgLogProb: -2),
            // Whisper without its confidences.
            TranscriptSegment(text: "naprawione"),
            // A script the profile does not have.
            TranscriptSegment(text: "привіт світ", noSpeechProb: 0.1, avgLogProb: -0.2),
            // Confidently outside the profile: the identifier vetoes it.
            TranscriptSegment(text: "veto u1", noSpeechProb: 0.1, avgLogProb: -0.2),
            // Empty.
            TranscriptSegment(text: "  ", noSpeechProb: 0.1, avgLogProb: -0.2),
        ]
        var segments: [(AudioChannel, Int, Int, String)] = [(.mic, 0, 6_000, words("a"))]
        for index in replies.indices {
            let start = 7_000 + index * 1_000
            segments.append((.mic, start, start + 500, "Thank you."))
        }
        segments.append((.mic, 16_000, 22_000, words("b")))
        let rig = try RepairRig(segments, identifier: ["veto u1": LanguageGuess(code: "de", confidence: 0.95)])
        let engine = RepairEngine(reply: { replies[$0] })
        let report = await rig.repair(engine: engine).run(meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: replies.count, replaced: 0, kept: replies.count, stop: .none))
        #expect(engine.calls.count == replies.count)
        for index in replies.indices { #expect(try rig.text(index + 1) == "Thank you.") }
    }

    // MARK: Bounds

    @Test func aBusyLeaseIsAwaitedSixtySecondsThenTheStageIsSkipped() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 6_500, 7_000, "Thank you."), (.mic, 8_000, 14_000, words("b")),
        ])
        // A dictation holds another model.
        let other = try await rig.lease.acquire(
            modelID: "other", folder: rig.directory.url.appending(path: "other"), engine: RepairEngine(),
            priority: .interactive, keepWarm: { .zero })
        let waited = Mutex(Duration.zero)
        let engine = RepairEngine()
        let report = await rig.repair(engine: engine, sleep: { duration in waited.withLock { $0 += duration } }).run(
            meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: 1, replaced: 0, kept: 0, stop: .busy))
        #expect(report.skipped == 1)
        #expect(waited.withLock { $0 } == LanguageRepair.busyWait)
        #expect(engine.calls.isEmpty)
        #expect(try rig.text(1) == "Thank you.")
        await other.release()
    }

    @Test func theTimeLimitStopsTheStageAndKeepsTheRest() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 7_000, 7_500, "Thank you."), (.mic, 8_500, 9_000, "Thank you."),
            (.mic, 10_000, 10_500, "Thank you."), (.mic, 12_000, 18_000, words("b")),
        ])
        let clock = RepairClock()
        // Each decode takes 40 s: the third would start after the 60 s limit.
        let engine = RepairEngine(onCall: { _ in clock.advance(.seconds(40)) })
        let report = await rig.repair(engine: engine, clock: clock).run(meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: 3, replaced: 2, kept: 0, stop: .timeLimit))
        #expect(report.skipped == 1)
        #expect(try rig.text(1) == "naprawione u0")
        #expect(try rig.text(2) == "naprawione u1")
        #expect(try rig.text(3) == "Thank you.")
        // The lease is given back: nothing holds the model any more.
        #expect(await rig.lease.activeLeases == 0)
    }

    @Test func aSpoolAnswerSkipsOneSegmentAndTheRepairGoesOn() async throws {
        // Suspect 1 is padded to 2 s (32 000 samples), suspect 2 is cut to 0.45 s by its neighbours (7 200).
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 7_000, 8_000, "Thank you."), (.mic, 9_000, 15_000, words("b")),
            (.mic, 15_100, 15_400, "Thank you."), (.mic, 15_450, 21_000, words("c")),
        ])
        let engine = RepairEngine(parkAbove: 100_000)
        engine.gate.close()
        // Another meeting's background transcription on the same model fills the queue to 20 000 samples below its
        // limit and waits inside the engine.
        let parkedLease = try await rig.lease.acquire(
            modelID: "whisper", folder: rig.directory.url.appending(path: "model"), engine: engine,
            priority: .background, keepWarm: { .zero })
        let parked = Task {
            try await parkedLease.transcribe(
                [Float](repeating: 0, count: SpeechEngineLease.backgroundLimit - 20_000), options: .none)
        }
        #expect(await spin { engine.parked })
        // Reads: 1 when the lease is taken, 2 before suspect 1 (answered `.spool`), 3 before suspect 2: the parked
        // call may finish from then on, and suspect 2 goes after it.
        let clock = RepairClock(onRead: { if $0 == 3 { engine.gate.open() } })
        let report = await rig.repair(engine: engine, clock: clock).run(meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: 2, replaced: 1, kept: 0, stop: .none))
        #expect(report.skipped == 1)
        #expect(try rig.text(1) == "Thank you.")
        #expect(try rig.text(3) == "naprawione u0")
        #expect(engine.calls.map(\.range) == [samples(15_000)..<samples(15_450)])
        _ = try await parked.value
        await parkedLease.release()
    }

    @Test func aDictationOnAnotherModelDuringTheRepairIsBusyAndTheRepairEnds() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 7_000, 7_500, "Thank you."), (.mic, 8_500, 9_000, "Thank you."),
            (.mic, 10_000, 16_000, words("b")),
        ])
        let dictation = Mutex<[String]>([])
        let lease = rig.lease
        let folder = rig.directory.url.appending(path: "parakeet")
        let engine = RepairEngine(onCall: { _ in
            do {
                let held = try await lease.acquire(
                    modelID: "parakeet", folder: folder, engine: RepairEngine(), priority: .interactive,
                    keepWarm: { .zero })
                await held.release()
                dictation.withLock { $0.append("served") }
            } catch {
                dictation.withLock { $0.append((error as? ModelLeaseError) == .busy ? "busy" : "other") }
            }
        })
        let report = await rig.repair(engine: engine).run(meetingID: rig.meetingID, uuid: rig.uuid)

        #expect(report == LanguageRepairReport(suspect: 2, replaced: 2, kept: 0, stop: .none))
        #expect(dictation.withLock { $0 } == ["busy", "busy"])
        // Once the repair is over, the dictation gets its model.
        let after = try await lease.acquire(
            modelID: "parakeet", folder: folder, engine: RepairEngine(), priority: .interactive, keepWarm: { .zero })
        #expect(await lease.residentKey?.modelID == "parakeet")
        await after.release()
    }

    // MARK: Finalizer paths

    private static func standardRig() throws -> RepairRig {
        try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 6_500, 7_000, "Thank you."), (.system, 8_000, 14_000, words("b")),
        ])
    }

    @Test(arguments: [true, false])
    func theRepairRunsWithDiarizationOffAndWithTheSpeakerModelMissing(enabled: Bool) async throws {
        let rig = try Self.standardRig()
        let engine = RepairEngine()
        let outcome = await rig.finalizer(
            enabled: enabled, folder: nil, diarizer: ScriptedDiarizer([]), repair: rig.repair(engine: engine)
        ).run(meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(outcome == (enabled ? .fallback(.modelMissing) : .disabled))
        #expect(try rig.text(1) == "naprawione u0")
    }

    @Test func theRepairRunsAfterAFailedAndAfterASuccessfulDiarization() async throws {
        let failed = try Self.standardRig()
        let failing = ScriptedDiarizer([.failure(DiarizationError.failed), .failure(DiarizationError.failed)])
        let outcome = await failed.finalizer(
            enabled: true, folder: URL(filePath: "/models"), diarizer: failing,
            repair: failed.repair(engine: RepairEngine())
        ).run(meetingID: failed.meetingID, uuid: failed.uuid)
        #expect(outcome == .fallback(.failed))
        #expect(try failed.text(1) == "naprawione u0")

        let diarized = try Self.standardRig()
        let spans = ScriptedDiarizer([
            .success([DiarizedSpan(cluster: "S1", startMs: 0, endMs: 7_000)]),
            .success([DiarizedSpan(cluster: "S1", startMs: 8_000, endMs: 14_000)]),
        ])
        let success = await diarized.finalizer(
            enabled: true, folder: URL(filePath: "/models"), diarizer: spans,
            repair: diarized.repair(engine: RepairEngine())
        ).run(meetingID: diarized.meetingID, uuid: diarized.uuid)
        #expect(success == .diarized(speakers: 2))
        #expect(try diarized.text(1) == "naprawione u0")
    }

    @Test func theRepairDoesNotRunAfterACancelledDiarization() async throws {
        let rig = try Self.standardRig()
        let engine = RepairEngine()
        let outcome = await rig.finalizer(
            enabled: true, folder: URL(filePath: "/models"),
            diarizer: ScriptedDiarizer([.failure(CancellationError())]),
            repair: rig.repair(engine: engine)
        ).run(meetingID: rig.meetingID, uuid: rig.uuid)
        #expect(outcome == .cancelled)
        #expect(engine.calls.isEmpty)
        #expect(rig.opened.channels.isEmpty)
        #expect(try rig.text(1) == "Thank you.")
    }

    @Test func cancellationDuringTheRepairStopsItAndLeavesTheMeetingProcessing() async throws {
        let rig = try RepairRig([
            (.mic, 0, 6_000, words("a")), (.mic, 7_000, 7_500, "Thank you."), (.mic, 8_500, 9_000, "Thank you."),
            (.mic, 10_000, 16_000, words("b")),
        ])
        // The app quits while the first segment is decoded.
        let engine = RepairEngine(onCall: { _ in withUnsafeCurrentTask { $0?.cancel() } })
        let finalizer = rig.finalizer(
            enabled: false, folder: nil, diarizer: ScriptedDiarizer([]), repair: rig.repair(engine: engine))
        let stillCancelled = await Task {
            await finalizer.hook(rig.meetingID, rig.uuid)
            return Task.isCancelled
        }.value
        // The session reads this flag and leaves the meeting `processing` with its spool.
        #expect(stillCancelled)
        #expect(engine.calls.count == 1)
        #expect(try rig.text(2) == "Thank you.")
        #expect(try rig.store.status(of: rig.meetingID) == .processing)
        #expect(FileManager.default.fileExists(atPath: rig.spool.directory(for: rig.uuid).path))
        #expect(await rig.lease.activeLeases == 0)
    }

    // MARK: Resume

    @Test func aResumedMeetingRebuildsTheProfileFromItsStoredTextsAndIsRepaired() async throws {
        let rig = try Self.standardRig()
        let identifier = rig.identifier()
        let engine = RepairEngine()
        // The real spool this time: the stage reads it like after a crash.
        let repair = LanguageRepair(
            store: rig.store,
            speech: {
                RepairSpeech(
                    kind: .whisper, modelID: "whisper", folder: rig.directory.url.appending(path: "model"),
                    engine: engine)
            }, lease: rig.lease, identifier: identifier, hints: { ["pl", "en"] },
            openTrack: LanguageRepair.spoolOpener(spool: rig.spool, keys: rig.keys))
        let finalizer = rig.finalizer(enabled: false, folder: nil, diarizer: ScriptedDiarizer([]), repair: repair)
        let resumer = MeetingResumer(
            store: rig.store, keys: rig.keys, spool: rig.spool, makeVAD: { ScriptedVAD([]) }, speech: { nil },
            lease: rig.lease, finalize: finalizer.hook)
        let meeting = try #require(try rig.store.recoverableMeeting(id: rig.meetingID))

        let outcome = await resumer.resume(meeting, events: { _ in })

        #expect(outcome == .ready)
        #expect(try rig.text(1) == "naprawione u0")
        // The profile came from the stored long segments, with the user's languages as the prior.
        #expect(identifier.calls.withLock { $0 }.contains { $0.hints == ["pl", "en"] })
        #expect(engine.calls.map(\.options) == [SpeechRequestOptions(whisperLanguage: .pinned("pl"))])
        // The real audio is a constant level, so only the length tells the range: 6.0 s to 7.5 s.
        #expect(engine.calls.map(\.range.count) == [samples(7_500) - samples(6_000)])
    }
}
