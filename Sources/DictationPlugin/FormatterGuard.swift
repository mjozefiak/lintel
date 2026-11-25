import Foundation

/// Checks what the formatting model returned and throws away what is not a cleaned version of the input
/// (spec: `FormatterGuard`). A rejected chunk is replaced by the raw text, so a bad answer never reaches the
/// user's document.
enum FormatterGuard {
    enum Verdict: Equatable, Sendable {
        case accepted(String)
        case rejected(Reason)
    }

    enum Reason: Equatable, Sendable {
        case empty
        case tooLong
        case tooShort
        case languageChanged
        case answered
        /// The output has a number the transcript does not (a converted unit, a changed hour, a made-up detail).
        case newNumber
    }

    /// The output may hold 0.6 to 1.15 times the input's words when the speaker said something that may go
    /// (a filler, a repetition, "first, second") or a number the model writes shorter.
    static let lengthRange = 0.6...1.15

    /// A self-correction takes back a stretch of the sentence together with its signal words, so the text may
    /// lose up to more than half of its words ("a, to znaczy b").
    static let correctionLengthRange = 0.4...1.15

    /// With nothing to remove the output keeps nearly all the words: dropping a detail is a loss.
    static let plainLengthRange = 0.85...1.15

    static func check(input: String, output rawOutput: String) -> Verdict {
        let output = clean(rawOutput)
        guard !output.isEmpty else { return .rejected(.empty) }

        if answersInsteadOfCleaning(input: input, output: output) { return .rejected(.answered) }

        if !SpokenNumbers.newNumbers(in: output, comparedTo: input).isEmpty { return .rejected(.newNumber) }

        // A spoken number counts as one word and a list marker as none: "dwadzieścia pięć tysięcy" becomes
        // "25 000" and "po pierwsze" becomes "1.".
        let inputWords = SpokenNumbers.wordCount(in: input)
        let outputWords = SpokenNumbers.wordCount(in: withoutListMarkers(output))
        // Converting numbers reshapes a sentence ("procent" becomes "%"), so a chunk with spoken numbers gets the
        // wide range too: the number check above is what protects its details.
        let range: ClosedRange<Double>
        switch Removals.kind(of: input) {
        case .correction: range = correctionLengthRange
        case .minor: range = lengthRange
        case .none: range = SpokenNumbers.containsNumberWord(input) ? lengthRange : plainLengthRange
        }
        // A very short chunk can lose a filler word and so fall under the ratio by itself.
        if inputWords >= 5 {
            let ratio = Double(outputWords) / Double(inputWords)
            if ratio > range.upperBound { return .rejected(.tooLong) }
            if ratio < range.lowerBound { return .rejected(.tooShort) }
        } else if outputWords > inputWords + 3 {
            return .rejected(.tooLong)
        }

        let before = Language.dominant(in: input)
        let after = Language.dominant(in: output)
        if before != .unknown, after != .unknown, before != after { return .rejected(.languageChanged) }
        return .accepted(output)
    }

    /// Removes thinking blocks and tags the model may echo, and the whitespace around the text.
    static func clean(_ text: String) -> String {
        var result = text
        // A reasoning block, closed or (when the model ran out of tokens) open to the end.
        while let open = result.range(of: "<think>") {
            if let close = result.range(of: "</think>", range: open.upperBound..<result.endIndex) {
                result.removeSubrange(open.lowerBound..<close.upperBound)
            } else {
                result.removeSubrange(open.lowerBound..<result.endIndex)
            }
        }
        // A template that opens the block itself leaves only the closing tag.
        if let close = result.range(of: "</think>", options: .backwards) {
            result.removeSubrange(result.startIndex..<close.upperBound)
        }
        for tag in ["<transcript>", "</transcript>", "<context>", "</context>"] {
            result = result.replacingOccurrences(of: tag, with: "")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func words(in text: String) -> Int {
        text.split(whereSeparator: \.isWhitespace).count
    }

    /// The text without the "-", "•", "1." and "2)" that start the lines of a list the model wrote.
    static func withoutListMarkers(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            var rest = Substring(line.drop { $0 == " " })
            if let first = rest.first, "-•*–".contains(first), rest.dropFirst().first == " " {
                rest = rest.dropFirst(2)
            } else {
                let digits = rest.prefix { $0.isASCII && $0.isNumber }
                let after = rest.dropFirst(digits.count)
                if !digits.isEmpty, let mark = after.first, ".)".contains(mark), after.dropFirst().first == " " {
                    rest = after.dropFirst(2)
                }
            }
            return String(rest)
        }.joined(separator: "\n")
    }

    private static let answerOpenings = [
        "oto ", "oczywiście", "jasne,", "jasne!", "sure,", "sure!", "sure.", "certainly", "of course",
        "here is", "here's", "here are", "i can't", "i cannot", "as an ai", "przepraszam",
    ]

    private static func answersInsteadOfCleaning(input: String, output: String) -> Bool {
        let lower = output.lowercased()
        let spoken = input.lowercased()
        return answerOpenings.contains {
            lower.hasPrefix($0) && !spoken.contains($0.trimmingCharacters(in: .punctuationCharacters))
        }
    }
}

/// A rough language detector for the guard: Polish or English, by diacritics and common words. It only has
/// to notice that a whole chunk changed language, so `unknown` is a fine answer for short or mixed text.
enum Language: Equatable, Sendable {
    case polish, english, unknown

