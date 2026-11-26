import AppKit
import Foundation
import LintelKit
import LintelProviders
import LintelSpeech
import LintelUI
import SwiftUI
import Synchronization
import os

/// Voice dictation (spec: Dyktowanie głosowe): records under a global shortcut, transcribes with a speech
/// model that runs inside Lintel, and pastes the text into the app in front. Audio never leaves the Mac
/// and is never written to disk.
///
/// - The shortcut's key-down and key-up go to `DictationController` (tap to toggle, hold to talk), which
///   runs `DictationSession`, the HUD and `TextPaster`.
/// - Models: `Models/speech/<id>/`, downloaded by `ModelManager` on the user's click, or a
///   folder the user points at. The engines never download.
///
/// Settings: `plugins.dictation.*` (see `DictationSettings.Key`). Disabled by default: the feature needs a
/// model download and the microphone.
@MainActor
public final class DictationPlugin: LintelPlugin {
    public nonisolated static let manifest = PluginManifest(
        id: "dictation",
        displayName: LocalizedStringResource("Dictation", comment: "Plugin name of voice dictation"),
        symbolName: "mic",
        order: 40,
        // The core since the owner decision of 2026-11-24: on for a new install.
        defaultEnabled: true,
        settingsGroup: .voice,
        summary: LocalizedStringResource(
            "Speak instead of typing.", comment: "Settings → Features: what Dictation does")
    )

    static let recordCommandID = "dictation.record"
    static let pasteLastRawCommandID = "dictation.pasteLastRaw"
    static let historyCommandID = "dictation.history"
    static let historyModeID: PanelModeID = "dictation.history"
    static let onboardingStepID = "dictation.setup"

    let context: PluginContext
    let settings: DictationSettings
    private let engine: SwitchingEngine
    private let authorizer: any MicrophoneAuthorizer
    private let models: ModelManager
    /// Downloads the built-in formatting models into `Models/llm/` (used by the settings in step 4.4).
    let llmModels: ModelManager
    nonisolated static let llmDirectoryName = "llm"
    nonisolated static let speechDirectoryName = "speech"
    /// The built-in formatting model, loaded on demand and freed after the keep-warm time.
    private let builtInLLM: KeepWarmRuntime
    private let hud: DictationHUDPanel
    let settingsModel: DictationSettingsModel
    #if DEBUG
    private var qaHUD: DictationHUDQA?
    /// `qa dictation play` (`DictationQAPlayback`): the WAV file played instead of the microphone, and the HUD wrapper.
    let qaPlayback = DictationQAPlayback()
    private(set) var qaRecorder: DictationQARecorder?
    #endif
    /// Internal for the tests (the pane's model of the tidy-up rows).
    let formattingModel: FormattingSettingsModel
    private let transport: any HTTPTransport
    /// The runner of the provider source, made on first use (`DictationProviders`).
    let providerRunner: ProviderRunnerHolder
    /// Whether the built-in formatting model is installed, as last read (`formatter(…)` is chosen synchronously when a
    /// dictation starts, so the local fallback of a provider source needs the answer ready).
    let builtInInstalled = BuiltInInstalledFlag()
    let history: DictationHistory
    /// The user's vocabulary (DICT-1.1); loaded on activation, so the settings pane never reads the disk.
    let vocabulary: VocabularyStore
    /// The Vocabulary section's model (DICT-1.2); it reads the store, which `activate()` loads.
    let vocabularyModel: VocabularyPanelModel
    /// The history as a Notes source (`noteSources`); its change streams end on `deactivate()`.
    let noteSource: DictationNoteSource
    private let noteChanges = NoteChangeHub()
    private let historyModel: HistorySettingsModel
    private(set) var controller: DictationController?
    /// Where app activations are posted (tests use their own centre).
    var appActivationCenter: NotificationCenter = .default
    private var activationObserver: AppActivationObserver?

    public convenience init(context: PluginContext) {
        self.init(context: context, makeBuiltInLLM: nil)
    }

