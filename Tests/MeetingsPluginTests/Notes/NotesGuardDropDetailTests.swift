import Foundation
import Testing

@testable import MeetingsPlugin

/// `NotesGuard.DropDetail`: the rule behind `unsupportedDetail` and the kind of miss behind `quoteNotInTranscript`
/// (a measurement aid; the reasons and the kept points are the same with or without it).
@Suite struct NotesGuardDropDetailTests {
    private let utterances = [
        NotesUtterance(startMs: 0, speaker: "Anna", text: "We should move the release to the second week of the month"),
        NotesUtterance(startMs: 10_000, speaker: "Marek", text: "because the testers need more time for the checks"),
        NotesUtterance(
            startMs: 20_000, speaker: "Anna", text: "The vendor has not answered our questions about the contract yet."),
    ]

    private func refusal(quote: String, text: String, time: Int = 0) -> NotesGuard.Refusal? {
        NotesGuard(utterances: utterances).refusal(
            of: GuardFixtures.point("p1", .summary, quote: quote, text: text, time: time))
    }

    @Test func aChangedWordIsTold() {
        let result = refusal(quote: "we should move the launch to the second week", text: "The release moves.")
        #expect(result == .init(.quoteNotInTranscript, detail: .quoteChangedWord))
    }

    @Test func manyOmittedWordsAreTold() {
        let result = refusal(quote: "we should move week of the month", text: "The release moves.")
        #expect(result == .init(.quoteNotInTranscript, detail: .quoteOmittedWords))
    }

    @Test func aQuoteAcrossASpeakerChangeIsTold() {
        let result = refusal(quote: "of the month because the testers need", text: "The testers need time.")
        #expect(result == .init(.quoteNotInTranscript, detail: .quoteSpeakerChange))
    }

    @Test func aQuoteThatIsNotThereIsAbsent() {
        let result = refusal(quote: "nobody said anything like this at all", text: "Nothing was said.")
        #expect(result == .init(.quoteNotInTranscript, detail: .quoteAbsent))
    }

    @Test func theRuleBehindAnUnsupportedDetailIsTold() {
        let quote = "The vendor has not answered our questions about the contract yet"
        #expect(
            refusal(quote: quote, text: "The vendor answered 12 questions.", time: 20_000)
                == .init(.unsupportedDetail, detail: .unsupportedNumber))
        #expect(
            refusal(quote: quote, text: "The vendor has no answer on Friday.", time: 20_000)
                == .init(.unsupportedDetail, detail: .unsupportedCalendarWord))
        #expect(
            refusal(quote: quote, text: "The vendor and Kowalski have not answered.", time: 20_000)
                == .init(.unsupportedDetail, detail: .unsupportedCapitalised))
        #expect(
            refusal(quote: quote, text: "Silence from the vendor about the contract.", time: 20_000)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func otherReasonsHaveNoDetailAndTheVerdictCountsTheDetails() {
        #expect(refusal(quote: "we should move the release", text: "") == .init(.emptyText))
        let verdict = NotesGuard(utterances: utterances).verifyPoints([
            GuardFixtures.point("p1", .summary, quote: "nobody said anything like this at all", text: "Nothing."),
            GuardFixtures.point(
                "p2", .summary, quote: "The vendor has not answered our questions about the contract yet",
                text: "The vendor answered 12 questions.", time: 20_000),
            GuardFixtures.point("p3", .summary, quote: "we should move the release to the second week", text: "A"),
        ])
        #expect(verdict.reasons[.quoteNotInTranscript] == 1 && verdict.reasons[.unsupportedDetail] == 1)
        #expect(verdict.details == [.quoteAbsent: 1, .unsupportedNumber: 1])
        #expect(verdict.verified.count == 1)
    }
}
