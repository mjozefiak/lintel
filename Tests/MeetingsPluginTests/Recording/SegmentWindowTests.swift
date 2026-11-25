import Foundation
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

@Suite struct SegmentWindowTests {
    @Test func widensBothSidesByTheRolls() {
        let range = SegmentWindow.widened(
            1_000..<2_000, notBefore: 0, received: 10_000, preRoll: 300, postRoll: 200)
        #expect(range == 700..<2_200)
    }

    @Test func neverReachesBackIntoAudioAlreadySent() {
        let range = SegmentWindow.widened(
            1_000..<2_000, notBefore: 900, received: 10_000, preRoll: 300, postRoll: 0)
        #expect(range == 900..<2_000)
    }

    @Test func aPreviousPostRollThatOverranTheStartDoesNotCutTheSpeech() {
        // The previous segment's widened end (1_100) lies past this one's detected start (1_000): the start of the
        // speech stays.
        let range = SegmentWindow.widened(
            1_000..<2_000, notBefore: 1_100, received: 10_000, preRoll: 300, postRoll: 0)
        #expect(range == 1_000..<2_000)
    }

    @Test func neverRunsPastWhatHasArrivedOrBeforeTheStart() {
        let range = SegmentWindow.widened(100..<900, notBefore: 0, received: 1_000, preRoll: 300, postRoll: 500)
        #expect(range == 0..<1_000)
    }

    @Test func theWidenedRangeNeverExceedsTheEnginesWindow() {
        let longest = 15 * rate
        // A range that is exactly the window (a cut) gets nothing.
        #expect(
            SegmentWindow.widened(
                20_000..<(20_000 + longest), notBefore: 0, received: 1_000_000, preRoll: 4_800, postRoll: 3_200)
                == 20_000..<(20_000 + longest))
        // A range a little short of it gets what fits, the margin before the speech giving way first.
        let detected = 20_000..<(20_000 + longest - 5_000)
        let range = SegmentWindow.widened(
            detected, notBefore: 0, received: 1_000_000, preRoll: 4_800, postRoll: 3_200)
        #expect(range.count == longest)
        #expect(range.upperBound == detected.upperBound + 3_200)
        #expect(range.lowerBound == detected.lowerBound - 1_800)
        // Margins too big for the window leave the detected range whole and drop the rest.
        let long = SegmentWindow.widened(
            detected, notBefore: 0, received: 1_000_000, preRoll: 90_000, postRoll: 90_000)
        #expect(long == (detected.lowerBound..<detected.upperBound + 5_000))
    }

    @Test func aCutKeepsThePreRollInsideTheWindow() {
        let longest = 15 * rate
        // Room before the start: the cut moves back by the pre-roll, so with it the piece is exactly the window.
        #expect(
            SegmentWindow.cutEnd(start: 20_000, notBefore: 0, preRoll: 4_800, longest: longest)
                == 20_000 - 4_800 + longest)
        // The audio before was sent already: no pre-roll, the cut is a full window after the start.
        #expect(
            SegmentWindow.cutEnd(start: 20_000, notBefore: 20_000, preRoll: 4_800, longest: longest) == 20_000 + longest
        )
        // A cut is always after the start, whatever the rolls.
        #expect(SegmentWindow.cutEnd(start: 100, notBefore: 0, preRoll: 90_000, longest: 50) == 101)
    }

    @Test func zeroRollsAndEmptyRangesAreLeftAlone() {
        #expect(
            SegmentWindow.widened(500..<900, notBefore: 0, received: 2_000, preRoll: 0, postRoll: 0) == 500..<900)
        #expect(
            SegmentWindow.widened(500..<500, notBefore: 0, received: 2_000, preRoll: 300, postRoll: 300)
                == 500..<500)
    }

    @Test func negativeRollsAreTreatedAsZero() {
        #expect(
            SegmentWindow.widened(500..<900, notBefore: 0, received: 2_000, preRoll: -5, postRoll: -5) == 500..<900)
    }
}

/// An engine that remembers how many samples every segment had.
private final class LengthEngine: SpeechEngine {
    private let lengths = Mutex<[Int]>([])
    var heard: [Int] { lengths.withLock { $0 } }
    var isLoaded: Bool { true }
    func load(modelFolder: URL) async throws {}
    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        lengths.withLock { $0.append(samples.count) }
        return TranscriptSegment(text: "words")
    }
    func unload() async {}
}

/// Like the real detector, it reports the end of speech late: `lag` samples after it happened, with the start
/// reported at once. (`ScriptedVAD` reports an end the moment it passes, when no audio after it exists yet.)
private final class LaggingVAD: VoiceActivityDetector {
    private let spans: [Range<Int>]
    private let lag: Int
    private let position = Mutex(0)

    init(_ spans: [Range<Int>], lag: Int) {
        self.spans = spans
        self.lag = lag
    }

