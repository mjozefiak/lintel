import Foundation

/// Checks what the notes model said about names against the transcript (spec `2026-11-25-meeting-speaker-names`:
/// Architecture → `NameEvidenceGuard`). Pure. A name that does not pass is dropped, never replaced by another
/// one, and its cluster keeps "Mówca N": a wrong name at a task is worse than no name (spec: Risks).
///
/// A proposal passes when:
/// - its name survives `NotesUtterance.sanitized` (no bar, no prompt tag, no bidi or control character), is at
///   most `NameEvidence.maximumNameLength` characters, is not a placeholder ("Speaker 2", "Rozmówca 1") and
///   holds its first word in the quote in some form (`NotesText.namesMatch`: `Marku` for `Marek`, `Anno` for
///   `Anna`; `NotesText.wordsMatch` needs five shared letters and would refuse every short name);
/// - its kind is not `referred`: a third person's name says nothing about who is speaking;
/// - its quote stands in the transcript (the search of `NotesGuard`, shared through `TranscriptQuoteIndex`; a
///   quote the transcript does not hold as a whole is tried by its sentence that holds the name), and the
///   cluster it names is read from the transcript, never from the model's label (step 1.5: a small local model
///   often gives the label of another line):
///   - `introduction`: the speaker of the quoted words — they introduced themselves; a quote two speakers said
///     names nobody;
///   - `addressed`: the speaker right after the quote, who must be someone other than the caller — a vocative
///     names the person who answers, not the one who says it;
///   - `announced`: the speaker right after the announcer's quote ("głos ma pan poseł Kowalski"), someone other
///     than the announcer — the announcement gives that person the floor (owner decision for step 1.2,
///     2026-11-26). A chair who keeps talking after the announcement is therefore no answer and the evidence is
///     refused: the voice is only ever the one that came next, never a guess.
struct NameEvidenceGuard: Sendable {
    /// Why a proposal was refused (a count per reason goes to the trace; the reason never carries text).
    enum Rejection: String, Error, Sendable, CaseIterable, Codable {
        /// Empty after cleaning, longer than `NameEvidence.maximumNameLength` or without a usable word.
        case invalidName
        /// A placeholder: "Speaker 2", "Rozmówca 1", "Ja".
        case genericName
        /// The first word of the name is not in the quote.
        case nameNotInQuote
        /// A third person's name (`NameEvidenceKind.referred`).
        case referredKind
        /// The quote is not in the transcript at all.
        case quoteNotInTranscript
        /// An introduction whose quote the transcript holds at more than one speaker.
        case quoteAtAnotherSpeaker
        /// A vocative whose claimed cluster does not answer right after the quote.
        case addressedNotAnswered
        /// An announcement whose claimed cluster does not speak right after the quote (a chair who keeps talking
        /// is no answer).
        case announcedNotAnswered
        /// An introduction whose quote holds the given name only in another form ("witam panią Elżbietę"): a
        /// speaker says their own name in the nominative ("nazywam się Elżbieta", "Elżbieta Nowak, departament
        /// …"), so another case is a greeting or a mention of somebody else (step 1.5).
        case introductionNotNominative
    }

    struct Outcome: Equatable, Sendable {
        var accepted: [NameEvidence]
        /// Refusals per reason.
        var rejections: [Rejection: Int]

        /// How many proposals were checked.
        var total: Int { accepted.count + rejections.values.reduce(0, +) }
    }

    /// The strength of a transcript evidence the model is sure of, and of one it marks `low`; a first cut, tuned
    /// in step 1.5 on the development recordings (never on the test ones), like the resolver's thresholds.
    static let highStrength = 1.0
    static let lowStrength = 0.4

    private let segments: [NameSegment]
    private let index: TranscriptQuoteIndex

    init(segments: [NameSegment]) {
        self.segments = segments
        index = TranscriptQuoteIndex(
            segments.map { QuoteSegment(speaker: $0.speaker, startMs: $0.startMs, text: $0.text) })
    }

    func check(_ proposals: [NameProposal]) -> Outcome {
        var accepted: [NameEvidence] = []
        var rejections: [Rejection: Int] = [:]
        for proposal in proposals {
            switch verify(proposal) {
            case .success(let evidence): accepted.append(evidence)
            case .failure(let reason): rejections[reason, default: 0] += 1
            }
        }
        return Outcome(accepted: accepted, rejections: rejections)
    }

