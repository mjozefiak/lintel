import AppKit
import SwiftUI

/// When a pill expands (spec `2026-11-25-minimal-hud`, "Hover"): 300 ms after the pointer enters it (movement inside
/// the pill does not restart the timer), and 500 ms after the pointer leaves it collapses again. Keyboard focus on a button inside the pill counts as hover
/// and expands at once. The time is injected (`sleep`), so tests drive it with a manual clock.
@MainActor @Observable
public final class PillHoverModel {
    public static let expandDelay: Duration = .milliseconds(300)
    public static let collapseDelay: Duration = .milliseconds(500)

    /// What the pill draws.
    public private(set) var isExpanded = false
    /// The pill's frame in the host's (flipped) coordinates, reported by `PillHoverRoot`; the pointer counts as on
    /// the pill only inside it, never in the transparent rest of the panel.
    public var pillFrame: CGRect = .zero

    @ObservationIgnored public private(set) var pointerInside = false
    @ObservationIgnored public private(set) var keyboardFocus = false
    /// Every change, for the QA spike's log (`PillHoverEvent`); never text.
    @ObservationIgnored public var onEvent: (PillHoverEvent) -> Void = { _ in }

    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var pending: Task<Void, Never>?

    public init(
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.sleep = sleep
    }

    /// The pointer is on the pill (`true`) or left it.
    public func pointer(inside: Bool) {
        guard inside != pointerInside else { return }
        pointerInside = inside
        onEvent(inside ? .pointerEntered : .pointerExited)
        reschedule()
    }

    /// A button inside the pill gained or lost keyboard focus.
    public func keyboardFocus(_ focused: Bool) {
        guard focused != keyboardFocus else { return }
        keyboardFocus = focused
        if focused {
            pending?.cancel()
            pending = nil
            set(expanded: true)
        } else {
            reschedule()
        }
    }

    /// New content, or the panel goes away: collapse at once and forget the pointer (a pill that appears under the
    /// pointer does not expand until the pointer moves).
    public func reset() {
        pending?.cancel()
        pending = nil
        pointerInside = false
        keyboardFocus = false
        set(expanded: false)
    }

    private func reschedule() {
        pending?.cancel()
        pending = nil
        let wanted = pointerInside || keyboardFocus
        guard wanted != isExpanded else { return }
        let delay = wanted ? Self.expandDelay : Self.collapseDelay
        let sleep = self.sleep
        pending = Task { [weak self] in
            do { try await sleep(delay) } catch { return }
            guard !Task.isCancelled else { return }
            self?.set(expanded: wanted)
        }
    }

    private func set(expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
        onEvent(expanded ? .expanded : .collapsed)
    }
}

public nonisolated enum PillHoverEvent: Equatable, Sendable {
    case pointerEntered
    case pointerExited
    case expanded
    case collapsed
}

/// The root of a pill panel: the pill centred in the fixed transparent frame (`PillMetrics.panelSize`), expanding
/// with a 0.2 s spring (instantly under Reduce Motion), reporting its frame to the hover model. Nothing but the pill
/// is drawn, so the rest of the panel stays transparent (and passes clicks through, risk R2).
public struct PillHoverRoot: View {
    private let content: PillContent
    private let hover: PillHoverModel
    private let alignment: Alignment
    private let onAction: (String) -> Void

    @Environment(\.lintelRingMotion) private var motion
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    /// - Parameter alignment: `.center`; a panel at the top of the screen may pin the pill's top edge, one at the
    ///   bottom its bottom edge.
    public init(
        _ content: PillContent, hover: PillHoverModel, alignment: Alignment = .center,
        onAction: @escaping (String) -> Void
    ) {
        self.content = content
        self.hover = hover
        self.alignment = alignment
        self.onAction = onAction
    }

    public var body: some View {
        let reduced = PillMotion.reduces(motion, system: systemReduceMotion)
        LintelPill(
            content, expanded: hover.isExpanded, onAction: onAction,
            onKeyboardFocus: { hover.keyboardFocus($0) }
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: {
            hover.pillFrame = $0
        }
        .frame(width: PillMetrics.panelSize.width, height: PillMetrics.panelSize.height, alignment: alignment)
        .animation(reduced ? nil : .spring(duration: 0.2), value: hover.isExpanded)
    }
}

/// The hosting view of a pill panel. The panels are non-activating and Lintel is usually not the active app, so
/// SwiftUI's `.onHover` is not reliable there; an `NSTrackingArea` with `.activeAlways` is (risk R3). The pointer
/// counts as on the pill only inside `PillHoverModel.pillFrame`.
@MainActor
public final class PillHoverHost<Content: View>: NSHostingView<Content> {
    public let hover: PillHoverModel
    private var trackingArea: NSTrackingArea?

    public init(rootView: Content, hover: PillHoverModel) {
        self.hover = hover
        super.init(rootView: rootView)
    }

    /// A host with its own hover model (no trap: plugin and shared code never traps).
    public required init(rootView: Content) {
        self.hover = PillHoverModel()
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    @MainActor @preconcurrency required init?(coder: NSCoder) {
        nil
    }

    /// The options of the tracking area (a test checks them).
    public static var trackingOptions: NSTrackingArea.Options {
        [.activeAlways, .mouseEnteredAndExited, .mouseMoved, .inVisibleRect]
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: Self.trackingOptions, owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        track(event)
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        track(event)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        hover.pointer(inside: false)
    }

    private func track(_ event: NSEvent) {
        track(at: convert(event.locationInWindow, from: nil))
    }

    /// The pointer at `point` (this view's coordinates).
    func track(at point: CGPoint) {
        hover.pointer(
            inside: Self.isOnPill(point, pillFrame: hover.pillFrame, bounds: bounds, isFlipped: isFlipped))
    }

    /// Whether a pointer at `point` (the view's coordinates) is on the pill. The pill's frame is in SwiftUI's top-left
    /// coordinates; a view that is not flipped measures from the bottom. Before the pill has reported its frame the
    /// whole view counts.
    static func isOnPill(_ point: CGPoint, pillFrame: CGRect, bounds: CGRect, isFlipped: Bool) -> Bool {
        guard !pillFrame.isEmpty else { return bounds.contains(point) }
        let topLeft = isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
        return pillFrame.contains(topLeft)
    }
}
