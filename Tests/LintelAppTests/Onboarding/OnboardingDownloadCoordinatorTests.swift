import Foundation
import LintelKit
import LintelSpeech
import LintelTestSupport
import Testing

@testable import LintelApp

/// The onboarding speech download (spec `2026-11-24-first-run-onboarding`, step 4.4): what a goal fetches, what it
/// leaves alone, the free-space check before the first byte, a failure that Try Again resumes, and a run that is
/// never started twice.
@Suite struct OnboardingDownloadCoordinatorTests {
    // MARK: Tests

    @Test func downloadsTheSpeechFilesTheGoalNeedsOnce() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        script.usages = [
            "dictation": [usage("parakeet-ultra")],
            "meetings": [
                usage("parakeet-ultra"),
                usage("diarization-community-1", kind: .diarization, required: false, selected: true),
            ],
        ]
        let coordinator = make(script: script, fake: fake)
        #expect(coordinator.state == .idle)

        coordinator.start(for: .both)

        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(script.asked == ["dictation", "meetings"])
        // Dictation and Meetings share the speech model: it is fetched once, and the speaker model once.
        #expect(await fake.installs == ["parakeet-ultra", "diarization-community-1"])
    }

    @Test func aDictationGoalAsksDictationOnly() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        script.usages = [
            "dictation": [usage("parakeet-ultra")],
            "meetings": [usage("diarization-community-1", kind: .diarization, required: false, selected: true)],
        ]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)

        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(script.asked == ["dictation"])
        #expect(await fake.installs == ["parakeet-ultra"])
    }

    @Test func progressCoversTheWholeDownload() async {
        let fake = FakeInstaller()
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)
        let total = ModelCatalog.parakeetUltra.totalBytes

        coordinator.start(for: .dictation)
        #expect(await fake.installsStarted.wait(atLeast: 1))
        await fake.emit(ModelProgress(bytesDone: total / 2, bytesTotal: total), for: "parakeet-ultra")

        let halfway = await waitForObserved("the progress to show") {
            coordinator.state == .downloading(ModelProgress(bytesDone: total / 2, bytesTotal: total))
        }
        #expect(halfway)
        if case .downloading(let progress) = coordinator.state {
            // Half the bytes, give or take the integer division of an odd package size.
            #expect(progress.fraction > 0.49 && progress.fraction < 0.51)
        }

        await fake.finish("parakeet-ultra")
        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
    }

    @Test func aLateProgressReportDoesNotBringTheBarBack() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)
        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        // The package reports its last bytes before `install` returns; the hop to the main actor can land later.
        await fake.emit(ModelProgress(bytesDone: 1, bytesTotal: 100), for: "parakeet-ultra")
        for _ in 0..<20 { await Task.yield() }
        #expect(coordinator.state == .done)
    }

    @Test func aFailedDownloadOffersTryAgainAndResumes() async {
        let fake = FakeInstaller(outcome: .fail(ModelError.httpStatus(503)))
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)
        let failed = await waitForObserved("the failure") { coordinator.state == .failed }
        #expect(failed)
        #expect(await fake.installs == ["parakeet-ultra"])

        // Try Again: the partial files stay with `ModelManager`, so the same call starts from where it stopped.
        await fake.setOutcome(.succeed)
        coordinator.retry()

        let reached = await waitForObserved("the resumed download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["parakeet-ultra", "parakeet-ultra"])
    }

    @Test func notEnoughSpaceStartsNothingUntilSpaceIsFreed() async {
        let fake = FakeInstaller(space: ModelSpaceCheck(needed: 3_000_000_000, available: 1_000_000_000))
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)

        let refused = await waitForObserved("the space state") {
            coordinator.state == .needsSpace(needed: 3_000_000_000, available: 1_000_000_000)
        }
        #expect(refused)
        #expect(await fake.installs.isEmpty)

        // Freed: the next Try Again checks the space again and downloads.
        await fake.setSpace(ModelSpaceCheck(needed: 3_000_000_000, available: 4_000_000_000))
        await fake.setOutcome(.succeed)
        coordinator.retry()

        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["parakeet-ultra"])
    }

    @Test func neverDownloadsTheNotesModel() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        script.usages = [
            "meetings": [
                usage("parakeet-ultra"),
                usage("diarization-community-1", kind: .diarization, required: false, selected: true),
                // On by default in Meetings (#252), but the First meeting step offers it; it is never fetched here.
                usage("llm-qwen3-4b-instruct-2507-q4km", kind: .llm, required: false, selected: true),
            ]
        ]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .meetings)

        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["parakeet-ultra", "diarization-community-1"])
        #expect(!(await fake.spaceChecks).contains("llm-qwen3-4b-instruct-2507-q4km"))
    }

    @Test func onlyUsagesTheGoalNeedsNowAreDownloaded() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        script.usages = [
            "dictation": [
                // Required but not selected: still needed.
                usage("whisper-large-v3-turbo", required: true, selected: false),
                // Neither required nor selected: a model the user did not pick.
                usage("parakeet-ultra", required: false, selected: false),
            ],
            "meetings": [
                // A folder the user chose already holds the files.
                usage("parakeet-ultra", customFolder: URL(filePath: "/Models/parakeet")),
                // The speaker model switched off.
                usage("diarization-community-1", kind: .diarization, required: false, selected: false),
            ],
        ]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .both)

        let reached = await waitForObserved("the download to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["whisper-large-v3-turbo"])
    }

    @Test func nothingToDownloadFinishesAtOnce() async {
        let fake = FakeInstaller(outcome: .succeed)
        let script = Script()
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)

        let reached = await waitForObserved("the run to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs.isEmpty)
        #expect(await fake.spaceChecks.isEmpty)
    }

    @Test func onlyTheFirstRunningStartDownloads() async {
        let fake = FakeInstaller()
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)
        // The same tick, while the first run has not reached `.downloading` yet: a second start must not duplicate it.
        coordinator.start(for: .dictation)
        #expect(await fake.installsStarted.wait(atLeast: 1))
        coordinator.retry()

        await fake.finish("parakeet-ultra")
        let reached = await waitForObserved("the first run to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["parakeet-ultra"])

        // Finished is finished: another call starts nothing.
        coordinator.start(for: .dictation)
        #expect(await fake.installs == ["parakeet-ultra"])
    }

    @Test func cancellingStopsTheRunAndTheNextStartResumesIt() async {
        let fake = FakeInstaller()
        let script = Script()
        script.usages = ["dictation": [usage("parakeet-ultra")]]
        let coordinator = make(script: script, fake: fake)

        coordinator.start(for: .dictation)
        #expect(await fake.installsStarted.wait(atLeast: 1))

        coordinator.cancel()
        #expect(coordinator.state == .idle)
        #expect(await fake.cancellations.wait(atLeast: 1))

        // The setup window closing does not cancel (spec, Edge Cases); a cancelled run resumes from its files.
        coordinator.start(for: .dictation)
        #expect(await fake.installsStarted.wait(atLeast: 2))
        await fake.finish("parakeet-ultra")
        let reached = await waitForObserved("the second run to finish") { coordinator.state == .done }
        #expect(reached)
        #expect(await fake.installs == ["parakeet-ultra", "parakeet-ultra"])
    }

    // MARK: Support

    /// One plugin's scripted `modelUsage`, and the plugin ids the coordinator asked about.
    @MainActor
    final class Script {
        var usages: [PluginID: [ModelUsage]] = [:]
        private(set) var asked: [PluginID] = []

        func answer(_ pluginID: PluginID) -> [ModelUsage] {
            asked.append(pluginID)
            return usages[pluginID] ?? []
        }
    }

    @MainActor
    private func make(script: Script, fake: FakeInstaller) -> OnboardingDownloadCoordinator {
        OnboardingDownloadCoordinator(
            usages: { script.answer($0) },
            manager: { _ in fake })
    }

    private func usage(
        _ packageID: String, kind: ModelKind = .speech, required: Bool = true, selected: Bool = true,
        customFolder: URL? = nil
    ) -> ModelUsage {
        ModelUsage(
            packageID: packageID, kind: kind,
            role: LocalizedStringResource("Test model", comment: "Test: a model usage's role"),
            isRequired: required, isSelected: selected, customFolder: customFolder)
    }
}

