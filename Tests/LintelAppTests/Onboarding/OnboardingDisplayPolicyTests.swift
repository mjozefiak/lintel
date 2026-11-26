import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// When the first-run onboarding flow opens (spec `2026-11-24-first-run-onboarding`, step 3.5): a new install sees
/// it, an install that finished the old welcome screen is pinned once, and a stored version is never rewritten.
@Suite struct OnboardingDisplayPolicyTests {
    @Test func aNewInstallShowsTheFlowAndWritesNothing() {
        let settings = InMemorySettingsStore()
        #expect(OnboardingDisplayPolicy.decide(settings: settings) == .showFlow)
        #expect(OnboardingDisplayPolicy.writes(for: .showFlow).isEmpty)
    }

    /// The two keys the old welcome screen wrote, as a plain value and an array.
    @Test(arguments: [true, false])
    func anInstallThatFinishedTheOldWelcomeIsPinnedOnce(shortcutCompleted: Bool) {
        let key =
            shortcutCompleted
            ? SettingsKeys.onboardingShortcutCompleted : SettingsKeys.onboardingCompletedSteps
        let stored: SettingValue = shortcutCompleted ? .bool(true) : .stringArray(["dictation.setup"])
        let settings = InMemorySettingsStore([key: stored])
        let decision = OnboardingDisplayPolicy.decide(settings: settings)
        #expect(decision == .hideAndPinLegacyFlow)
        #expect(
            OnboardingDisplayPolicy.writes(for: decision) == [
                OnboardingSettingWrite(key: SettingsKeys.onboardingFlowVersion, value: .integer(1))
            ])
    }

    @Test(arguments: [1, 2, 3])
    func aStoredVersionHidesTheFlowAndIsNeverRewritten(_ version: Int) {
        let settings = InMemorySettingsStore([SettingsKeys.onboardingFlowVersion: .integer(version)])
        let decision = OnboardingDisplayPolicy.decide(settings: settings)
        #expect(decision == .hide)
        #expect(OnboardingDisplayPolicy.writes(for: decision).isEmpty)
    }

    @Test func aStoredVersionWinsOverTheOldWelcomeAnswer() {
        let settings = InMemorySettingsStore([
            SettingsKeys.onboardingShortcutCompleted: .bool(true),
            SettingsKeys.onboardingFlowVersion: .integer(2),
        ])
        #expect(OnboardingDisplayPolicy.decide(settings: settings) == .hide)
    }

    @Test func closingRecordsTheFlowOnlyWhenNoVersionIsStored() {
        let fresh = InMemorySettingsStore()
        #expect(
            OnboardingDisplayPolicy.closingWrites(settings: fresh) == [
                OnboardingSettingWrite(key: SettingsKeys.onboardingFlowVersion, value: .integer(2))
            ])
        let pinned = InMemorySettingsStore([SettingsKeys.onboardingFlowVersion: .integer(1)])
        #expect(OnboardingDisplayPolicy.closingWrites(settings: pinned).isEmpty)
    }

    @Test func aFirstLaunchThatEndedWithoutClosingShowsTheFlowAgain() throws {
        // Every launch since v0.1 creates `ranking.sqlite`, so its presence must not make a new install look
        // old: the policy never consults it.
        let root = FileManager.default.temporaryDirectory.appending(path: "onboarding-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: "ranking.sqlite"))

        #expect(OnboardingDisplayPolicy.decide(settings: InMemorySettingsStore()) == .showFlow)
    }

    @Test func theGoalIsRememberedAndReadBack() {
        let settings = InMemorySettingsStore()
        #expect(OnboardingDisplayPolicy.goal(settings: settings) == .both)

        settings.setValue(.string("dictation"), forKey: SettingsKeys.onboardingGoal)
        #expect(OnboardingDisplayPolicy.goal(settings: settings) == .dictation)

        settings.setValue(.string("video"), forKey: SettingsKeys.onboardingGoal)
        #expect(OnboardingDisplayPolicy.goal(settings: settings) == .both)

        #expect(
            OnboardingDisplayPolicy.goalWrite(.meetingNotes)
                == OnboardingSettingWrite(key: SettingsKeys.onboardingGoal, value: .string("meetingNotes")))
    }

    @Test func theChecklistRowIsShownUnlessTheUserHidIt() {
        let settings = InMemorySettingsStore()
        #expect(!OnboardingDisplayPolicy.checklistHidden(settings: settings))

        settings.setValue(.bool(true), forKey: SettingsKeys.onboardingChecklistHidden)
        #expect(OnboardingDisplayPolicy.checklistHidden(settings: settings))
    }
}
