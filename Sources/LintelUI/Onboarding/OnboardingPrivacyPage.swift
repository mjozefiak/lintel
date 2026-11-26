import SwiftUI

/// What the privacy page shows: the rail and whether the meeting consent sentence belongs (a goal with meetings).
public nonisolated struct OnboardingPrivacyState: Equatable, Sendable {
    public var rail: OnboardingStepRailState
    public var includesMeetingConsent: Bool

    public init(rail: OnboardingStepRailState, includesMeetingConsent: Bool) {
        self.rail = rail
        self.includesMeetingConsent = includesMeetingConsent
    }
}

/// Step 2, "Your words stay on this Mac" (prototype `onb.privacy`): three points, and with meetings one sentence
/// about telling the other people. Nothing to choose; the button is "Next: Allow Access". Pure view.
public struct OnboardingPrivacyPage: View {
    private let state: OnboardingPrivacyState
    private let onBack: () -> Void
    private let onPrimary: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    public init(
        _ state: OnboardingPrivacyState, onBack: @escaping () -> Void = {}, onPrimary: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onBack = onBack
        self.onPrimary = onPrimary
    }

    public static var heading: String {
        String(localized: "Your words stay on this Mac", comment: "Onboarding privacy page heading")
    }

    public static var subheading: String {
        String(localized: "This is how Lintel works, from the first day.", comment: "Onboarding privacy page line")
    }

    /// The three points, with the symbol each one has.
    public static var points: [(symbol: String, text: String)] {
        [
            (
                "lock",
                String(
                    localized: "Recordings, notes and dictations are saved on this Mac, encrypted.",
                    comment: "Onboarding privacy point 1")
            ),
            (
                "shield",
                String(
                    localized:
                        "Nothing is sent anywhere. Later you can choose Claude to write notes; Lintel asks first.",
                    comment: "Onboarding privacy point 2")
            ),
            (
                "checkmark.circle",
                String(localized: "No account and no sign-up.", comment: "Onboarding privacy point 3")
            ),
        ]
    }

    public static var consentSentence: String {
        String(
            localized: "When you record a meeting, tell the other people. Lintel reminds you.",
            comment: "Onboarding privacy page: the consent reminder for meetings")
    }

    public var body: some View {
        OnboardingWindowFrame(
            rail: state.rail, heading: Self.heading, subheading: Self.subheading,
            primaryTitle: OnboardingPrimaryTitles.allowAccess, showsBack: true, onBack: onBack, onPrimary: onPrimary
        ) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(Self.points.enumerated()), id: \.offset) { _, point in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: point.symbol)
                            .foregroundStyle(LintelBrand.secondaryText)
                            .frame(width: 20 * textSize.scale)
                            .accessibilityHidden(true)
                        Text(point.text)
                            .font(textSize.font(.title3))
                            .foregroundStyle(LintelBrand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if state.includesMeetingConsent {
                OnboardingNote(text: Self.consentSentence)
                    .padding(.top, 6)
            }
        }
    }
}
