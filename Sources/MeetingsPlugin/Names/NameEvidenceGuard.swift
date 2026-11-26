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
/// - its quote stands in the transcript (the search of `NotesGuard`, shared through `TranscriptQuoteIndex`), at
///   the speaker the claim is about:
///   - `introduction`: the quote is the claimed cluster's own words — they introduced themselves;
///   - `addressed`: the quote is the caller's, the claimed cluster is the one who speaks right after it — a
///     vocative names the person who answers, not the one who says it;
///   - `announced`: the quote is the announcer's ("głos ma pan poseł Kowalski"), the claimed cluster is the one
///     who speaks right after it — the announcement gives that person the floor (owner decision for step 1.2,
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
        /// The quote stands in the transcript, but not among the claimed cluster's words (an introduction).
        case quoteAtAnotherSpeaker
        /// A vocative whose claimed cluster does not answer right after the quote.
        case addressedNotAnswered
        /// An announcement whose claimed cluster does not speak right after the quote (a chair who keeps talking
        /// is no answer).
        case announcedNotAnswered
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

        let quoteWords = index.quoteWords(from: proposal.quote)
        guard !quoteWords.isEmpty, let anywhere = index.find(quoteWords, near: 0) else {
            return .failure(.quoteNotInTranscript)
        }
        var match = anywhere
        switch proposal.kind {
        case .introduction:
            guard let own = index.find(quoteWords, near: 0, speaker: proposal.speaker) else {
                return .failure(.quoteAtAnotherSpeaker)
            }
            match = own
        case .addressed, .announced:
            // A vocative and an announcement both name somebody other than the person saying it: the cluster is
            // the one that speaks right after the quote (the vocative names who answers, the announcement gives
            // them the floor). A chair who keeps talking is no answer.
            let answer = index.wordSegment[anywhere.range.upperBound - 1] + 1
            guard index.speaker(of: anywhere.range.lowerBound) != proposal.speaker, answer < segments.count,
                segments[answer].speaker == proposal.speaker
            else { return .failure(proposal.kind == .addressed ? .addressedNotAnswered : .announcedNotAnswered) }
        case .referred: break
        }

        guard let name = verifiedName(cleaned, in: quoteWords) else { return .failure(.nameNotInQuote) }
        let first = index.wordSegment[match.range.lowerBound]
        let last = index.wordSegment[match.range.upperBound - 1]
        return .success(
            NameEvidence(
                source: .transcript,
                name: name,
                speaker: proposal.speaker,
                kind: proposal.kind,
                segment: first,
                startMs: segments[first].startMs,
                endMs: segments[last].endMs,
                strength: proposal.confidence == .high ? Self.highStrength : Self.lowStrength,
                confidence: proposal.confidence))
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
