import Foundation
import LintelKit
import LintelSpeech
import Testing

@testable import MeetingsPlugin

/// Issue #315: the language repair never starts a cold Whisper load. A load holds the lease for its whole length
/// (the first Whisper load took 143 s in the step 2.5 measurement), so a Parakeet dictation that arrives meanwhile
/// gets "speech model busy". The repair takes the model that is already in memory; with none warm it takes
/// Parakeet, the model a Parakeet dictation needs anyway, and never Whisper while Parakeet is installed.
@MainActor
@Suite struct RepairLanguageChoiceTests {
    private static let parakeet = ModelCatalog.parakeetUltra
    private static let whisper = ModelCatalog.whisperLargeV3Turbo

    private nonisolated static func folder(_ package: ModelPackage) -> URL {
        URL(filePath: "/models/\(package.id)")
    }

    /// A runtime whose speech models are exactly `installed`, at the folder the download would be in. Its own
    /// lease, so what another test leaves in memory never decides this one's model.
    private func makeRuntime(installed: Set<String>) throws -> MeetingsRuntime {
        let harness = try MeetingsHarness()
        var runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        runtime.locateSpeech = { package, _ in
            installed.contains(package.id) ? .installed(Self.folder(package)) : .missing
        }
        runtime.lease = SpeechEngineLease(sleep: { _ in })
        return runtime
    }

    /// Holds `package` in memory the way a meeting or a dictation leaves it, so the repair can share it.
    private func warm(_ package: ModelPackage, on runtime: MeetingsRuntime) async throws -> SpeechLease {
        try await runtime.lease.acquire(
            modelID: package.id, folder: Self.folder(package), engine: ScriptedEngine(texts: [:]),
            priority: .interactive, keepWarm: { .zero })
    }

    @Test func aColdWhisperIsNotTakenWhileParakeetIsInstalled() async throws {
        let runtime = try makeRuntime(installed: [Self.whisper.id, Self.parakeet.id])
        let speech = try #require(await runtime.repairSpeech())

        #expect(speech.kind == .parakeet)
        #expect(speech.modelID == Self.parakeet.id)
        #expect(speech.folder == Self.folder(Self.parakeet))
        // Nothing was loaded to choose: taking the cold Whisper would have started its load.
        #expect(await runtime.lease.residentKey == nil)
    }

    @Test func theModelInMemoryIsTakenWhisperIncluded() async throws {
        let whisperWarm = try makeRuntime(installed: [Self.whisper.id, Self.parakeet.id])
        let whisper = try await warm(Self.whisper, on: whisperWarm)
        let chosen = try #require(await whisperWarm.repairSpeech())
        #expect(chosen.kind == .whisper)
        #expect(chosen.modelID == Self.whisper.id)
        await whisper.release()

        let parakeetWarm = try makeRuntime(installed: [Self.whisper.id, Self.parakeet.id])
        let parakeet = try await warm(Self.parakeet, on: parakeetWarm)
        let shared = try #require(await parakeetWarm.repairSpeech())
        #expect(shared.kind == .parakeet)
        #expect(shared.modelID == Self.parakeet.id)
        await parakeet.release()
    }

    @Test func whisperIsStillTheRepairWhenParakeetIsNotInstalled() async throws {
        let runtime = try makeRuntime(installed: [Self.whisper.id])
        let speech = try #require(await runtime.repairSpeech())
        #expect(speech.kind == .whisper)
        #expect(speech.modelID == Self.whisper.id)
    }

    @Test func parakeetIsTheRepairWhenWhisperIsNotInstalled() async throws {
        let runtime = try makeRuntime(installed: [Self.parakeet.id])
        let speech = try #require(await runtime.repairSpeech())
        #expect(speech.kind == .parakeet)
        #expect(speech.modelID == Self.parakeet.id)
    }

    @Test func noInstalledModelMeansNoRepair() async throws {
        let runtime = try makeRuntime(installed: [])
        #expect(await runtime.repairSpeech() == nil)
    }
}
