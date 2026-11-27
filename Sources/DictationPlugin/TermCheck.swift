import Foundation

/// The guard's term check (spec `2026-11-25-dictation-cleanup-levels`, Phase 3): a word the speaker may not lose must
/// come back in the cleaned text. Two kinds of word are protected:
/// - **vocabulary words**: a term or a spoken variant of the user's vocabulary that the transcript holds (the
///   `TermReplacer` runs after the formatter and works only on the exact word, so a model that "corrects" a variant
///   breaks the replacement);
/// - **names**: a capitalised word that does not start a sentence ("Anna", "Kubernetes", "CSV").
///
/// Words are compared without case and diacritics. A name may be inflected (Polish "Anna" becomes "Anny"): it counts as
/// kept when an output word shares its stem. A line break is not a word. A chunk with a self-correction signal is
/// exempt, because the withdrawn stretch goes on purpose ("do Anny, nie, do Marka").
enum TermCheck {
    /// Whether the transcript holds a protected word that the output lacks.
    static func lostWord(input: String, output: String, vocabulary: [String]) -> Bool {
        let outputTokens = tokens(output)
        for phrase in vocabularyPhrases(vocabulary, in: input) where !contains(outputTokens, phrase) { return true }
        let outputSet = Set(outputTokens)
        for name in names(in: input) where !outputSet.contains(name) && !hasInflection(of: name, in: outputTokens) {
            return true
        }
        return false
    }

    /// The words of `text` without case and diacritics (`ł`, `đ` and `ø` too, which the system folding keeps), split at
    /// everything that is not a letter or a digit.
    static func tokens(_ text: String) -> [String] {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "ł", with: "l").replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "ø", with: "o")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    /// The vocabulary's words that the input holds as a whole run of words.
    private static func vocabularyPhrases(_ vocabulary: [String], in input: String) -> [[String]] {
        let spoken = tokens(input)
        return vocabulary.map(tokens).filter { !$0.isEmpty && contains(spoken, $0) }
    }

    /// The capitalised words of the input that are not the first word of a sentence, folded. The first word of the
    /// chunk and every word after a full stop, question or exclamation mark, an ellipsis or a line break starts one.
    static func names(in input: String) -> [String] {
        var result: [String] = []
        var startsSentence = true
        for line in input.split(separator: "\n", omittingEmptySubsequences: true) {
            startsSentence = true
            for word in line.split(whereSeparator: \.isWhitespace) {
                if !startsSentence {
                    for part in word.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                    where part.count >= 2 && part.first?.isUppercase == true {
                        result.append(contentsOf: tokens(String(part)))
                    }
                }
                let end = word.last { !"\"'”’)]»".contains($0) }
                startsSentence = end.map { ".?!…".contains($0) } ?? startsSentence
            }
        }
        return result
    }

    /// An output word with the stem of `name`: the name minus up to two closing letters, at least three letters.
    private static func hasInflection(of name: String, in outputTokens: [String]) -> Bool {
        guard name.count >= 4, name.allSatisfy(\.isLetter) else { return false }
        let stem = String(name.prefix(max(3, name.count - 2)))
        return outputTokens.contains { $0.hasPrefix(stem) }
    }

    private static func contains(_ tokens: [String], _ phrase: [String]) -> Bool {
        guard !phrase.isEmpty, tokens.count >= phrase.count else { return false }
        for start in 0...(tokens.count - phrase.count) where Array(tokens[start..<start + phrase.count]) == phrase {
            return true
        }
        return false
    }
}
