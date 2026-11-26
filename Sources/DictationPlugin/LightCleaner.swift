import Foundation

/// The Light cleanup level (spec `2026-11-25-dictation-cleanup-levels`): removes filler words from a fixed list and
/// nothing else. Pure rules, no language model, no I/O, and it cannot fail: it always returns `.formatted`.
///
/// What it does:
/// - A token is a filler only when it is a whole whitespace-separated token from the list (any case) with at most one
///   trailing `,` `.` `?` or `!`. "yyy…" or "(eee)" is left alone.
/// - It edits only the spans around a removed token: the rest of the text is returned byte for byte, so a text without
///   fillers comes back identical (the whitespace is never normalised).
/// - The comma that belonged to the filler goes with it, a comma before a filler that ends the sentence is replaced
///   by the sentence's full stop, and the next word gets a capital letter when the (capitalised) filler started a
///   sentence.
/// - It never removes a repetition, a false start or a real word ("no", "więc", "jakby", "tak" are not fillers here;
///   Standard handles them), never touches a digit, and keeps every word of the user's vocabulary.
struct LightCleaner: TextFormatter {
    /// Hesitation sounds, lowercased. Polish and English together: the engine writes what it hears in any language.
    static let fillers: Set<String> = ["yyy", "yy", "eee", "ee", "eem", "yhm", "um", "uh", "erm", "uhm"]

    /// The words of the user's vocabulary (terms and spoken variants) read for every chunk, so an edit applies to the
    /// next dictation. A filler that is one of those words stays, and so does the word after a removed filler.
    private let protectedWords: @Sendable () -> [String]

    init(protectedWords: @escaping @Sendable () -> [String] = { [] }) {
        self.protectedWords = protectedWords
    }

    func format(chunk: String, previousContext: String?) async throws -> FormatResult {
        FormatResult(text: Self.clean(chunk, protecting: protectedWords()), outcome: .formatted)
    }

    // MARK: Rules

    private struct Token {
        /// The whitespace before the token (the first token's holds the text's leading whitespace).
        var space: String
        var text: String
    }

    private struct Filler {
        /// What follows the filler word in its token: "", "," or one sentence-final mark.
        var trailing: Character?
        var startsWithCapital: Bool
    }

    static func clean(_ text: String, protecting terms: [String] = []) -> String {
        let (tokens, tail) = split(text)
        let protected = Self.words(in: terms)
        // Nothing to remove: the input, untouched.
        guard tokens.contains(where: { Self.filler($0.text, protected: protected) != nil }) else { return text }

        var output: [Token] = []
        var carriedSpace: String?
        var capitalizeNext = false
        for token in tokens {
            guard let filler = Self.filler(token.text, protected: protected) else {
                var kept = token
                if let carriedSpace { kept.space = carriedSpace }
                carriedSpace = nil
                if capitalizeNext { kept.text = Self.capitalized(kept.text, protected: protected) }
                capitalizeNext = false
                output.append(kept)
                continue
            }
            // The engine capitalises a filler that starts a sentence: that is the signal. A capital in the middle of a
            // sentence is a name, and what follows it stays as it is.
            if filler.startsWithCapital, output.last.map({ Self.endsSentence($0.text) }) ?? true {
                capitalizeNext = true
            }
            if let mark = filler.trailing, ".?!".contains(mark) {
                // The filler ended its sentence: the next word starts a new one.
                capitalizeNext = true
                if var previous = output.popLast() {
                    // "X, yyy." → "X.": the comma before it makes way for the full stop.
                    if previous.text.hasSuffix(",") { previous.text.removeLast() }
                    if let last = previous.text.last, last.isLetter || last.isNumber || ")\"”»".contains(last) {
                        previous.text.append(mark)
                    }
                    output.append(previous)
                }
            }
            // The whitespace before a removed token goes with it, except what shapes the text: leading whitespace
            // and a line break stay for the next token.
            if output.isEmpty {
                carriedSpace = carriedSpace ?? token.space
            } else if token.space.contains(where: \.isNewline), carriedSpace?.contains(where: \.isNewline) != true {
                carriedSpace = token.space
            }
        }
        return output.map { $0.space + $0.text }.joined() + (output.isEmpty ? "" : tail)
    }

    /// The tokens of `text` and the whitespace after the last one.
    private static func split(_ text: String) -> (tokens: [Token], tail: String) {
        var tokens: [Token] = []
        var space = ""
        var word = ""
        for character in text {
            if character.isWhitespace {
                if !word.isEmpty {
                    tokens.append(Token(space: space, text: word))
                    space = ""
                    word = ""
                }
                space.append(character)
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty {
            tokens.append(Token(space: space, text: word))
            return (tokens, "")
        }
        return (tokens, space)
    }

    private static func filler(_ token: String, protected: Set<String>) -> Filler? {
        var core = Substring(token)
        var trailing: Character?
        if let last = core.last, ",.?!".contains(last) {
            trailing = last
            core = core.dropLast()
        }
        guard !core.isEmpty, fillers.contains(core.lowercased()), !protected.contains(fold(core)) else { return nil }
        return Filler(trailing: trailing, startsWithCapital: core.first?.isUppercase == true)
    }

    private static func endsSentence(_ token: String) -> Bool {
        guard let last = token.last else { return false }
        return ".?!…".contains(last)
    }

    /// The token with its first letter in upper case, when it is a lowercase letter and not a word of the vocabulary
    /// ("iPhone" stays). A digit or a symbol is left as it is.
    private static func capitalized(_ token: String, protected: Set<String>) -> String {
        guard let first = token.first, first.isLowercase,
            !protected.contains(fold(token.trimmingCharacters(in: .punctuationCharacters)))
        else { return token }
        return first.uppercased() + token.dropFirst()
    }

    /// Every word of the terms and their spoken variants, folded (case and diacritics) and without punctuation.
    private static func words(in terms: [String]) -> Set<String> {
        var words = Set<String>()
        for term in terms {
            for part in term.split(whereSeparator: \.isWhitespace) {
                let word = fold(part.trimmingCharacters(in: .punctuationCharacters))
                if !word.isEmpty { words.insert(word) }
            }
        }
        return words
    }

    private static func fold<S: StringProtocol>(_ text: S) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