    /// `makeBuiltInLLM` replaces the built-in formatting runtime (tests); `nil` is the real one over llama.cpp.
    /// `authorizer` replaces the system's microphone permission (tests).
    init(
        context: PluginContext, makeBuiltInLLM: ((DictationSettings, ModelManager) -> KeepWarmRuntime)?,
        authorizer: any MicrophoneAuthorizer = SystemMicrophoneAuthorizer()
    ) {
        self.context = context
        self.authorizer = authorizer
        let settings = DictationSettings(context.settings)
        self.settings = settings
        engine = SwitchingEngine(
            engines: [
                ModelCatalog.parakeetUltra.id: ParakeetEngine(),
                ModelCatalog.whisperLargeV3Turbo.id: WhisperKitEngine(language: { settings.speechLanguage }),
            ],
            selected: { settings.speechModelID })
        let models = ModelManagers.shared.manager(
            for: context.modelsDirectory.appending(path: Self.speechDirectoryName, directoryHint: .isDirectory),
            logger: context.logger)
        self.models = models
        // Formatting models (ADR 0005) live next to the speech models in the shared `Models/` folder (ADR 0006).
        let llmModels = ModelManagers.shared.manager(
            for: context.modelsDirectory.appending(path: Self.llmDirectoryName, directoryHint: .isDirectory),
            logger: context.logger)
        self.llmModels = llmModels
        builtInLLM =
            makeBuiltInLLM?(settings, llmModels)
            ?? KeepWarmRuntime(
                runtime: LlamaRuntime(),
                modelURL: {
                    let model = settings.builtInLLMModel
                    guard let folder = await llmModels.location(of: model.package).folder,
                        let file = model.fileURL(in: folder)
                    else { throw LlamaError.modelNotFound }
                    return file
                },
                keepWarm: { settings.keepWarm }, lease: .shared)
        let workspace = context.workspace
        #if DEBUG
        // The pane and the banner of a `--qa` run read the permission as granted too, and never show the prompt.
        let settingsAuthorizer: any MicrophoneAuthorizer =
            context.settings.bool(DictationQAPlayback.settingName, default: false)
            ? DictationQAAuthorizer(playback: DictationQAPlayback(), base: authorizer, isQARun: true) : authorizer
        #else
        let settingsAuthorizer = authorizer
        #endif
        settingsModel = DictationSettingsModel(
            package: ModelCatalog.package(id: settings.speechModelID) ?? ModelCatalog.parakeetUltra, manager: models,
            settings: settings,
            authorizer: settingsAuthorizer,
            pickFolder: { Self.chooseModelFolder() },
            openURL: { url in Task { try? await workspace.open(url) } })
        // The banner reads the model's place and the microphone; a change makes the shell read it again.
        let resultsChanged = context.resultsChanged
        settingsModel.onStatusChange = { resultsChanged() }
        let noteChanges = noteChanges
        history = DictationHistory(
            directory: context.storageDirectory, keychain: context.keychain, settings: settings,
            clock: context.clock, logger: context.logger,
            changed: {
                resultsChanged()
                noteChanges.notify()
            })
        #if DEBUG
        vocabulary = VocabularyQA.makeStore(context: context)
        #else
        vocabulary = VocabularyStore(directory: context.storageDirectory, logger: context.logger)
        #endif
        vocabularyModel = VocabularyPanelModel(
            store: vocabulary, settings: settings,
            revealInFinder: { url in workspace.revealInFinder([url]) })
        noteSource = DictationNoteSource(
            history: history, hub: noteChanges, retentionDays: { settings.retentionDays })
        historyModel = HistorySettingsModel(settings: settings, history: history)
        let keptNoteCopies = context.keptNoteCopies
        let deleteKeptNoteCopies = context.deleteKeptNoteCopies
        historyModel.keptCopies = { await keptNoteCopies(Self.manifest.id) }
        historyModel.deleteKeptCopies = { await deleteKeptNoteCopies(Self.manifest.id, false) }
        let transport = LoopbackTransport()
        self.transport = transport
        let providerRunner = ProviderRunnerHolder(providers: .standard, cachesDirectory: context.cachesDirectory)
        self.providerRunner = providerRunner
        let installed = builtInInstalled
        formattingModel = FormattingSettingsModel(
            settings: settings, transport: transport, llmModels: llmModels, runtime: builtInLLM,
            providerStatus: { await providerRunner.runner.report(of: $0, lane: .interactive) })
        formattingModel.onBuiltInLocation = { installed.set($0.folder != nil) }
        let openSettings = context.openSettings
        let openModels = context.openModels
        // The HUD's buttons call back into the controller, which exists once the plugin is active.
        let relay = ControllerRelay()
        // A missing or broken speech model goes to the Models pane; the microphone problem goes to Settings.
        hud = DictationHUDPanel(
            onCancel: { relay.controller?.cancel() }, onOpenSettings: { openSettings() },
            onOpenModels: { openModels(settings.speechModelID) })
        self.relay = relay
        #if DEBUG
        qaRecorder = DictationQARecorder(wrapping: hud)
        #endif
    }

