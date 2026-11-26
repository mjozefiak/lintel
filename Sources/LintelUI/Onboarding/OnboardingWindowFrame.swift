import SwiftUI

/// The frame every onboarding page shares (prototype `.onbw`): the step rail on the left; on the right the step
/// label, the heading, one line under it, the page's content, and below a hairline the footer with Back and the
/// one primary button. The primary button is never disabled (C10) and names its result (owner decision 5).
///
/// Pure view: no I/O. The window is 820 x 580 whatever the text size, so the body scrolls only when a page
/// holds more than fits (nothing in the gallery does, which is what the pictures check).
public struct OnboardingWindowFrame<Content: View>: View {
    private let rail: OnboardingStepRailState
    private let heading: String
    private let subheading: String?
    private let primaryTitle: String
    private let showsBack: Bool
    private let onBack: () -> Void
    private let onPrimary: () -> Void
    private let content: Content
    @Environment(\.lintelTextSize) private var textSize

    public init(
        rail: OnboardingStepRailState,
        heading: String,
        subheading: String?,
        primaryTitle: String,
        showsBack: Bool,
        onBack: @escaping () -> Void = {},
        onPrimary: @escaping () -> Void = {},
        @ViewBuilder content: () -> Content
    ) {
        self.rail = rail
        self.heading = heading
        self.subheading = subheading
        self.primaryTitle = primaryTitle
        self.showsBack = showsBack
        self.onBack = onBack
        self.onPrimary = onPrimary
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: 0) {
            OnboardingStepRail(rail)
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let label = rail.stepLabel {
                            Text(label)
                                .font(textSize.font(.callout))
                                .foregroundStyle(LintelBrand.secondaryText)
                        }
                        Text(heading)
                            .font(textSize.font(.title1, weight: .bold))
                            .foregroundStyle(LintelBrand.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                            .padding(.top, 4)
                            .padding(.bottom, 6)
                        if let subheading {
                            Text(subheading)
                                .font(textSize.font(.title3))
                                .foregroundStyle(LintelBrand.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 16)
                        }
                        content
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, OnboardingLayout.bodyInset)
                    .padding(.top, OnboardingLayout.bodyTopInset)
                    .padding(.bottom, 12)
                }
                .scrollIndicators(.never)
                LintelDivider()
                footer
            }
        }
        .font(textSize.font(.body))
        .frame(width: OnboardingLayout.windowWidth, height: OnboardingLayout.windowHeight)
        .background(LintelBrand.windowBackground)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if showsBack {
                Button(action: onBack) { Text(Self.backTitle).padding(.horizontal, 4).padding(.vertical, 2) }
                    .buttonStyle(LintelSecondaryButtonStyle())
            }
            Spacer(minLength: 0)
            Button(action: onPrimary) { Text(primaryTitle).padding(.horizontal, 6).padding(.vertical, 2) }
                .buttonStyle(LintelPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, OnboardingLayout.footerHorizontalPadding)
        .padding(.vertical, OnboardingLayout.footerVerticalPadding)
    }

    public nonisolated static var backTitle: String {
        String(localized: "Back", comment: "Onboarding footer button that goes to the step before")
    }
}

/// A grouped card in the warm neutrals (prototype `.group`): the rows of a page one under the other, a hairline
/// between them.
struct OnboardingGroup<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) { content }
            .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: OnboardingLayout.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OnboardingLayout.cornerRadius)
                    .strokeBorder(LintelBrand.hairline, lineWidth: 1))
    }
}

/// The side note under a page's content (prototype `.note-ln`): an info mark and one line in `secondaryText`.
struct OnboardingNote: View {
    let text: String
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle")
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(textSize.font(.callout))
        .foregroundStyle(LintelBrand.secondaryText)
        .padding(.top, 12)
    }
}