/// A `ModelInstalling` answered from a script: the free space per package, and how each install ends. A waiting
/// install reports progress and finishes only when the test says so, or on cancellation. Nothing touches the disk
/// or the network.
actor FakeInstaller: ModelInstalling {
    enum Outcome: Sendable {
        case succeed
        case fail(ModelError)
        /// Stays until `finish(_:)`, `fail(_:with:)` or the run's cancellation.
        case wait
    }

    private(set) var spaceChecks: [String] = []
    /// Every `install` call's package id, in order: a duplicate, a retry or a resume shows here.
    private(set) var installs: [String] = []
    let installsStarted = CountLatch()
    let cancellations = CountLatch()

    private var defaultSpace: ModelSpaceCheck
    private var spaces: [String: ModelSpaceCheck] = [:]
    private var defaultOutcome: Outcome
    private var outcomes: [String: Outcome] = [:]
    private var progressClosures: [String: @Sendable (ModelProgress) -> Void] = [:]
    private var continuations: [String: CheckedContinuation<Void, any Error>] = [:]

    init(
        space: ModelSpaceCheck = ModelSpaceCheck(needed: 1_000, available: 1_000_000_000_000),
        outcome: Outcome = .wait
    ) {
        defaultSpace = space
        defaultOutcome = outcome
    }

    func setSpace(_ space: ModelSpaceCheck, for packageID: String? = nil) {
        if let packageID {
            spaces[packageID] = space
        } else {
            defaultSpace = space
        }
    }

    func setOutcome(_ outcome: Outcome, for packageID: String? = nil) {
        if let packageID {
            outcomes[packageID] = outcome
        } else {
            defaultOutcome = outcome
        }
    }

    func emit(_ progress: ModelProgress, for packageID: String) {
        progressClosures[packageID]?(progress)
    }

    func finish(_ packageID: String) {
        continuations.removeValue(forKey: packageID)?.resume()
    }

    func fail(_ packageID: String, with error: ModelError) {
        continuations.removeValue(forKey: packageID)?.resume(throwing: error)
    }

    func spaceCheck(for package: ModelPackage) -> ModelSpaceCheck {
        spaceChecks.append(package.id)
        return spaces[package.id] ?? defaultSpace
    }

    func install(
        _ package: ModelPackage, progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> URL {
        try Task.checkCancellation()
        installs.append(package.id)
        installsStarted.increment()
        switch outcomes[package.id] ?? defaultOutcome {
        case .succeed:
            // Kept, so a test can report late bytes after the run ended (the hop to the main actor can land after).
            progressClosures[package.id] = progress
            progress(ModelProgress(bytesDone: package.totalBytes, bytesTotal: package.totalBytes))
            return URL(filePath: "/fake/\(package.id)")
        case .fail(let error):
            throw error
        case .wait:
            progressClosures[package.id] = progress
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                    continuations[package.id] = continuation
                }
            } onCancel: {
                Task { await self.cancelInstall(package.id) }
            }
            return URL(filePath: "/fake/\(package.id)")
        }
    }

    private func cancelInstall(_ packageID: String) {
        guard let continuation = continuations.removeValue(forKey: packageID) else { return }
        cancellations.increment()
        continuation.resume(throwing: CancellationError())
    }
}
