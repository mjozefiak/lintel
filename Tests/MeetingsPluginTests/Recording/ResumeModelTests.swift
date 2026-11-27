import Foundation
import LintelKit
import LintelSpeech
import Synchronization
import Testing

@testable import MeetingsPlugin

/// Which speech model a resumed meeting is transcribed with (#314). Pure: the resumer then looks the package up
/// where Lintel installed it.
@Suite struct ResumeModelTests {
    private let parakeet = ModelCatalog.parakeetUltra
    private let whisper = ModelCatalog.whisperLargeV3Turbo

    @Test func theStoredModelWinsOverTheOneChosenInSettingsNow() {
        // Settings now says Parakeet; the meeting was recorded with Whisper (and the other way round).
        #expect(MeetingsRuntime.resumePackage(storedModelID: whisper.id, selected: parakeet) == whisper)
        #expect(MeetingsRuntime.resumePackage(storedModelID: parakeet.id, selected: whisper) == parakeet)
    }

    @Test func aRowThatRecordedNoModelFollowsTheChoiceInSettings() {
        #expect(MeetingsRuntime.resumePackage(storedModelID: "", selected: whisper) == whisper)
    }

    @Test func aStoredModelThatIsNoLongerInTheCatalogIsGoneAndNothingElseIsUsed() {
        #expect(MeetingsRuntime.resumePackage(storedModelID: "removed-model", selected: parakeet) == nil)
    }
}

/// The same question through the resumer `MeetingsRuntime` really builds and the real `ModelManager` over a
/// temporary `Models/speech/`: the settings, the lookup, the resumer and the library are the app's own path.
/// Only the two devices are stand-ins (the real engines and the Silero detector load the models' weights).
///
/// The model files are sparse (their exact sizes, none of their bytes), which is all
/// `ModelManager.location(of:)` reads to call a package installed.
@MainActor
@Suite struct ResumeModelRuntimeTests {
    private let parakeet = ModelCatalog.parakeetUltra
    private let whisper = ModelCatalog.whisperLargeV3Turbo

    /// Settings now say Parakeet (the default) while the meeting was recorded with Whisper, and both models are
    /// installed: nothing but the id stored with the meeting may decide which one a resumption uses, for the
    /// detector and the engine alike.
    @Test func aResumptionUsesTheStoredModelAndNotTheOneInSettings() async throws {
        let rig = try ResumeRig()
        let installed = try rig.install(parakeet, whisper)
        let meeting = try await rig.seed(storedModelID: whisper.id)

        let log = ResumeSetupLog()
        let library = rig.library(runtime: rig.runtime(log: log))
        library.open()
        let store = try #require(library.store)

        #expect(await pollUntil { (try? store.audioState(of: meeting.id)) == .deleted })
        #expect(try store.status(of: meeting.id) == .ready)
        #expect(log.detectorFolders == [installed.folder(of: whisper)])
        #expect(log.engines == [whisper.id])
        #expect(await rig.lease.activeLeases == 0)
        library.close()
    }

    /// A folder the user chose belongs to the model chosen in Settings: a meeting recorded with another model is
    /// still resumed from the copy Lintel installed, never from that folder.
    @Test func theFolderChosenForTheSettingsModelIsNotUsedForTheStoredOne() async throws {
        let custom = try TemporaryDirectory()
        let rig = try ResumeRig(settings: [
            "plugins.meetings.speechModel": .string(whisper.id),
            "plugins.meetings.speechModelFolder": .string(custom.url.path),
        ])
        let installed = try rig.install(parakeet)
        try installFiles(of: whisper, in: custom.url)
        let meeting = try await rig.seed(storedModelID: parakeet.id)

        let log = ResumeSetupLog()
        let library = rig.library(runtime: rig.runtime(log: log))
        library.open()
        let store = try #require(library.store)

        #expect(await pollUntil { (try? store.audioState(of: meeting.id)) == .deleted })
        #expect(try store.status(of: meeting.id) == .ready)
        #expect(log.detectorFolders == [installed.folder(of: parakeet)])
        #expect(log.engines == [parakeet.id])
        library.close()
    }

    /// A stored model that is not installed any more leaves the meeting `incomplete` with its spool: it waits
    /// for that model instead of switching to the one in Settings.
    @Test func aStoredModelThatIsNotInstalledLeavesTheMeetingIncomplete() async throws {
        let rig = try ResumeRig()
        _ = try rig.install(parakeet)
        let meeting = try await rig.seed(storedModelID: whisper.id)

        let log = ResumeSetupLog()
        let library = rig.library(runtime: rig.runtime(log: log))
        library.open()
        let store = try #require(library.store)

        #expect(await pollUntil { (try? store.status(of: meeting.id)) == .incomplete })
        #expect(try store.audioState(of: meeting.id) == .spool)
        #expect(log.engines.isEmpty)
        #expect(log.detectorFolders.isEmpty)
        library.close()
    }
}

