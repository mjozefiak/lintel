import Foundation
import LintelKit
import LintelSpeech
import Observation

/// The `ModelManager` calls the onboarding download makes, so the coordinator is tested with a fake and no test
/// reaches the network or the disk. The real `ModelManager` conforms; the live coordinator uses the same ones as
/// Settings → Models (`ModelManagers.shared`), so one download queue and one `.partial/` folder serve both.
nonisolated protocol ModelInstalling: Sendable {
    /// The space `install` asks for before it downloads anything (what is still missing, plus 10 %) and what the
    /// volume has, so the free space is known before the first byte.
    func spaceCheck(for package: ModelPackage) async -> ModelSpaceCheck
    /// Downloads and verifies `package`, reporting progress as it goes. A failed or cancelled attempt keeps the
    /// partial files, so the next call resumes instead of starting over (`ModelManager`).
    func install(
        _ package: ModelPackage, progress: @escaping @Sendable (ModelProgress) -> Void
    ) async throws -> URL
}

extension ModelManager: ModelInstalling {}

/// Which core features the onboarding's goal step chose, as far as the speech download is concerned (spec
/// `2026-11-24-first-run-onboarding`, step 1 "Your goal"). The names are the future `OnboardingGoal`'s raw values
/// (Phase 3, #343), so the flow maps its own type onto this one in a line.
enum OnboardingSpeechGoal: String, Sendable {
    case dictation
    case meetings
    case both

    /// The plugins whose `modelUsage` the goal needs, in onboarding order.
    var pluginIDs: [PluginID] {
        switch self {
        case .dictation: ["dictation"]
        case .meetings: ["meetings"]
        case .both: ["dictation", "meetings"]
        }
    }
}

/// Downloads the speech files the chosen onboarding goal needs, in the background after the goal step (spec
/// `2026-11-24-first-run-onboarding`: step 1 "Your goal", step 4.4 and Q8, Edge Cases "Downloads").
///
/// Leaving the goal step starts the download of the speech packages the goal's plugins report through `modelUsage`
/// with `isRequired` or `isSelected`: the speech model of Dictation and Meetings, and the speaker model while
/// Meetings uses one. A plugin that is off, a model the user points at their own folder, and the notes model
/// (offered in the First meeting step, #252) are never downloaded here.
///
/// The free space is checked once, for every package, before the first byte. It never blocks Continue: `state` is
/// what the step rail reads while the user goes on. A failure keeps the partial files that `ModelManager` resumes
/// on `retry()`, and the setup window closing does not cancel the run (Edge Cases: downloads continue).
@MainActor
@Observable
final class OnboardingDownloadCoordinator {
    /// What the step rail draws: nothing, "Getting dictation ready · 40 %", done, the offline line with Try Again,
    /// or the sizes when the disk is too small (no Download button until space is freed).
    enum State: Equatable, Sendable {
        case idle
        /// The whole download's progress over every package still needed; `ModelProgress.fraction` is the part to
        /// show, any late report after a run ended is dropped.
        case downloading(ModelProgress)
        case done
        /// Not enough free space for the packages still needed, in bytes. Nothing was started.
        case needsSpace(needed: Int, available: Int)
        /// The download stopped (offline, an HTTP or checksum error). `retry()` continues where it stopped.
        case failed
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let usages: @MainActor (PluginID) -> [ModelUsage]
    @ObservationIgnored private let manager: @Sendable (ModelKind) -> (any ModelInstalling)?
    @ObservationIgnored private var goal: OnboardingSpeechGoal?
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Bumped by every start and cancel. A run, and the progress reports it handed out, writes nothing once a
    /// newer run began: the progress callback hops to the main actor and can arrive after the run ended.
    @ObservationIgnored private var runID = 0
    /// Whether the current run may still write `state`; cleared when it ends or is cancelled.
    @ObservationIgnored private var isRunning = false

    /// - Parameters:
    ///   - usages: the `modelUsage` of the plugin with this id while it is active, else `[]` (the shell answers from
    ///     `PluginHost`); a switched-off feature therefore downloads nothing.
    ///   - manager: the model manager of a kind's folder (`ModelManagers.shared`), or `nil` for a kind the
    ///     onboarding download never touches.
    init(
        usages: @escaping @MainActor (PluginID) -> [ModelUsage],
        manager: @escaping @Sendable (ModelKind) -> (any ModelInstalling)?
    ) {
        self.usages = usages
        self.manager = manager
    }

    /// The app's coordinator: the packages live under `Models/speech` and `Models/diarization`, the folders the
    /// plugins load them from, downloaded through the same `ModelManagers.shared` managers as Settings → Models.
    static func live(
        modelsDirectory: URL, usages: @escaping @MainActor (PluginID) -> [ModelUsage],
        registry: ModelManagers = .shared
    ) -> OnboardingDownloadCoordinator {
        OnboardingDownloadCoordinator(
            usages: usages,
            manager: { kind in
                let folder: String
                switch kind {
                case .speech: folder = "speech"
                case .diarization: folder = "diarization"
                default: return nil
                }
                return registry.manager(for: modelsDirectory.appending(path: folder, directoryHint: .isDirectory))
            })
    }

