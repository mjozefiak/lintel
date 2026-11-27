import Foundation
import LintelSpeech
import LintelTestSupport
import Synchronization
import Testing

@testable import DictationPlugin
@testable import LintelProviders

/// Spec `2026-11-25-dictation-cleanup-levels`, A10 and A11 (Phase 5): the limit after the key release when the
/// tidying runs at an external provider. The limit counts on an injected clock; no real time passes.
@Suite(.timeLimit(.minutes(1))) struct ProviderDeadlineTests {
    private static let second = AudioFormat.sampleRate
    private static let selection = DictationSettings.ProviderSelection(provider: .claudeCode, model: "sonnet")

    /// Two segments of 50 words (so two chunks) with a 3 s pause between them.
    private static let words = [
        "jutro", "zadzwonię", "do", "klienta", "w", "sprawie", "umowy", "oraz", "wyślę", "ofertę",
    ]
    private static func text(_ offset: Int) -> String {
        (0..<50).map { words[($0 + offset) % words.count] }.joined(separator: " ")
    }

    private final class TwoChunkEngine: SpeechEngine, @unchecked Sendable {
        var isLoaded: Bool { true }
        func load(modelFolder: URL) async throws {}
        func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
            // The test audio carries the second it is from in its samples: the segment from 1 s is the first one.
            let key = Int((samples.first ?? 0) * 100 + 0.5)
            return TranscriptSegment(text: ProviderDeadlineTests.text(key == 1 ? 0 : 3))
        }
        func unload() async {}
    }

    /// The tidied form the guard accepts: the chunk, capitalised and ended with a full stop.
    private static func tidy(_ spec: ProviderProcessSpec) -> String {
        let input = String(decoding: spec.stdin, as: UTF8.self)
        let transcript =
            input.components(separatedBy: "<transcript>").last?
            .components(separatedBy: "</transcript>").first ?? ""
        return transcript.prefix(1).uppercased() + transcript.dropFirst() + "."
    }

    private struct Rig {
        let process: FakeProviderProcess
        let session: DictationSession
        let clock: TestClock
        let formatter: ProviderFormatter
    }

    /// A session over two chunks. The provider answers the first one at once; `later` decides the second.
    private func rig(
        level: DictationSettings.CleanupLevel = .standard, deadline: Duration? = .seconds(4),
        later: @escaping @Sendable (Int, ProviderProcessSpec) async throws -> ProviderProcessOutput
    ) -> Rig {
        let process = FakeProviderProcess { call, spec in
            if call == 1 { return FakeProviderProcess.output(answer: Self.tidy(spec)) }
            return try await later(call, spec)
        }
        let formatter = ProviderFormatter(
            runner: FakeProviderProcess.runner(process), selection: Self.selection, level: level,
            currentSelection: { Self.selection })
        let clock = TestClock()
        let second = Self.second
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 8),
            vad: RangeVAD([second..<(2 * second), (5 * second)..<(6 * second)]), engine: TwoChunkEngine(),
            formatter: formatter, releaseDeadline: deadline, clock: clock, modelFolder: URL(filePath: "/tmp/none"))
        return Rig(process: process, session: session, clock: clock, formatter: formatter)
    }

    /// Chunk 1 closes while the user is still recording (the pause after it is long); wait until it is at the provider,
    /// so its request is the first one in the lane and the order of the two is not left to the scheduler.
    private func waitUntilTheFirstChunkIsOut(_ process: FakeProviderProcess) async throws {
        for _ in 0..<1000 where process.contentRuns < 1 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(process.contentRuns >= 1)
    }

    /// Waits until chunk 1 has been answered and chunk 2 is out at the provider, with the limit's timer running.
    private func waitUntilTheSecondChunkIsOut(_ rig: Rig) async throws {
        for _ in 0..<1000 where rig.process.contentRuns < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(rig.process.contentRuns == 2)
        await rig.clock.waitForSleepers(1)
    }

    @Test func aChunkStillOutAtTheLimitIsPastedAsSpokenAndItsRequestIsCancelled() async throws {
        let rig = rig { _, _ in
            try await Task.sleep(for: .seconds(60))
            return FakeProviderProcess.output(answer: "never")
        }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let finishing = Task { try await rig.session.finish() }
        try await waitUntilTheSecondChunkIsOut(rig)
        // The limit runs from the key release, so nothing happens before it.
        rig.clock.advance(by: .seconds(3))
        try await Task.sleep(for: .milliseconds(50))
        #expect(rig.process.cancelledRuns == 0)
        rig.clock.advance(by: .seconds(1))
        let output = try await finishing.value
        let first = Self.text(0)
        let second = Self.text(3)
        // The finished chunk stays tidied, the late one is raw.
        #expect(output.formatting.chunks == 2)
        #expect(output.formatting.fellBack == 1)
        #expect(output.formatting.isPartial)
        #expect(output.formatting.notableReason == .tooSlow)
        #expect(output.rawText == first + " " + second)
        #expect(output.text.hasPrefix(first.prefix(1).uppercased() + first.dropFirst() + "."))
        #expect(output.text.hasSuffix(second))
        // The late request's process was cancelled, not left running.
        #expect(rig.process.cancelledRuns == 1)
    }

    @Test func theLimitIsFreeForTheNextDictationAfterItFired() async throws {
        let rig = rig { call, spec in
            if call == 3 { return FakeProviderProcess.output(answer: Self.tidy(spec)) }
            try await Task.sleep(for: .seconds(60))
            return FakeProviderProcess.output(answer: "never")
        }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let finishing = Task { try await rig.session.finish() }
        try await waitUntilTheSecondChunkIsOut(rig)
        rig.clock.advance(by: .seconds(4))
        _ = try await finishing.value
        // The same runner (one lane, one slot) serves the next request at once.
        let next = try await rig.formatter.format(chunk: Self.text(0), previousContext: nil)
        #expect(next.outcome == .formatted)
        #expect(rig.process.contentRuns == 3)
    }

    @Test func answersThatBeatTheLimitAreAllKept() async throws {
        let rig = rig { _, spec in FakeProviderProcess.output(answer: Self.tidy(spec)) }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let output = try await rig.session.finish()
        #expect(output.formatting.chunks == 2)
        #expect(output.formatting.fellBack == 0)
        #expect(!output.formatting.isPartial)
        #expect(output.formatting.notableReason == nil)
        #expect(rig.process.cancelledRuns == 0)
    }

    @Test func aSessionWithoutALimitWaitsForTheFormatter() async throws {
        // A local source has no release limit: the chunk is waited for (its own timeout applies).
        let rig = rig(deadline: nil) { _, spec in
            try await Task.sleep(for: .milliseconds(200))
            return FakeProviderProcess.output(answer: Self.tidy(spec))
        }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let output = try await rig.session.finish()
        #expect(output.formatting.fellBack == 0)
        #expect(rig.clock.sleepCalls == 0)
    }

    @Test func cancellingTheSessionStopsTheLimitsTimer() async throws {
        let rig = rig { _, _ in
            try await Task.sleep(for: .seconds(60))
            return FakeProviderProcess.output(answer: "never")
        }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let finishing = Task { try await rig.session.finish() }
        try await waitUntilTheSecondChunkIsOut(rig)
        await rig.session.cancel()
        await #expect(throws: DictationSession.Failure.cancelled) { try await finishing.value }
        #expect(await rig.clock.waitForCancelledSleeps(1))
    }

    @Test func aGuardRejectionDoesNotHideATooSlowChunk() async throws {
        // Chunk 1 comes back with an invented number (rejected by the guard); chunk 2 is too slow: "too slow" is what
        // the user is told.
        let process = FakeProviderProcess { call, spec in
            if call == 1 { return FakeProviderProcess.output(answer: Self.tidy(spec) + " 25") }
            try await Task.sleep(for: .seconds(60))
            return FakeProviderProcess.output(answer: "never")
        }
        let formatter = ProviderFormatter(
            runner: FakeProviderProcess.runner(process), selection: Self.selection, level: .standard,
            currentSelection: { Self.selection })
        let clock = TestClock()
        let second = Self.second
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 8),
            vad: RangeVAD([second..<(2 * second), (5 * second)..<(6 * second)]), engine: TwoChunkEngine(),
            formatter: formatter, releaseDeadline: .seconds(4), clock: clock, modelFolder: URL(filePath: "/tmp/none"))
        try await session.start()
        try await waitUntilTheFirstChunkIsOut(process)
        let finishing = Task { try await session.finish() }
        for _ in 0..<1000 where process.contentRuns < 2 { try await Task.sleep(for: .milliseconds(10)) }
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(4))
        let output = try await finishing.value
        #expect(output.formatting.fellBack == 2)
        #expect(output.formatting.firstReason == .rejected(.newNumber))
        #expect(output.formatting.notableReason == .tooSlow)
    }

    @Test func aTooSlowChunkWinsOverAnEarlierProviderFailure() async throws {
        // Chunk 1 fails because the network is down, chunk 2 is too slow: the user is told "too slow".
        let process = FakeProviderProcess { call, _ in
            if call == 1 { return FakeProviderProcess.output(answer: "fetch failed: ENOTFOUND", isError: true) }
            try await Task.sleep(for: .seconds(60))
            return FakeProviderProcess.output(answer: "never")
        }
        let formatter = ProviderFormatter(
            runner: FakeProviderProcess.runner(process), selection: Self.selection, level: .standard,
            currentSelection: { Self.selection })
        let clock = TestClock()
        let second = Self.second
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 8),
            vad: RangeVAD([second..<(2 * second), (5 * second)..<(6 * second)]), engine: TwoChunkEngine(),
            formatter: formatter, releaseDeadline: .seconds(4), clock: clock, modelFolder: URL(filePath: "/tmp/none"))
        try await session.start()
        try await waitUntilTheFirstChunkIsOut(process)
        let finishing = Task { try await session.finish() }
        for _ in 0..<1000 where process.contentRuns < 2 { try await Task.sleep(for: .milliseconds(10)) }
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(4))
        let output = try await finishing.value
        #expect(output.formatting.firstReason == .provider(.network))
        #expect(output.formatting.notableReason == .tooSlow)
    }

    @Test func aProviderFailureAloneIsTheNotableReason() async throws {
        let rig = rig(deadline: nil) { _, _ in
            FakeProviderProcess.output(answer: "Not logged in. Please run /login.", isError: true)
        }
        try await rig.session.start()
        try await waitUntilTheFirstChunkIsOut(rig.process)
        let output = try await rig.session.finish()
        // Chunk 1 was answered with a tidy text; chunk 2 is the signed-out failure.
        #expect(output.formatting.notableReason == .provider(.notSignedIn))
    }
}
