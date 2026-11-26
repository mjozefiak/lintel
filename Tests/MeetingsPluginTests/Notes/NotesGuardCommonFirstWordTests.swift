import Foundation
import Testing

@testable import MeetingsPlugin

/// Rules `g1`, S2: the first word of a summary point is capitalised for being first. It is no invented name when
/// the transcript writes it in lowercase inside a sentence, never capitalised inside one, and it is no word of a
/// speaker's label. Decisions and tasks, numbers, weekdays and names are checked as before.
@Suite struct NotesGuardCommonFirstWordTests {
    private static let quote = "the budget for the campaign is fine"

    private func utterances(extra: String = "our spending is under control this time.", speaker: String = "Marek")
        -> [NotesUtterance]
    {
        [
            NotesUtterance(
                startMs: 0, speaker: "Anna", text: "we looked again and the budget for the campaign is fine."),
            NotesUtterance(startMs: 10_000, speaker: speaker, text: extra),
        ]
    }

    private func refusal(
        _ text: String, kind: NotesPointKind = .summary, utterances: [NotesUtterance]? = nil
    ) -> NotesGuard.Refusal? {
        NotesGuard(utterances: utterances ?? self.utterances()).refusal(
            of: GuardFixtures.point("p1", kind, quote: Self.quote, text: text))
    }

    @Test func aCommonWordAtTheStartPasses() {
        #expect(refusal("Spending on the campaign is fine.") == nil)
    }

    @Test func aCommonWordAtTheStartFailedBeforeOnlyForBeingFirst() {
        let withoutTheWord = utterances(extra: "nothing else to add.")
        #expect(
            refusal("Spending on the campaign is fine.", utterances: withoutTheWord)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func anInventedNameAtTheStartStillFails() {
        #expect(
            refusal("Kowalski finds the campaign budget fine.")
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func aNameThatIsAlsoACommonWordStillFails() {
        let english = utterances(extra: "we asked Grace about the grace period yesterday.")
        #expect(
            refusal("Grace finds the campaign budget fine.", utterances: english)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
        let polish = [
            NotesUtterance(startMs: 0, speaker: "Anna", text: "budżet na kampanię jest w porządku."),
            NotesUtterance(startMs: 10_000, speaker: "Marek", text: "w ogrodzie rośnie róża, a Róża przyjdzie jutro."),
        ]
        #expect(
            NotesGuard(utterances: polish).refusal(
                of: GuardFixtures.point(
                    "p1", .summary, quote: "budżet na kampanię jest w porządku",
                    text: "Róża uważa budżet na kampanię za w porządku."))
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func aWordOfASpeakersLabelStillFails() {
        let labelled = utterances(extra: "the rose garden needs water.", speaker: "Rose Lane")
        #expect(
            refusal("Rose finds the campaign budget fine.", utterances: labelled)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func onlyTheFirstWordOfTheTextIsWaived() {
        #expect(
            refusal("The campaign is fine. Spending is too.")
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func decisionsAndTasksAreCheckedAsBefore() {
        #expect(
            refusal("Spending on the campaign is fine.", kind: .decision)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
        #expect(
            refusal("Spending on the campaign is fine.", kind: .task)
                == .init(.unsupportedDetail, detail: .unsupportedSentenceStart))
    }

    @Test func aNumberOrAWeekdayFromOutsideTheUtteranceStillFails() {
        #expect(
            refusal("Spending on the campaign is fine on Friday.")
                == .init(.unsupportedDetail, detail: .unsupportedCalendarWord))
        #expect(
            refusal("Spending on the campaign is fine at 40 euro.")
                == .init(.unsupportedDetail, detail: .unsupportedNumber))
    }
}
