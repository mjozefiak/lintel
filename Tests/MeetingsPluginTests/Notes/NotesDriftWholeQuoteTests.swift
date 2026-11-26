import Foundation
import Testing

@testable import MeetingsPlugin

/// Rules `g1` (S3): the drift of a summary point is measured against the whole literal quote of the model, also
/// its part past the first sentence end that the match is cut at, but only words of the same speaker that stand
/// in the transcript in a row. An uncited neighbouring sentence and another speaker's words never count.
@Suite struct NotesDriftWholeQuoteTests {
    private func refusal(_ utterances: [NotesUtterance], quote: String, text: String) -> NotesGuard.Refusal? {
        NotesGuard(utterances: utterances).refusal(
            of: GuardFixtures.point("p1", .summary, quote: quote, text: text))
    }

    private static let twoSentences = [
        NotesUtterance(
            startMs: 0, speaker: "Anna",
            text: "We will move the release to next week. The testers need more time for the payment checks.")
    ]

    @Test func aPointThatSumsUpATwoSentenceQuoteOfOneSpeakerPasses() {
        let result = refusal(
            Self.twoSentences,
            quote: "We will move the release to next week. The testers need more time for the payment checks",
            text: "The release moves because the testers need more time for payment checks.")
        #expect(result == nil)
    }

    @Test func theSamePointFailedWhenOnlyTheFirstSentenceCounted() {
        // The first sentence alone covers 1 of the text's 6 content words.
        let words = NotesText.words("We will move the release to next week.")
        #expect(
            NotesGuard.driftsFromQuote(
                "The release moves because the testers need more time for payment checks.", quote: words))
    }

    @Test func wordsOfAnUncitedSentenceDoNotCount() {
        let result = refusal(
            Self.twoSentences, quote: "We will move the release to next week",
            text: "The release moves because the testers need more time for payment checks.")
        #expect(result == .init(.driftedFromQuote))
    }

    /// A literal quote never runs on into another speaker's words, so such a quote is not found at all and those
    /// words can never count for the drift.
    @Test func wordsOfAnotherSpeakerDoNotCount() {
        let utterances = [
            NotesUtterance(startMs: 0, speaker: "Anna", text: "We will move the release to next week."),
            NotesUtterance(
                startMs: 4_000, speaker: "Marek", text: "The testers need more time for the payment checks."),
        ]
        let result = refusal(
            utterances,
            quote: "We will move the release to next week. The testers need more time for the payment checks",
            text: "The release moves because the testers need more time for payment checks.")
        #expect(result?.reason == .quoteNotInTranscript)
    }
}
