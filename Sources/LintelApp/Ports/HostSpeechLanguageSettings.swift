import Foundation
import LintelKit
import LintelSpeech
import Synchronization

/// Hands every reader of `HostSpeechLanguageSettings.changes` its own stream and wakes them all after an update.
/// One per app (`AppEnvironment.speechLanguageChanges`), so a change made in the Meetings pane reaches Dictation.
nonisolated final class SpeechLanguageChangeHub: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    /// A new stream that yields after every change. It keeps at most one pending signal, so a slow reader sees
    /// "something changed" once instead of a queue.
    func makeStream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { _ = $0.removeValue(forKey: id) }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    /// Wakes every open stream. The continuations are read under the lock and called outside it.
    func notify() {
        let all = continuations.withLock { Array($0.values) }
        for continuation in all { continuation.yield() }
    }

    /// The number of open streams (tests).
    var streamCount: Int { continuations.withLock { $0.count } }
}

/// The host's implementation of the shared language setting (spec `2026-11-23-automatic-language-detection`, step
/// 2.1) over the `app.speech.*` keys of `SettingsStore`. Reading validates and never writes: codes outside
/// `SpeechLanguageCatalog` are dropped, the list is de-duplicated and capped at 10, a missing or empty list is
/// derived from the Mac's languages, an unknown mode reads as Automatic and a single language that is not in the
/// catalog falls back to the first listed language.
nonisolated struct HostSpeechLanguageSettings: SpeechLanguageSettings {
    /// "You can list up to 10 languages."
    static let maximumLanguages = 10
    /// The stored values of `app.speech.languageMode`.
    static let automaticMode = "auto"
    static let singleMode = "single"

    private let store: any SettingsStore
    private let hub: SpeechLanguageChangeHub
    private let preferredLanguages: @Sendable () -> [String]

    init(
        store: any SettingsStore, hub: SpeechLanguageChangeHub,
        preferredLanguages: @escaping @Sendable () -> [String] = { Locale.preferredLanguages }
    ) {
        self.store = store
        self.hub = hub
        self.preferredLanguages = preferredLanguages
    }

    func current() -> SpeechLanguageSelection {
        var languages: [String] = []
        if case .stringArray(let stored) = store.value(forKey: SettingsKeys.speechLanguages) {
            languages = Self.validated(stored)
        }
        let isDerived = languages.isEmpty
        if isDerived {
            languages = Self.derivedLanguages(from: preferredLanguages())
        }
        let mode: SpeechLanguageSelection.Mode
        if case .string(Self.singleMode) = store.value(forKey: SettingsKeys.speechLanguageMode) {
            var single: String?
            if case .string(let code) = store.value(forKey: SettingsKeys.speechSingleLanguage),
                SpeechLanguageCatalog.contains(code)
            {
                single = code
            }
            mode = .single(single ?? languages.first ?? Self.fallbackLanguage)
        } else {
            mode = .automatic
        }
        return SpeechLanguageSelection(mode: mode, languages: languages, isDerived: isDerived)
    }

    func update(_ selection: SpeechLanguageSelection) {
        let before = current()
        let languages = Self.validated(selection.languages)
        if selection.isDerived || languages.isEmpty {
            store.setValue(nil, forKey: SettingsKeys.speechLanguages)
        } else {
            store.setValue(.stringArray(languages), forKey: SettingsKeys.speechLanguages)
        }
        switch selection.mode {
        case .automatic:
            store.setValue(.string(Self.automaticMode), forKey: SettingsKeys.speechLanguageMode)
        case .single(let code):
            store.setValue(.string(Self.singleMode), forKey: SettingsKeys.speechLanguageMode)
            // An unknown code is not stored: the single language then reads as the first listed one.
            store.setValue(
                SpeechLanguageCatalog.contains(code) ? .string(code) : nil, forKey: SettingsKeys.speechSingleLanguage)
        }
        if current() != before {
            hub.notify()
        }
    }

    var changes: AsyncStream<Void> { hub.makeStream() }

    /// The language when nothing else is known: English is the product's core language.
    static let fallbackLanguage = "en"

    /// Catalog codes only, first occurrence kept, at most 10.
    static func validated(_ codes: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for code in codes where SpeechLanguageCatalog.contains(code) && seen.insert(code).inserted {
            result.append(code)
            if result.count == maximumLanguages { break }
        }
        return result
    }

    /// The list while the user never edited it: each preferred language reduced to its catalog code (`pl-PL` →
    /// `pl`, `zh-Hans-CN` → `zh`, `nb` → `no`), languages outside the catalog dropped, duplicates dropped, order
    /// kept, at most 10, and English when nothing matches.
    static func derivedLanguages(from preferred: [String]) -> [String] {
        let codes = validated(preferred.compactMap(SpeechLanguageCatalog.normalize))
        return codes.isEmpty ? [fallbackLanguage] : codes
    }
}
