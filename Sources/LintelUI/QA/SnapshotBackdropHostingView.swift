#if DEBUG
import AppKit
import SwiftUI

/// DEBUG only (QA, `--qa-hud` with `--qa-snapshot`): a hosting view that is transparent on screen, like the real HUD,
/// and puts an opaque backdrop behind the content only in the bitmap `cacheDisplay` makes. `cacheDisplay` does not
/// draw the glass material, so without it a snapshot would show the labels on nothing. The backdrop is cut to the
/// HUD's own shape, so the corners of the snapshot stay transparent. Not a contract.
public final class SnapshotBackdropHostingView<Content: View>: NSHostingView<Content> {
    /// The shape the HUD is drawn in, in this view's coordinates (a flipped one is fine: the shapes are symmetric).
    public var backdropShape: (NSRect) -> NSBezierPath = { NSBezierPath(rect: $0) }
    public var backdropColor: NSColor = LintelBrand.windowBackgroundColor

    public override func cacheDisplay(in rect: NSRect, to bitmap: NSBitmapImageRep) {
        super.cacheDisplay(in: rect, to: bitmap)
        Self.paintBackdrop(
            in: bitmap, viewBounds: bounds, path: backdropShape(bounds), color: backdropColor)
    }

    /// Fills `path` (view points) behind what the bitmap already holds, so only the area inside the shape gets
    /// the colour and a pixel outside it keeps alpha 0.
    static func paintBackdrop(
        in bitmap: NSBitmapImageRep, viewBounds: NSRect, path: NSBezierPath, color: NSColor
    ) {
        guard viewBounds.width > 0, viewBounds.height > 0,
            let context = NSGraphicsContext(bitmapImageRep: bitmap)
        else { return }
        let scale = CGFloat(bitmap.pixelsWide) / viewBounds.width
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.compositingOperation = .destinationOver
        let transform = NSAffineTransform()
        transform.scale(by: scale)
        let scaled = path.copy() as? NSBezierPath ?? path
        scaled.transform(using: transform as AffineTransform)
        color.setFill()
        scaled.fill()
    }

    /// A capsule or rounded rectangle path for `rect`.
    public static func roundedPath(_ rect: NSRect, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    }
}
#endif