    /// Internal so tests can hand `modelUsage` a controller.
    let relay: ControllerRelay

    private static func chooseModelFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Button of the model folder picker")
        panel.message = String(
            localized: "Choose the folder that contains the speech model's files.",
            comment: "Message of the model folder picker")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// The formatter for a new session, chosen by the level in force when the dictation starts: none when the cleanup is
    /// off, `LightCleaner` for Light (no model, no server, no lease, no provider), else the formatter of the EFFECTIVE
    /// source (`DictationSettings.effectiveSource`): the user's server, the built-in model, or the external provider
    /// (only for a level it serves; any other runs locally, and with nothing local the text is pasted as spoken).
    /// `protectedWords` are the vocabulary's terms and variants, which Light never removes or changes.
    nonisolated static func formatter(
        settings: DictationSettings, transport: any HTTPTransport, builtIn: KeepWarmRuntime, logger: Logger,
        protectedWords: @escaping @Sendable () -> [String] = { [] }, builtInInstalled: Bool = true,
        providerRunner: ProviderRunnerHolder? = nil
    ) -> (any TextFormatter)? {
        guard let level = settings.effectiveLevel else { return nil }
        if level == .light { return LightCleaner(protectedWords: protectedWords) }
        switch settings.effectiveSource(for: level, builtInInstalled: builtInInstalled) {
        case .server:
            return LocalLLMFormatter(transport: transport, target: { settings.llmTarget }, level: level, logger: logger)
        case .builtIn:
            return BuiltInFormatter(runtime: builtIn, level: level, logger: logger)
        case .provider(let selection):
            guard let providerRunner else { return nil }
            // The authorization re-reads the settings before every process: the source must still be the provider, and
            // it must be the one this session started with.
            return ProviderFormatter(
                runner: providerRunner.runner, selection: selection, level: level,
                currentSelection: { settings.llmSource == .provider ? settings.providerSelection : nil },
                logger: logger)
        case .none:
            return nil
        }
    }

    /// "Claude": what a HUD line calls the provider that is chosen (the descriptor's short name).
    nonisolated static func providerName(settings: DictationSettings) -> String {
        let chosen = settings.providerSelection?.provider
        return (DictationSettings.knownProviders.first { $0.id == chosen } ?? DictationSettings.knownProviders.first)?
            .shortName ?? "Claude"
    }

    /// How long after the key release the session waits for formatting that is still out: only the provider source has a
    /// limit (`ProviderLevels.releaseDeadline`, owner decision 2026-11-26); the local sources keep their own timeouts.
    nonisolated static func releaseDeadline(settings: DictationSettings, builtInInstalled: Bool) -> Duration? {
        guard let level = settings.effectiveLevel,
            case .provider = settings.effectiveSource(for: level, builtInInstalled: builtInInstalled)
        else { return nil }
        return ProviderLevels.releaseDeadline(for: level)
    }

    /// The model the history records for a dictation, by the source that ran: the built-in model's id, the server's model
    /// name, or `cli:claude-code/sonnet` for the provider; `nil` at Light or Off, and where nothing ran, so the note's
    /// column stays empty and never shows a fake name (a local fallback records the local model, not the provider).
    nonisolated static func formatterModel(settings: DictationSettings, builtInInstalled: Bool = true) -> String? {
        guard let level = settings.effectiveLevel else { return nil }
        switch settings.effectiveSource(for: level, builtInInstalled: builtInInstalled) {
        case .builtIn: return settings.builtInLLMModel.id
        case .server: return settings.llmModel
        case .provider(let selection): return selection.historyMark
        case .none: return nil
        }
    }

    /// The words Light keeps: the vocabulary's terms and spoken variants, empty while the vocabulary is switched off.
    nonisolated static func protectedWords(
        settings: DictationSettings, vocabulary: VocabularyStore
    ) -> @Sendable () -> [String] {
        { settings.vocabularyEnabled ? vocabulary.terms.flatMap { [$0.term] + $0.aliases } : [] }
    }

