import AppKit
import SwiftUI

extension EnvironmentValues {
    /// Increase Contrast for every `LintelPill` below: `nil` follows the system (`colorSchemeContrast`, which SwiftUI
    /// does not let a view set); the design gallery sets `true` to draw the bordered look.
    @Entry public var lintelIncreasedContrast: Bool? = nil
}

/// The HUD pill (spec `2026-11-25-minimal-hud`): a glass capsule with one line at most, drawn from a `PillContent`.
/// It hugs its content up to the width limit of the text size (`PillMetrics.maxWidth`) and never wraps. The ring
/// glyphs are `LintelRing`; colours are `LintelBrand` tokens only. The pill is one accessibility element whose
/// label says everything and whose actions are every button, hover-only ones included.
///
/// Expanding is the host's decision (`PillHoverModel`, `PillHoverHost`); the pill only draws `expanded`.
public struct LintelPill: View {
    private let content: PillContent
    private let expanded: Bool
    private let onAction: (String) -> Void
    private let onKeyboardFocus: (Bool) -> Void

    @Environment(\.lintelTextSize) private var textSize
    @Environment(\.lintelRingMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.colorSchemeContrast) private var systemContrast
    @Environment(\.lintelIncreasedContrast) private var contrastOverride
    @FocusState private var focusedControl: String?

    /// - Parameters:
    ///   - expanded: the hover state: hover content, the hover-only ✕ and the wider width limit.
    ///   - onAction: called with the `id` of the pressed button (or of the accessibility action).
    ///   - onKeyboardFocus: a button inside the pill gained (`true`) or lost keyboard focus; the host treats focus
    ///     as hover.
    public init(
        _ content: PillContent, expanded: Bool = false, onAction: @escaping (String) -> Void = { _ in },
        onKeyboardFocus: @escaping (Bool) -> Void = { _ in }
    ) {
        self.content = content
        self.expanded = expanded
        self.onAction = onAction
        self.onKeyboardFocus = onKeyboardFocus
    }

    private var increasedContrast: Bool { contrastOverride ?? (systemContrast == .increased) }
    private var reduced: Bool { PillMotion.reduces(motion, system: systemReduceMotion) }
    private var showsHover: Bool { expanded && content.hasHoverContent }

