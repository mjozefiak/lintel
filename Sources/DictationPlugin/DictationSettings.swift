import Foundation
import LintelKit
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
        /// decision 2026-11-26). Offered since 2026-11-27 (owner decision): `DictationSettings.fullIsOffered` gates it.
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
    }

    static let defaultSpeechModel = "parakeet-ultra"
    static let defaultKeepWarmMinutes = 10

    /// Whether Full is offered and runs. Spec phase 2: Full ships only when every measured target passes; with this off
    /// a stored `full` (a build that offers Full wrote it) shows and runs as Standard and the popup has no Full.
    /// **On since 2026-11-27 (owner decision after the Phase 2b measurement):** Full prompt v3 meets every Full target on
    /// the owner's corpus (self-corrections 6 of 7 against Standard's 5, no invented greeting, sign-off or lost number,
    /// chat WER equal to Standard's, fewer lost content words), so the popup offers Full and a stored `full` runs as Full.
    /// The flag stays the one place that would hide it again, and `DictationSettings(_:offersFull:)` is the same seam
    /// for tests.
    static let fullIsOffered = true

    private let settings: PluginSettings
    let offersFull: Bool

    init(_ settings: PluginSettings, offersFull: Bool = DictationSettings.fullIsOffered) {
        self.settings = settings
        self.offersFull = offersFull
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

    /// The level that runs now: `nil` while the cleanup is off. A stored `full` runs as Full while Full is offered (the
    /// shipped build since 2026-11-27) and as Standard while it is not.
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
