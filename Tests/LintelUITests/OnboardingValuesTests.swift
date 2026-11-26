import Foundation
import Testing

@testable import LintelUI

/// The onboarding pages' value states (spec `2026-11-24-first-run-onboarding`, step 3.2). The views take these
/// plain structs, never the flow types of the shell, so the rules that live in them are tested here. The runner has
/// no compiled string catalog, so the words below are the English source strings.
@Suite struct OnboardingValuesTests {
    private static let titles = ["Your goal", "Privacy", "Access", "Try dictation", "First meeting"]

    @Test func theRailMarksOneCurrentStepAndTheOnesBeforeItDone() {
        let rail = OnboardingStepRailState(titles: Self.titles, currentIndex: 2)
        #expect(rail.steps.map(\.status) == [.done, .done, .current, .upcoming, .upcoming])
        #expect(rail.currentIndex == 2)
        #expect(rail.steps.map(\.title) == Self.titles)
        #expect(Set(rail.steps.map(\.id)).count == 5)
    }

    @Test func theStepLabelIsOneBased() {
        #expect(OnboardingStepRailState(titles: Self.titles, currentIndex: 2).stepLabel == "Step 3 of 5")
        #expect(OnboardingStepRailState(titles: Self.titles, currentIndex: 0).stepLabel == "Step 1 of 5")
        #expect(
            OnboardingStepRailState(titles: Array(Self.titles.prefix(4)), currentIndex: 3).stepLabel == "Step 4 of 4")
    }

    @Test func aRailWithNoCurrentStepHasNoLabel() {
        let rail = OnboardingStepRailState(titles: Self.titles, currentIndex: 9)
        #expect(rail.currentIndex == nil)
        #expect(rail.stepLabel == nil)
    }

    @Test func eachStepIsSpokenWithItsPositionAndState() {
        let rail = OnboardingStepRailState(titles: Self.titles, currentIndex: 2)
        #expect(rail.spokenLabel(at: 2) == "Access, Step 3 of 5, current")
        #expect(rail.spokenLabel(at: 0) == "Your goal, Step 1 of 5, done")
        #expect(rail.spokenLabel(at: 4) == "First meeting, Step 5 of 5, not yet")
        #expect(rail.spokenLabel(at: 5) == "")
        #expect(rail.spokenLabel(at: -1) == "")
    }

    @Test func theDownloadLineShowsAWholePercent() {
        #expect(OnboardingRailDownload.dictation(progress: 0.4).text == "Getting dictation ready · 40 %")
        #expect(OnboardingRailDownload.dictation(progress: 0.404).percent == 40)
        #expect(OnboardingRailDownload.dictation(progress: 0.405).percent == 41)
    }

    @Test func theDownloadProgressStaysBetweenZeroAndOne() {
        #expect(OnboardingRailDownload(title: "x", progress: -0.5).progress == 0)
        #expect(OnboardingRailDownload(title: "x", progress: 7).progress == 1)
        #expect(OnboardingRailDownload(title: "x", progress: 7).percent == 100)
    }

    @Test func eachGoalNamesItsButton() {
        #expect(OnboardingGoalChoice.both.primaryTitle == "Set Up Both")
        #expect(OnboardingGoalChoice.dictation.primaryTitle == "Set Up Dictation")
        #expect(OnboardingGoalChoice.meetingNotes.primaryTitle == "Set Up Meeting Notes")
        #expect(Set(OnboardingGoalChoice.allCases.map(\.primaryTitle)).count == 3)
    }

    @Test func theGoalChoicesAreTheThreeOfTheSpecWithBothFirstChosenByDefault() {
        #expect(OnboardingGoalChoice.allCases == [.dictation, .meetingNotes, .both])
        #expect(OnboardingGoalChoice.allCases.map(\.rawValue) == ["dictation", "meetingNotes", "both"])
        let state = OnboardingGoalState(rail: OnboardingStepRailState(titles: Self.titles, currentIndex: 0))
        #expect(state.selection == .both)
        #expect(OnboardingGoalChoice.dictation.title == "Type what I say")
        #expect(OnboardingGoalChoice.meetingNotes.title == "Write my meeting notes")
        #expect(OnboardingGoalChoice.both.title == "Both")
    }

    @Test func theNextButtonsNameTheStepThatComesNext() {
        #expect(OnboardingPrimaryTitles.allowAccess == "Next: Allow Access")
        #expect(OnboardingPrimaryTitles.tryDictation == "Next: Try Dictation")
        #expect(OnboardingPrimaryTitles.firstMeeting == "Next: First Meeting")
        #expect(OnboardingPrimaryTitles.openLintel == "Open Lintel")
    }

    @Test func thePermissionRowsKeepTheirIdentityAndTheStateTheyAreGiven() {
        let mic = OnboardingAccessRow.microphone(.allowed)
        let type = OnboardingAccessRow.typeIntoApps(.needsOK)
        let call = OnboardingAccessRow.callAudio(.notNeededNow)
        #expect([mic.id, type.id, call.id] == ["microphone", "accessibility", "system-audio"])
        #expect([mic.state, type.state, call.state] == [.allowed, .needsOK, .notNeededNow])
        #expect(mic.title == "Microphone")
        #expect(type.title == "Type into other apps")
        #expect(call.title == "Hear other people in a call")
        #expect(type.reason == "So your words appear where your cursor is.")
        #expect(call.reason == "So notes include what the others say.")
    }

    @Test func allAllowedIgnoresARowThatIsNotNeededAndNeedsAtLeastOneRow() {
        let rail = OnboardingStepRailState(titles: Self.titles, currentIndex: 2)
        func state(_ rows: [OnboardingAccessRow]) -> OnboardingAccessState {
            OnboardingAccessState(rail: rail, rows: rows, primaryTitle: "Next")
        }
        #expect(state([.microphone(.allowed), .typeIntoApps(.allowed)]).allAllowed)
        #expect(state([.microphone(.allowed), .callAudio(.notNeededNow)]).allAllowed)
        #expect(!state([.microphone(.allowed), .typeIntoApps(.needsOK)]).allAllowed)
        #expect(!state([.microphone(.allowed), .callAudio(.checking)]).allAllowed)
        #expect(!state([.microphone(.allowed), .callAudio(.checkFailed)]).allAllowed)
        #expect(!state([.callAudio(.notNeededNow)]).allAllowed)
        #expect(!state([]).allAllowed)
    }

    @Test func theMoveStateIsOffByDefault() {
        let rail = OnboardingStepRailState(titles: Self.titles, currentIndex: 2)
        #expect(!OnboardingAccessState(rail: rail, rows: [], primaryTitle: "Next").needsMoveToApplications)
    }
}
