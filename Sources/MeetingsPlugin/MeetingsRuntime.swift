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
    /// The shared "Languages I speak" setting (`PluginContext.speechLanguages`), read for every segment.
    let speechLanguages: any SpeechLanguageSettings
    let speechManager: ModelManager
    let diarizationManager: ModelManager
    /// At most one recording at a time, shared by everything that can start one.
    let gate = MeetingSessionGate()
    let logger: Logger
    var makeMicrophone: @Sendable (_ deviceUID: String?, _ deviceName: String?) -> any AudioInput = {
        MicrophoneCapture(deviceUID: $0, deviceName: $1)
    }
    var makeSystemAudio: @Sendable () -> any AudioInput = { SystemAudioSource(backend: CoreAudioProcessTapBackend()) }
    /// The default input as a log line, read when the microphone does not start.
    var inputDiagnostics: @Sendable () -> String = { DefaultInputObserver.diagnostics() }
    /// Yields when the system's default input changes while recording.
    var defaultInputChanges: (@Sendable () -> AsyncStream<Void>)? = { DefaultInputObserver.changes() }
    /// Where a speech package is, with the folder the user chose for it (`nil` = the download). Tests replace it,
    /// so the engine choice runs without model files.
    var locateSpeech: @Sendable (ModelPackage, URL?) async -> ModelLocation
    /// Whether the session starts the microphone again when it stops (off in a `--qa` run, whose track never ends).
    var retriesMicrophone = true

    @MainActor
    init(context: PluginContext, settings: MeetingsSettings) {
        self.settings = settings
        speechLanguages = context.speechLanguages
        logger = context.logger
        speechManager = ModelManagers.shared.manager(
            for: context.modelsDirectory.appending(path: MeetingsUI.speechDirectoryName, directoryHint: .isDirectory),
            logger: context.logger)
        let manager = self.speechManager
        locateSpeech = { await manager.location(of: $0, customFolder: $1) }
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

    /// Where `package` is. A folder the user chose counts only for the model chosen in Settings: "Choose Folder…"
    /// writes that model's key, so Whisper reached through the router always comes from its download.
    func location(of package: ModelPackage) async -> ModelLocation {
        let custom = settings.speechModelID == package.id ? settings.speechModelFolder : nil
        return await locateSpeech(package, custom)
    }

    /// Whether the Whisper model can be loaded now.
    func isWhisperInstalled() async -> Bool {
        await location(of: ModelCatalog.whisperLargeV3Turbo).folder != nil
    }

    /// The model the next recording uses (`MeetingEngineRouting`): the chosen one, or Whisper when the languages
    /// in play need it and it is installed.
    func routedSpeechPackage() async -> ModelPackage {
        let selected = speechPackage
        let installed = selected.id == ModelCatalog.whisperLargeV3Turbo.id ? true : await isWhisperInstalled()
        return MeetingEngineRouting.package(
            selected: selected, selection: speechLanguages.current(), whisperInstalled: installed)
    }

    /// Where the speech model of the next recording is. Read when a recording starts, so the engine is fixed for
    /// that recording and its stored model id is the engine that really transcribed it.
    func speechLookup() async -> SpeechModelLookup {
        let package = await routedSpeechPackage()
        if package.id != speechPackage.id {
            logger.notice("Meetings: the languages need Whisper, recording with it")
        }
        let location = await location(of: package)
        if let folder = location.folder { return .ready(modelID: package.id, folder: folder) }
        if case .customFolderUnavailable = location { return .unavailable }
        return .missing
    }

    /// One engine per recording, fixed to the model the recording started with: a change in Settings during
    /// the meeting applies to the next one.
    /// The engines hold no language: every request carries its own `SpeechRequestOptions` (`MeetingLanguage`),
    /// because the lease shares one engine with Dictation.
    func makeEngine(modelID: String) -> any SpeechEngine {
        SwitchingEngine(
            engines: [
                ModelCatalog.parakeetUltra.id: ParakeetEngine(),
                ModelCatalog.whisperLargeV3Turbo.id: WhisperKitEngine(),
            ],
            selected: { modelID })
    }

    /// A new profile for one recording or one recovery run, over the shared language setting.
    func makeLanguage() -> MeetingLanguage { MeetingLanguage(settings: speechLanguages) }

    // MARK: Session

    func makeFinalizer(store: MeetingsStore, keys: MeetingKeys, spool: SpoolStorage) -> MeetingFinalizer {
        let settings = settings
        let manager = diarizationManager
        let languages = speechLanguages
        let runtime = self
        let repair = LanguageRepair(
            store: store, speech: { await runtime.repairSpeech() }, hints: { languages.current().languages },
            openTrack: LanguageRepair.spoolOpener(spool: spool, keys: keys), logger: logger)
        return MeetingFinalizer(
            store: store, keys: keys, spool: spool, isEnabled: { settings.diarization },
            modelFolder: {
                await manager.location(
                    of: ModelCatalog.diarizationCommunity1, customFolder: settings.diarizationModelFolder
                ).folder
            }, languageRepair: repair, logger: logger)
    }

    /// The language repair's model: Whisper when it is installed (it can be pinned to a language), else Parakeet
    /// (a script hint only). A custom folder counts only for the model chosen in Settings, as everywhere else.
    func repairSpeech() async -> RepairSpeech? {
        let candidates: [(ModelPackage, RepairSpeech.Kind)] = [
            (ModelCatalog.whisperLargeV3Turbo, .whisper), (ModelCatalog.parakeetUltra, .parakeet),
        ]
        for (package, kind) in candidates {
            if let folder = await location(of: package).folder {
                return RepairSpeech(
                    kind: kind, modelID: package.id, folder: folder, engine: makeEngine(modelID: package.id))
            }
        }
        return nil
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
            defaultInputChanges: defaultInputChanges, language: makeLanguage(), logger: logger)
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
            }, finalize: finalizer.hook, keepAudio: { [settings] in settings.keepAudio },
            makeLanguage: { runtime.makeLanguage() }, logger: logger)
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