    func process(_ samples: [Float]) async throws -> [VADEvent] {
        let (from, to) = position.withLock { position -> (Int, Int) in
            defer { position += samples.count }
            return (position, position + samples.count)
        }
        var events: [VADEvent] = []
        for span in spans {
            if (from..<to).contains(span.lowerBound) {
                events.append(VADEvent(kind: .speechStart, sampleIndex: span.lowerBound))
            }
            if (from..<to).contains(span.upperBound + lag) {
                events.append(VADEvent(kind: .speechEnd, sampleIndex: span.upperBound))
            }
        }
        return events
    }
}

/// A detector with scripted speech spans that also reports a scripted probability per call.
private final class ProbabilityVAD: VoiceActivityDetector {
    private let base: ScriptedVAD
    private let batches = Mutex<[[Float]]>([])

    init(spans: [Range<Int>], batches: [[Float]]) {
        base = ScriptedVAD(spans)
        self.batches.withLock { $0 = batches }
    }

    func process(_ samples: [Float]) async throws -> [VADEvent] { try await base.process(samples) }

    func drainProbabilities() async -> [Float] {
        batches.withLock { $0.isEmpty ? [] : $0.removeFirst() }
    }
}

@Suite struct SegmentPaddingSessionTests {
    private func limits(_ rig: SessionRig, pre: Int, post: Int) -> MeetingSessionLimits {
        var limits = rig.shortLimits
        limits.segmentPreRoll = .milliseconds(pre)
        limits.segmentPostRoll = .milliseconds(post)
        return limits
    }

    private func run(
        _ script: TrackScript, pre: Int, post: Int, rig: SessionRig, engine: LengthEngine
    ) async throws -> (outcome: MeetingSessionOutcome, rows: [SegmentRow]) {
        let lagging = LaggingVAD(script.spans, lag: rate / 2)
        let session = MeetingSession(
            store: rig.store, keys: rig.keys, spool: rig.spool, mic: UnavailableAudioInput(), system: rig.system,
            makeVAD: { lagging }, engine: engine, modelID: "test-model",
            modelFolder: rig.directory.url.appending(path: "model"), lease: rig.lease,
            sleepAssertion: rig.sleepAssertion, gate: rig.gate, limits: limits(rig, pre: pre, post: post),
            retriesMicrophone: false)
        let id = try await session.start()
        rig.system.push(script.samples)
        rig.system.end()
        let outcome = await session.finish()
        return (outcome, try rig.rows(id))
    }

    @Test func theEngineGetsThePreRollAndPostRollAndTheTranscriptCarriesThem() async throws {
        let rig = try SessionRig()
        let engine = LengthEngine()
        var script = TrackScript()
        script.silence(3)
        script.say(11, seconds: 2)
        script.silence(12)
        let (outcome, rows) = try await run(script, pre: 300, post: 200, rig: rig, engine: engine)
        #expect(outcome.result == .ready)
        #expect(engine.heard == [Int(2.5 * Double(rate))])
        #expect(rows.first?.startMs == 2_700)
        #expect(rows.first?.endMs == 5_200)
    }

    @Test func withoutRollsTheEngineGetsExactlyTheDetectedRange() async throws {
        let rig = try SessionRig()
        let engine = LengthEngine()
        var script = TrackScript()
        script.silence(3)
        script.say(11, seconds: 2)
        script.silence(12)
        let (_, rows) = try await run(script, pre: 0, post: 0, rig: rig, engine: engine)
        #expect(engine.heard == [2 * rate])
        #expect(rows.first?.startMs == 3_000)
    }

