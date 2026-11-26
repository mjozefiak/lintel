import Foundation

/// How Whisper picks the language of each segment of one session in Automatic mode (spec
/// `2026-11-23-automatic-language-detection`, "Meetings and Dictation, Whisper"). Pure; one value per session, fed
/// in the order the segments are sent.
///
/// - Until the profile is settled, a segment of at least `minimumDetectionDuration` gets a constrained detection
///   among the candidates, falling back to the profile's dominant language or the first listed one.
/// - A shorter segment is pinned to that same language: Whisper pads short audio and guesses badly, so detection
///   never runs on it.
/// - Once settled, segments are pinned to the dominant language and every `recheckInterval`-th long one is
///   detected again, so a session that changes language follows within a few segments.
/// - A detection that fails or throws ends in the fallback inside the engine (`WhisperKitEngine`), never in an
///   error.
///
/// Memory only: a counter and language codes.
public struct AutomaticWhisperLanguage: Sendable, Equatable {
    /// A segment shorter than this is never detected: the engine's own lower bound, the same 3 s as the profile's
    /// (#132).
    public static let minimumDetectionDuration = TimeInterval(WhisperKitEngine.minimumDetectionSeconds)
    /// After the profile settled, every this-many-th long segment is detected again.
    public static let recheckInterval = 10
    /// The language of a session with no list and no profile: the product's core language.
    public static let fallbackLanguage = "en"

    /// Long segments sent since the profile settled.
    public private(set) var longSegmentsSinceSettled = 0

    public init() {}

    /// The choice for the next segment, and one step of the re-check counter.
    ///
    /// - Parameters:
    ///   - duration: the segment's audio, in seconds (the text is not known before decoding).
    ///   - languages: the user's list, in order.
    ///   - profile: the session's profile now.
    public mutating func choice(
        duration: TimeInterval, languages: [String], profile: LanguageProfile
    ) -> WhisperLanguageChoice {
        let pin = Self.pinnedLanguage(languages: languages, profile: profile)
        guard duration >= Self.minimumDetectionDuration else { return .pinned(pin) }
        if profile.isSettled {
            longSegmentsSinceSettled += 1
            guard longSegmentsSinceSettled.isMultiple(of: Self.recheckInterval) else { return .pinned(pin) }
        }
        let candidates = Self.candidates(languages: languages, profile: profile)
        guard candidates.count > 1 else { return .pinned(pin) }
        return .detect(candidates: candidates, fallback: pin)
    }

    /// The profile's dominant language, else the first listed one, else English.
    public static func pinnedLanguage(languages: [String], profile: LanguageProfile) -> String {
        profile.dominant ?? languages.first ?? fallbackLanguage
    }

    /// The user's list, plus the profile's dominant language when the list lacks it: the profile is identified
    /// against the whole catalog (a Polish and English list must not turn Ukrainian speech into Polish), so a
    /// detection must be able to confirm it. Only languages Whisper knows; no duplicates, order kept.
    public static func candidates(languages: [String], profile: LanguageProfile) -> [String] {
        var result: [String] = []
        for code in languages + [profile.dominant].compactMap({ $0 }) where !result.contains(code) {
            guard SpeechLanguageCatalog.language(for: code)?.whisperSupported ?? false else { continue }
            result.append(code)
        }
        return result
    }
}