    /// The vocabulary step of a dictation (DICT-1.1): the user's terms replace what was said, or nothing
    /// changes while `plugins.dictation.vocabularyEnabled` is off or the vocabulary is empty. Read per call, so
    /// the switch and edits apply to the next dictation.
    nonisolated static func termReplacement(
        settings: DictationSettings, vocabulary: VocabularyStore
    ) -> @Sendable (String) -> String {
        { text in settings.vocabularyEnabled ? vocabulary.replacer.apply(to: text) : text }
    }

    // MARK: Lifecycle

    public func activate() async throws {
        let context = context
        #if DEBUG
        // `--qa-hud dictation:<state>`: draws the HUD in that state, nothing else (docs/qa.md).
        if let name = context.settings.string(DictationHUDQA.settingName) {
            let hud = DictationHUDQA()
            if hud.show(named: name) {
                qaHUD = hud
            } else {
                context.logger.error("Unknown --qa-hud dictation state")
            }
        }
        #endif
        let settings = settings
        let engine = engine
        let lease = SpeechEngineLease.shared
        let transport = transport
        let history = history
        let builtInLLM = builtInLLM
        let vocabulary = vocabulary
        let builtInInstalled = builtInInstalled
        let providerRunner = providerRunner
        #if DEBUG
        let qaPlayback = qaPlayback
        let qaRecorder = qaRecorder
        let isQARun = context.settings.bool(DictationQAPlayback.settingName, default: false)
        let authorizer: any MicrophoneAuthorizer = DictationQAAuthorizer(
            playback: qaPlayback, base: self.authorizer, isQARun: isQARun)
        let hud: any HUDPresenter = qaRecorder ?? self.hud
        #else
        let authorizer = self.authorizer
        let hud: any HUDPresenter = self.hud
        #endif
        let controller = DictationController(
            .init(
                authorizer: authorizer, models: models,
                package: { ModelCatalog.package(id: settings.speechModelID) ?? ModelCatalog.parakeetUltra },
                customFolder: { settings.speechModelFolder },
                makeSession: { folder, onEvent in
                    #if DEBUG
                    let audio: any AudioInput =
                        qaPlayback.input(isQARun: isQARun)
                        ?? MicrophoneCapture(deviceUID: settings.inputDevice, deviceName: settings.inputDeviceName)
                    #else
                    let audio: any AudioInput = MicrophoneCapture(
                        deviceUID: settings.inputDevice, deviceName: settings.inputDeviceName)
                    #endif
                    return DictationSession(
                        audio: audio,
                        vad: LazyVAD(modelFolder: folder.appending(path: ModelCatalog.sileroVADPath)),
                        engine: engine,
                        formatter: Self.formatter(
                            settings: settings, transport: transport, builtIn: builtInLLM, logger: context.logger,
                            protectedWords: Self.protectedWords(settings: settings, vocabulary: vocabulary),
                            builtInInstalled: builtInInstalled.value, providerRunner: providerRunner),
                        releaseDeadline: Self.releaseDeadline(
                            settings: settings, builtInInstalled: builtInInstalled.value),
                        replaceTerms: Self.termReplacement(settings: settings, vocabulary: vocabulary),
                        modelFolder: folder, lease: lease, modelID: settings.speechModelID,
                        keepWarm: { settings.keepWarm }, logger: context.logger, onEvent: onEvent)
                },
                lease: lease,
                paster: TextPaster(
                    pasteboard: context.pasteboard, events: context.events, workspace: context.workspace,
                    permissions: context.permissions, clock: context.clock,
                    restoresClipboard: { settings.restoresClipboard }, logger: context.logger),
                hud: hud, claimEscape: context.claimEscapeKey, openSettings: context.openSettings,
                clock: context.clock,
                recordHistory: {
                    #if DEBUG
                    qaRecorder?.record($0)
                    #endif
                    history.record($0)
                },
                frontmostBundleID: { context.workspace.frontmostApplication?.bundleIdentifier },
                formatMode: { settings.effectiveLevel == nil ? .raw : .clean },
                speechModelID: { settings.speechModelID },
                formatterModel: { Self.formatterModel(settings: settings, builtInInstalled: builtInInstalled.value) },
                providerName: { Self.providerName(settings: settings) }))
        self.controller = controller
        relay.controller = controller
        history.open()
        vocabulary.load()
        vocabularyModel.reload()
        #if DEBUG
        VocabularyQA.apply(to: vocabularyModel, context: context)
        #endif
        // The banner's state is known before the shell first reads it; coming back from System Settings or from
        // a download elsewhere re-reads it.
        await settingsModel.refreshStatus()
        // Where the built-in model is, for the local fallback of a provider source (no process, no download).
        await formattingModel.refreshBuiltIn()
        let model = settingsModel
        activationObserver = AppActivationObserver(center: appActivationCenter) {
            Task { await model.refreshStatus() }
        }
    }

