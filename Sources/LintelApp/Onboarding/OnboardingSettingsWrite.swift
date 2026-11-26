import Foundation
import LintelKit

/// One settings write the first-run onboarding makes, as data: the pure onboarding types return these and the
/// shell applies them through `SettingsStore`, so no decision about the user's settings is hidden in a view or in
/// a side effect (spec `2026-11-24-first-run-onboarding`, step 3.5).
struct OnboardingSettingWrite: Equatable, Sendable {
    let key: String
    let value: SettingValue
}
