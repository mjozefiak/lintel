import Foundation
import LintelKit
import SwiftUI
import Testing

@testable import LintelApp

/// The first-run onboarding's state machine (spec `2026-11-24-first-run-onboarding`, step 3.3): the steps for each
/// goal, the primary buttons, Skip, Back, completion and Escape, as data.
@Suite struct OnboardingFlowTests {
    private static func step(
        _ id: String, title: String, goal: OnboardingGoal? = nil, primaryActionTitle: String? = nil
    ) -> OnboardingStep {
        OnboardingStep(
            id: id,
            title: LocalizedStringResource(stringLiteral: title),
            symbolName: "star",
            goal: goal,
            primaryActionTitle: primaryActionTitle.map { LocalizedStringResource(stringLiteral: $0) }
        ) {
            AnyView(EmptyView())
        }
    }

    /// Dictation and Meetings, each serving its goal, plus a step that serves every goal.
    private static let corePlugins = [
        OnboardingPluginSteps(
            pluginID: "dictation", steps: [step("dictation.setup", title: "Dictation", goal: .dictation)]),
        OnboardingPluginSteps(
            pluginID: "meetings", steps: [step("meetings.setup", title: "Meetings", goal: .meetingNotes)]),
        OnboardingPluginSteps(pluginID: "addon", steps: [step("addon.setup", title: "Add-on")]),
    ]

    private static func title(_ flow: OnboardingFlow) -> String? {
        flow.primaryTitle.map { String(localized: $0) }
    }

    @Test(arguments: [
        (
            OnboardingGoalChoice.both,
            ["goal", "privacy", "access", "dictation.setup", "meetings.setup", "addon.setup"]
        ),
        (.dictation, ["goal", "privacy", "access", "dictation.setup", "addon.setup"]),
        (.meetingNotes, ["goal", "privacy", "access", "meetings.setup", "addon.setup"]),
    ])
    func pagesFollowTheChosenGoal(goal: OnboardingGoalChoice, ids: [String]) {
        let flow = OnboardingFlow(plugins: Self.corePlugins, goal: goal)
        #expect(flow.pages.map(\.id) == ids)
        #expect(flow.current?.id == "goal")
    }

    @Test func theGoalPageChangesTheFollowingStepsAndNothingElseDoes() {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        flow.choose(.dictation)
        #expect(flow.goal == .dictation)
        #expect(flow.pages.map(\.id) == ["goal", "privacy", "access", "dictation.setup", "addon.setup"])

        flow.advance()
        flow.choose(.both)
        #expect(flow.goal == .dictation, "only the goal page may change the goal")
    }

    @Test func thePrimaryButtonNamesTheNextStep() throws {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        #expect(flow.primaryAction == .setGoal(.both))
        #expect(Self.title(flow) == "Set Up Both")

        flow.choose(.meetingNotes)
        #expect(flow.primaryAction == .setGoal(.meetingNotes))
        #expect(Self.title(flow) == "Set Up Meeting Notes")
        flow.choose(.both)

        flow.advance()
        #expect(flow.primaryAction == .allowAccess)
        #expect(Self.title(flow) == "Next: Allow Access")

        flow.advance()
        #expect(flow.primaryAction == .next("dictation.setup"))
        #expect(Self.title(flow) == "Next: Dictation")

        flow.advance()
        #expect(flow.primaryAction == .next("meetings.setup"))
        #expect(Self.title(flow) == "Next: Meetings")

        flow.advance()
        #expect(flow.primaryAction == .next("addon.setup"))
        #expect(Self.title(flow) == "Next: Add-on")

        flow.advance()
        #expect(flow.primaryAction == .openLintel)
        #expect(Self.title(flow) == "Open Lintel")
    }

    @Test func aStepThatDeclaresItsButtonKeepsIt() {
        let plugins = [
            OnboardingPluginSteps(
                pluginID: "dictation",
                steps: [
                    Self.step(
                        "dictation.setup", title: "Dictation", goal: .dictation, primaryActionTitle: "Try It Now")
                ])
        ]
        var flow = OnboardingFlow(plugins: plugins, goal: .dictation)
        flow.advance()
        flow.advance()
        flow.advance()
        #expect(flow.current?.id == "dictation.setup")
        #expect(flow.primaryAction == .stepDeclared)
        #expect(Self.title(flow) == "Try It Now")
    }

    @Test func withoutPluginStepsTheAccessPageFinishesTheFlow() {
        var flow = OnboardingFlow()
        #expect(flow.pages.map(\.id) == ["goal", "privacy", "access"])
        flow.advance()
        flow.advance()
        #expect(flow.primaryAction == .openLintel)

        flow.advance()
        #expect(flow.isComplete)
        #expect(flow.current == nil)
        #expect(flow.primaryAction == nil)
        #expect(flow.primaryTitle == nil)
    }

