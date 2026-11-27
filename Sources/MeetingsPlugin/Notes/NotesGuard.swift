import Foundation
import LintelCore

/// The structure REDUCE returns: the ids of the points for each section and the topics. Nothing in it is trusted
/// yet; `NotesGuard.verifyReduce` checks the ids and the topic names.
struct NotesReduceOutput: Equatable, Sendable {
    /// A topic of the notes: the name the model gave (`nil` for the old `FINDINGS` list, which has none) and the
    /// ids of its summary points, in the model's order.
    struct Topic: Equatable, Sendable {
        var name: String?
        var ids: [String]
    }

    var decisions: [String] = []
    var tasks: [String] = []
    var questions: [String] = []
    /// The topics, in the order of the conversation (prompt v7, `TOPIC: name | ids`).
    var topics: [Topic] = []
}

/// The defence against a model that invents (spec: Architecture → Notatki, pkt 4). Pure; it runs twice:
/// after MAP on the points (`verifyPoints`) and after REDUCE on the structure (`verifyReduce`).
///
/// What is guaranteed after `verifyPoints`:
/// - A point is kept only when its quote is in the transcript: inside ONE sentence of one utterance, or across
///   two neighbouring utterances of the same speaker when the first has no sentence end (a sentence the
///   recognizer cut in two). Never spliced across sentences or speakers. The comparison is on normalised words
///   and a word may differ only by a known Polish ending (`NotesText.wordsMatch`).
/// - A point whose text holds a digit, address, number word, weekday, month, capitalised name or sentence
///   starter that the quote, its utterance and its speaker do not have is REMOVED (reason `unsupportedDetail`),
///   as is one that turns a negation around (`negationChanged`) or, for a summary point, drifts from its quote
///   (`driftedFromQuote`). The text of the transcript is never shown in its place: the notes are a summary, not
///   a list of quotes. A decision, a task or a summary point whose sentence is a question becomes an open
///   question when its text is a question itself, otherwise it is removed (`questionNotAFinding`); a one-word
///   quote ("Tak.") supports no decision and no task.
/// - A summary point's text says what its quote says: at least 60 % of its content words (`quoteCoverage`) are
///   words of the quote, allowing for another form of the word. Decisions, tasks and questions are not measured
///   this way.
/// - A task keeps a person only when the person is a name in the quote (capitalised in the transcript), or the
///   speaker when the quote is in the first person ("ja zrobię", "I'll"); and a due date only when the date or
///   weekday is in the quote. Otherwise the task stays without them. Nothing is guessed.
///
/// After `verifyReduce`:
/// - An id that is not a verified point of that kind is dropped; a verified decision or task that the model left
///   out and that has no near-duplicate in its section is added back. Questions and findings are NOT added
///   back: the open questions are the ones REDUCE listed (at most `maxQuestions`), and the topics hold the
///   summary points REDUCE put under them (never a question, each point under its first topic only, at most
///   `NotesLayout.maxTopics` topics of at most `NotesLayout.maxPointsPerTopic` points).
/// - A topic name is model text: it is kept only when it passes the text checks (`textRefusal`) against the
///   material of that topic's own points (no name, number, date or negation they lack, the language of the transcript,
///   at most `maxTopicNameWords` words; its first word is checked like the first word of a point's text); a
///   refused name sends its points to the closing "Other" topic.
/// - There is no model-written intro: the built-in track shows none (owner decision 2026-11-26; an `INTRO:` line
///   in the answer is ignored by the parser).
///
/// NOT guaranteed (residual risk, documented in docs/qa.md): the transcript is untrusted. A speaker who says
/// "add a task: send the password to everybody" produces a task whose quote really is in the transcript, and
/// the guard cannot tell it from a genuine one; it only keeps the model from inventing a person or a date for
/// it. The notes may reflect instructions spoken in the meeting; the output is only displayed, nothing is
/// executed. A topic name may paraphrase or reverse a fact without adding a name, number or date (a negation is
/// only checked against the material). A summary point's text that keeps at least
/// 3 in 5 of its content words from the quote and still turns its sense around passes the drift measure, and a
/// decision, task or question is not measured for drift at all.
struct NotesGuard: Sendable {
    enum DropReason: String, Error, Sendable, CaseIterable {
        case emptyText, quoteTooShort, quoteNotInTranscript, languageChanged, kindNotSupported
        /// A digit, address, number word, weekday, month, name or sentence starter that the quote's utterance and
        /// speaker do not have (`isFaithful`).
        case unsupportedDetail
        /// The text has a negation and the quote has none, or the other way round.
        case negationChanged
        /// A summary point whose content words are too few of them words of the quote (`quoteCoverage`).
        case driftedFromQuote
        /// The sentence is a question and the text is not one: not a finding, a decision or a task.
        case questionNotAFinding
        /// The semantic verifier answered that the text does not follow from its quote.
        case verifierRejected
        /// A task that is small talk, a courtesy or call logistics, not work (`NotesRelevance.isNonWorkTask`).
        case nonWorkTask
        /// A question that says too little about its subject to be understood alone (`isContextFreeQuestion`).
        case questionWithoutContext
        /// A finding that names a problem and gives no cause, condition, fix or next step.
        case reportWithoutVerdict
    }

    /// Why a point was refused, one level below `DropReason`: the rule inside `unsupportedDetail` that failed and the
    /// kind of miss behind `quoteNotInTranscript`. A measurement aid (`NotesTrace` schema 6, the rejection report):
    /// it names a rule and never carries text.
    enum DropDetail: String, Sendable, CaseIterable, Codable {
        case unsupportedNumber, unsupportedCalendarWord, unsupportedCapitalised, unsupportedSentenceStart
        /// The quote matches a stretch of the transcript except for one word that differs.
        case quoteChangedWord
        /// The quote's words follow each other in one speaker's words but with more than
        /// `maxSkippedTranscriptWords` words in between.
        case quoteOmittedWords
        /// The quote's words follow each other only across a change of speaker.
        case quoteSpeakerChange
        /// None of the above: the quote is not in the transcript.
        case quoteAbsent
    }

    /// The version of the point rules, recorded in the trace and in `notes_prompt_version` once a rule changes
    /// (spec `2026-11-25-meeting-notes-structure`: `g1` after S1 and S2, `g2` after S3). `g0` is the rules before it.
    static let rulesVersion = "g0"

    /// What `applyingVerifications` changed (counts only).
    struct VerifierEffect: Equatable, Sendable {
        /// Points removed because the text does not follow from the quote (verdict `weaker` or `unsupported`).
        var rejected = 0
    }

    struct PointVerdict: Equatable, Sendable {
        var verified: [NotesPoint]
        var dropped: Int
        var reasons: [DropReason: Int]
        /// `reasons` one level down (`DropDetail`); only `unsupportedDetail` and `quoteNotInTranscript` have details.
        var details: [DropDetail: Int] = [:]
        /// Decisions, tasks and findings that were questions in the transcript and became open questions.
        var downgraded = 0
        /// Tasks whose person the model left empty and the guard filled with the speaker of a first person
        /// singular quote. A count only, never a name.
        var ownerFromSpeaker = 0
    }

