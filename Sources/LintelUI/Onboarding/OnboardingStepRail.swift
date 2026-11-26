import SwiftUI

/// The onboarding window's left rail (prototype `.oside`): the mark and name, the tagline, the steps with the
/// current one marked, and while a speech download runs one line with its progress at the bottom.
///
/// Pure view over `OnboardingStepRailState`: no I/O. Colours only from `LintelBrand`, sizes from `lintelTextSize`.
/// The list is one accessibility container; each step says "Access, Step 3 of 5, current".
public struct OnboardingStepRail: View {
    private let state: OnboardingStepRailState
    @Environment(\.lintelTextSize) private var textSize

    public init(_ state: OnboardingStepRailState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                LintelRing(.idle, mark: .meeting, baseSize: 26)
                    .accessibilityHidden(true)
                Text("Lintel")
                    .font(textSize.font(.title3, weight: .bold))
                    .foregroundStyle(LintelBrand.ink)
            }
            .padding(.horizontal, 4)
            Text(Self.tagline)
                .foregroundStyle(LintelBrand.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
                .padding(.top, 2)
                .padding(.bottom, 22)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(state.steps.enumerated()), id: \.element.id) { index, step in
                    row(index: index, step: step)
                }
            }
            .accessibilityElement(children: .contain)
            Spacer(minLength: 12)
            if let download = state.download {
                downloadLine(download)
            }
        }
        .font(textSize.font(.body))
        .padding(.top, 40)
        .padding(.horizontal, 16)
        .padding(.bottom, 18)
        .frame(width: OnboardingLayout.railWidth)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(LintelBrand.sidebarBackground)
        .overlay(alignment: .trailing) { LintelDivider(axis: .vertical) }
    }

    public static var tagline: String {
        String(localized: "Your words, on this Mac.", comment: "Onboarding rail: the line under the app name")
    }

    private func row(index: Int, step: OnboardingRailStep) -> some View {
        let isCurrent = step.status == .current
        return HStack(spacing: 10) {
            marker(index: index, status: step.status)
            Text(step.title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(step.status == .upcoming ? LintelBrand.secondaryText : LintelBrand.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isCurrent ? LintelBrand.windowSelectionTint : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if isCurrent {
                // The prototype's inset 3 pt bar on the current step.
                UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 8)
                    .fill(LintelBrand.accent)
                    .frame(width: 3)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.spokenLabel(at: index))
    }

    private func marker(index: Int, status: OnboardingRailStep.Status) -> some View {
        let size = 22 * textSize.scale
        return ZStack {
            switch status {
            case .done:
                Circle().fill(LintelBrand.fill)
                Image(systemName: "checkmark")
                    .font(.system(size: 11 * textSize.scale, weight: .bold))
                    .foregroundStyle(LintelBrand.ink)
            case .current:
                Circle().strokeBorder(LintelBrand.accent, lineWidth: 1.5)
                Text("\(index + 1)")
                    .font(textSize.font(.footnote, weight: .semibold))
                    .foregroundStyle(LintelBrand.accentText)
            case .upcoming:
                Circle().strokeBorder(LintelBrand.hairline, lineWidth: 1.5)
                Text("\(index + 1)")
                    .font(textSize.font(.footnote, weight: .semibold))
                    .foregroundStyle(LintelBrand.secondaryText)
            }
        }
        .frame(width: size, height: size)
    }

    private func downloadLine(_ download: OnboardingRailDownload) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(download.text)
                .font(textSize.font(.callout))
                .foregroundStyle(LintelBrand.ink)
                .fixedSize(horizontal: false, vertical: true)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LintelBrand.fill)
                    Capsule().fill(LintelBrand.accent).frame(width: proxy.size.width * download.progress)
                }
            }
            .frame(height: 4)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(download.text)
    }
}