    // MARK: Starting and stopping

    /// Called when the user leaves the goal step: starts the download for `goal` and returns at once. A second call
    /// while one runs, or after it finished, does nothing.
    func start(for goal: OnboardingSpeechGoal) {
        guard state == .idle, task == nil else { return }
        self.goal = goal
        begin()
    }

    /// "Try Again" after a failure, and the re-check after the user freed space: checks the free space again and
    /// resumes the partial downloads. A running or finished run is left alone.
    func retry() {
        guard task == nil else { return }
        switch state {
        case .failed, .needsSpace: begin()
        case .idle, .downloading, .done: break
        }
    }

    /// Stops the running download and forgets its state; the files already downloaded stay, so a later
    /// `start(for:)` resumes them. The setup window closing does not call this: downloads continue in the
    /// background (spec, Edge Cases), so only the app's own teardown or a changed goal should.
    func cancel() {
        runID += 1
        isRunning = false
        task?.cancel()
        task = nil
        state = .idle
    }

    private func begin() {
        guard let goal else { return }
        runID += 1
        let id = runID
        isRunning = true
        let downloads = downloads(for: goal)
        task = Task { [weak self] in
            await self?.run(downloads, id: id)
        }
    }

    // MARK: What to download

    private struct Download {
        let package: ModelPackage
        let manager: any ModelInstalling
    }

    /// The packages the goal needs, each once: Dictation and Meetings share the speech model, and it is fetched
    /// once. Skips what needs no download (a model already installed is left out by the space check) and the
    /// language models, which the First meeting step offers instead (#252).
    private func downloads(for goal: OnboardingSpeechGoal) -> [Download] {
        var seen: Set<String> = []
        var result: [Download] = []
        for pluginID in goal.pluginIDs {
            for usage in usages(pluginID) {
                // The notes model is offered in the First meeting step, never fetched here.
                guard usage.kind != .llm else { continue }
                // A model the plugin may use but does not need now (the speaker model switched off).
                guard usage.isRequired || usage.isSelected else { continue }
                // A folder the user chose already holds the files; the download would never be used.
                guard usage.customFolder == nil else { continue }
                guard !seen.contains(usage.packageID) else { continue }
                guard let package = package(for: usage), let manager = manager(usage.kind) else { continue }
                seen.insert(usage.packageID)
                result.append(Download(package: package, manager: manager))
            }
        }
        return result
    }

    /// The catalog package of a usage; an unknown id or a kind the onboarding download never fetches is skipped.
    private func package(for usage: ModelUsage) -> ModelPackage? {
        switch usage.kind {
        case .speech: ModelCatalog.package(id: usage.packageID)
        case .diarization: ModelCatalog.diarizationPackage(id: usage.packageID)
        default: nil
        }
    }

    // MARK: The run

    private func run(_ downloads: [Download], id: Int) async {
        defer {
            if runID == id {
                isRunning = false
                task = nil
            }
        }
        // The free space first, for every package, before anything is downloaded (spec: R9, Edge Cases). An
        // installed package needs nothing and is left out; its `needed` is 0.
        var pending: [Download] = []
        var needed = 0
        var available = 0
        for download in downloads {
            guard isRunning, runID == id, !Task.isCancelled else { return }
            let check = await download.manager.spaceCheck(for: download.package)
            guard check.needed > 0 else { continue }
            // The packages share the `Models/` volume, so the first pending check's free space is the all of them.
            if pending.isEmpty { available = check.available }
            needed += check.needed
            pending.append(download)
        }
        guard isRunning, runID == id, !Task.isCancelled else { return }
        guard !pending.isEmpty else {
            state = .done
            return
        }
        guard needed <= available else {
            state = .needsSpace(needed: needed, available: available)
            return
        }

        let total = pending.reduce(0) { $0 + $1.package.totalBytes }
        var done = 0
        state = .downloading(ModelProgress(bytesDone: 0, bytesTotal: total))
        do {
            for download in pending {
                let base = done
                _ = try await download.manager.install(download.package) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.isRunning, self.runID == id else { return }
                        self.state = .downloading(
                            ModelProgress(bytesDone: base + progress.bytesDone, bytesTotal: total))
                    }
                }
                done += download.package.totalBytes
            }
            guard isRunning, runID == id else { return }
            state = .done
        } catch is CancellationError {
            // `cancel()` has already put the state back; the partial files stay for the next run.
        } catch let ModelError.insufficientSpace(needed, available) {
            guard isRunning, runID == id else { return }
            state = .needsSpace(needed: needed, available: available)
        } catch {
            guard isRunning, runID == id else { return }
            state = .failed
        }
    }
}