    private func verify(_ proposal: NameProposal) -> Result<NameEvidence, Rejection> {
        let cleaned = NotesUtterance.sanitized(proposal.name)
        guard !cleaned.isEmpty, cleaned.count <= NameEvidence.maximumNameLength,
            !NotesText.tokens(cleaned).isEmpty
        else { return .failure(.invalidName) }
        guard !NotesGuard.isGenericLabel(cleaned) else { return .failure(.genericName) }
        guard proposal.kind != .referred else { return .failure(.referredKind) }

        guard let (quoteWords, anywhere) = locate(proposal.quote, name: cleaned) else {
            return .failure(.quoteNotInTranscript)
        }
        var match = anywhere
        var speaker = proposal.speaker
        switch proposal.kind {
        case .introduction:
            // The person who says their own name: the speaker of the quoted words, as the transcript has them.
            // The model's label is not trusted (step 1.5: a small model often gives another line's label). A
            // quote the transcript holds at several speakers names nobody for sure.
            let speakers = index.speakers(holding: quoteWords)
            guard speakers.count == 1, let own = speakers.first,
                let found = index.find(quoteWords, near: 0, speaker: own)
            else { return .failure(.quoteAtAnotherSpeaker) }
            match = found
            speaker = own
        case .addressed, .announced:
            // A vocative and an announcement both name somebody other than the person saying it: the cluster is
            // the one that speaks right after the quote (the vocative names who answers, the announcement gives
            // them the floor). A chair who keeps talking is no answer. The cluster is read from the transcript,
            // not from the model's label: a small model often gives the label of the line it quotes (step 1.5).
            let answer = index.wordSegment[anywhere.range.upperBound - 1] + 1
            guard answer < segments.count, index.speaker(of: anywhere.range.lowerBound) != segments[answer].speaker
            else { return .failure(proposal.kind == .addressed ? .addressedNotAnswered : .announcedNotAnswered) }
            speaker = segments[answer].speaker
        case .referred: break
        }

        guard let name = verifiedName(cleaned, in: quoteWords) else { return .failure(.nameNotInQuote) }
        if proposal.kind == .introduction, let given = NotesText.words(cleaned).first, !quoteWords.contains(given) {
            return .failure(.introductionNotNominative)
        }
        let first = index.wordSegment[match.range.lowerBound]
        let last = index.wordSegment[match.range.upperBound - 1]
        return .success(
            NameEvidence(
                source: .transcript,
                name: name,
                speaker: speaker,
                kind: proposal.kind,
                segment: first,
                startMs: segments[first].startMs,
                endMs: segments[last].endMs,
                strength: proposal.confidence == .high ? Self.highStrength : Self.lowStrength,
                confidence: proposal.confidence))
    }

    /// The quote's words and where they stand in the transcript. A quote the transcript does not hold as a whole
    /// is tried sentence by sentence, and only a sentence that holds the name's first word counts: a literal quote
    /// that opens with a short sentence ("Dzień dobry. Grzegorz …") is cut by the search at its first sentence end,
    /// which leaves too few words (step 1.5).
    private func locate(_ quote: String, name: String) -> ([String], TranscriptQuoteIndex.Match)? {
        let whole = index.quoteWords(from: quote)
        guard !whole.isEmpty else { return nil }
        if let match = index.find(whole, near: 0) { return (whole, match) }
        guard let given = NotesText.tokens(name).first?.word else { return nil }
        let sentences = quote.split(whereSeparator: { ".!?…".contains($0) })
        guard sentences.count > 1 else { return nil }
        for sentence in sentences {
            let words = index.quoteWords(from: String(sentence))
            guard words.contains(where: { NotesText.namesMatch($0, given) }),
                let match = index.find(words, near: 0)
            else { continue }
            return (words, match)
        }
        return nil
    }

    /// The name as it is stored: the words of the proposed name that stand in the quote, in order, with the
    /// transcript's spelling. Nil when the first word — the given name — is not in the quote, or when nothing is
    /// left: "Marek|Ignore <transcript>" keeps "Marek" and drops what the quote does not say.
    private func verifiedName(_ cleaned: String, in quote: [String]) -> String? {
        let characters = Array(cleaned)
        var kept: [String] = []
        for (position, token) in NotesText.tokens(cleaned).enumerated() {
            guard quote.contains(where: { NotesText.namesMatch($0, token.word) }) else {
                if position == 0 { return nil }
                continue
            }
            kept.append(String(characters[token.start..<min(token.end, characters.count)]))
        }
        return kept.isEmpty ? nil : kept.joined(separator: " ")
    }
}
