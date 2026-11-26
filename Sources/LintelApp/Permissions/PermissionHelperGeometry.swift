import CoreGraphics

/// Where the floating permission helper sits, as pure geometry (spec 2026-11-24, "Floating helper panel").
///
/// Two coordinate spaces meet here: `WindowSample.bounds` and the display frames from `CGDisplayBounds` have their
/// origin at the top left of the primary display and grow downwards, `NSWindow` frames have it at the bottom left
/// and grow upwards. Everything below works in the first space; `flipped` converts a rectangle between the two.
nonisolated enum PermissionHelperGeometry {
    /// The space between the panel and the window it sits beside.
    static let gap: CGFloat = 8
    /// The menu bar's share of the top of a display: the panel never goes under it.
    static let menuBarHeight: CGFloat = 28
    /// The margin from the corner of the display when there is no window to sit beside.
    static let cornerMargin: CGFloat = 24

    /// `rect` in the other vertical convention. `primaryHeight` is the height of the primary display. It is its
    /// own inverse: top left to bottom left and back.
    static func flipped(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// The frame for a panel of `size` at the edge of `anchor` (the System Settings window, or Lintel's own window):
    /// to its right when that fits on the display it is on, else to its left, else inside it at the right edge.
    /// Vertically centred on the anchor and kept on the display below the menu bar.
    static func frame(size: CGSize, beside anchor: CGRect, displays: [CGRect]) -> CGRect {
        guard let region = usableRegion(for: anchor, displays: displays) else {
            return CGRect(
                origin: CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2), size: size)
        }
        let y = clamp(anchor.midY - size.height / 2, lower: region.minY, upper: region.maxY - size.height)
        let right = anchor.maxX + gap
        let left = anchor.minX - gap - size.width
        let x: CGFloat
        if right + size.width <= region.maxX {
            x = right
        } else if left >= region.minX {
            x = left
        } else {
            x = clamp(anchor.maxX - size.width - gap, lower: region.minX, upper: region.maxX - size.width)
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// The frame when Lintel has no window either: the bottom right corner of the first display.
    static func cornerFrame(size: CGSize, displays: [CGRect]) -> CGRect {
        guard let display = displays.first else { return CGRect(origin: .zero, size: size) }
        return CGRect(
            x: display.maxX - size.width - cornerMargin, y: display.maxY - size.height - cornerMargin,
            width: size.width, height: size.height)
    }

    /// The display `anchor` mostly lies on, without the menu bar; the first display when it lies on none.
    private static func usableRegion(for anchor: CGRect, displays: [CGRect]) -> CGRect? {
        let best =
            displays.max { overlap($0, anchor) < overlap($1, anchor) }.flatMap { overlap($0, anchor) > 0 ? $0 : nil }
            ?? displays.first
        guard let display = best else { return nil }
        return CGRect(
            x: display.minX, y: display.minY + menuBarHeight, width: display.width,
            height: max(0, display.height - menuBarHeight))
    }

    private static func overlap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let i = a.intersection(b)
        return i.isNull ? 0 : i.width * i.height
    }

    /// `value` between the bounds; a range too small for the panel pins it to `lower`.
    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        upper < lower ? lower : min(max(value, lower), upper)
    }
}

/// How the panel appears: it slides in from where the user pressed Allow, or fades when Reduce Motion is on.
nonisolated enum PermissionHelperMotion: Equatable {
    /// From this frame (AppKit coordinates) to the panel's place.
    case slide(from: CGRect)
    case fade

    /// Reduce Motion, or no known starting place, means a fade.
    static func choose(reduceMotion: Bool, origin: CGRect?) -> PermissionHelperMotion {
        guard !reduceMotion, let origin else { return .fade }
        return .slide(from: origin)
    }
}
