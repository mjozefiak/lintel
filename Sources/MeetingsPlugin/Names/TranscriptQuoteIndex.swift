import Foundation

/// One segment of a transcript as the quote search sees it: the speaker's label, the start time and the text.
/// `NotesGuard` builds it from `NotesUtterance`, the name evidence from `NameSegment`; the database's ids are not
/// part of it, so the search stays pure.
struct QuoteSegment: Equatable, Sendable {
    var speaker: String
    var startMs: Int
    var text: String
}

/// The words of a transcript, with what finding a quote in it needs: the normalised word, its original capital,
/// its place in a sentence, character offsets, its segment, and the sentence and segment ranges. One
/// representation for `NotesGuard` (the quotes of the notes) and `NameEvidenceGuard` (the quotes of the names);
/// it is a pure index and holds no text of its own beyond the segments it was built from.
struct TranscriptQuoteIndex: Sendable {
    /// A quote placed in the transcript.
    struct Match: Equatable, Sendable {
        var range: Range<Int>
        var wholeUtterance: Bool
        /// How many leading quote words the range matches: all of them, or fewer when a literal quote ran on
        /// past a sentence end and only its first sentence was matched.
        var quoteCount: Int
    }

    /// The kind of miss behind a quote the index could not place (measurement only; never any text).
    enum Miss: String, Sendable, CaseIterable, Codable {
        /// The quote's words follow each other only across a change of speaker.
        case speakerChange
        /// The quote matches a stretch of the transcript except for one word that differs.
        case changedWord
        /// The quote's words follow each other in one speaker's words but with more than
        /// `maxSkippedTranscriptWords` words in between.
        case omittedWords
        /// None of the above: the quote is not in the transcript.
        case absent
    }

    let segments: [QuoteSegment]
    let words: [String]
    let capitalised: [Bool]
    let startsSentence: [Bool]
    let charStart: [Int]
    let charEnd: [Int]
    /// The segment each word belongs to.
    let wordSegment: [Int]
    /// The sentence each word belongs to.
    let wordSentence: [Int]
    let sentenceRanges: [Range<Int>]
    let sentenceTerminators: [Character?]
    let segmentRanges: [Range<Int>]
    let speakerNames: [String]

    /// The index over a transcript, in time order. A segment with no words takes no words and its
    /// `segmentRanges` entry stays empty.
    init(_ segments: [QuoteSegment]) {
        self.segments = segments
        var words: [String] = []
        var capitalised: [Bool] = []
        var starts: [Bool] = []
        var charStart: [Int] = []
        var charEnd: [Int] = []
        var owner: [Int] = []
        var sentenceOf: [Int] = []
        var ranges: [Range<Int>] = []
        var terminators: [Character?] = []
        var segmentRanges = Array(repeating: 0..<0, count: segments.count)
        var current = -1
        var open = false
        var previousSpeaker: String?
        for (index, segment) in segments.enumerated() {
            let tokens = NotesText.tokens(segment.text)
            guard !tokens.isEmpty else { continue }
            let first = words.count
            for (position, token) in tokens.enumerated() {
                let continues = position == 0 && open && previousSpeaker == segment.speaker && current >= 0
                if position > 0, let end = token.sentenceEnd { terminators[current] = end }
                if (position == 0 && !continues) || (position > 0 && token.sentenceEnd != nil) {
                    current += 1
                    ranges.append(words.count..<words.count)
                    terminators.append(nil)
                }
                words.append(token.word)
                capitalised.append(token.capitalised)
                starts.append(token.startsSentence)
                charStart.append(token.start)
                charEnd.append(token.end)
                owner.append(index)
                sentenceOf.append(current)
                ranges[current] = ranges[current].lowerBound..<words.count
            }
            segmentRanges[index] = first..<words.count
            let last = segment.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            let terminated = last.map { ".!?\u{2026}".contains($0) } ?? false
            if terminated { terminators[current] = last }
            open = !terminated
            previousSpeaker = segment.speaker
        }
        self.words = words
        self.capitalised = capitalised
        self.startsSentence = starts
        self.charStart = charStart
        self.charEnd = charEnd
        wordSegment = owner
        wordSentence = sentenceOf
        sentenceRanges = ranges
        sentenceTerminators = terminators
        self.segmentRanges = segmentRanges
        speakerNames = Array(Set(segments.map(\.speaker))).sorted()
    }

