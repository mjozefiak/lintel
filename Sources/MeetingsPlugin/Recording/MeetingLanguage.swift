import Foundation
import LintelKit
import LintelSpeech
import Synchronization

/// The language of one meeting while it is recorded (spec `2026-11-23-automatic-language-detection`, step 2.3): the
/// shared setting, read for every request, and the `LanguageProfile` the transcribed text builds. The session feeds
/// it from `accept`; the track workers, which run outside the session's actor, read a snapshot when they send a
/// segment, so every request carries its own options (the engine is shared with Dictation through the lease).
///
/// Memory only: the profile holds language codes and seconds. Text is looked at, never kept or logged.
final class MeetingLanguage: Sendable {
    private let settings: any SpeechLanguageSettings
    private let identifier: any TextLanguageIdentifier
    private let profile = Mutex(LanguageProfile())

    init(settings: any SpeechLanguageSettings, identifier: any TextLanguageIdentifier = NaturalLanguageIdentifier()) {
        self.settings = settings
        self.identifier = identifier
    }

    /// The profile now.
    var snapshot: LanguageProfile { profile.withLock { $0 } }

    /// Adds one accepted segment. Only a segment of at least `LanguageProfile.minimumDuration` and `minimumWords`
    /// is identified, with the user's list as hints and the whole catalog as the constraint (a list of Polish and
    /// English must not turn Ukrainian speech into Polish). The identifier runs outside the lock.
    func observe(_ text: String, duration: TimeInterval) {
        let segment = ProfileSegment(text: text, duration: duration)
        guard LanguageProfile.isEligible(segment),
            let guess = identifier.identify(text, hints: settings.current().languages, constraints: nil)
        else { return }
        profile.withLock { $0.add(guess, duration: duration) }
    }

    /// What the next segment is sent with: the setting now and the profile now.
    func options() -> SpeechRequestOptions {
        Self.options(for: settings.current(), profile: snapshot)
    }

    /// - Always one language: Whisper pinned to it; Parakeet gets the hint of that language's script only (none
    ///   for a language in another script, Serbian or one outside the catalog).
    /// - Automatic: Parakeet gets no hint until the profile is settled, then the script of the profile when it
    ///   has one (a mix of scripts gives none). Whisper is pinned to the first listed language (its detection
    ///   comes in step 2.5).
    static func options(for selection: SpeechLanguageSelection, profile: LanguageProfile) -> SpeechRequestOptions {
        switch selection.mode {
        case .single(let code):
            return SpeechRequestOptions(
                scriptHint: ScriptHint.hint(forLanguages: [code]), whisperLanguage: .pinned(code))
        case .automatic:
            return SpeechRequestOptions(
                scriptHint: profile.scriptHint, whisperLanguage: .pinned(pinnedLanguage(for: selection)))
        }
    }

    /// The language Whisper is pinned to: the single language, else the first listed one, else English.
    static func pinnedLanguage(for selection: SpeechLanguageSelection) -> String {
        if case .single(let code) = selection.mode { return code }
        return selection.languages.first ?? fallbackLanguage
    }

    /// The product's core language, when a context offers no list at all.
    static let fallbackLanguage = "en"
}
