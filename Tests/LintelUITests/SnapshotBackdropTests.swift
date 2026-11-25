#if DEBUG
import AppKit
import Testing

@testable import LintelUI

@MainActor
struct SnapshotBackdropTests {
    @Test("the backdrop fills the shape and leaves the corners transparent")
    func cornersStayTransparent() throws {
        let bounds = NSRect(x: 0, y: 0, width: 120, height: 48)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 96, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        SnapshotBackdropHostingView<EmptyViewForTest>.paintBackdrop(
            in: bitmap, viewBounds: bounds,
            path: SnapshotBackdropHostingView<EmptyViewForTest>.roundedPath(bounds, radius: 24),
            color: .white)
        let corner = try #require(bitmap.colorAt(x: 1, y: 1))
        let centre = try #require(bitmap.colorAt(x: 120, y: 48))
        #expect(corner.alphaComponent == 0)
        #expect(centre.alphaComponent == 1)
    }

    /// A Retina bitmap (`size` in points, twice as many pixels): the graphics context works in points, so the
    /// backdrop must be scaled by `size / bounds`, not by `pixels / bounds` (it used to overshoot the capsule).
    @Test("the backdrop leaves the corners transparent when the bitmap has 2 pixels per point")
    func cornersStayTransparentOnARetinaBitmap() throws {
        let bounds = NSRect(x: 0, y: 0, width: 120, height: 48)
        let bitmap = try #require(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 240, pixelsHigh: 96, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = bounds.size
        SnapshotBackdropHostingView<EmptyViewForTest>.paintBackdrop(
            in: bitmap, viewBounds: bounds,
            path: SnapshotBackdropHostingView<EmptyViewForTest>.roundedPath(bounds, radius: 24),
            color: .white)
        #expect(try #require(bitmap.colorAt(x: 1, y: 1)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: 238, y: 94)).alphaComponent == 0)
        #expect(try #require(bitmap.colorAt(x: 120, y: 48)).alphaComponent == 1)
        // Just inside the straight edge, 2 points from the left: painted.
        #expect(try #require(bitmap.colorAt(x: 6, y: 48)).alphaComponent == 1)
    }
}

import SwiftUI

private typealias EmptyViewForTest = SwiftUI.EmptyView
#endif