/// What the resumer asked for: the folder the detector resolved and the engine's model id.
final class ResumeSetupLog: Sendable {
    private let state = Mutex<(folders: [String], engines: [String])>(([], []))

    func recordDetectorFolder(_ url: URL) { state.withLock { $0.folders.append(url.path) } }
    func recordEngine(_ modelID: String) { state.withLock { $0.engines.append(modelID) } }

    var detectorFolders: [String] { state.withLock { $0.folders } }
    var engines: [String] { state.withLock { $0.engines } }
}

/// Stands in for `FolderResolvingVAD`: it asks for the folder the same way (when the first audio arrives) and
/// records it, then answers like the scripted detector of the recovery tests.
private actor FolderRecordingVAD: VoiceActivityDetector {
    struct ModelMissing: Error {}

    private let folder: @Sendable () async -> URL?
    private let spans: [Range<Int>]
    private let log: ResumeSetupLog
    private var detector: ScriptedVAD?

    init(folder: @escaping @Sendable () async -> URL?, spans: [Range<Int>], log: ResumeSetupLog) {
        self.folder = folder
        self.spans = spans
        self.log = log
    }

    func process(_ samples: [Float]) async throws -> [VADEvent] {
        if detector == nil {
            guard let folder = await folder() else { throw ModelMissing() }
            log.recordDetectorFolder(folder)
            detector = ScriptedVAD(spans)
        }
        guard let detector else { return [] }
        return try await detector.process(samples)
    }
}

/// A crash left a `processing` meeting with a spool, and the settings name one model while the meeting was
/// recorded with another: the fakes the resumer gets are only its two devices.
@MainActor
private final class ResumeRig {
    /// One utterance, so the resumer has something to transcribe and stores a segment.
    private static let track = TrackScript.build([(1, 12, 3)], tail: 1)
    private static let texts: [Int: String] = [12: "Druga wypowiedź"]

    private let rig: RecoveryRig
    private let models: URL

    init(settings: [String: SettingValue] = [:]) throws {
        // Speakers are not the subject here, and the real diarizer needs its own model.
        rig = try RecoveryRig(
            texts: Self.texts,
            settings: settings.merging(["plugins.meetings.diarization": .bool(false)]) { given, _ in given })
        models = rig.harness.context.modelsDirectory.appending(
            path: MeetingsUI.speechDirectoryName, directoryHint: .isDirectory)
    }

    var harness: MeetingsHarness { rig.harness }
    var lease: SpeechEngineLease { rig.lease }

    /// Writes the packages' files at their sizes as Lintel installs them (`Models/speech/<id>/`) and returns them.
    @discardableResult
    func install(_ packages: ModelPackage...) throws -> InstalledModels {
        for package in packages { try installFiles(of: package, in: models.appending(path: package.id)) }
        return InstalledModels(root: models)
    }

    func seed(storedModelID: String) async throws -> (id: Int64, uuid: UUID) {
        try await rig.seed(.processing, mic: Self.track, modelID: storedModelID)
    }

    /// The app's own resumer (`MeetingsRuntime.makeResumer`), with the devices replaced.
    func runtime(log: ResumeSetupLog) -> MeetingsRuntime {
        var runtime = MeetingsRuntime(context: harness.context, settings: harness.meetingsSettings)
        let spans = Self.track.spans
        let engine = rig.engine
        runtime.makeVAD = { folder in FolderRecordingVAD(folder: folder, spans: spans, log: log) }
        runtime.makeEngine = { id in
            log.recordEngine(id)
            return engine
        }
        runtime.lease = rig.lease
        return runtime
    }

    func library(runtime: MeetingsRuntime) -> MeetingsLibrary {
        rig.library(resumer: { store, keys, spool in runtime.makeResumer(store: store, keys: keys, spool: spool) })
    }
}

/// Where the packages were written, so a test can say which folder the detector should have asked for.
private struct InstalledModels {
    let root: URL

    func folder(of package: ModelPackage) -> String { root.appending(path: package.id).path }
}

/// Creates every file of `package` in `folder` (the package's own folder) at its exact size, sparsely:
/// `ModelManager.location(of:)` compares sizes only, so nothing reads these files and nothing but their length
/// is on disk.
private func installFiles(of package: ModelPackage, in folder: URL) throws {
    for entry in package.files {
        let file = folder.appending(path: package.relativePath(of: entry.file, in: entry.source))
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(entry.file.size))
        try handle.close()
    }
}
