import SwiftUI

/// What the goal page shows: the rail and the choice (default Both).
public nonisolated struct OnboardingGoalState: Equatable, Sendable {
    public var rail: OnboardingStepRailState
    public var selection: OnboardingGoalOption

    public init(rail: OnboardingStepRailState, selection: OnboardingGoalOption = .both) {
        self.rail = rail
        self.selection = selection
    }
}

/// Step 1, "What would you like Lintel to do?" (prototype `onb.goal`): three choices, "You can change this later
/// in Settings.", and one primary button that names the choice ("Set Up Both"). Pure view over a value state;
/// the shell turns a choice into plugin switches.
public struct OnboardingGoalPage: View {
    private let state: OnboardingGoalState
    private let onSelect: (OnboardingGoalOption) -> Void
    private let onPrimary: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    public init(
        _ state: OnboardingGoalState,
        onSelect: @escaping (OnboardingGoalOption) -> Void = { _ in },
        onPrimary: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onSelect = onSelect
        self.onPrimary = onPrimary
    }

    public var body: some View {
        OnboardingWindowFrame(
            rail: state.rail, heading: Self.heading, subheading: Self.subheading,
            primaryTitle: state.selection.primaryTitle, showsBack: false, onPrimary: onPrimary
        ) {
            VStack(spacing: 10) {
                ForEach(OnboardingGoalOption.allCases) { choice in
                    option(choice)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.heading)
        }
    }

    public static var heading: String {
        String(localized: "What would you like Lintel to do?", comment: "Onboarding goal page heading")
    }

    public static var subheading: String {
        String(
            localized: "You can change this later in Settings.", comment: "Onboarding goal page line under the heading")
    }

    private func option(_ choice: OnboardingGoalOption) -> some View {
        let selected = choice == state.selection
        return Button {
            onSelect(choice)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                LintelRing(.idle, mark: choice == .dictation ? .dictation : .meeting, baseSize: 22)
                    .foregroundStyle(LintelBrand.secondaryText)
                    .padding(.top, 1)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(choice.title)
                        .font(textSize.font(.title3, weight: .semibold))
                        .foregroundStyle(LintelBrand.ink)
                    Text(choice.detail)
                        .font(textSize.font(.title3))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18 * textSize.scale))
                    .foregroundStyle(selected ? LintelBrand.accent : LintelBrand.secondaryText)
                    .accessibilityHidden(true)
            }
            .padding(14)
            .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? LintelBrand.accent : LintelBrand.hairline, lineWidth: selected ? 2 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title)
        .accessibilityHint(choice.detail)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
