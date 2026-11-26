import Foundation
import Testing

@testable import LintelSpeech

/// Answers with fixed decoder confidences, as `WhisperKitEngine` reports them.
private struct ConfidentEngine: SpeechEngine {
    var isLoaded: Bool { true }
    func load(modelFolder: URL) async throws {}
    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        try await transcribe(samples, options: .none)
    }
    func transcribe(_ samples: [Float], options: SpeechRequestOptions) async throws -> TranscriptSegment {
        TranscriptSegment(text: "segment", noSpeechProb: 0.25, avgLogProb: -0.5)
    }
    func unload() async {}
}

/// The language repair (spec step 2.4) reads Whisper's `noSpeechProb` and `avgLogProb` through the switching
/// engine and the lease; neither may rebuild the segment and drop them.
@Suite struct TranscriptConfidenceTests {
    @Test func parakeetStyleSegmentsHaveNoConfidence() {
        let segment = TranscriptSegment(text: "text")
        #expect(segment.noSpeechProb == nil && segment.avgLogProb == nil)
    }

    @Test func theSwitchingEngineAndTheLeaseKeepTheConfidences() async throws {
        let switching = SwitchingEngine(engines: ["whisper": ConfidentEngine()], selected: { "whisper" })
        let direct = try await switching.transcribe([0.1], options: .none)
        #expect(direct.noSpeechProb == 0.25 && direct.avgLogProb == -0.5)

        let directory = try TemporaryDirectory()
        let lease = try await SpeechEngineLease(sleep: { _ in }).acquire(
            modelID: "whisper", folder: directory.url, engine: switching, priority: .background,
            keepWarm: { .zero })
        let outcome = try await lease.transcribe([0.1], options: SpeechRequestOptions(whisperLanguage: .pinned("pl")))
        #expect(outcome == .transcript(TranscriptSegment(text: "segment", noSpeechProb: 0.25, avgLogProb: -0.5)))
        await lease.release()
    }
}
