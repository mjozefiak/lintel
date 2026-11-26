import Foundation
import LintelKit
import LintelProviders
import LintelSpeech

/// `plugins.dictation.*` (a protected contract from the release that ships it, `BACKWARD_COMPATIBILITY.md` §3).
/// Phase 1 reads the speech model, the microphone, keep-warm and the clipboard restore; the formatting and
/// history keys arrive with their phases.
struct DictationSettings: Sendable {
    enum Key {
        static let speechModel = "speechModel"
        static let speechLanguage = "speechLanguage"
        static let speechModelFolder = "speechModelFolder"
        static let inputDevice = "inputDevice"
        static let inputDeviceName = "inputDeviceName"
        static let keepWarmMinutes = "keepWarmMinutes"
        static let restoreClipboard = "restoreClipboard"
        static let mode = "mode"
        static let cleanupLevel = "cleanupLevel"
        static let llmEndpoint = "llmEndpoint"
        static let llmModel = "llmModel"
        static let llmSource = "llmSource"
        static let builtInLLMModel = "builtInLLMModel"
        static let provider = "provider"
        static let providerModel = "providerModel"
        static let historyEnabled = "historyEnabled"
        static let retentionDays = "retentionDays"
        static let maximumEntries = "maximumEntries"
        static let vocabularyEnabled = "vocabularyEnabled"
    }

    static let defaultRetentionDays = 30
    static let defaultMaximumEntries = 500
    static let retentionDayChoices = [1, 7, 30, 90]
    static let maximumEntryChoices = [100, 250, 500, 1000]

    /// What happens to the transcript before it is pasted.
    enum Mode: String, Sendable, CaseIterable {
        /// The transcript as the speech model wrote it.
        case raw
        /// Cleaned up by the user's local language model ("Porządkuj").
        case cleanup
    }

    /// How much the cleanup changes (spec `2026-11-25-dictation-cleanup-levels`). `mode` stays the on/off switch
    /// (`raw` = Off); the level only matters while `mode` is `cleanup`.
    enum CleanupLevel: String, Sendable, CaseIterable {
        /// Filler words out, nothing else: `LightCleaner`, no language model.
        case light
        /// Today's cleanup by a language model (`CleanupPrompt`).
        case standard
        /// Standard plus email layout, paragraphs for a longer dictation and a smoothed style (spec phase 2, owner
        /// decision 2026-11-26). Offered only while `DictationSettings.fullIsOffered` is on.
        case full

        /// Whether a language model does the work at this level.
        var usesModel: Bool { self != .light }
    }

    /// Where the cleanup model runs.
    enum LLMSource: String, Sendable, CaseIterable {
        /// The user's own server on this Mac (Ollama, LM Studio, llama-server).
        case server
        /// The model Lintel downloaded and runs itself (ADR 0005).
        case builtIn
        /// An external AI provider's CLI (spec `2026-11-25-dictation-cleanup-levels`, Phase 5): the dictated text leaves
        /// the Mac. Chosen only in Settings, which is the consent; an older build reads this value as `.server`.
        case provider
    }

    /// Where the tidying of one dictation really runs: the chosen source, or the local fallback when the provider is
    /// chosen but cannot serve the level (spec "Source × level").
    enum EffectiveSource: Equatable, Sendable {
        case provider(ProviderSelection)
        case builtIn
        case server
        /// No model runs: Light, or a provider source with no level offered and nothing local to fall back to.
        case none
    }

    /// The provider and model the user chose for dictation: `plugins.dictation.provider` + `providerModel`. Its own
    /// choice, never inherited from Meetings (spec A13).
    struct ProviderSelection: Equatable, Sendable {
        var provider: ProviderID
        var model: String

        /// What the history records for a dictation tidied by it: `cli:claude-code/sonnet`.
        var historyMark: String { "cli:\(provider.rawValue)/\(model)" }
    }

    /// The providers this build knows (the descriptors of `LintelProviders`); an id outside the list is "not chosen".
    static let knownProviders: [ProviderDescriptor] = [.claudeCode]

    static let defaultSpeechModel = "parakeet-ultra"
    static let defaultKeepWarmMinutes = 10

    /// Whether Full is offered and runs. Spec phase 2: Full ships only when its measured targets pass; with this off a
    /// stored `full` (a newer build wrote it) shows and runs as Standard and the popup has no Full. **Off since the first
    /// measurement (2026-11-26):** Full met every target but one, self-corrections OK 57 % against Standard's 71 % on the
    /// owner's corpus (4 of 7 items against 5 of 7), so it waits for the owner's decision. A DEBUG build turns it on for
    /// QA with `plugins.dictation.qaOfferFull=true`.
    static let fullIsOffered = false