    @Test func nothingIsSentTwiceWhenSegmentsAreCloseOrCutAtTheModelWindow() async throws {
        let rig = try SessionRig()
        let engine = LengthEngine()
        var script = TrackScript()
        script.silence(1)
        // 20 s of speech: cut at 15 s (the continuation starts exactly at the cut), then a pause (the detector's
        // minimum silence is 0.75 s) that the pre- and post-roll of the neighbours cover between them, then a
        // second utterance.
        script.say(11, seconds: 20)
        script.silence(0.7)
        script.say(12, seconds: 2)
        script.silence(12)
        let (outcome, rows) = try await run(script, pre: 500, post: 500, rig: rig, engine: engine)
        #expect(outcome.result == .ready)
        // Every sample from 0.5 s (the pre-roll before the speech) to 24.2 s (the post-roll after the last piece) was
        // sent exactly once, in three pieces: the long utterance is cut so that its pre-roll fits in the window,
        // and nothing is repeated at the cut.
        #expect(engine.heard.count == 3)
        #expect(engine.heard.first == MeetingSession.longestSegment)
        #expect(engine.heard.allSatisfy { $0 <= MeetingSession.longestSegment })
        #expect(engine.heard.reduce(0, +) == Int(23.7 * Double(rate)))
        #expect(rows.count == 3)
        // The ranges in the transcript do not overlap.
        for (a, b) in zip(rows, rows.dropFirst()) { #expect(a.endMs <= b.startMs) }
    }

    @Test func probabilitiesAreCountedAsNearMissesOnlyWhileNoSpeechIsOpen() async throws {
        let rig = try SessionRig()
        let sink = Mutex<CaptureCounters?>(nil)
        var limits = rig.shortLimits
        limits.vadEntryThreshold = 0.85
        var script = TrackScript()
        script.silence(16)
        // One batch per 0.1 s chunk of the track; a chunk of the detector is 256 ms but the count is per entry.
        let probabilities: [[Float]] = [[0.2], [0.6, 0.7], [0.2], [0.65], [0.9], [0.55, 0.99]]
        let vad = ProbabilityVAD(spans: [], batches: probabilities)
        let session = MeetingSession(
            store: rig.store, keys: rig.keys, spool: rig.spool, mic: UnavailableAudioInput(), system: rig.system,
            makeVAD: { vad }, engine: rig.engine, modelID: "test-model",
            modelFolder: rig.directory.url.appending(path: "model"), lease: rig.lease,
            sleepAssertion: rig.sleepAssertion, gate: rig.gate, limits: limits,
            recordCounters: { value in sink.withLock { $0 = value } }, retriesMicrophone: false)
        _ = try await session.start()
        rig.system.push(script.samples)
        rig.system.end()
        _ = await session.finish()
        let stats = try #require(sink.withLock { $0 }).system.segmentingStats
        #expect(stats.chunks == 8)
        // 0.6, 0.7 | 0.65 | 0.55 (0.2 is under the floor) are below the entry threshold; 0.9 is above and ends a run; 0.99 is speech.
        #expect(stats.nearMissChunks == 4)
        #expect(stats.nearMissRuns == 3)
        #expect(stats.longestNearMissRun == 2)
        #expect(stats.probabilityHistogram == [0, 0, 2, 0, 0, 1, 2, 1, 0, 2])
    }

    @Test func aProbabilityThatIsNotANumberIsIgnoredAndDoesNotTrap() {
        var stats = SegmentingStats()
        stats.add(.nan)
        stats.add(.infinity)
        stats.add(-.infinity)
        stats.add(0.95)
        stats.add(1.5)
        stats.add(-0.2)
        #expect(stats.chunks == 3)
        #expect(stats.probabilityHistogram == [1, 0, 0, 0, 0, 0, 0, 0, 0, 2])
    }

    @Test func chunksWhileSpeechIsOpenAreNeverNearMisses() async throws {
        let rig = try SessionRig()
        let sink = Mutex<CaptureCounters?>(nil)
        var limits = rig.shortLimits
        limits.vadEntryThreshold = 0.85
        var script = TrackScript()
        script.say(11, seconds: 3)
        script.silence(13)
        // One batch per 0.1 s chunk: speech opens in call 0 and closes in call 30.
        var batches = [[Float]](repeating: [], count: 60)
        batches[0] = [0.9]
        batches[1] = [0.6]  // inside speech: not a near miss
        batches[31] = [0.6]  // after it: a near miss
        batches[33] = [0.9]  // ends the run
        batches[35] = [0.3]  // a second run
        let vad = ProbabilityVAD(spans: script.spans, batches: batches)
        let session = MeetingSession(
            store: rig.store, keys: rig.keys, spool: rig.spool, mic: UnavailableAudioInput(), system: rig.system,
            makeVAD: { vad }, engine: rig.engine, modelID: "test-model",
            modelFolder: rig.directory.url.appending(path: "model"), lease: rig.lease,
            sleepAssertion: rig.sleepAssertion, gate: rig.gate, limits: limits,
            recordCounters: { value in sink.withLock { $0 = value } }, retriesMicrophone: false)
        _ = try await session.start()
        rig.system.push(script.samples)
        rig.system.end()
        _ = await session.finish()
        let stats = try #require(sink.withLock { $0 }).system.segmentingStats
        #expect(stats.chunks == 5)
        #expect(stats.nearMissChunks == 2)
        #expect(stats.nearMissRuns == 2)
        #expect(stats.longestNearMissRun == 1)
    }

    @Test func countersWrittenBeforeTheDetectorStatisticsExistedStillDecode() throws {
        var counters = CaptureCounters()
        counters.system.segmentsSent = 4
        counters.system.segmentingStats.nearMissChunks = 2
        let data = try JSONEncoder().encode(counters)
        var json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        var system = try #require(json["system"] as? [String: Any])
        system.removeValue(forKey: "segmenting")
        json["system"] = system
        let old = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(CaptureCounters.self, from: old)
        #expect(decoded.system.segmentsSent == 4)
        #expect(decoded.system.segmentingStats == SegmentingStats())
        #expect(try JSONDecoder().decode(CaptureCounters.self, from: data) == counters)
    }
}
