import Foundation

/// A segment's text and length, what the profile and the repair look at. No audio.
public struct ProfileSegment: Sendable, Equatable {
    public let text: String
    public let duration: TimeInterval

    public init(text: String, duration: TimeInterval) {
        self.text = text
        self.duration = duration
    }
}

/// What a meeting or a dictation has been spoken in so far. The principle of the spec: **a short fragment never
/// picks the language; the session does**, from the text of its long segments, weighted by length.
///
/// Only a segment of at least `minimumDuration` seconds and `minimumWords` words is looked at, and only a guess
/// with at least `minimumConfidence` counts. Memory only: language codes and seconds, never text.
public struct LanguageProfile: Sendable, Equatable {
    /// A segment shorter than this never decides the language (#132: none of its wrong segments is longer).
    public static let minimumDuration: TimeInterval = 3
    public static let minimumWords = 10
    public static let minimumConfidence = 0.8
    /// Seconds of confident speech after which the profile is settled and may send a script hint.
    public static let settleSeconds: TimeInterval = 30
    /// A language needs this share of the profile to count (for its script, and as "in the profile").
    public static let minimumShare = 0.15
    /// Seconds of confident speech from which an unsettled profile may still be used to repair short segments.
    public static let minimumRepairSeconds: TimeInterval = 10

    /// Confident seconds per language code.
    public private(set) var seconds: [String: TimeInterval] = [:]

    public init() {}

    /// Whether a segment is long enough to be looked at.
    public static func isEligible(_ segment: ProfileSegment) -> Bool {
        segment.duration >= minimumDuration && TextScript.wordCount(segment.text) >= minimumWords
    }

    /// Adds one identified segment. Short, empty or unsure observations are ignored.
    public mutating func add(_ guess: LanguageGuess, duration: TimeInterval) {
        guard duration >= Self.minimumDuration, guess.confidence >= Self.minimumConfidence,
            SpeechLanguageCatalog.contains(guess.code)
        else { return }
        seconds[guess.code, default: 0] += duration
    }

    /// Identifies an eligible segment and adds it. Returns whether it counted.
    @discardableResult
    public mutating func add(
        _ segment: ProfileSegment, identifier: any TextLanguageIdentifier, hints: [String]
    ) -> Bool {
        guard Self.isEligible(segment),
            let guess = identifier.identify(segment.text, hints: hints, constraints: nil),
            guess.confidence >= Self.minimumConfidence
        else { return false }
        add(guess, duration: segment.duration)
        return true
    }

    /// The profile of a transcript stored earlier (a meeting resumed after a crash): nothing else is saved.
    public static func rebuilt(
        from segments: [ProfileSegment], identifier: any TextLanguageIdentifier, hints: [String]
    ) -> LanguageProfile {
        var profile = LanguageProfile()
        for segment in segments { profile.add(segment, identifier: identifier, hints: hints) }
        return profile
    }

    public var confidentSeconds: TimeInterval { seconds.values.reduce(0, +) }

    /// 30 s of confident speech seen.
    public var isSettled: Bool { confidentSeconds >= Self.settleSeconds }

    /// Enough to repair short segments with, settled or not.
    public var isUsableForRepair: Bool { confidentSeconds >= Self.minimumRepairSeconds }

    /// Share of the confident speech per language, 0...1; empty while nothing was seen.
    public var shares: [String: Double] {
        let total = confidentSeconds
        guard total > 0 else { return [:] }
        return seconds.mapValues { $0 / total }
    }

    /// The language with the most speech; a tie goes to the code that sorts first, so it never flips.
    public var dominant: String? {
        seconds.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    /// Languages that hold at least `minimumShare` of the profile.
    public func languages(minimumShare: Double = Self.minimumShare) -> Set<String> {
        Set(shares.filter { $0.value >= minimumShare }.keys)
    }

    /// The scripts of those languages: what a script hint or the suspect rule is allowed to assume.
    public func scripts(minimumShare: Double = Self.minimumShare) -> Set<LanguageScript> {
        SpeechLanguageCatalog.scripts(of: Array(languages(minimumShare: minimumShare)))
    }

    /// The script hint for the next segment: only once settled, and only when every language of the profile is
    /// written in one hintable script (Polish and Ukrainian together give none).
    public var scriptHint: ScriptHint? {
        guard isSettled else { return nil }
        return ScriptHint.hint(for: scripts())
    }
}
