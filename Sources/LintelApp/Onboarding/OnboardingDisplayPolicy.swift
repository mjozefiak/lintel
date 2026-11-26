import Foundation
import LintelKit

/// Whether this launch shows the first-run onboarding flow (spec `2026-11-24-first-run-onboarding`, step 3.5).
/// Pure: it reads what the settings store holds and answers what to do, and which value to write once; the shell
/// applies the writes and opens the window (step 3.4 wires it in). Nothing here is used by the app yet.
enum OnboardingDisplayPolicy {
    /// The old welcome screen's version: an install that finished it before this flow existed.
    static let legacyFlowVersion = 1
    /// This flow's version: written when it is finished or closed.
    static let currentFlowVersion = 2

    enum Decision: Equatable {
        /// Show the flow.
        case showFlow
        /// Do not show it, and write `flowVersion = 1` once: the install finished the old welcome screen.
        case hideAndPinLegacyFlow
        /// Do not show it, and write nothing.
        case hide
    }

    /// What this launch does. A stored `flowVersion` decides first: any stored value (the old screen's `1`, this
    /// flow's `2`, or a newer build's) never shows the flow and is never rewritten. Without it, an install that
    /// answered the old welcome screen (`app.onboarding.shortcutCompleted` or `app.onboarding.completedSteps`
    /// stored) is pinned to `1`; anything else is a new install and shows the flow. `ranking.sqlite` is
    /// deliberately not consulted: every launch creates it, and a first launch that ended without closing the
    /// window must show the flow again.
    static func decide(settings: any SettingsStore) -> Decision {
        if storedFlowVersion(settings) != nil {
            return .hide
        }
        let answeredOldWelcome =
            settings.value(forKey: SettingsKeys.onboardingShortcutCompleted) != nil
            || settings.value(forKey: SettingsKeys.onboardingCompletedSteps) != nil
        return answeredOldWelcome ? .hideAndPinLegacyFlow : .showFlow
    }

    /// The writes a decision makes: `flowVersion = 1` for `.hideAndPinLegacyFlow`, so the pin happens once, and
    /// nothing for the other decisions.
    static func writes(for decision: Decision) -> [OnboardingSettingWrite] {
        switch decision {
        case .hideAndPinLegacyFlow:
            return [
                OnboardingSettingWrite(
                    key: SettingsKeys.onboardingFlowVersion, value: .integer(legacyFlowVersion))
            ]
        case .showFlow, .hide:
            return []
        }
    }

    /// The write that records that the flow was finished or closed, so it is not forced again. It is `nil` when a
    /// version is already stored: a stored `1` or `2` is never overwritten (an old install reopened with "Show
    /// welcome again" keeps its `1`).
    static func closingWrites(settings: any SettingsStore) -> [OnboardingSettingWrite] {
        guard storedFlowVersion(settings) == nil else { return [] }
        return [
            OnboardingSettingWrite(
                key: SettingsKeys.onboardingFlowVersion, value: .integer(currentFlowVersion))
        ]
    }

    /// The goal the goal page preselects on "Show welcome again" (`app.onboarding.goal`; absent means "Both").
    static func goal(settings: any SettingsStore) -> OnboardingGoalChoice {
        guard case .string(let raw) = settings.value(forKey: SettingsKeys.onboardingGoal) else { return .both }
        return OnboardingGoalChoice(stored: raw)
    }

    /// The write that records the chosen goal.
    static func goalWrite(_ choice: OnboardingGoalChoice) -> OnboardingSettingWrite {
        OnboardingSettingWrite(key: SettingsKeys.onboardingGoal, value: .string(choice.rawValue))
    }

    /// Whether the user hid the setup checklist row (`app.onboarding.checklistHidden`).
    static func checklistHidden(settings: any SettingsStore) -> Bool {
        guard case .bool(let hidden) = settings.value(forKey: SettingsKeys.onboardingChecklistHidden) else {
            return false
        }
        return hidden
    }

    /// `app.onboarding.flowVersion` as an `Int`; a value of another type was not written by this feature and
    /// counts as absent.
    private static func storedFlowVersion(_ settings: any SettingsStore) -> Int? {
        guard case .integer(let version) = settings.value(forKey: SettingsKeys.onboardingFlowVersion) else {
            return nil
        }
        return version
    }
}
