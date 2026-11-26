import Foundation
import LintelKit
import LintelSpeech

/// One-time move of the two per-plugin Whisper languages into the shared "Languages I speak" list (spec
/// `2026-11-23-automatic-language-detection`, Data Model, step 2.3; `BACKWARD_COMPATIBILITY.md` §3).
///
/// `plugins.meetings.speechLanguage` and `plugins.dictation.speechLanguage` were written only by the Whisper language
/// row, so a stored value is a choice the user made. When at least one exists and the user has no list of their own
/// yet, the list becomes those values (Meetings first, no duplicates) followed by the Mac's languages, at most 10.
/// The mode is never written: it stays Automatic (owner decision D1), so a former Whisper pin becomes a prior. Then
/// both old keys are removed and the marker is set, so a value an older build writes later stays unread.
///
/// Runs once per install, in `AppEnvironment.pinPreviousPluginDefaults`, before any plugin reads its settings.
nonisolated struct SpeechLanguageMigration {
    /// The full keys of the removed `MeetingsSettings` / `DictationSettings` `speechLanguage` entries. They are
    /// declared here only, because nothing else reads them any more.
    static let meetingsLanguageKey = "plugins.meetings.speechLanguage"
    static let dictationLanguageKey = "plugins.dictation.speechLanguage"

    enum Outcome: Equatable {
        /// The marker was set: nothing was read or changed.
        case alreadyMigrated
        /// Neither old key held a language.
        case nothingToMove
        /// The user already has a list of their own; the old values were dropped.
        case listAlreadyPresent
        /// The list was written from the old values (and the Mac's languages).
        case moved([String])
    }

    @discardableResult
    static func run(
        settings: any SettingsStore, preferredLanguages: () -> [String] = { Locale.preferredLanguages }
    ) -> Outcome {
        guard settings.value(forKey: SettingsKeys.speechLegacyLanguageMigrated) == nil else { return .alreadyMigrated }
        defer {
            settings.setValue(nil, forKey: meetingsLanguageKey)
            settings.setValue(nil, forKey: dictationLanguageKey)
            settings.setValue(.bool(true), forKey: SettingsKeys.speechLegacyLanguageMigrated)
        }
        // Only a stored catalog code counts; anything else (a value written by hand) was read as `pl` before and
        // carried no choice.
        let stored = [meetingsLanguageKey, dictationLanguageKey].compactMap { key -> String? in
            guard case .string(let code) = settings.value(forKey: key), SpeechLanguageCatalog.contains(code) else {
                return nil
            }
            return code
        }
        guard !stored.isEmpty else { return .nothingToMove }
        // A list the host would read as the user's own (non-empty after validation) wins; an empty or unreadable
        // one reads as derived, so it is replaced.
        if case .stringArray(let list) = settings.value(forKey: SettingsKeys.speechLanguages),
            !HostSpeechLanguageSettings.validated(list).isEmpty
        {
            return .listAlreadyPresent
        }
        let languages = HostSpeechLanguageSettings.validated(
            stored + HostSpeechLanguageSettings.derivedLanguages(from: preferredLanguages()))
        settings.setValue(.stringArray(languages), forKey: SettingsKeys.speechLanguages)
        return .moved(languages)
    }
}
