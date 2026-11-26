import SwiftUI

/// The empty state of a list or a pane (spec `2026-11-24-notes-explorer-main-window`, C13): an outlined ring, one
/// sentence, optionally one line of help and one action. The action is a bordered button, never filled: Record
/// Meeting is the window's only filled button, and links stay neutral (owner decision 4). The ring is decoration; the
/// words carry the meaning, and the group reads as one element for VoiceOver.
public struct EmptyStateView: View {
    private let message: Text
    private let hint: Text?
    private let actionTitle: Text?
    private let action: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    public init(message: Text, hint: Text? = nil, actionTitle: Text? = nil, action: @escaping () -> Void = {}) {
        self.message = message
        self.hint = hint
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 10 * textSize.scale) {
            LintelRing(.idle, mark: .meeting, baseSize: 40)
                .accessibilityHidden(true)
            message
                .font(textSize.font(.callout, weight: .medium))
                .foregroundStyle(LintelBrand.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                hint
                    .font(textSize.font(.callout))
                    .foregroundStyle(LintelBrand.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let actionTitle {
                Button(action: action) { actionTitle }
                    .buttonStyle(LintelSecondaryButtonStyle())
                    .padding(.top, 2 * textSize.scale)
            }
        }
        .padding(.horizontal, 18 * textSize.scale)
        .padding(.vertical, 24 * textSize.scale)
        .frame(maxWidth: 320 * textSize.scale)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}
