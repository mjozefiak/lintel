import Foundation
import Testing

@testable import MeetingsPlugin

/// Rules `g1`, S1: a quote the model changed (a word replaced, more than two words left out) is anchored to the
/// shortest fragment of ONE sentence of one speaker that holds 80 % of its content words in order, and every
/// later check reads that fragment, never the whole sentence of the recognizer and never the model's words.
@Suite struct NotesGuardAnchoringTests {
    private static let billing =
        "Okay so after the call yesterday we agreed that the billing team will migrate the invoice service before "
        + "the audit and then we also talked about the 40 laptops for the offsite"
    private static let changedQuote = "the billing team will move the invoice service before the audit"

    private func verdict(_ utterances: [NotesUtterance], _ point: NotesPoint) -> NotesGuard.PointVerdict {
        NotesGuard(utterances: utterances).verifyPoints([point])
    }

    private func refusal(_ utterances: [NotesUtterance], _ point: NotesPoint) -> NotesGuard.Refusal? {
        NotesGuard(utterances: utterances).refusal(of: point)
    }

    private func summary(_ quote: String, _ text: String, time: Int = 0) -> NotesPoint {
        GuardFixtures.point("p1", .summary, quote: quote, text: text, time: time)
    }

    @Test func aQuoteWithAChangedWordIsAnchoredToAFragmentNotToTheWholeSentence() {
        let result = verdict(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: Self.billing)],
            summary(Self.changedQuote, "The billing team migrates the invoice service before the audit."))
        #expect(result.dropped == 0)
        #expect(result.reanchored == 1)
        let quote = result.verified.first?.quote ?? ""
        #expect(quote == "billing team will migrate the invoice service before the audit")
        #expect(!quote.contains("laptops") && !quote.contains("yesterday"))
    }

    @Test func aLiteralQuoteIsNotCountedAsAnchored() {
        let result = verdict(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: Self.billing)],
            summary(
                "the billing team will migrate the invoice service before the audit",
                "The billing team migrates the invoice service before the audit."))
        #expect(result.dropped == 0)
        #expect(result.reanchored == 0)
    }

    @Test func aDetailFromTheRestOfALongSentenceDoesNotPass() {
        let result = refusal(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: Self.billing)],
            summary(Self.changedQuote, "The billing team migrates the invoice service before the audit and 40 laptops.")
        )
        #expect(result == .init(.unsupportedDetail, detail: .unsupportedNumber))
    }

    @Test func aPointThatNeedsASecondSentenceStillFails() {
        let utterances = [
            NotesUtterance(
                startMs: 0, speaker: "Anna",
                text: "The billing team will migrate the invoice service before the audit. The vendor signed it.")
        ]
        let result = refusal(
            utterances,
            summary(
                "the billing team will move the invoice service before the audit the vendor signed",
                "The billing team migrates the invoice service before the audit and the vendor signed."))
        #expect(result?.reason == .quoteNotInTranscript)
    }

    @Test func aQuoteAcrossASpeakerChangeIsNotAnchored() {
        let utterances = [
            NotesUtterance(startMs: 0, speaker: "Anna", text: "the billing team will migrate the invoice"),
            NotesUtterance(startMs: 3_000, speaker: "Marek", text: "service before the audit starts."),
        ]
        let result = refusal(
            utterances, summary(Self.changedQuote, "The billing team migrates the invoice service before the audit."))
        #expect(result?.reason == .quoteNotInTranscript)
    }

    @Test func theFragmentIsTheNearestInTimeAndNeverTooFarFromTheModelsTime() {
        let sentence = "the billing team will migrate the invoice service before the audit."
        let utterances = [
            NotesUtterance(startMs: 0, speaker: "Anna", text: sentence),
            NotesUtterance(startMs: 200_000, speaker: "Marek", text: sentence),
        ]
        let text = "The billing team migrates the invoice service before the audit."
        let near = verdict(utterances, summary(Self.changedQuote, text, time: 190_000))
        #expect(near.verified.first?.speaker == "Marek")
        let far = refusal([utterances[1]], summary(Self.changedQuote, text, time: 0))
        #expect(far?.reason == .quoteNotInTranscript)
    }

    @Test func aNegationOfTheSentenceOutsideTheFragmentStopsTheAnchoring() {
        let english = refusal(
            [
                NotesUtterance(
                    startMs: 0, speaker: "Anna",
                    text: "Honestly we will not let the billing team migrate the invoice service before the audit.")
            ],
            summary(Self.changedQuote, "The billing team migrates the invoice service before the audit."))
        #expect(english?.reason == .quoteNotInTranscript)
        let polish = refusal(
            [
                NotesUtterance(
                    startMs: 0, speaker: "Marek",
                    text: "Na razie nie zatwierdzamy budżetu marketingowego na kampanię jesienną dla klientów.")
            ],
            summary(
                "zatwierdzamy budżet reklamowy na kampanię jesienną dla klientów",
                "Zatwierdzamy budżet na kampanię jesienną dla klientów."))
        #expect(polish?.reason == .quoteNotInTranscript)
    }

    @Test func aTextThatUsesTheWordTheModelChangedIsRefused() {
        let result = refusal(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: Self.billing)],
            summary(
                "the billing team will migrate the payment service before the audit",
                "The billing team migrates the payment service before the audit."))
        #expect(result?.reason == .quoteNotInTranscript)
    }

    @Test func aQuoteWithTooFewContentWordsIsNotAnchored() {
        let result = refusal(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: "we move it to the next sprint then.")],
            summary("we push it to the sprint", "The team moves it to the sprint."))
        #expect(result?.reason == .quoteNotInTranscript)
    }

    @Test func aTaskKeepsADueDateOnlyWhenTheFragmentHasIt() {
        let utterances = [
            NotesUtterance(
                startMs: 0, speaker: "Anna", text: "Right, I will send the signed contract to the vendor quickly.")
        ]
        let task = GuardFixtures.point(
            "p1", .task, quote: "I will send the signed contract to the vendor on friday",
            text: "Send the signed contract to the vendor.", due: "friday")
        let result = verdict(utterances, task)
        #expect(result.dropped == 0)
        #expect(result.reanchored == 1)
        #expect(result.verified.first?.due == nil)
    }

    @Test func theTraceCountsTheAnchoredPoints() {
        let result = verdict(
            [NotesUtterance(startMs: 0, speaker: "Anna", text: Self.billing)],
            summary(Self.changedQuote, "The billing team migrates the invoice service before the audit."))
        let trace = NotesTraceVerification(proposed: 1, verdict: result)
        #expect(trace.reanchored == 1)
    }
}