    public func deactivate() async {
        // The streams end when this method returns, after the history is closed: a read that started earlier may
        // still answer, a read after the history closed throws.
        defer { noteChanges.finishAll() }
        activationObserver?.stop()
        activationObserver = nil
        await controller?.shutDown()
        await builtInLLM.unload()
        history.close()
        controller = nil
        relay.controller = nil
    }

    /// "Erase Data": the host deletes `Plugins/dictation/` (the history) after this. Removes the history's
    /// Keychain item; the folder (`dictation.sqlite`) is deleted by the host. Downloaded models live in the
    /// shared `Models/` folder (ADR 0006) and stay; "Remove model" in Settings deletes them.
    public func eraseData() async throws {
        // The vocabulary first: a history that cannot be erased must not keep the user's terms alive.
        try vocabulary.erase()
        vocabularyModel.reload()
        try history.erase()
    }

    // MARK: Contributions

    public var commands: [PluginCommand] {
        let relay = relay
        return [
            PluginCommand(
                id: Self.recordCommandID,
                title: LocalizedStringResource("Dictate", comment: "Menu item and command that starts dictation"),
                symbolName: "mic",
                defaultShortcut: KeyShortcut(key: "d", modifiers: [.control, .option]),
                run: { relay.controller?.menu() },
                onKeyEvent: { phase in relay.controller?.keyEvent(phase) }),
            PluginCommand(
                id: Self.pasteLastRawCommandID,
                title: LocalizedStringResource(
                    "Paste raw version of the last dictation",
                    comment: "Menu item and command that pastes the last dictation without formatting"),
                symbolName: "text.badge.minus",
                run: { relay.controller?.pasteLastRaw() }),
            PluginCommand(
                id: Self.historyCommandID,
                title: LocalizedStringResource(
                    "Dictation History", comment: "Menu item and command that opens the dictation history"),
                symbolName: "clock.arrow.circlepath",
                panelMode: Self.historyModeID),
        ]
    }

    public var panelModes: [PanelMode] {
        let history = history
        let relay = relay
        var source = DictationHistorySource(
            store: { history.storeBox.value },
            paste: { text in await relay.pasteFromHistory(text) },
            delete: { id in try await history.delete([id]) })
        let openNote = context.openNote
        source.openInNotes = { row in
            guard let storeID = history.storeID else { return }
            _ = await openNote(DictationNoteSource.key(storeID: storeID, row: row))
        }
        return [
            PanelMode(
                id: Self.historyModeID,
                title: LocalizedStringResource(
                    "Dictation History", comment: "Menu item and command that opens the dictation history"),
                symbolName: "clock.arrow.circlepath",
                source: source,
                filters: [
                    PanelModeFilter(
                        id: HistoryFilter.all.rawValue,
                        title: LocalizedStringResource("All", comment: "Dictation history filter"),
                        symbolName: "list.bullet"),
                    PanelModeFilter(
                        id: HistoryFilter.formatted.rawValue,
                        title: LocalizedStringResource("Formatted", comment: "Dictation history filter"),
                        symbolName: "wand.and.stars"),
                    PanelModeFilter(
                        id: HistoryFilter.raw.rawValue,
                        title: LocalizedStringResource("Raw", comment: "Dictation history filter"),
                        symbolName: "text.alignleft"),
                ],
                makeStatus: { AnyView(DictationHistoryStatusView(history: history)) },
                makePreview: { candidate in
                    AnyView(
                        DictationPreview(
                            id: DictationPresentation.entryID(candidate.itemKey),
                            load: { id in try? history.storeBox.value?.entry(id) }))
                },
                makeEmptyView: { AnyView(DictationHistoryEmptyView(history: history)) })
        ]
    }

    public var noteSources: [any NoteSource] { [noteSource] }

