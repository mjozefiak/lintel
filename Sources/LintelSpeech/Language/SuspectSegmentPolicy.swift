import Foundation

/// The finalization rule of the spec, pure: which short segments of a meeting are suspect (probably decoded in
/// the wrong language or script, or invented on noise), and whether a new decoding may replace one.
///
/// A segment longer than `maximumSeconds` and `maximumWords` is **never** suspect, so real English inside a Polish
/// meeting stays. `LanguageRepair` (a later step) does the decoding; this decides, from the text and the
/// profile, and never sees audio.
public struct SuspectSegmentPolicy: Sendable {
    /// A segment is a candidate only when it is at most this many words, or at most this long.
    public static let maximumWords = 3
    public static let maximumSeconds: TimeInterval = 2
    /// How sure the identifier must be that a text is in a language outside the profile.
    public static let confidentOutsideProfile = 0.8

    private let identifier: any TextLanguageIdentifier

    public init(identifier: any TextLanguageIdentifier) {
        self.identifier = identifier
    }

    /// Whether `segment` is short enough to be touched at all.
    public static func isShort(_ segment: ProfileSegment) -> Bool {
        segment.duration <= maximumSeconds || TextScript.wordCount(segment.text) <= maximumWords
    }

    /// Whether `segment` should be decoded again. Without a profile that has a dominant language the answer is
    /// always no, and so is one with less than `LanguageProfile.minimumRepairSeconds` of confident speech: nothing is
    /// rewritten on a guess.
    public func isSuspect(_ segment: ProfileSegment, profile: LanguageProfile) -> Bool {
        guard Self.isShort(segment), profile.isUsableForRepair, let dominant = profile.dominant else { return false }
        let inProfile = profile.languages()
        let scripts = profile.scripts()
        if let script = TextScript.dominant(in: segment.text), !scripts.isEmpty, !scripts.contains(script) {
            return true
        }
        if isConfidentlyOutside(segment.text, profile: inProfile) { return true }
        // English filler on a short acknowledgement while the meeting is not in English.
        return dominant != "en" && BackChannelPhrases.isBackChannel(segment.text, language: "en")
            && !BackChannelPhrases.isBackChannel(segment.text, language: dominant)
    }

    /// Whether `text`, a new decoding of a suspect segment, may replace the original. All must hold:
    /// it is not empty, its script is a script of the profile, it is on no back-channel or hallucination list of
    /// any language (Whisper pinned to Polish answers noise with Polish filler, which would "agree" with the
    /// profile), and the identifier does not place it confidently in a language outside the profile. A short
    /// text the identifier is unsure about passes: the identifier may veto, never approve.
    ///
    /// The decoder's own confidence (`noSpeechProb`, `avgLogProb`) is the repair's check, not this one.
    public func acceptsReplacement(_ text: String, profile: LanguageProfile) -> Bool {
        guard let script = TextScript.dominant(in: text), profile.scripts().contains(script) else { return false }
        if BackChannelPhrases.isBackChannelInAnyLanguage(text) || BackChannelPhrases.isHallucination(text) {
            return false
        }
        return !isConfidentlyOutside(text, profile: profile.languages())
    }

    /// No hints are passed on purpose: a hint is a prior in favour of the profile's languages and, on the short
    /// texts this looks at, would make nearly every text look like one of them, which disables the rule and the veto.
    private func isConfidentlyOutside(_ text: String, profile languages: Set<String>) -> Bool {
        guard !languages.isEmpty,
            let guess = identifier.identify(text, hints: [], constraints: nil)
        else { return false }
        return guess.confidence >= Self.confidentOutsideProfile && !languages.contains(guess.code)
    }
}
