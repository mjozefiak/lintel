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
    private struct State {
        var profile = LanguageProfile()
        /// Automatic Whisper: one re-check counter for the whole meeting, both tracks and replays included.
        var whisper = AutomaticWhisperLanguage()
    }

    private let settings: any SpeechLanguageSettings
    private let identifier: any TextLanguageIdentifier
    private let state = Mutex(State())

    init(settings: any SpeechLanguageSettings, identifier: any TextLanguageIdentifier = NaturalLanguageIdentifier()) {
        self.settings = settings
        self.identifier = identifier
    }

    /// The profile now.
    var snapshot: LanguageProfile { state.withLock { $0.profile } }

    /// Adds one accepted segment. Only a segment of at least `LanguageProfile.minimumDuration` and `minimumWords`
    /// is identified, with the user's list as hints and the whole catalog as the constraint (a list of Polish and
    /// English must not turn Ukrainian speech into Polish). The identifier runs outside the lock.
    func observe(_ text: String, duration: TimeInterval) {
        let segment = ProfileSegment(text: text, duration: duration)
        guard LanguageProfile.isEligible(segment),
            let guess = identifier.identify(text, hints: settings.current().languages, constraints: nil)
        else { return }
        state.withLock { $0.profile.add(guess, duration: duration) }
    }

    /// What the next segment is sent with: the setting now, the profile now and the segment's length (Whisper
    /// detects only long segments). Called once per request, in the order the segments are sent.
    func options(duration: TimeInterval) -> SpeechRequestOptions {
        let selection = settings.current()
        return state.withLock { state in
            Self.options(for: selection, profile: state.profile, duration: duration, whisper: &state.whisper)
        }
    }

    /// - Always one language: Whisper pinned to it; Parakeet gets the hint of that language's script only (none
    ///   for a language in another script, Serbian or one outside the catalog).
    /// - Automatic: Parakeet gets no hint until the profile is settled, then the script of the profile when it
    ///   has one (a mix of scripts gives none), and never while a listed language needs Whisper (the router's
    ///   "Parakeet without hint"). Whisper follows `AutomaticWhisperLanguage`: a constrained detection among the
    ///   list for a long segment until the profile is settled and for every 10th long one after it, else pinned to
    ///   the profile's dominant language or the first listed one.
    static func options(
        for selection: SpeechLanguageSelection, profile: LanguageProfile, duration: TimeInterval,
        whisper: inout AutomaticWhisperLanguage
    ) -> SpeechRequestOptions {
        switch selection.mode {
        case .single(let code):
            return SpeechRequestOptions(
                scriptHint: ScriptHint.hint(forLanguages: [code]), whisperLanguage: .pinned(code))
        case .automatic:
            return SpeechRequestOptions(
                scriptHint: MeetingEngineRouting.allowsScriptHint(selection) ? profile.scriptHint : nil,
                whisperLanguage: whisper.choice(duration: duration, languages: selection.languages, profile: profile))
        }
    }

    /// The options of one request on their own, for a caller without a meeting's counter (tests, tools).
    static func options(
        for selection: SpeechLanguageSelection, profile: LanguageProfile, duration: TimeInterval = 0
    ) -> SpeechRequestOptions {
        var whisper = AutomaticWhisperLanguage()
        return options(for: selection, profile: profile, duration: duration, whisper: &whisper)
    }
}