    /// Offers a history entry to the shell's Notes workspace (`PluginContext.openNote`). `true` only when a
    /// section took it; the default handler returns `false`. The history's "Open in Lintel" action (⌘O) goes through the same context call.
    func openNote(entryID: Int64) -> Bool {
        guard let storeID = history.storeID else { return false }
        return context.openNote(DictationNoteSource.key(storeID: storeID, row: entryID))
    }

    public var requiredPermissions: Set<Permission> { [.microphone, .accessibility] }

    /// The models dictation uses, for the shell's Models pane (spec `2026-11-04-lintel-main-window`, step 3.2):
    /// the selected speech model (required unless the user chose a folder for it) and the built-in formatting model
    /// (optional, selected only while the built-in source is chosen; in use while a request holds it, as the
    /// Formatting settings check today).
    public var modelUsage: [ModelUsage] {
        let settings = settings
        let relay = relay
        let builtInLLM = builtInLLM
        let speech = ModelCatalog.package(id: settings.speechModelID) ?? ModelCatalog.parakeetUltra
        return [
            ModelUsage(
                packageID: speech.id, kind: .speech,
                role: LocalizedStringResource(
                    "Dictation", comment: "Models pane: what Dictation uses the speech model for"),
                // With a chosen folder the downloaded copy is not needed; the pane shows the folder's state.
                isRequired: settings.speechModelFolder == nil, isSelected: true,
                chooseFolder: { settings.setSpeechModelFolder($0) },
                customFolder: settings.speechModelFolder,
                isInUse: { relay.controller?.isBusy ?? false }),
            ModelUsage(
                packageID: settings.builtInLLMModel.id, kind: .llm,
                role: LocalizedStringResource(
                    "Formatting", comment: "Models pane: what Dictation uses the language model for"),
                isRequired: false, isSelected: settings.llmSource == .builtIn,
                isInUse: { await builtInLLM.isInUse() }),
        ]
    }

    public var onboardingSteps: [OnboardingStep] {
        let model = settingsModel
        let permissions = context.permissions
        return [
            OnboardingStep(
                id: Self.onboardingStepID,
                title: LocalizedStringResource("Dictation", comment: "Plugin name of voice dictation"),
                symbolName: "mic",
                text: DictationSetupView.text
            ) {
                AnyView(
                    DictationSetupView(
                        model: model, accessibilityAllowed: { permissions.status(of: .accessibility) == .granted })
                )
            }
        ]
    }

    /// Recording or producing the text of a dictation (`DictationController.busyReason`); `nil` before activation.
    public var busyReason: BusyReason? { controller?.busyReason }

    /// The main window's banner (prototype `set-dictation`). The shell reads it only while the plugin is active
    /// and while the view draws, so it only reads: the model's place and the microphone are re-read on
    /// activation, when the pane appears and when Lintel becomes the active app, and a change signals
    /// `resultsChanged`. A denied microphone or Accessibility is listed by the shell's derivation; the title's
    /// number counts it (`ThingsToDo`).
    public var settingsStatus: SettingsStatus? {
        let model = settingsModel
        let history = history
        let denied = ThingsToDo.deniedPermissions(
            requiredPermissions, countedByPlugin: model.microphone == .notDetermined ? [.microphone] : [],
            reader: context.permissions)
        return Self.settingsStatus(
            location: model.location, microphone: model.microphone, history: history.status,
            modelTitle: model.package.title, packageID: model.package.id, deniedPermissions: denied,
            allowMicrophone: { await model.requestMicrophoneAccess() },
            retryHistory: { history.open() })
    }

    /// The banner ids of the plugin's own actions.
    nonisolated static let allowMicrophoneActionID = "allowMicrophone"
    nonisolated static let retryHistoryActionID = "retry"