    @Test func continueRecordsEveryPageAndFinishesTheFlow() {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        while flow.current != nil {
            flow.advance()
        }
        #expect(flow.isComplete)
        #expect(
            flow.outcomes == [
                "goal": .finished,
                "privacy": .finished,
                "access": .finished,
                "dictation.setup": .finished,
                "meetings.setup": .finished,
                "addon.setup": .finished,
            ])
        flow.advance()
        #expect(flow.isComplete, "advancing after the last page changes nothing")
    }

    @Test func skipIsOfferedOnlyOnAPluginStepAndRecordsIt() {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        #expect(flow.current?.id == "goal")
        #expect(!flow.showsSkip)

        flow.advance()
        #expect(flow.current?.id == "privacy")
        #expect(!flow.showsSkip)

        flow.advance()
        #expect(flow.current?.id == "access")
        #expect(!flow.showsSkip)
        var refused = flow
        refused.skip()
        #expect(refused.index == flow.index)
        #expect(refused.outcomes["access"] == nil)

        flow.advance()
        #expect(flow.current?.id == "dictation.setup")
        #expect(flow.showsSkip)
        flow.skip()
        #expect(flow.outcomes["dictation.setup"] == .skipped)
        #expect(flow.current?.id == "meetings.setup")
    }

    @Test func backGoesOnePageBackAndStopsAtTheGoalPage() {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        flow.back()
        #expect(flow.current?.id == "goal")

        flow.advance()
        flow.advance()
        #expect(flow.current?.id == "access")
        flow.back()
        #expect(flow.current?.id == "privacy")
    }

    @Test func escapeAsksBeforeClosingOnlyWhileADownloadRuns() {
        var flow = OnboardingFlow()
        #expect(flow.escapeAction == .closeWindow)
        flow.isDownloading = true
        #expect(flow.escapeAction == .askToClose)
        flow.isDownloading = false
        #expect(flow.escapeAction == .closeWindow)
    }

    /// C10 (spec Resolved assumption 5): Continue is never greyed out, on any page, for any goal, downloading or not.
    @Test func thePrimaryButtonIsNeverDisabled() {
        for goal in OnboardingGoalChoice.allCases {
            for downloading in [false, true] {
                var flow = OnboardingFlow(plugins: Self.corePlugins, goal: goal)
                flow.isDownloading = downloading
                while let page = flow.current {
                    #expect(flow.isPrimaryEnabled, "\(page.id) for \(goal), downloading: \(downloading)")
                    flow.advance()
                }
            }
        }
    }

    @Test(arguments: [
        (OnboardingGoalChoice.both, [String]()),
        (.dictation, ["plugins.meetings.enabled"]),
        (.meetingNotes, ["plugins.dictation.enabled"]),
    ])
    func leavingTheGoalPageSwitchesOffOnlyTheOtherCorePlugin(
        choice: OnboardingGoalChoice, expectedKeys: [String]
    ) {
        let writes = OnboardingFlow.switchWrites(for: choice, plugins: Self.corePlugins)
        #expect(writes.map(\.key) == expectedKeys)
        #expect(writes.allSatisfy { $0.value == .bool(false) })
    }

    @Test func aPluginWithoutStepsOrWithASharedStepIsNeverSwitchedOff() {
        let plugins = [
            OnboardingPluginSteps(pluginID: "quiet", steps: []),
            OnboardingPluginSteps(pluginID: "shared", steps: [Self.step("shared.setup", title: "Shared")]),
            OnboardingPluginSteps(
                pluginID: "mixed",
                steps: [
                    Self.step("mixed.a", title: "A", goal: .dictation),
                    Self.step("mixed.b", title: "B", goal: .meetingNotes),
                ]),
        ]
        #expect(OnboardingFlow.switchWrites(for: .dictation, plugins: plugins).isEmpty)
        #expect(OnboardingFlow.switchWrites(for: .meetingNotes, plugins: plugins).isEmpty)
    }

    @Test func theFlowWritesTheSwitchesOfTheGoalItHolds() {
        var flow = OnboardingFlow(plugins: Self.corePlugins)
        #expect(flow.goalWrites.isEmpty)
        flow.choose(.dictation)
        #expect(flow.goalWrites.map(\.key) == ["plugins.meetings.enabled"])
    }

    @Test func aStoredGoalOfAnUnknownValueReadsAsBoth() {
        #expect(OnboardingGoalChoice(stored: nil) == .both)
        #expect(OnboardingGoalChoice(stored: "both") == .both)
        #expect(OnboardingGoalChoice(stored: "dictation") == .dictation)
        #expect(OnboardingGoalChoice(stored: "meetingNotes") == .meetingNotes)
        #expect(OnboardingGoalChoice(stored: "video") == .both)
    }
}
