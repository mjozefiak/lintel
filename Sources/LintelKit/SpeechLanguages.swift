import Foundation

/// The languages the user speaks, shared by Dictation and Meetings (spec `2026-11-23-automatic-language-detection`,
/// owner decision D2). Language values are Whisper's language codes as plain strings (ISO 639-1 where one exists,
/// plus a few three-letter ones such as `haw` and `yue`), so this target does not depend on the speech layer.
public struct SpeechLanguageSelection: Sendable, Equatable {
    public enum Mode: Sendable, Equatable {
        /// Lintel recognises the language by itself; `languages` is the prior.
        case automatic
        /// Every recording and dictation is pinned to this one language.
        case single(String)
    }

    public var mode: Mode
    /// Catalog codes, ordered, 1...10 when read from the host.
    public var languages: [String]
    /// `true` while the user never edited the list: it is derived from the Mac's languages and nothing is stored.
    public var isDerived: Bool

    public init(mode: Mode, languages: [String], isDerived: Bool) {
        self.mode = mode
        self.languages = languages
        self.isDerived = isDerived
    }
}

/// The host's shared language setting (`PluginContext.speechLanguages`). Plugins read `current()` when a session
/// starts and when a segment is decoded; the Languages sheet writes through `update(_:)`.
public protocol SpeechLanguageSettings: Sendable {
    /// The validated selection. Reading never writes anything.
    func current() -> SpeechLanguageSelection
    /// Stores the selection (the host validates it first). A selection with `isDerived` or an empty list stores no
    /// list, so it is derived again from the Mac's languages.
    func update(_ selection: SpeechLanguageSelection)
    /// Yields after every change. Each read returns a NEW stream (an `AsyncStream` has one consumer, and two plugins
    /// and two panes listen).
    var changes: AsyncStream<Void> { get }
}

/// The default of a context built without a host (tests, previews): always the same selection, `update` does
/// nothing and `changes` finishes at once.
public struct FixedSpeechLanguageSettings: SpeechLanguageSettings {
    private let selection: SpeechLanguageSelection

    public init(_ mode: SpeechLanguageSelection.Mode = .automatic, _ languages: [String] = ["en"]) {
        selection = SpeechLanguageSelection(mode: mode, languages: languages, isDerived: true)
    }

    public func current() -> SpeechLanguageSelection { selection }

    public func update(_ selection: SpeechLanguageSelection) {}

    public var changes: AsyncStream<Void> { AsyncStream { $0.finish() } }
}