    private static let polishWords: Set<String> = [
        "i", "w", "z", "na", "nie", "że", "się", "to", "jest", "do", "jak", "ale", "co", "po", "czy", "tak",
        "już", "go", "ma", "by", "bo", "dla", "tego", "jeszcze", "tylko", "przez", "mam", "będzie", "może",
        "który", "która", "które", "tym", "więc", "też", "oraz",
    ]
    private static let englishWords: Set<String> = [
        "the", "and", "of", "to", "in", "is", "that", "it", "for", "was", "on", "are", "with", "as", "this",
        "be", "at", "have", "from", "or", "an", "not", "we", "you", "but", "will", "should", "would", "can",
    ]

    static func dominant(in text: String) -> Language {
        let tokens = text.lowercased().split { !$0.isLetter }.map(String.init)
        guard tokens.count >= 4 else { return .unknown }
        var polish = 0
        var english = 0
        for token in tokens {
            if polishWords.contains(token) { polish += 1 }
            if englishWords.contains(token) { english += 1 }
            if token.contains(where: { "ąćęłńóśźż".contains($0) }) { polish += 2 }
        }
        if polish >= english + 2 { return .polish }
        if english >= polish + 2 { return .english }
        return .unknown
    }
}

/// What a speaker says that the cleaned text may leave out: the only reason the output may be much shorter than
/// the transcript. Without any of it the guard holds the output to nearly the input's length (spec: fidelity).
enum Removals {
    enum Kind: Equatable, Sendable {
        /// Nothing to remove: the output keeps almost every word.
        case none
        /// A filler, an immediate repetition or a spoken list marker.
        case minor
        /// A self-correction signal: a withdrawn stretch goes with it.
        case correction
    }

    private static let fillers: Set<String> = [
        "yyy", "yy", "yyyy", "eee", "ee", "eeee", "eh", "em", "emm", "ymm", "hm", "hmm", "mhm", "mmm", "um",
        "umm", "uh", "uhm", "uhh", "ehm",
    ]

    /// Signal words of a withdrawn version.
    private static let corrections: [[String]] = [
        ["i", "mean"], ["sorry"], ["actually"], ["wait"], ["nie", "czekaj"], ["czekaj"], ["to", "znaczy"],
        ["albo", "jednak"], ["a", "właściwie"], ["przepraszam"], ["pardon"], ["pomyłka"], ["scratch", "that"],
        ["or", "rather"], ["oops"], ["ups"], ["a", "nie"],
    ]

    /// Words and phrases that are lost when a list is written as a list or a sentence is started over.
    private static let minors: [[String]] = [
        ["no", "więc"], ["you", "know"], ["po", "pierwsze"], ["po", "drugie"], ["po", "trzecie"], ["first"],
        ["second"], ["third"], ["firstly"], ["secondly"], ["thirdly"],
    ]

    static func kind(of input: String) -> Kind {
        let tokens = input.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if corrections.contains(where: { contains(tokens, $0) }) { return .correction }
        if tokens.contains(where: { fillers.contains($0) }) || minors.contains(where: { contains(tokens, $0) })
            || repeats(tokens)
        {
            return .minor
        }
        return .none
    }

    static func mayRemove(from input: String) -> Bool { kind(of: input) != .none }

    private static func contains(_ tokens: [String], _ phrase: [String]) -> Bool {
        guard tokens.count >= phrase.count else { return false }
        for start in 0...(tokens.count - phrase.count) where Array(tokens[start..<start + phrase.count]) == phrase {
            return true
        }
        return false
    }

    /// "we should we should", "to to": an immediate repetition of up to three words.
    private static func repeats(_ tokens: [String]) -> Bool {
        for size in 1...3 where tokens.count >= size * 2 {
            for start in 0...(tokens.count - size * 2)
            where tokens[start..<start + size] == tokens[start + size..<start + size * 2] {
                return true
            }
        }
        return false
    }
}
