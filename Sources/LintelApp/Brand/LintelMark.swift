import AppKit
import LintelUI
import SwiftUI

/// The ring of the Lintel mark. The geometry (an outer radius of 112, an inner radius of 66, a 60° cut at -135°, the
/// thinner small cut for 24 pt and below) lives in `LintelUI` since the working ring shares it.
typealias LintelMarkRing = LintelRingShape

/// The Lintel mark: a ring with a cut and a core in the accent colour.
struct LintelMark: View {
    var ring: Color = .primary
    var core: Color = LintelBrand.accent
    var small = false

    var body: some View {
        GeometryReader { proxy in
            let unit = min(proxy.size.width, proxy.size.height) / 256
            ZStack {
                LintelMarkRing(small: small).fill(ring)
                Circle()
                    .fill(core)
                    .frame(width: (small ? 80 : 68) * unit, height: (small ? 80 : 68) * unit)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension LintelMark {
    /// The menu bar glyph: a template image, so the system draws it in the menu bar's colour. The core is
    /// part of the same black shape, separated from the ring by the gap.
    @MainActor
    static func menuBarImage(points: CGFloat = 18) -> NSImage {
        let content = ZStack {
            LintelMarkRing(small: true).fill(.black)
            Circle().fill(.black).frame(width: points * 80 / 256, height: points * 80 / 256)
        }
        .frame(width: points, height: points)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        let image = renderer.nsImage ?? NSImage(size: NSSize(width: points, height: points))
        image.size = NSSize(width: points, height: points)
        image.isTemplate = true
        return image
    }
}