    private let settings: PluginSettings
    let offersFull: Bool

    init(_ settings: PluginSettings, offersFull: Bool = DictationSettings.fullIsOffered) {
        self.settings = settings
        #if DEBUG
        self.offersFull = offersFull || settings.bool("qaOfferFull", default: false)
        #else
        self.offersFull = offersFull
        #endif
    }

    var speechModelID: String { settings.string(Key.speechModel) ?? Self.defaultSpeechModel }

    /// `pl` or `en`; only the Whisper engine uses it.
    var speechLanguage: String { settings.string(Key.speechLanguage) == "en" ? "en" : "pl" }

    /// A folder the user downloaded the model into by hand.
    var speechModelFolder: URL? {
        guard let path = settings.string(Key.speechModelFolder), !path.isEmpty else { return nil }
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// The input device's UID; `nil` follows the system's input.
    var inputDevice: String? {
        guard let uid = settings.string(Key.inputDevice), !uid.isEmpty else { return nil }
        return uid
    }

    var keepWarm: Duration {
        .seconds(60 * max(0, settings.integer(Key.keepWarmMinutes, default: Self.defaultKeepWarmMinutes)))
    }

    var restoresClipboard: Bool { settings.bool(Key.restoreClipboard, default: true) }

    /// Whether the user's vocabulary is applied after formatting (DICT-1.1); the pane for it is DICT-1.2.
    var vocabularyEnabled: Bool { settings.bool(Key.vocabularyEnabled, default: true) }

    var mode: Mode { settings.string(Key.mode).flatMap(Mode.init(rawValue:)) ?? .raw }

    /// The stored level; a missing or unknown value reads as `standard`, which is what `mode = cleanup` did before
    /// levels existed. Nothing is migrated.
    var cleanupLevel: CleanupLevel {
        settings.string(Key.cleanupLevel).flatMap(CleanupLevel.init(rawValue:)) ?? .standard
    }

    /// The level that runs now: `nil` while the cleanup is off. A stored `full` runs as Standard while Full is not
    /// offered.
    var effectiveLevel: CleanupLevel? {
        guard mode == .cleanup else { return nil }
        switch cleanupLevel {
        case .light: return .light
        case .standard: return .standard
        case .full: return offersFull ? .full : .standard
        }
    }

    /// Whether the cleanup needs a language model (server or built-in) right now.
    var usesModel: Bool { effectiveLevel?.usesModel ?? false }

    /// The formatting server's address, always a loopback one (the setter refuses anything else).
    var llmEndpoint: URL? {
        settings.string(Key.llmEndpoint).flatMap { LoopbackPolicy.parse($0) }
    }

    var llmModel: String? {
        guard let model = settings.string(Key.llmModel), !model.isEmpty else { return nil }
        return model
    }

    /// The server and model to format with, or `nil` until both are chosen.
    var llmTarget: LocalLLMFormatter.Target? {
        guard let url = llmEndpoint, let model = llmModel else { return nil }
        return .init(baseURL: url, model: model)
    }

    var llmSource: LLMSource { settings.string(Key.llmSource).flatMap(LLMSource.init(rawValue:)) ?? .server }

    /// The built-in model chosen in Settings; the default one until another is chosen or when the stored id is
    /// no longer in the catalog.
    var builtInLLMModel: LLMModel {
        settings.string(Key.builtInLLMModel).flatMap { LLMModelCatalog.model(id: $0) } ?? LLMModelCatalog.defaultModel
    }

    /// The provider the user chose for dictation, or `nil` while none is chosen (the provider source is then not
    /// selectable and a stored `provider` source runs locally). A missing or empty model is the descriptor's default; a
    /// model the provider does not offer (the hidden Haiku, a typed id) is "not chosen", never a guess: `ProviderRunner`
    /// starts nothing for it.
    var providerSelection: ProviderSelection? {
        guard let id = settings.string(Key.provider), !id.isEmpty,
            let descriptor = Self.knownProviders.first(where: { $0.id.rawValue == id })
        else { return nil }
        let stored = settings.string(Key.providerModel)
        let model = stored.flatMap { $0.isEmpty ? nil : $0 } ?? descriptor.defaultModelID
        guard ProviderDescriptor.isValidModelID(model), descriptor.models.contains(where: { $0.id == model }) else {
            return nil
        }
        return ProviderSelection(provider: descriptor.id, model: model)
    }

    /// Choosing the provider (the consent): writes the provider and its model, and makes it the source.
    func setProvider(_ selection: ProviderSelection) {
        settings.set(selection.provider.rawValue, for: Key.provider)
        settings.set(selection.model, for: Key.providerModel)
    }

    func clearProvider() {
        settings.removeValue(for: Key.provider)
        settings.removeValue(for: Key.providerModel)
    }

    /// Where `level` runs now (spec "Source × level"). `builtInInstalled` is the answer of a cached check, because the
    /// formatter is chosen synchronously when a dictation starts: the provider source serves only the levels in
    /// `offered`; any other level runs locally: the built-in model when it is installed, else the user's server when
    /// one is set, else not at all (raw). The source stored beside it is never changed by this.
    func effectiveSource(
        for level: CleanupLevel, builtInInstalled: Bool, offered: Set<CleanupLevel> = ProviderLevels.offered
    ) -> EffectiveSource {
        guard level.usesModel else { return .none }
        switch llmSource {
        case .builtIn: return .builtIn
        case .server: return .server
        case .provider:
            if let selection = providerSelection, offered.contains(level) { return .provider(selection) }
            if builtInInstalled { return .builtIn }
            return llmTarget != nil ? .server : .none
        }
    }

    #if DEBUG
    /// DEBUG only (`--qa-setting plugins.dictation.qaProviderStatus=ready|notInstalled|notSignedIn|incompatibleVersion|newerVersion`):
    /// the state the provider row shows, with no process started. Release builds never read it.
    var qaProviderStatus: ProviderStatus? {
        settings.string("qaProviderStatus").flatMap(ProviderStatus.init(rawValue:))
    }
    #endif

    func setLLMSource(_ source: LLMSource) { settings.set(source.rawValue, for: Key.llmSource) }
    func setBuiltInLLMModel(_ model: LLMModel) { settings.set(model.id, for: Key.builtInLLMModel) }

    /// Whether finished dictations are kept (encrypted) in the history.
    var historyEnabled: Bool { settings.bool(Key.historyEnabled, default: true) }
    var retentionDays: Int { max(1, settings.integer(Key.retentionDays, default: Self.defaultRetentionDays)) }
    var maximumEntries: Int { max(1, settings.integer(Key.maximumEntries, default: Self.defaultMaximumEntries)) }

    func setHistoryEnabled(_ value: Bool) { settings.set(value, for: Key.historyEnabled) }
    func setRetentionDays(_ days: Int) { settings.set(days, for: Key.retentionDays) }
    func setMaximumEntries(_ count: Int) { settings.set(count, for: Key.maximumEntries) }

    func setMode(_ mode: Mode) { settings.set(mode.rawValue, for: Key.mode) }
    func setCleanupLevel(_ level: CleanupLevel) { settings.set(level.rawValue, for: Key.cleanupLevel) }
    func setLLMModel(_ model: String?) {
        if let model, !model.isEmpty {
            settings.set(model, for: Key.llmModel)
        } else {
            settings.removeValue(for: Key.llmModel)
        }
    }

    /// Returns false (and stores nothing) when the address is not on this Mac.
    @discardableResult
    func setLLMEndpoint(_ text: String) -> Bool {
        if text.trimmingCharacters(in: .whitespaces).isEmpty {
            settings.removeValue(for: Key.llmEndpoint)
            return true
        }
        guard let url = LoopbackPolicy.parse(text) else { return false }
        settings.set(url.absoluteString, for: Key.llmEndpoint)
        return true
    }

    func setSpeechModelFolder(_ url: URL?) {
        if let url {
            settings.set(url.path, for: Key.speechModelFolder)
        } else {
            settings.removeValue(for: Key.speechModelFolder)
        }
    }

    /// The chosen device's name as Settings showed it, kept so the message "Microphone … is unavailable" can name a
    /// device that is unplugged; `nil` when the choice predates the name (the UID may still tell, for USB).
    var inputDeviceName: String? {
        guard let name = settings.string(Key.inputDeviceName), !name.isEmpty else { return nil }
        return name
    }

    func setInputDevice(_ uid: String?, name: String? = nil) {
        if let uid { settings.set(uid, for: Key.inputDevice) } else { settings.removeValue(for: Key.inputDevice) }
        if uid != nil, let name, !name.isEmpty {
            settings.set(name, for: Key.inputDeviceName)
        } else {
            settings.removeValue(for: Key.inputDeviceName)
        }
    }

    func setKeepWarmMinutes(_ minutes: Int) { settings.set(minutes, for: Key.keepWarmMinutes) }
    func setRestoresClipboard(_ value: Bool) { settings.set(value, for: Key.restoreClipboard) }
    func setVocabularyEnabled(_ value: Bool) { settings.set(value, for: Key.vocabularyEnabled) }
    func setSpeechModelID(_ id: String) { settings.set(id, for: Key.speechModel) }
    func setSpeechLanguage(_ language: String) { settings.set(language, for: Key.speechLanguage) }
}