    // MARK: The quote

    /// The fewest quote words a match needs unless it is a whole utterance (`quoteTooShort` in `NotesGuard`).
    static let minimumQuoteWords = 3

    /// How many transcript words, in all, a quote may skip between its first and last word (`dha czy chciał`
    /// for the quote `dha chciał`).
    static let maxSkippedTranscriptWords = 2

    /// The quote without a leading `[mm:ss]` and `Speaker:` the model may have copied along.
    func quoteWords(from quote: String) -> [String] {
        var text = quote.trimmingCharacters(in: .whitespaces)
        if let match = text.prefixMatch(of: /\[?\d{1,3}:\d{2}(:\d{2})?\]?[ ]*/) {
            text = String(text[match.range.upperBound...])
        }
        for name in speakerNames where text.hasPrefix(name + ":") {
            text = String(text.dropFirst(name.count + 1))
            break
        }
        return NotesText.words(text)
    }

    /// The first place in the transcript where all quote words follow each other (by `wordsMatch`): a literal
    /// match within one speaker's words (cut at the first sentence end it crosses), one with gaps within one
    /// sentence; with several, the one closest in time to `near`. An exact match (no gaps) wins over one that
    /// skips up to `maxSkippedTranscriptWords` filler words; the first and the last quote word never have a gap
    /// at the edge, and a skipped word is never a negation, a number, a word with a digit or a capitalised name
    /// the quote does not contain. `speaker` limits the search to one speaker's words (the name evidence checks
    /// the quote stands at the speaker the model claims).
    func find(_ quote: [String], near time: Int, speaker: String? = nil) -> Match? {
        guard !quote.isEmpty, words.count >= quote.count else { return nil }
        if let exact = find(quote, near: time, skips: 0, speaker: speaker) { return exact }
        guard quote.count >= 2, Self.maxSkippedTranscriptWords > 0 else { return nil }
        return find(quote, near: time, skips: Self.maxSkippedTranscriptWords, speaker: speaker)
    }

    private func find(_ quote: [String], near time: Int, skips: Int, speaker: String?) -> Match? {
        var best: Match?
        var bestDistance = Int.max
        for start in 0...(words.count - quote.count)
        where (speaker == nil || self.speaker(of: start) == speaker) && NotesText.wordsMatch(words[start], quote[0]) {
            guard var end = matchEnd(quote, index: 1, after: start, skips: skips, literal: skips == 0) else {
                continue
            }
            var quoteCount = quote.count
            if skips > 0 {
                // A match with gaps stays in one sentence.
                guard wordSentence[start] == wordSentence[end - 1] else { continue }
            } else if wordSentence[start] != wordSentence[end - 1] {
                // A literal quote that runs on past a sentence end (within one speaker's words, see `matchEnd`)
                // is matched on its first sentence only; the rest of the quote is ignored. Too short a start
                // is no match.
                end = sentenceRanges[wordSentence[start]].upperBound
                quoteCount = end - start
                guard quoteCount >= Self.minimumQuoteWords else { continue }
            }
            let range = start..<end
            let distance = abs(segments[wordSegment[start]].startMs - time)
            if distance < bestDistance {
                bestDistance = distance
                // A match with gaps or a cut one is never a whole utterance: it must not get round `quoteTooShort`.
                best = Match(
                    range: range,
                    wholeUtterance: quoteCount == quote.count && range.count == quote.count && isWhole(range),
                    quoteCount: quoteCount)
            }
        }
        return best
    }