    /// Most important first: what keeps dictation from working (the speech model, a microphone macOS has not
    /// asked about yet; "N things to do" as in the prototype), then a history that cannot be opened (dictation
    /// still works; Try Again, nothing is deleted), else "Ready". `deniedPermissions` is how many denied required
    /// permissions the shell adds to the detail; the number in the title counts them too.
    static func settingsStatus(
        location: ModelLocation,
        microphone: MicrophoneAccess,
        history: DictationHistory.Status,
        modelTitle: String,
        packageID: String,
        deniedPermissions: Int = 0,
        allowMicrophone: @escaping @MainActor @Sendable () async -> Void,
        retryHistory: @escaping @MainActor @Sendable () async -> Void
    ) -> SettingsStatus? {
        let needsModel = location.folder == nil
        let needsMicrophone = microphone == .notDetermined
        let getModel = SettingsStatusAction(
            title: LocalizedStringResource(
                "Get It in Models", comment: "Settings banner button: opens the Models pane on the missing model"),
            destination: .models(packageID: packageID))
        let askMicrophone = SettingsStatusAction(
            title: LocalizedStringResource("Allow Microphone", comment: "Button that asks for microphone access"),
            destination: .plugin(id: allowMicrophoneActionID, perform: allowMicrophone))
        let title = ThingsToDo.title((needsModel ? 1 : 0) + (needsMicrophone ? 1 : 0) + deniedPermissions)
        switch (needsModel, needsMicrophone) {
        case (true, true):
            return SettingsStatus(
                level: .attention, title: title,
                detail: LocalizedStringResource(
                    "Allow the microphone and get the speech model.",
                    comment: "Settings banner detail: the microphone was not asked yet and the speech model is missing"
                ),
                fix: [askMicrophone, getModel])
        case (true, false):
            let detail: LocalizedStringResource
            if case .customFolderUnavailable = location {
                detail = LocalizedStringResource(
                    "The speech model’s folder isn’t available.",
                    comment: "Settings → Dictation banner detail: the folder the user chose for the model is gone")
            } else {
                detail = LocalizedStringResource(
                    "The speech model isn’t installed.", comment: "Settings banner detail: the speech model is missing")
            }
            return SettingsStatus(level: .attention, title: title, detail: detail, fix: [getModel])
        case (false, true):
            return SettingsStatus(
                level: .attention, title: title,
                detail: LocalizedStringResource(
                    "Allow the microphone so Lintel can hear you.",
                    comment: "Settings → Dictation banner detail: macOS has not asked for the microphone yet"),
                fix: [askMicrophone])
        case (false, false):
            break
        }
        let paused = LocalizedStringResource(
            "History is paused (dictation)", defaultValue: "History is paused",
            comment: "Settings → Dictation banner when the dictation history cannot be opened")
        let tryAgain = SettingsStatusAction(
            title: LocalizedStringResource(
                "Try Again (dictation history)", defaultValue: "Try Again",
                comment: "Settings → Dictation banner button that opens the dictation history again"),
            destination: .plugin(id: retryHistoryActionID, perform: retryHistory))
        switch history {
        case .unavailable:
            return SettingsStatus(
                level: .attention, title: paused,
                detail: LocalizedStringResource(
                    "Lintel can’t read the history’s key. Nothing was deleted.",
                    comment: "Settings → Dictation banner detail when the history key cannot be read"),
                fix: [tryAgain])
        case .failed:
            return SettingsStatus(
                level: .attention, title: paused,
                detail: LocalizedStringResource(
                    "The history couldn’t be opened. Dictation still works.",
                    comment: "Settings → Dictation banner detail when the history database cannot be opened"),
                fix: [tryAgain])
        case .closed, .ready:
            break
        }
        return SettingsStatus(
            level: .ok,
            title: LocalizedStringResource("Ready", comment: "Settings banner level, spoken"),
            detail: LocalizedStringResource(
                "Speech model: \(modelTitle).",
                comment: "Settings → Dictation banner detail when dictation is ready: the speech model's name"))
    }

    public func settingsPane() -> AnyView? {
        AnyView(
            DictationSettingsPane(
                model: settingsModel, formatting: formattingModel, history: historyModel,
                vocabulary: vocabularyModel,
                recorder: context.makeShortcutRecorder(Self.recordCommandID), isActive: controller != nil,
                openModels: context.openModels))
    }
}

/// Lets the HUD and the command reach the controller, which is created when the plugin activates.
@MainActor
final class ControllerRelay {
    var controller: DictationController?

    func pasteFromHistory(_ text: String) async {
        await controller?.pasteFromHistory(text)
    }
}

/// Whether the built-in formatting model is installed, as last read by the Settings model (the formatter is chosen
/// synchronously when a dictation starts).
final class BuiltInInstalledFlag: Sendable {
    private let state = Mutex(true)
    /// Starts as `true`: until the model's place is read, the built-in source behaves as before this flag existed.
    var value: Bool { state.withLock { $0 } }
    func set(_ installed: Bool) { state.withLock { $0 = installed } }
}
