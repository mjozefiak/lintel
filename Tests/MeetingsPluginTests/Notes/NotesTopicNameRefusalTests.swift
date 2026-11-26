import Foundation
import Testing

@testable import MeetingsPlugin

/// Why the guard refuses the name of a topic: the reason is an enum, written to the audit, never any text. The
/// same checks once guarded the model's intro paragraph, which the built-in track no longer writes.
@Suite struct NotesTopicNameRefusalTests {
    let guardrail = NotesGuard(utterances: GuardFixtures.transcript())
    let points = GuardFixtures.verified

    @Test(
        "A refused name carries the rule that refused it",
        arguments: [
            ("Budżet marketingowy 50 tysięcy złotych", NotesGuard.TextRefusal.unsupportedNumber),
            ("Budżet marketingowy we wtorek", .unsupportedCalendarWord),
            ("Budżet marketingowy dyrektora Nowaka", .unsupportedCapitalised),
            ("Budżet nie ofert", .negation),
            ("The budget for the next quarter", .languageChanged),
            ("Budżet marketingowy w wysokości czterdziestu tysięcy złotych na przyszły kwartał", .tooManyWords),
            (String(repeating: "x", count: 201), .tooLong),
        ])
    func theRefusalIsReturned(name: String, expected: NotesGuard.TextRefusal) {
        #expect(guardrail.topicNameRefusal(name, points: points) == expected)
    }

    @Test func aNameMadeOfTheWordsOfItsPointsPasses() {
        #expect(guardrail.topicNameRefusal("Budżet na przyszły kwartał", points: points) == nil)
    }

    /// The name is checked against the points of its own topic only, so it cannot borrow a fact from elsewhere.
    @Test func aNameCannotBorrowAFactFromAnotherTopic() {
        #expect(guardrail.topicNameRefusal("Oferta dla klienta", points: [GuardFixtures.topic]) != nil)
        #expect(guardrail.topicNameRefusal("Oferta dla klienta", points: [GuardFixtures.offer]) == nil)
    }

    @Test func aRefusedNameIsCountedInTheAuditAndItsPointsGoToOther() {
        let output = NotesReduceOutput(topics: [.init(name: "Budżet 50 tysięcy", ids: ["p5", "p6"])])
        let other = GuardFixtures.point(
            "p6", .summary, quote: "Zatwierdzamy budżet marketingowy", text: "Zatwierdzono budżet marketingowy.",
            time: 21_000)
        let result = guardrail.auditedVerifyReduce(output, points: [GuardFixtures.topic, other])
        #expect(result.audit.topicNameRefused == 1)
        #expect(result.verdict.topics.map(\.isOther) == [true])
    }
}
