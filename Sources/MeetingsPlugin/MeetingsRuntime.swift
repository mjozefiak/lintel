import Foundation
import LintelKit
import LintelSpeech
import os

/// The real parts behind the controller and the library: the speech engine, the voice activity detector, the
/// audio sources, the sleep assertion and the finalizer (diarization). Nothing here runs in a test: tests give
/// the controller and the library fakes instead (spec: Architecture, "Wyjątek od ...").
///
/// Audio sources are created per session by `makeMicrophone` and `makeSystemAudio`; they are the only places
/// that reach AVAudioEngine and Core Audio.
struct MeetingsRuntime: Sendable {
    let settings: MeetingsSettings
    let speechManager: ModelManager
    let diarizationManager: ModelManager
    /// At most one recording at a time, shared by everything that can start one.
    let gate = MeetingSessionGate()
    let logger: Logger
    var makeMicrophone: @Sendable (_ deviceUID: String?, _ deviceName: String?) -> any AudioInput = {
        MicrophoneCapture(deviceUID: $0, deviceName: $1)
    }
    var makeSystemAudio: @Sendable () -> any AudioInput = { SystemAudioSource(backend: CoreAudioProcessTapBackend()) }
    /// The default input as a log line, read when the microphone does not start; its name and UID are hashed
    /// (issue #269, `InputDeviceInfo.logDescription`).
    var inputDiagnostics: @Sendable () -> String = { DefaultInputObserver.diagnostics() }
    /// Yields when the system's default input changes while recording.
    var defaultInputChanges: (@Sendable () -> AsyncStream<Void>)? = { DefaultInputObserver.changes() }
    /// Whether the session starts the microphone again when it stops (off in a `--qa` run, whose track never ends).
    var retriesMicrophone = true

    @MainActor
    init(context: PluginContext, settings: MeetingsSettings) {
        self.settings = settings
        logger = context.logger
        speechManager = ModelManagers.shared.manager(
            for: context.modelsDirectory.appending(path: MeetingsUI.speechDirectoryName, directoryHint: .isDirectory),
            logger: context.logger)
        diarizationManager = ModelManagers.shared.manager(
            for: context.modelsDirectory.appending(
                path: MeetingsUI.diarizationDirectoryName, directoryHint: .isDirectory),
            logger: context.logger)
        #if DEBUG
        // A `--qa` run records WAV files or silence, never the tester's microphone or the system audio.
        if let qa = settings.qaAudio {
            makeMicrophone = { _, _ in QAAudioSource(file: qa.micWAV) }
            makeSystemAudio = { QAAudioSource(file: qa.systemWAV) }
            inputDiagnostics = { "" }
            defaultInputChanges = nil
            retriesMicrophone = false
        }
        #endif
    }

    // MARK: Models

    var speechPackage: ModelPackage {
        ModelCatalog.package(id: settings.speechModelID) ?? ModelCatalog.parakeetUltra
    }

    /// Where the speech model chosen in Settings is.
    func speechLookup() async -> SpeechModelLookup {
        let package = speechPackage
        let location = await speechManager.location(of: package, customFolder: settings.speechModelFolder)
        if let folder = location.folder { return .ready(modelID: package.id, folder: folder) }
        if case .customFolderUnavailable = location { return .unavailable }
        return .missing
    }

    /// One engine per recording, fixed to the model the recording started with: a change in Settings during
    /// the meeting applies to the next one.
    func makeEngine(modelID: String) -> any SpeechEngine {
        let settings = settings
        return SwitchingEngine(
            engines: [
                ModelCatalog.parakeetUltra.id: ParakeetEngine(language: { settings.speechLanguage }),
                ModelCatalog.whisperLargeV3Turbo.id: WhisperKitEngine(language: { settings.speechLanguage }),
            ],
            selected: { modelID })
    }

    // MARK: Session

    func makeFinalizer(store: MeetingsStore, keys: MeetingKeys, spool: SpoolStorage) -> MeetingFinalizer {
        let settings = settings
        let manager = diarizationManager
        return MeetingFinalizer(
            store: store, keys: keys, spool: spool, isEnabled: { settings.diarization },
            modelFolder: {
                await manager.location(
                    of: ModelCatalog.diarizationCommunity1, customFolder: settings.diarizationModelFolder
                ).folder
            }, logger: logger)
    }

