import Foundation
import NaturalLanguage

/// What the identifier thinks a text is written in.
public struct LanguageGuess: Sendable, Equatable {
    /// A catalog code.
    public let code: String
    /// 0...1. Below about 8 words this is not reliable, so a short text may veto a language, never confirm it.
    public let confidence: Double

    public init(code: String, confidence: Double) {
        self.code = code
        self.confidence = confidence
    }
}

/// Finds the language of transcribed text. A port, so the logic that uses it is tested with a fake.
public protocol TextLanguageIdentifier: Sendable {
    /// - Parameters:
    ///   - hints: languages the user speaks, as a prior (more likely, not exclusive).
    ///   - constraints: when set, the answer is one of these codes; `nil` means every catalog language.
    /// - Returns: the best guess, or `nil` when the text says nothing (no letters, nothing recognised).
    func identify(_ text: String, hints: [String], constraints: [String]?) -> LanguageGuess?
}

/// Apple's `NLLanguageRecognizer`: offline, a system framework, no model to download. The catalog is the
/// constraint, so a language Lintel cannot transcribe is never an answer.
public struct NaturalLanguageIdentifier: TextLanguageIdentifier {
    public init() {}

    public func identify(_ text: String, hints: [String], constraints: [String]?) -> LanguageGuess? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains(where: \.isLetter) else { return nil }
        let recognizer = NLLanguageRecognizer()
        let allowed = constraints ?? SpeechLanguageCatalog.all.map(\.code)
        // The whole catalog is not passed as a constraint: with all ~100 languages the recogniser answers
        // nothing for some texts (Japanese was one), so the answer is filtered to the catalog afterwards.
        if constraints != nil { recognizer.languageConstraints = allowed.flatMap(Self.languages(for:)) }
        // Hints are a prior: they share half of the probability mass, so the text still decides.
        let listed = hints.filter { allowed.contains($0) }
        if !listed.isEmpty {
            let weight = 0.5 / Double(listed.count)
            var prior: [NLLanguage: Double] = [:]
            for code in listed { for language in Self.languages(for: code) { prior[language] = weight } }
            recognizer.languageHints = prior
        }
        recognizer.processString(trimmed)
        // The best hypothesis the catalog (or the constraint) allows.
        for (language, confidence) in recognizer.languageHypotheses(withMaximum: 8).sorted(by: { $0.value > $1.value })
        {
            if let code = SpeechLanguageCatalog.normalize(language.rawValue), allowed.contains(code) {
                return LanguageGuess(code: code, confidence: confidence)
            }
        }
        return nil
    }

    /// The recogniser's names for a catalog code (Chinese comes as two scripts, Norwegian as three codes).
    static func languages(for code: String) -> [NLLanguage] {
        switch code {
        case "zh": [.simplifiedChinese, .traditionalChinese]
        case "no": [NLLanguage("no"), NLLanguage("nb"), NLLanguage("nn")]
        default: [NLLanguage(code)]
        }
    }
}