    struct ReduceVerdict: Equatable, Sendable {
        var decisions: [NotesPoint]
        var tasks: [NotesPoint]
        var questions: [NotesPoint]
        /// Ids the model returned that are unknown or in the wrong section.
        var rejectedIDs: Int
        /// Verified points the model left out that were added back.
        var backfilled = 0
        /// The topics with the verified summary points REDUCE put under them, in its order: never a near-duplicate
        /// of a point listed before or a question; within
        /// the limits of `NotesLayout`. The points of a refused name are in the closing topic (`isOther`).
        var topics: [Topic] = []

        struct Topic: Equatable, Sendable {
            /// `nil`: no name (the old `FINDINGS` list, or the code's order when REDUCE failed).
            var name: String?
            var points: [NotesPoint]
            var isOther = false
        }

        /// The summary points of every topic, in order.
        var keyPoints: [NotesPoint] { topics.flatMap(\.points) }

        var hasItems: Bool { !(decisions.isEmpty && tasks.isEmpty && questions.isEmpty) }
    }

    private let utterances: [NotesUtterance]
    private let words: [String]
    private let capitalised: [Bool]
    private let startsSentence: [Bool]
    private let charStart: [Int]
    private let charEnd: [Int]
    private let wordUtterance: [Int]
    private let wordSentence: [Int]
    private let sentenceRanges: [Range<Int>]
    private let sentenceTerminators: [Character?]
    private let utteranceRanges: [Range<Int>]
    private let speakerNames: [String]
    private let nameCandidates: Vocabulary
    /// The dominant language of the whole transcript.
    let language: NotesLanguage