    public var body: some View {
        let height = PillMetrics.height(textSize)
        let circle = content.isCircle(expanded: expanded)
        let glyph = PillMetrics.glyph(textSize)
        PillWidthLimit(maxWidth: PillMetrics.maxWidth(textSize, expanded: showsHover)) {
            HStack(spacing: PillMetrics.spacing) {
                PillGlyphView(glyph: content.glyph, badge: content.badge)
                ForEach(Array(content.live.enumerated()), id: \.offset) { _, live in
                    liveView(live)
                }
                if let lineGlyph = content.lineGlyph {
                    PillGlyphView(glyph: lineGlyph, badge: false)
                }
                if let text = content.text {
                    Text(verbatim: text)
                        .font(font)
                        .foregroundStyle(LintelBrand.ink)
                        .lineLimit(1)
                        .truncationMode(content.truncation == .middle ? .middle : .tail)
                        .layoutPriority(1)
                }
                if let action = content.action { button(action) }
                if showsHover { hoverContent }
                if let stop = content.stop { button(stop) }
                if content.showsClose(expanded: expanded), let close = content.close { closeButton(close) }
            }
            .padding(.leading, circle ? (height - glyph) / 2 : PillMetrics.leadingPadding)
            .padding(.trailing, circle ? (height - glyph) / 2 : PillMetrics.trailingPadding)
            .frame(height: height)
            .glassEffect(.regular, in: .capsule)
            .overlay {
                if increasedContrast {
                    Capsule().strokeBorder(LintelBrand.ink.opacity(0.6), lineWidth: 1)
                }
            }
        }
        .environment(\.lintelRingMotion, reduced ? .reduced : motion)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: content.accessibilityLabel))
        .accessibilityActions {
            ForEach(content.accessibilityActions) { action in
                Button(action.name) { onAction(action.id) }
            }
        }
        .onChange(of: focusedControl) { _, focused in onKeyboardFocus(focused != nil) }
    }

    private var font: Font { .system(size: PillMetrics.fontSize(textSize), weight: .medium) }

    @ViewBuilder private func liveView(_ live: PillLive) -> some View {
        switch live {
        case .wave(let level):
            PillWave(level: level, scale: PillMetrics.scale(textSize), reduced: reduced, animates: !reduced && motion != .frozen)
        case .clock(let time, let amber):
            Text(verbatim: time)
                .font(font.monospacedDigit())
                .foregroundStyle(amber ? LintelBrand.statusAttention : LintelBrand.ink)
                .lineLimit(1)
                .fixedSize()
        }
    }

    @ViewBuilder private var hoverContent: some View {
        if let hoverText = content.hoverText {
            Text(verbatim: hoverText)
                .font(font.monospacedDigit())
                .foregroundStyle(LintelBrand.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        ForEach(Array(content.hoverLevels.enumerated()), id: \.offset) { _, level in
            PillLevelView(level: level, font: font, scale: PillMetrics.scale(textSize))
        }
        ForEach(content.hoverActions) { action in button(action) }
    }

    private func button(_ action: PillAction) -> some View {
        Button {
            onAction(action.id)
        } label: {
            PillButtonLabel(action: action, font: font, control: PillMetrics.control(textSize))
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: action.id)
        .fixedSize()
    }

    private func closeButton(_ close: PillClose) -> some View {
        let control = PillMetrics.control(textSize)
        return Button {
            onAction(close.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: control * 0.45, weight: .semibold))
                .foregroundStyle(LintelBrand.secondaryText)
                .frame(width: control, height: control)
                .background(LintelBrand.fill, in: Circle())
                // The hit area is 24 pt at M, a little larger than the 22 pt circle.
                .frame(width: control + 2, height: control + 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($focusedControl, equals: close.id)
    }
}

/// Proposes at most `maxWidth` to its content and takes the content's size, so the pill hugs a short line and
/// shortens a long one instead of growing past the limit (a plain `.frame(maxWidth:)` lets an ideal-size child
/// overflow).
struct PillWidthLimit: Layout {
    var maxWidth: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let width = min(proposal.width ?? .infinity, maxWidth)
        let ideal = child.sizeThatFits(ProposedViewSize(width: nil, height: proposal.height))
        if ideal.width <= width { return ideal }
        return child.sizeThatFits(ProposedViewSize(width: width, height: proposal.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}

/// The leading glyph: the ring, or a symbol in its status colour, at the ring's size.
struct PillGlyphView: View {
    let glyph: PillGlyph
    let badge: Bool
    @Environment(\.lintelTextSize) private var textSize

    var body: some View {
        let points = PillMetrics.glyph(textSize)
        if let ring = glyph.ring(badge: badge) {
            // The pill's label says it all; the ring adds no element of its own.
            LintelRing(ring.state, mark: ring.mark, baseSize: 16).accessibilityHidden(true)
        } else {
            Image(systemName: symbol)
                .font(.system(size: points * 0.85, weight: .semibold))
                .foregroundStyle(colour)
                .frame(width: points, height: points)
                .accessibilityHidden(true)
        }
    }

    private var symbol: String {
        switch glyph {
        case .attention, .error: "exclamationmark.triangle.fill"
        case .microphone: "mic.slash.fill"
        case .done: "checkmark"
        case .person: "person.fill"
        case .live, .working: "circle"
        }
    }

    private var colour: Color {
        switch glyph {
        case .attention, .microphone: LintelBrand.statusAttention
        case .error: LintelBrand.statusError
        case .done: LintelBrand.accent
        case .person, .live, .working: LintelBrand.ink
        }
    }
}

/// The voice wave: seven bars following the level, tallest in the middle. Under Reduce Motion the bars stay flat at
/// the current level and nothing animates.
struct PillWave: View {
    let level: Double
    let scale: CGFloat
    let reduced: Bool
    let animates: Bool

    static let profile: [CGFloat] = [0.35, 0.6, 0.85, 1, 0.85, 0.6, 0.35]
    static let barWidth: CGFloat = 3
    static let barSpacing: CGFloat = 3.5
    static let maxHeight: CGFloat = 16

    static func height(level: Double, profile: CGFloat, reduced: Bool) -> CGFloat {
        let clamped = CGFloat(min(1, max(0, level.isFinite ? level : 0)))
        return 3 + 13 * clamped * (reduced ? 0.6 : profile)
    }

    var body: some View {
        HStack(spacing: Self.barSpacing * scale) {
            ForEach(0..<Self.profile.count, id: \.self) { index in
                Capsule()
                    .fill(LintelBrand.accent)
                    .frame(
                        width: Self.barWidth * scale,
                        height: Self.height(level: level, profile: Self.profile[index], reduced: reduced) * scale)
            }
        }
        .frame(height: Self.maxHeight * scale)
        .animation(animates ? .easeOut(duration: 0.08) : nil, value: level)
        .accessibilityHidden(true)
    }
}

/// A hover meter: its name and a short bar (OD-5, OD-12).
struct PillLevelView: View {
    let level: PillLevel
    let font: Font
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 4 * scale) {
            Text(verbatim: level.name)
                .font(font)
                .foregroundStyle(LintelBrand.secondaryText)
                .lineLimit(1)
                .fixedSize()
            Capsule()
                .fill(LintelBrand.fill)
                .frame(width: 22 * scale, height: 4 * scale)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(LintelBrand.accent)
                        .frame(width: 22 * scale * CGFloat(min(1, max(0, level.level))), height: 4 * scale)
                }
        }
        .accessibilityHidden(true)
    }
}

/// The look of a pill button.
struct PillButtonLabel: View {
    let action: PillAction
    let font: Font
    let control: CGFloat

    var body: some View {
        switch action.style {
        case .stop:
            RoundedRectangle(cornerRadius: control * 0.08)
                .fill(LintelBrand.ink)
                .frame(width: control * 0.36, height: control * 0.36)
                .frame(width: control, height: control)
                .background(LintelBrand.fill, in: Circle())
                .contentShape(Circle())
        case .link:
            Text(verbatim: action.title)
                .font(font)
                .foregroundStyle(LintelBrand.accentText)
                .lineLimit(1)
        case .button, .primary:
            Text(verbatim: action.title)
                .font(font)
                .foregroundStyle(action.style == .primary ? LintelBrand.onAccent : LintelBrand.ink)
                .lineLimit(1)
                .padding(.horizontal, control * 0.45)
                .frame(height: control)
                .background(action.style == .primary ? LintelBrand.accent : LintelBrand.fill, in: Capsule())
                .contentShape(Capsule())
        }
    }
}