    /// The two tracks of a recording. A recording of the system audio only gets a microphone that never starts: the
    /// session carries on with the other track.
    func makeSources(_ request: MeetingSessionRequest) -> (microphone: any AudioInput, system: (any AudioInput)?) {
        let microphone: any AudioInput =
            request.recordsMicrophone
            ? makeMicrophone(settings.inputDevice, settings.inputDeviceName) : UnavailableAudioInput()
        return (microphone, request.recordsSystemAudio ? makeSystemAudio() : nil)
    }

    func makeSession(_ request: MeetingSessionRequest) -> MeetingSession {
        let finalizer = makeFinalizer(store: request.store, keys: request.keys, spool: request.spool)
        let vadFolder = request.modelFolder.appending(path: ModelCatalog.sileroVADPath)
        let sources = makeSources(request)
        return MeetingSession(
            store: request.store, keys: request.keys, spool: request.spool, mic: sources.microphone,
            system: sources.system,
            makeVAD: { LazyVAD(modelFolder: vadFolder, tuning: MeetingVAD.tuning, recordsProbabilities: true) },
            engine: makeEngine(modelID: request.modelID),
            modelID: request.modelID, modelFolder: request.modelFolder, sleepAssertion: IOKitSleepAssertion(),
            gate: gate, beforeReady: finalizer.hook, sourceBundleID: request.sourceBundleID,
            keepAudio: { [settings] in settings.keepAudio },
            recordCounters: Self.counterRecorder(
                directory: request.spool.root.deletingLastPathComponent(), logger: logger),
            retriesMicrophone: request.recordsMicrophone && retriesMicrophone, inputDiagnostics: inputDiagnostics,
            defaultInputChanges: defaultInputChanges, logger: logger)
    }

    /// Writes a finished meeting's counters (numbers only) next to the library; a failure is logged and nothing else.
    static func counterRecorder(directory: URL, logger: Logger) -> @Sendable (CaptureCounters) -> Void {
        let store = CaptureCountersStore(directory: directory)
        return { counters in
            do { try store.record(counters) } catch { logger.error("The capture counters could not be saved") }
        }
    }

    // MARK: Recovery and "Dokończ"

    /// The resumer the library uses after a crash and for "Dokończ": the same speech setup and finalizer.
    func makeResumer(store: MeetingsStore, keys: MeetingKeys, spool: SpoolStorage) -> any MeetingResuming {
        let finalizer = makeFinalizer(store: store, keys: keys, spool: spool)
        let runtime = self
        return MeetingResumer(
            store: store, keys: keys, spool: spool,
            makeVAD: { FolderResolvingVAD(folder: { await runtime.speechLookup().folder }) },
            speech: {
                guard case .ready(let id, let folder) = await runtime.speechLookup() else { return nil }
                return ResumeSpeech(engine: runtime.makeEngine(modelID: id), modelID: id, folder: folder)
            }, finalize: finalizer.hook, keepAudio: { [settings] in settings.keepAudio }, logger: logger)
    }
}

extension SpeechModelLookup {
    var folder: URL? {
        if case .ready(_, let folder) = self { return folder }
        return nil
    }
}

/// An input that never starts. The session treats it as a microphone that could not be opened.
struct UnavailableAudioInput: AudioInput {
    struct Unavailable: Error {}

    func start(onLevel: @escaping @Sendable (Float) -> Void) async throws -> AsyncStream<[Float]> {
        throw Unavailable()
    }

    func stop() async {}
}

/// Silero detection for the resumer, which needs the detector before it knows the model folder: the folder is
/// looked up when the first audio arrives.
actor FolderResolvingVAD: VoiceActivityDetector {
    struct ModelMissing: Error {}

    private let folder: @Sendable () async -> URL?
    private var detector: SileroVAD?

    init(folder: @escaping @Sendable () async -> URL?) {
        self.folder = folder
    }

    func process(_ samples: [Float]) async throws -> [VADEvent] {
        if detector == nil {
            guard let folder = await folder() else { throw ModelMissing() }
            detector = try SileroVAD(
                modelFolder: folder.appending(path: ModelCatalog.sileroVADPath), tuning: MeetingVAD.tuning)
        }
        return try await detector?.process(samples) ?? []
    }
}