    /// The end (exclusive) of the transcript words matching `quote[index...]` after the word at `position`,
    /// skipping at most `skips` words in all, or nil. A `literal` match may run over a sentence end but stays with
    /// one speaker (`find` cuts it at the first sentence end); any other stays within one sentence.
    private func matchEnd(_ quote: [String], index: Int, after position: Int, skips: Int, literal: Bool) -> Int? {
        if index == quote.count { return position + 1 }
        for gap in 0...skips {
            let next = position + 1 + gap
            guard next < words.count else { return nil }
            if literal {
                guard speaker(of: next) == speaker(of: position) else { return nil }
            } else {
                guard wordSentence[next] == wordSentence[position] else { return nil }
            }
            if gap > 0, !canSkip(position + gap, quote: quote) { return nil }
            if NotesText.wordsMatch(words[next], quote[index]),
                let end = matchEnd(quote, index: index + 1, after: next, skips: skips - gap, literal: literal)
            {
                return end
            }
        }
        return nil
    }

    /// The kind of miss behind a quote that `find` did not place (measurement only; it runs for refused points).
    /// Checked in this order: the quote's words in sequence across a change of speaker; one word that differs
    /// in a stretch of the transcript of the quote's length; the words in order within one speaker's words with
    /// more than `maxSkippedTranscriptWords` words in between; otherwise absent.
    func missKind(of quote: [String]) -> Miss {
        guard quote.count >= 2, words.count >= quote.count else { return .absent }
        for start in 0...(words.count - quote.count) where NotesText.wordsMatch(words[start], quote[0]) {
            var index = 1
            while index < quote.count, NotesText.wordsMatch(words[start + index], quote[index]) { index += 1 }
            if index == quote.count, speaker(of: start) != speaker(of: start + quote.count - 1) {
                return .speakerChange
            }
        }
        if quote.count >= 3 {
            for start in 0...(words.count - quote.count) {
                let window = words[start..<(start + quote.count)]
                let mismatches = zip(window, quote).filter { !NotesText.wordsMatch($0, $1) }.count
                if mismatches == 1, wordSentence[start] == wordSentence[start + quote.count - 1] {
                    return .changedWord
                }
            }
        }
        let reach = quote.count + 12
        for start in words.indices where NotesText.wordsMatch(words[start], quote[0]) {
            var position = start
            var matched = 1
            let limit = min(words.count, start + reach)
            var next = start + 1
            while matched < quote.count, next < limit, speaker(of: next) == speaker(of: start) {
                if NotesText.wordsMatch(words[next], quote[matched]) {
                    matched += 1
                    position = next
                }
                next += 1
            }
            if matched == quote.count, position - start + 1 > quote.count { return .omittedWords }
        }
        return .absent
    }

    /// The speaker's label (consecutive segments of one speaker are one speaker).
    func speaker(of word: Int) -> String { segments[wordSegment[word]].speaker }

    /// Whether the transcript word at `index` may be left out of a quote.
    private func canSkip(_ index: Int, quote: [String]) -> Bool {
        let word = words[index]
        if Self.negations.contains(word) || NotesText.isNumberWord(word) { return false }
        if word.contains(where: \.isNumber) { return false }
        if capitalised[index], !quote.contains(where: { NotesText.wordsMatch($0, word) }) { return false }
        return true
    }

    /// The negation words a quote may not skip over, and `NotesGuard` counts in a point's text.
    static let negations: Set<String> = [
        "nie", "nigdy", "nikt", "nic", "zaden", "zadna", "zadne", "not", "no", "never", "nobody", "nothing", "none",
        "cannot", "without",
    ]

    private func isWhole(_ range: Range<Int>) -> Bool {
        let segment = wordSegment[range.lowerBound]
        guard wordSegment[range.upperBound - 1] == segment else { return false }
        return segmentRanges[segment] == range
    }

    /// The original text of the matched words (and the sentence end after them when they end the sentence).
    func excerpt(of range: Range<Int>) -> String {
        var pieces: [String] = []
        let covered = Set(range.map { wordSegment[$0] }).sorted()
        for index in covered {
            let inside = range.filter { wordSegment[$0] == index }
            guard let first = inside.first, let last = inside.last else { continue }
            let characters = Array(segments[index].text)
            pieces.append(String(characters[charStart[first]..<min(charEnd[last], characters.count)]))
        }
        var text = pieces.joined(separator: " ")
        let sentence = wordSentence[range.upperBound - 1]
        if sentenceRanges[sentence].upperBound == range.upperBound, let end = sentenceTerminators[sentence],
            !text.hasSuffix(String(end))
        {
            text.append(end)
        }
        return text
    }
}