    init(utterances: [NotesUtterance]) {
        self.utterances = utterances
        var words: [String] = []
        var capitalised: [Bool] = []
        var starts: [Bool] = []
        var charStart: [Int] = []
        var charEnd: [Int] = []
        var owner: [Int] = []
        var sentenceOf: [Int] = []
        var ranges: [Range<Int>] = []
        var terminators: [Character?] = []
        var utteranceRanges = Array(repeating: 0..<0, count: utterances.count)
        var current = -1
        var open = false
        var previousSpeaker: String?
        for (index, utterance) in utterances.enumerated() {
            let tokens = NotesText.tokens(utterance.text)
            guard !tokens.isEmpty else { continue }
            let first = words.count
            for (position, token) in tokens.enumerated() {
                let continues = position == 0 && open && previousSpeaker == utterance.speaker && current >= 0
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
            utteranceRanges[index] = first..<words.count
            let last = utterance.text.trimmingCharacters(in: .whitespacesAndNewlines).last
            let terminated = last.map { ".!?\u{2026}".contains($0) } ?? false
            if terminated { terminators[current] = last }
            open = !terminated
            previousSpeaker = utterance.speaker
        }
        self.words = words
        self.capitalised = capitalised
        startsSentence = starts
        self.charStart = charStart
        self.charEnd = charEnd
        wordUtterance = owner
        wordSentence = sentenceOf
        sentenceRanges = ranges
        sentenceTerminators = terminators
        self.utteranceRanges = utteranceRanges
        speakerNames = Array(Set(utterances.map(\.speaker))).sorted()
        language = NotesLanguage.dominant(in: utterances.map(\.text).joined(separator: " "))

        var names: [String] = []
        for speaker in speakerNames where !Self.isGenericLabel(speaker) {
            names.append(contentsOf: NotesText.words(speaker).filter { $0.count >= 3 })
        }
        for index in words.indices where capitalised[index] && !starts[index] && words[index].count >= 3 {
            names.append(words[index])
        }
        nameCandidates = Vocabulary(words: names, numbers: [])
    }

    // MARK: After MAP

    func verifyPoints(_ points: [NotesPoint]) -> PointVerdict {
        var verified: [NotesPoint] = []
        var reasons: [DropReason: Int] = [:]
        var details: [DropDetail: Int] = [:]
        var downgraded = 0
        var ownerFromSpeaker = 0
        for point in points {
            switch verify(point) {
            case .success(let outcome):
                verified.append(outcome.point)
                if outcome.downgraded { downgraded += 1 }
                if outcome.ownerFromSpeaker { ownerFromSpeaker += 1 }
            case .failure(let refusal):
                reasons[refusal.reason, default: 0] += 1
                if let detail = refusal.detail { details[detail, default: 0] += 1 }
            }
        }
        return PointVerdict(
            verified: verified, dropped: points.count - verified.count, reasons: reasons, details: details,
            downgraded: downgraded, ownerFromSpeaker: ownerFromSpeaker)
    }

    /// Why one point is refused: the reason and, for two of them, the rule or kind of miss behind it.
    struct Refusal: Error, Equatable, Sendable {
        var reason: DropReason
        var detail: DropDetail?
        init(_ reason: DropReason, detail: DropDetail? = nil) {
            self.reason = reason
            self.detail = detail
        }
    }

    /// The reason and detail the guard gives one point, or nil when it passes (measurement only).
    func refusal(of point: NotesPoint) -> Refusal? {
        if case .failure(let refusal) = verify(point) { return refusal }
        return nil
    }

    /// The verdict after the semantic verifier, by point id. Pure. A missing entry, or one whose source is not
    /// `answered` (malformed, cut off, failed, cancelled), changes nothing (fail closed: a broken runtime never
    /// removes a point). A point answered `weaker` or `unsupported` is REMOVED (`verifierRejected`); its quote
    /// is never shown in its place.
    static func applyingVerifications(
        _ verifications: [String: NotesVerification], to verdict: PointVerdict
    ) -> (verdict: PointVerdict, effect: VerifierEffect) {
        var result = verdict
        var effect = VerifierEffect()
        result.verified = verdict.verified.filter { point in
            guard let verification = verifications[point.id], verification.source == .answered,
                verification.verdict != .supported
            else { return true }
            effect.rejected += 1
            return false
        }
        if effect.rejected > 0 {
            result.dropped += effect.rejected
            result.reasons[.verifierRejected, default: 0] += effect.rejected
        }
        return (result, effect)
    }

    /// How many utterances on each side of the quoted one the verifier sees.
    static let verificationContextUtterances = 2

    /// The verifier's request for a verified point: the claim, the transcript's own quote and the quoted
    /// utterance with `verificationContextUtterances` neighbours on each side, from the transcript the guard
    /// checked against.
    func verificationRequest(for point: NotesPoint, claim: String) -> NotesVerificationRequest {
        var context: [NotesVerificationRequest.Line] = []
        if let center = point.utterance, utterances.indices.contains(center) {
            let low = max(0, center - Self.verificationContextUtterances)
            let high = min(utterances.count - 1, center + Self.verificationContextUtterances)
            context = utterances[low...high].map { .init(speaker: $0.speaker, text: $0.text) }
        }
        return NotesVerificationRequest(kind: point.kind, text: claim, quote: point.quote, context: context)
    }

    private struct Match {
        var range: Range<Int>
        var wholeUtterance: Bool
        /// How many leading quote words the range matches: all of them, or fewer when a literal quote ran on
        /// past a sentence end and only its first sentence was matched.
        var quoteCount: Int
    }

    /// The fewest quote words a match needs unless it is a whole utterance (`quoteTooShort`).
    static let minimumQuoteWords = 3

    private struct Outcome {
        var point: NotesPoint
        var downgraded = false
        /// Set when the person is the speaker, given by the guard (`ownerFromSpeaker`).
        var ownerFromSpeaker = false
    }

    private func verify(_ point: NotesPoint) -> Result<Outcome, Refusal> {
        var point = point
        point.text = Self.plain(point.text)
        point.quote = Self.plain(point.quote)
        guard !point.text.isEmpty else { return .failure(Refusal(.emptyText)) }

        let allQuoteWords = NotesText.words(strippingLinePrefix(point.quote))
        guard !allQuoteWords.isEmpty, let match = find(allQuoteWords, near: point.timeMs) else {
            return .failure(Refusal(.quoteNotInTranscript, detail: missKind(of: allQuoteWords)))
        }
        // Only the matched part of the quote counts from here on (all of it, unless it was cut at a sentence end).
        let quoteWords = Array(allQuoteWords.prefix(match.quoteCount))
        guard quoteWords.count >= Self.minimumQuoteWords || match.wholeUtterance else {
            return .failure(Refusal(.quoteTooShort))
        }
        let claimsDecision = point.kind == .decision || point.kind == .task
        if claimsDecision, quoteWords.count == 1 { return .failure(Refusal(.kindNotSupported)) }

        let textLanguage = NotesLanguage.dominant(in: point.text)
        let quoteLanguage = NotesLanguage.dominant(in: point.quote)
        if textLanguage != .unknown, quoteLanguage != .unknown, textLanguage != quoteLanguage {
            return .failure(Refusal(.languageChanged))
        }

        let covered = Set(match.range.map { wordUtterance[$0] }).sorted()
        let excerpt = self.excerpt(of: match.range)
        var outcome = Outcome(point: point)
        outcome.point.timeMs = utterances[covered[0]].startMs
        outcome.point.speaker = utterances[covered[0]].speaker
        outcome.point.utterance = covered[0]
        outcome.point.sentence = wordSentence[match.range.lowerBound]
        // What is shown as the quote is the transcript's own text.
        outcome.point.quote = excerpt

        // A sentence that is a question is no decision, task or finding. It stays as an open question only when
        // the model wrote it as one.
        if outcome.point.kind != .question, isQuestion(sentence: wordSentence[match.range.lowerBound]) {
            guard outcome.point.text.hasSuffix("?") else { return .failure(Refusal(.questionNotAFinding)) }
            outcome.point.kind = .question
            outcome.downgraded = true
        }
        switch outcome.point.kind {
        case .task:
            if NotesRelevance.isNonWorkTask(text: outcome.point.text) {
                return .failure(Refusal(.nonWorkTask))
            }
        case .question:
            if NotesRelevance.isContextFreeQuestion(outcome.point.text) {
                return .failure(Refusal(.questionWithoutContext))
            }
        case .summary:
            if NotesRelevance.isReportWithoutVerdict(outcome.point.text) {
                return .failure(Refusal(.reportWithoutVerdict))
            }
        case .decision: break
        }
        let vocabulary = Vocabulary(
            words: covered.flatMap { Array(words[utteranceRanges[$0]]) }
                + covered.flatMap { NotesText.words(utterances[$0].speaker) },
            numbers: covered.flatMap {
                NotesText.numberUnits(utterances[$0].text) + NotesText.linkUnits(utterances[$0].text)
            })
        if let rule = Self.faithfulnessRefusal(outcome.point.text, vocabulary: vocabulary, strictStart: false) {
            return .failure(Refusal(.unsupportedDetail, detail: DropDetail(rawValue: rule.rawValue)))
        }
        // A point must not turn a negation around: "nie zatwierdzamy" restated as "zatwierdzono", or the other
        // way round, keeps every word faithful and still flips the meaning.
        if Self.hasNegation(NotesText.words(outcome.point.text)) != Self.hasNegation(quoteWords) {
            return .failure(Refusal(.negationChanged))
        }
        // A summary point is a fact of the discussion in other words; when most of those words are not the
        // quote's, the sense may have been turned around without anything the checks above see.
        if outcome.point.kind == .summary, Self.driftsFromQuote(outcome.point.text, quote: Array(words[match.range])) {
            return .failure(Refusal(.driftedFromQuote))
        }

        if outcome.point.kind == .task {
            outcome.point.person = checkedPerson(
                point.person, match: match, speaker: utterances[covered[0]].speaker)
            if outcome.point.person == nil, Self.isEmptyPerson(point.person), covered.count == 1,
                let owner = ownerFromSpeaker(match.range, speaker: utterances[covered[0]].speaker)
            {
                outcome.point.person = owner
                outcome.ownerFromSpeaker = true
            }
            outcome.point.due = checkedDue(point.due, quoteWords: quoteWords)
        } else {
            outcome.point.person = nil
            outcome.point.due = nil
        }
        return .success(outcome)
    }

    /// The original text of the matched words (and the sentence end after them when they end the sentence).
    private func excerpt(of range: Range<Int>) -> String {
        var pieces: [String] = []
        let covered = Set(range.map { wordUtterance[$0] }).sorted()
        for index in covered {
            let inside = range.filter { wordUtterance[$0] == index }
            guard let first = inside.first, let last = inside.last else { continue }
            let characters = Array(utterances[index].text)
            pieces.append(String(characters[charStart[first]..<min(charEnd[last], characters.count)]))
        }
        var text = pieces.joined(separator: " ")
        let sentence = wordSentence[range.upperBound - 1]
        if sentenceRanges[sentence].upperBound == range.upperBound, let end = sentenceTerminators[sentence],
            !text.hasSuffix(String(end))
        {
            text.append(end)
        }
        return Self.plain(text)
    }

    private static let interrogativeOpeners: Set<String> = [
        "czy", "kto", "co", "kiedy", "jak", "jaki", "jaka", "jakie", "dlaczego", "czemu", "gdzie", "ile", "ktory",
        "ktora", "ktore", "skad", "dokad", "po", "who", "what", "when", "how", "why", "where", "which", "do", "does",
        "did", "can", "could", "should", "would", "is", "are", "will", "shall", "have", "has",
    ]
    private static let tagCues: Set<String> = [
        "ok", "okej", "okay", "tak", "prawda", "zgoda", "right", "yes", "agreed", "dobra", "dobrze",
    ]

    /// The sentence ends with a question mark and is either opened by a question word or has no confirming tag
    /// ("..., ok?") at its end: a question, not a statement.
    private func isQuestion(sentence: Int) -> Bool {
        guard sentenceTerminators[sentence] == "?" else { return false }
        let range = sentenceRanges[sentence]
        if Self.interrogativeOpeners.contains(words[range.lowerBound]) { return true }
        return !words[range].suffix(3).contains { Self.tagCues.contains($0) }
    }

    /// The quote without a leading `[mm:ss]` and `Speaker:` the model may have copied along.
    private func strippingLinePrefix(_ quote: String) -> String {
        var text = quote.trimmingCharacters(in: .whitespaces)
        if let match = text.prefixMatch(of: /\[?\d{1,3}:\d{2}(:\d{2})?\]?[ ]*/) {
            text = String(text[match.range.upperBound...])
        }
        for name in speakerNames where text.hasPrefix(name + ":") {
            text = String(text.dropFirst(name.count + 1))
            break
        }
        return text
    }

    /// How many transcript words, in all, a quote may skip between its first and last word (`dha czy chciał`
    /// for the quote `dha chciał`).
    static let maxSkippedTranscriptWords = 2

    /// The first place in the transcript where all quote words follow each other (by `wordsMatch`): a literal
    /// match within one speaker's words (cut at the first sentence end it crosses), one with gaps within one
    /// sentence; with several, the one closest in time to `near`. An exact match (no gaps) wins over one that
    /// skips up to `maxSkippedTranscriptWords` filler words; the first and the last quote word never have a gap
    /// at the edge, and a skipped word is never a negation, a number, a word with a digit or a capitalised name
    /// the quote does not contain.
    private func find(_ quote: [String], near time: Int) -> Match? {
        guard !quote.isEmpty, words.count >= quote.count else { return nil }
        if let exact = find(quote, near: time, skips: 0) { return exact }
        guard quote.count >= 2, Self.maxSkippedTranscriptWords > 0 else { return nil }
        return find(quote, near: time, skips: Self.maxSkippedTranscriptWords)
    }

    private func find(_ quote: [String], near time: Int, skips: Int) -> Match? {
        var best: Match?
        var bestDistance = Int.max
        for start in 0...(words.count - quote.count) where NotesText.wordsMatch(words[start], quote[0]) {
            guard var end = matchEnd(quote, index: 1, after: start, skips: skips, literal: skips == 0) else { continue }
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
            let distance = abs(utterances[wordUtterance[start]].startMs - time)
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
    private func missKind(of quote: [String]) -> DropDetail {
        guard quote.count >= 2, words.count >= quote.count else { return .quoteAbsent }
        for start in 0...(words.count - quote.count) where NotesText.wordsMatch(words[start], quote[0]) {
            var index = 1
            while index < quote.count, NotesText.wordsMatch(words[start + index], quote[index]) { index += 1 }
            if index == quote.count, speaker(of: start) != speaker(of: start + quote.count - 1) {
                return .quoteSpeakerChange
            }
        }
        if quote.count >= 3 {
            for start in 0...(words.count - quote.count) {
                let window = words[start..<(start + quote.count)]
                let mismatches = zip(window, quote).filter { !NotesText.wordsMatch($0, $1) }.count
                if mismatches == 1, wordSentence[start] == wordSentence[start + quote.count - 1] {
                    return .quoteChangedWord
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
            if matched == quote.count, position - start + 1 > quote.count { return .quoteOmittedWords }
        }
        return .quoteAbsent
    }

    /// The speaker's label (consecutive utterances of one speaker are one speaker).
    private func speaker(of word: Int) -> String { utterances[wordUtterance[word]].speaker }

    /// Whether the transcript word at `index` may be left out of a quote.
    private func canSkip(_ index: Int, quote: [String]) -> Bool {
        let word = words[index]
        if Self.negations.contains(word) || NotesText.isNumberWord(word) { return false }
        if word.contains(where: \.isNumber) { return false }
        if capitalised[index], !quote.contains(where: { NotesText.wordsMatch($0, word) }) { return false }
        return true
    }

    private func isWhole(_ range: Range<Int>) -> Bool {
        let utterance = wordUtterance[range.lowerBound]
        guard wordUtterance[range.upperBound - 1] == utterance else { return false }
        return utteranceRanges[utterance] == range
    }

    // MARK: Person and date of a task

    private static let personStoplist: Set<String> = [
        "ja", "ty", "on", "ona", "ono", "my", "wy", "oni", "one", "kto", "ktos", "nikt", "wszyscy", "wszystkich",
        "zespol", "team", "everyone", "someone", "somebody", "nobody", "who", "we", "you", "they", "he", "she", "it",
        "tak", "nie", "dobrze", "dzieki", "prosze", "ok", "okej", "pan", "pani", "panie", "this", "that", "the",
    ]
    private static let firstPersonWords: Set<String> = [
        "ja", "zrobie", "wezme", "przygotuje", "wysle", "sprawdze", "zajme", "ogarne", "napisze", "dopisze",
        "poprawie", "zadzwonie", "skontaktuje", "ustale", "przejrze", "przeanalizuje", "dostarcze", "zorganizuje",
        "my", "zrobimy", "wezmiemy", "wyslemy", "zajmiemy",
    ]
    private static let firstPersonPairs: [(String, String)] = [
        ("i", "will"), ("i", "ll"), ("i", "can"), ("i", "ve"), ("i", "take"), ("i", "am"), ("i", "m"), ("let", "me"),
        ("we", "will"), ("we", "ll"),
    ]

    static func isGenericLabel(_ label: String) -> Bool {
        let flat = NotesText.words(label).joined(separator: " ")
        if flat.isEmpty { return true }
        return flat.wholeMatch(
            of: /(speaker|mowca|rozmowca|uczestnik|participant|unknown|nieznany|inni|ja|ty|my|on|ona|i|me|you)( \d+)?/)
            != nil
    }

    /// The plural forms of `firstPersonWords` and `firstPersonPairs`: they say "we", so they name nobody.
    private static let pluralWords: Set<String> = ["my", "zrobimy", "wezmiemy", "wyslemy", "zajmiemy"]
    private static let pluralPairs: [(String, String)] = [("we", "will"), ("we", "ll")]

    private static func isEmptyPerson(_ person: String?) -> Bool {
        guard let person else { return true }
        return plain(person).isEmpty
    }

    /// The speaker owns a task the model gave no person when the quote lies in one utterance, says "I" (a
    /// singular marker, no plural one) and the speaker's label is a real name.
    private func ownerFromSpeaker(_ range: Range<Int>, speaker: String) -> String? {
        guard !Self.isGenericLabel(speaker) else { return nil }
        let quote = Array(words[range])
        let singular = quote.contains { Self.firstPersonWords.contains($0) && !Self.pluralWords.contains($0) }
        var pairSingular = false
        var plural = quote.contains { Self.pluralWords.contains($0) }
        for index in quote.indices.dropLast() {
            let pair = (quote[index], quote[index + 1])
            if Self.pluralPairs.contains(where: { $0 == pair }) {
                plural = true
            } else if Self.firstPersonPairs.contains(where: { $0 == pair }) {
                pairSingular = true
            }
        }
        guard (singular || pairSingular) && !plural else { return nil }
        return speaker
    }

    private func hasFirstPersonMarker(_ range: Range<Int>) -> Bool {
        let quote = Array(words[range])
        if quote.contains(where: { Self.firstPersonWords.contains($0) }) { return true }
        for index in quote.indices.dropLast() {
            if Self.firstPersonPairs.contains(where: { $0.0 == quote[index] && $0.1 == quote[index + 1] }) {
                return true
            }
        }
        return false
    }

    /// The person is a name that stands in the quote (capitalised in the transcript, not a function word). The
    /// speaker's label is accepted only when the quote is in the first person and the label is a real name.
    private func checkedPerson(_ person: String?, match: Match, speaker: String) -> String? {
        guard let person = person.map(Self.plain), !person.isEmpty, !Self.isGenericLabel(person) else { return nil }
        let candidates = match.range.filter { index in
            capitalised[index] && words[index].count >= 3 && !Self.personStoplist.contains(words[index])
                && (!startsSentence[index] || nameCandidates.containsName(words[index]))
        }
        var kept: [String] = []
        for part in person.split(whereSeparator: \.isWhitespace) {
            let word = NotesText.words(String(part)).joined()
            guard word.count >= 3, !Self.personStoplist.contains(word) else { continue }
            if candidates.contains(where: { NotesText.namesMatch(words[$0], word) }) { kept.append(String(part)) }
        }
        if !kept.isEmpty { return kept.joined(separator: " ") }

        guard hasFirstPersonMarker(match.range), !Self.isGenericLabel(speaker) else { return nil }
        let claimed = NotesText.words(person).filter { $0.count >= 3 && !Self.personStoplist.contains($0) }
        let own = NotesText.words(speaker).filter { $0.count >= 3 }
        let same = claimed.contains { name in own.contains { NotesText.namesMatch($0, name) } }
        return same ? speaker : nil
    }

    private func checkedDue(_ due: String?, quoteWords: [String]) -> String? {
        guard let due = due.map(Self.plain), !due.isEmpty else { return nil }
        let dueWords = NotesText.words(due)
        let temporal = dueWords.filter { Temporal.isDateWord($0) }
        let required = temporal.isEmpty ? dueWords.filter { $0.count >= 3 } : temporal
        guard !required.isEmpty else { return nil }
        let allStated = required.allSatisfy { word in quoteWords.contains { NotesText.wordsMatch($0, word) } }
        return allStated ? due : nil
    }

    /// One line of plain text: reasoning blocks and control characters out.
    static func plain(_ text: String) -> String {
        MarkdownText.cleaned(NotesText.clean(text), keepNewlines: false).trimmingCharacters(
            in: .whitespacesAndNewlines)
    }

    // MARK: Faithfulness of a text

    /// Words a sentence of notes may start with without being a name (normalised).
    private static let sentenceStarters: Set<String> = [
        "zespol", "spotkanie", "ustalono", "zatwierdzono", "omowiono", "uczestnicy", "nalezy", "trzeba", "decyzja",
        "zadanie", "pytanie", "kto", "co", "czy", "jak", "kiedy", "dlaczego", "gdzie", "po", "w", "na", "do", "z", "i",
        "a", "ale", "oraz", "to", "ten", "ta", "te", "jest", "sa", "byl", "bylo", "zostalo", "zostala", "zostal",
        "zostana", "wszyscy", "podczas", "dyskusja", "rozmowa", "uzgodniono", "przyjeto", "postanowiono", "rozmawiano",
        "dotyczylo", "dotyczyla", "przedstawiono", "poruszono", "nastepnie", "ponadto", "takze", "rowniez", "wreszcie",
        "na koniec", "the", "we", "it", "they", "he", "she", "this", "that", "there", "an", "in", "on", "after",
        "during", "meeting", "team", "participants", "decision", "action", "who", "what", "when", "how", "why",
        "where", "is", "are", "will", "should", "can", "do", "does", "please", "also", "then", "next", "first",
        "finally", "overall", "all", "everyone", "someone", "the team", "discussion", "agreed", "decided",
    ]

    /// True when `text` has no digit, number word, weekday or month, and no capitalised word that `vocabulary`
    /// does not have. A sentence starter is capitalised for being first: it passes when it is a common starter
    /// (`strictStart`), or, for a point's text, when it shares four letters with a word of the vocabulary (the
    /// infinitive of the quote's verb).
    static func isFaithful(_ text: String, vocabulary: Vocabulary, strictStart: Bool) -> Bool {
        faithfulnessRefusal(text, vocabulary: vocabulary, strictStart: strictStart) == nil
    }

    /// `isFaithful` with the reason it refuses (the first rule that fails), or nil when the text is faithful.
    static func faithfulnessRefusal(_ text: String, vocabulary: Vocabulary, strictStart: Bool) -> TextRefusal? {
        for unit in NotesText.numberUnits(text) + NotesText.linkUnits(text) where !vocabulary.numbers.contains(unit) {
            return .unsupportedNumber
        }
        for token in NotesText.tokens(text) {
            let word = token.word
            if word.contains(where: \.isNumber) { continue }
            if NotesText.isNumberWord(word) {
                if !vocabulary.hasExactly(word) { return .unsupportedNumber }
                continue
            }
            if Temporal.isCalendarWord(word) {
                if !vocabulary.contains(word) { return .unsupportedCalendarWord }
                continue
            }
            guard token.capitalised, word.count >= 2 else { continue }
            if vocabulary.containsName(word) { continue }
            guard token.startsSentence else { return .unsupportedCapitalised }
            if sentenceStarters.contains(word) { continue }
            if !strictStart, word.count >= 4, vocabulary.sharesStem(word) { continue }
            return .unsupportedSentenceStart
        }
        return nil
    }

    // MARK: Drift of a summary point from its quote

    /// A summary point keeps its text only when at least 3 of every 5 of its content words are words of the
    /// quote (`quoteCoverage`). Chosen on the reversed key points of a real meeting (coverage 0 to 0.5) and the
    /// faithful paraphrases of the corpus (0.67 and more); see `NotesDriftTests`.
    static let minimumQuoteCoverage = (covered: 3, of: 5)

    /// Function words of four letters or more, and words a note uses to frame what was said ("Mówca mówi,
    /// że…"): they say nothing about the fact, so they are not counted. Shorter words are not counted at all.
    private static let notContentWords: Set<String> = [
        "jest", "przez", "przed", "ktory", "ktora", "ktore", "ktorzy", "ktorych", "ktorym", "ktorej", "tego",
        "temu", "tych", "tymi", "jako", "oraz", "takze", "rowniez", "bedzie", "beda", "byla", "byly", "byli",
        "zostanie", "zostaly", "zostali", "mozna", "moze", "jego", "nich", "nimi", "swoj", "swoja", "swoje",
        "swoich", "ktos", "wszystko", "wszyscy", "wszystkie", "tylko", "jeszcze", "wiec", "jednak", "albo", "czyli",
        "gdyz", "poniewaz", "zeby", "kiedy", "gdzie", "podczas", "miedzy", "wobec", "wedlug", "dzieki", "poza",
        "tutaj", "teraz", "mowca", "mowi", "mowil", "mowila", "mowia", "rozmowca", "uczestnik", "uwaza",
        "stwierdza", "stwierdzil", "zauwaza", "podkresla", "wspomina", "wspomnial", "twierdzi", "mowa", "temat",
        "tematu", "kwestia", "kwestii", "that", "this", "with", "from", "have", "will", "would", "should", "could",
        "they", "them", "their", "there", "what", "which", "about", "into", "than", "then", "been", "were", "also",
        "only", "some", "very", "just", "does", "each", "says", "said", "speaker", "mentions",
    ]

    /// How many of the content words of `text` (words of at least four letters that are not in
    /// `notContentWords` or `sentenceStarters`, each counted once) are words of `quote`, by
    /// `NotesText.wordsMatch` or `NotesText.sharesStem`.
    static func quoteCoverage(of text: String, quote: [String]) -> (covered: Int, total: Int) {
        var seen = Set<String>()
        var covered = 0
        for word in NotesText.words(text)
        where word.count >= 4 && !notContentWords.contains(word) && !sentenceStarters.contains(word) {
            guard seen.insert(word).inserted else { continue }
            if quote.contains(where: { NotesText.wordsMatch($0, word) || NotesText.sharesStem($0, word) }) {
                covered += 1
            }
        }
        return (covered, seen.count)
    }

    /// The text has content words and fewer than `minimumQuoteCoverage` of them are the quote's.
    static func driftsFromQuote(_ text: String, quote: [String]) -> Bool {
        let coverage = quoteCoverage(of: text, quote: quote)
        return coverage.total > 0
            && coverage.covered * minimumQuoteCoverage.of < coverage.total * minimumQuoteCoverage.covered
    }

    // MARK: After REDUCE

    /// Checks the structure REDUCE returned against the verified points (the output of `verifyPoints`). A point
    /// the model left out is added back to its section unless a near-duplicate is listed there: nothing that
    /// was verified disappears because the model forgot it.
    ///
    /// `durationMs` is the length of the meeting (the topic limit, `NotesLayout.maxTopics`); without it the last
    /// utterance plus one minute.
    func verifyReduce(_ output: NotesReduceOutput, points: [NotesPoint], durationMs: Int? = nil) -> ReduceVerdict {
        var audit: ReduceAudit?
        return verifyReduce(output, points: points, durationMs: durationMs, audit: &audit)
    }

    /// The length of the meeting the limits use: `durationMs`, or the last utterance plus one minute (as
    /// `NotesFactGuard`) when it is missing or shorter than the transcript (a recording whose length was not saved).
    func meetingLength(_ durationMs: Int?) -> Int {
        let lastUtterance = utterances.map(\.startMs).max() ?? 0
        guard let durationMs, durationMs > lastUtterance else { return lastUtterance + 60_000 }
        return durationMs
    }

    /// Why `textRefusal` refuses a topic name: the rule that failed, never any text.
    enum TextRefusal: String, Sendable, Codable {
        case tooLong, tooManyWords, languageChanged, negation
        case unsupportedNumber, unsupportedCalendarWord, unsupportedCapitalised, unsupportedSentenceStart
    }

    /// What `verifyReduce` did with every id and point, for `NotesTrace` (ids, kinds and counts only).
    struct ReduceAudit: Equatable, Sendable {
        /// Points added back to their section.
        var backfilled: Set<String> = []
        /// Points not added back, with the point in their section that near-duplicates them.
        var nearDuplicateOf: [String: String] = [:]
        /// Verified points the model listed in another kind's section: the kinds of those sections.
        var misfiled: [String: [NotesPointKind]] = [:]
        /// Listed ids that are no verified point.
        var unknownIDs = 0
        /// Ids listed again in their own section (kept once).
        var repeatedIDs = 0
        /// Summary points REDUCE put under a topic that were not kept: a question, or over the limit of topics or
        /// of points per topic (`NotesLayout`).
        var findingsOverLimit: Set<String> = []
        /// Topic names refused by the fact check (their points went to "Other").
        var topicNameRefused = 0
        /// Questions REDUCE listed that were not shown because of the limit (`NotesGuard.maxQuestions`).
        var questionsOverLimit: Set<String> = []
    }

    /// `verifyReduce` with its audit; the verdict is the one `verifyReduce` returns.
    func auditedVerifyReduce(
        _ output: NotesReduceOutput, points: [NotesPoint], durationMs: Int? = nil
    ) -> (verdict: ReduceVerdict, audit: ReduceAudit) {
        var audit: ReduceAudit? = ReduceAudit()
        let verdict = verifyReduce(output, points: points, durationMs: durationMs, audit: &audit)
        return (verdict, audit ?? ReduceAudit())
    }

    private func verifyReduce(
        _ output: NotesReduceOutput, points: [NotesPoint], durationMs: Int?, audit: inout ReduceAudit?
    ) -> ReduceVerdict {
        let byID = Dictionary(points.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rejected = 0
        var trail = audit

        func section(_ ids: [String], kind: NotesPointKind) -> [NotesPoint] {
            var seen = Set<String>()
            var result: [NotesPoint] = []
            for id in ids {
                guard let point = byID[id], point.kind == kind else {
                    rejected += 1
                    if byID[id] == nil {
                        trail?.unknownIDs += 1
                    } else {
                        trail?.misfiled[id, default: []].append(kind)
                    }
                    continue
                }
                if seen.insert(id).inserted {
                    result.append(point)
                } else {
                    trail?.repeatedIDs += 1
                }
            }
            return result
        }

        var decisions = section(output.decisions, kind: .decision)
        var tasks = section(output.tasks, kind: .task)
        var questions = section(output.questions, kind: .question)

        let listed = Set((decisions + tasks + questions).map(\.id))
        var backfilled = 0
        // Decisions and tasks are rare and each one matters, so one REDUCE forgot is added back. Questions and
        // findings are not: what REDUCE did not choose stays out.
        var backfilledTasks = Set<String>()
        func fill(_ list: inout [NotesPoint], kind: NotesPointKind) {
            for point in points where point.kind == kind && !listed.contains(point.id) {
                // Tasks are merged with their twins below, which also keeps the person and date of either.
                if kind != .task, let twin = list.first(where: { Self.nearDuplicate($0, point) }) {
                    trail?.nearDuplicateOf[point.id] = twin.id
                    continue
                }
                list.append(point)
                backfilled += 1
                trail?.backfilled.insert(point.id)
                if kind == .task { backfilledTasks.insert(point.id) }
            }
        }
        fill(&decisions, kind: .decision)
        fill(&tasks, kind: .task)
        // The model may list one piece of work twice (restated later, or in two chunks); it stands once.
        let unique = NotesRelevance.deduplicatedTasks(tasks)
        tasks = unique.tasks
        for (id, twin) in unique.removed {
            trail?.nearDuplicateOf[id] = twin
            if backfilledTasks.contains(id) {
                backfilled -= 1
                trail?.backfilled.remove(id)
            }
        }
        if questions.count > Self.maxQuestions {
            for point in questions[Self.maxQuestions...] { trail?.questionsOverLimit.insert(point.id) }
            questions = Array(questions.prefix(Self.maxQuestions))
        }

        // The topics are the ones REDUCE wrote, in its order. A summary point stands under its first topic only,
        // never as a question or a near twin of one listed. A topic name the facts do
        // not back sends its points to "Other"; the limits of `NotesLayout` cut the rest.
        var topics: [ReduceVerdict.Topic] = []
        var other: [NotesPoint] = []
        var listedKeys: [NotesPoint] = []
        var seenKeys = Set<String>()
        for topic in output.topics {
            var kept: [NotesPoint] = []
            for id in topic.ids {
                guard let point = byID[id], point.kind == .summary else {
                    rejected += 1
                    if byID[id] == nil {
                        trail?.unknownIDs += 1
                    } else {
                        trail?.misfiled[id, default: []].append(.summary)
                    }
                    continue
                }
                guard seenKeys.insert(id).inserted else {
                    trail?.repeatedIDs += 1
                    continue
                }
                if point.text.hasSuffix("?") {
                    trail?.findingsOverLimit.insert(id)
                    continue
                }
                if let twin = listedKeys.first(where: { Self.nearDuplicate($0, point) }) {
                    trail?.nearDuplicateOf[id] = twin.id
                    continue
                }
                kept.append(point)
                listedKeys.append(point)
            }
            guard !kept.isEmpty else { continue }
            let given = topic.name.map(Self.topicName) ?? ""
            if given.isEmpty {
                topics.append(.init(name: nil, points: kept))
            } else if let name = acceptedTopicName(given, points: kept) {
                topics.append(.init(name: name, points: kept))
            } else {
                trail?.topicNameRefused += 1
                other.append(contentsOf: kept)
            }
        }
        // Findings without a name (the old list, the code's order of failed batches) are one topic, where the
        // first of them stood: the composer gives it one heading.
        if let first = topics.firstIndex(where: { $0.name == nil }) {
            let unnamed = topics.filter { $0.name == nil }.flatMap(\.points)
            topics.removeAll { $0.name == nil }
            topics.insert(.init(name: nil, points: unnamed), at: first)
        }
        let maxTopics = NotesLayout.maxTopics(durationMs: meetingLength(durationMs))
        func cut(_ points: some Sequence<NotesPoint>) {
            for point in points { trail?.findingsOverLimit.insert(point.id) }
        }
        if topics.count > maxTopics {
            cut(topics[maxTopics...].flatMap(\.points))
            topics = Array(topics.prefix(maxTopics))
        }
        for index in topics.indices where topics[index].points.count > NotesLayout.maxPointsPerTopic {
            cut(topics[index].points[NotesLayout.maxPointsPerTopic...])
            topics[index].points = Array(topics[index].points.prefix(NotesLayout.maxPointsPerTopic))
        }
        if !other.isEmpty {
            cut(other.dropFirst(NotesLayout.maxPointsPerTopic))
            topics.append(.init(name: nil, points: Array(other.prefix(NotesLayout.maxPointsPerTopic)), isOther: true))
        }
        audit = trail
        return ReduceVerdict(
            decisions: decisions, tasks: tasks, questions: questions, rejectedIDs: rejected, backfilled: backfilled,
            topics: topics)
    }

    /// The most open questions the notes show.
    static let maxQuestions = 5
    /// The longest topic name, in words.
    static let maxTopicNameWords = 8

    /// A topic name as one plain line, without the quotes, colon or full stop a model may leave around it.
    static func topicName(_ raw: String) -> String {
        plain(raw).trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”„«»:;.,-–— ").union(.whitespaces))
    }

    /// Why a topic name is refused, or nil: longer than `maxTopicNameWords`, or failing the text checks
    /// (`textRefusal`: language, negation, numbers, dates, names, sentence start) against the material of the topic's
    /// own points only, so a name cannot borrow a fact from another part of the meeting.
    func topicNameRefusal(_ name: String, points: [NotesPoint]) -> TextRefusal? {
        if name.count > 200 { return .tooLong }
        if name.split(whereSeparator: \.isWhitespace).count > Self.maxTopicNameWords { return .tooManyWords }
        // A name is a heading: its first word is capitalised for being first, so it passes like the first word
        // of a point's text (a word of four letters or more that shares a stem with the topic's material); a name
        // the points do not have is still refused, at the start or later.
        return textRefusal(name, material: textMaterial(points: points), strictStart: false)
    }

    /// The name a topic is shown with: `name` when `topicNameRefusal` passes it, or, when only its first word is
    /// refused (`unsupportedSentenceStart`: a capitalised word its points do not have, such as "Core" in "Core
    /// functionality"), the rest of the name with its new first word capitalised, when that word is a word of the
    /// points (four letters or more, without a digit, sharing a stem with their material, so the name never
    /// starts with "i", "and" or a number) and the rest passes the same checks. Nil when neither passes.
    func acceptedTopicName(_ name: String, points: [NotesPoint]) -> String? {
        guard let refusal = topicNameRefusal(name, points: points) else { return name }
        guard refusal == .unsupportedSentenceStart else { return nil }
        let words = name.split(whereSeparator: \.isWhitespace)
        guard words.count >= 2, let next = NotesText.words(String(words[1])).first, next.count >= 4,
            !next.contains(where: \.isNumber),
            textMaterial(points: points).vocabulary.sharesStem(next)
        else { return nil }
        let rest = words.dropFirst().joined(separator: " ")
        let shorter = rest.prefix(1).uppercased() + rest.dropFirst()
        return topicNameRefusal(shorter, points: points) == nil ? shorter : nil
    }

    /// The same utterance and sentence, or quotes that share most of their words.
    static func nearDuplicate(_ first: NotesPoint, _ second: NotesPoint) -> Bool {
        if first.kind != second.kind { return false }
        if let u1 = first.utterance, let u2 = second.utterance, let s1 = first.sentence, let s2 = second.sentence,
            u1 == u2, s1 == s2
        {
            return true
        }
        let a = Set(NotesText.words(first.quote))
        let b = Set(NotesText.words(second.quote))
        guard !a.isEmpty, !b.isEmpty else { return false }
        return Double(a.intersection(b).count) / Double(a.union(b).count) >= 0.7
    }

    private static func hasNegation(_ words: [String]) -> Bool {
        words.contains { negations.contains($0) }
    }

    private static let negations: Set<String> = [
        "nie", "nigdy", "nikt", "nic", "zaden", "zadna", "zadne", "not", "no", "never", "nobody", "nothing", "none",
        "cannot", "without",
    ]

    /// What a topic name is checked against: the vocabulary of the verified material and whether it has a negation.
    private struct TextMaterial {
        var vocabulary: Vocabulary
        var hasNegation: Bool
    }

    private func textMaterial(points: [NotesPoint]) -> TextMaterial {
        var corpus: [String] = []
        var numbers: [String] = []
        for point in points {
            for field in [point.quote, point.text, point.person ?? "", point.due ?? ""] where !field.isEmpty {
                corpus.append(contentsOf: NotesText.words(field))
                numbers.append(contentsOf: NotesText.numberUnits(field) + NotesText.linkUnits(field))
            }
        }
        for speaker in speakerNames {
            corpus.append(contentsOf: NotesText.words(speaker))
            numbers.append(contentsOf: NotesText.numberUnits(speaker))
        }
        return TextMaterial(
            vocabulary: Vocabulary(words: corpus, numbers: numbers),
            hasNegation: corpus.contains(where: { Self.negations.contains($0) }))
    }

    /// The checks of a topic name, besides its length: it is in the language of the transcript, has a negation only
    /// when the material has one, and every number written with digits (a decimal, a time or a date counts as one
    /// unit: `3.5` is not `5.3`), spelled-out number, weekday, month and capitalised word is in the material (the
    /// quotes, the texts of the verified points, the person and due date of the tasks, the speakers' names) or, for
    /// a capitalised word, is one of a short list of common sentence starters.
    private func textRefusal(_ text: String, material: TextMaterial, strictStart: Bool = true) -> TextRefusal? {
        let textLanguage = NotesLanguage.dominant(in: text)
        if language != .unknown, textLanguage != .unknown, textLanguage != language { return .languageChanged }
        if NotesText.words(text).contains(where: { Self.negations.contains($0) }), !material.hasNegation {
            return .negation
        }
        return Self.faithfulnessRefusal(text, vocabulary: material.vocabulary, strictStart: strictStart)
    }

    /// Words grouped by their first two letters, so a lookup stays cheap for a long list.
    struct Vocabulary: Sendable {
        private var groups: [String: [String]] = [:]
        private var exact: Set<String> = []
        let numbers: Set<String>

        init(words: [String], numbers: [String]) {
            for word in words {
                groups[String(word.prefix(2)), default: []].append(word)
                exact.insert(word)
            }
            self.numbers = Set(numbers)
        }

        func hasExactly(_ word: String) -> Bool { exact.contains(word) }

        func contains(_ word: String) -> Bool {
            exact.contains(word)
                || (groups[String(word.prefix(2))]?.contains { NotesText.wordsMatch($0, word) } ?? false)
        }

        func containsName(_ word: String) -> Bool {
            exact.contains(word)
                || (groups[String(word.prefix(2))]?.contains {
                    NotesText.namesMatch($0, word) || NotesText.wordsMatch($0, word)
                } ?? false)
        }

        /// A word that begins like `word` (four letters): the verb of the quote in another form.
        func sharesStem(_ word: String) -> Bool {
            let stem = word.prefix(4)
            return groups[String(word.prefix(2))]?.contains { $0.hasPrefix(stem) } ?? false
        }
    }
}

/// Weekdays and months, by the forms they take in a sentence, and the words that name a relative date.
enum Temporal {
    private static let groups: [String: String] = {
        let table: [[String]] = [
            ["poniedzialek", "poniedzialku", "poniedzialkiem", "poniedzialki", "poniedzialkow", "poniedzialkach"],
            ["wtorek", "wtorku", "wtorkiem", "wtorki", "wtorkow", "wtorkach"],
            ["sroda", "srode", "srody", "srodzie", "srodami", "srodach", "srodzien"],
            ["czwartek", "czwartku", "czwartkiem", "czwartki", "czwartkow", "czwartkach"],
            ["piatek", "piatku", "piatkiem", "piatki", "piatkow", "piatkach"],
            ["sobota", "sobote", "soboty", "sobocie", "sobotach"],
            ["niedziela", "niedziele", "niedzieli", "niedzielach"],
            ["styczen", "stycznia", "styczniu"], ["luty", "lutego", "lutym"], ["marzec", "marca", "marcu"],
            ["kwiecien", "kwietnia", "kwietniu"], ["maj", "maja", "maju"], ["czerwiec", "czerwca", "czerwcu"],
            ["lipiec", "lipca", "lipcu"], ["sierpien", "sierpnia", "sierpniu"],
            ["wrzesien", "wrzesnia", "wrzesniu"], ["pazdziernik", "pazdziernika", "pazdzierniku"],
            ["listopad", "listopada", "listopadzie"], ["grudzien", "grudnia", "grudniu"],
            ["monday", "mondays"], ["tuesday", "tuesdays"], ["wednesday", "wednesdays"], ["thursday", "thursdays"],
            ["friday", "fridays"], ["saturday", "saturdays"], ["sunday", "sundays"], ["january"], ["february"],
            ["march"], ["april"], ["june"], ["july"], ["august"], ["september"], ["october"], ["november"],
            ["december"],
        ]
        var result: [String: String] = [:]
        for forms in table { for form in forms { result[form] = forms[0] } }
        return result
    }()

    private static let relative = [
        "jutro", "dzis", "dzisiaj", "pojutrze", "wczoraj", "tomorrow", "today", "tonight", "yesterday",
        "tydzien", "tygodni", "miesiac", "miesiec", "kwartal", "week", "month", "quarter", "eod", "eow", "asap",
        "weekend", "przyszl", "nastepn", "next",
    ]

    /// The weekday or month a form belongs to (`piatku` → `piatek`), `nil` for any other word.
    static func group(of word: String) -> String? {
        groups[word]
    }

    /// A weekday or a month name.
    static func isCalendarWord(_ word: String) -> Bool {
        groups[word] != nil
    }

    /// The month groups of January to December, in the order a numeric date writes them (`15.03` is March).
    private static let monthGroups = [
        "styczen", "luty", "marzec", "kwiecien", "maj", "czerwiec",
        "lipiec", "sierpien", "wrzesien", "pazdziernik", "listopad", "grudzien",
    ]

    /// The group a month number names (`3` → `marzec`), `nil` outside 1 to 12.
    static func monthGroup(_ number: Int) -> String? {
        (1...12).contains(number) ? monthGroups[number - 1] : nil
    }

    /// Anything a due date is made of: a number, a weekday, a month, a relative day or period.
    static func isDateWord(_ word: String) -> Bool {
        word.contains(where: \.isNumber) || isCalendarWord(word)
            || relative.contains { word.hasPrefix($0) && word.count <= $0.count + 4 }
    }
}
