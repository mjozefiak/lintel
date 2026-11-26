import SwiftUI

/// One row of the main window's sidebar (prototype `.si`): a symbol, a title and, optionally, a count. Selection is the
/// only place Verdigris appears; the count stays in the secondary colour. The row is one button for VoiceOver and
/// reads "title, count". Shared by the shell's default row and the sections' own blocks (the notes collections).
public struct SidebarRow: View {
    private let title: String
    private let symbolName: String
    private let count: Int?
    private let isSelected: Bool
    private let action: () -> Void
    @Environment(\.lintelTextSize) private var textSize

    /// The sidebar's metrics (the Settings sidebar uses the same): row padding 5 × 8, 29 pt at Medium, 7 pt corners.
    public static let rowInset: CGFloat = 8
    public static let rowHeight: CGFloat = 29
    public static let rowCornerRadius: CGFloat = 7

    public init(title: String, symbolName: String, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.symbolName = symbolName
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .font(textSize.font(.body))
                    .foregroundStyle(isSelected ? LintelBrand.accentText : LintelBrand.secondaryText)
                    .frame(width: (16 * textSize.scale).rounded())
                    .accessibilityHidden(true)
                Text(verbatim: title)
                    .font(textSize.font(.body, weight: isSelected ? .semibold : nil))
                    .foregroundStyle(isSelected ? LintelBrand.accentText : LintelBrand.ink)
                    .lineLimit(2)
                Spacer(minLength: 4)
                if let count {
                    Text(verbatim: "\(count)")
                        .font(textSize.font(.callout))
                        .foregroundStyle(LintelBrand.secondaryText)
                        .monospacedDigit()
                }
            }
            .padding(EdgeInsets(top: 5, leading: 8, bottom: 5, trailing: 8))
            .frame(maxWidth: .infinity, minHeight: (Self.rowHeight * textSize.scale).rounded(), alignment: .leading)
            .background(
                isSelected ? LintelBrand.windowSelectionTint : Color.clear,
                in: RoundedRectangle(cornerRadius: Self.rowCornerRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Self.rowInset)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: count.map { "\(title), \($0)" } ?? title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
