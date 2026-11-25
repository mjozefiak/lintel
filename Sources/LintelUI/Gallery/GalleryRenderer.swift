#if DEBUG
import AppKit
import SwiftUI

/// DEBUG only: draws a gallery state in a variant into a bitmap with the real views, through an invisible
/// `NSWindow` and `NSHostingView` and `cacheDisplay` (spec `2026-11-23-swiftui-design-gallery`). `ImageRenderer` is not
/// used: it does not draw AppKit-backed controls (a grouped `Form`, `Toggle`, `TextField`).
///
/// Language is an axis of the PROCESS, not of the view: almost every text is `String(localized:)` without a bundle
/// or locale, which reads the process's languages. A variant in another language fails with
/// `GalleryError.languageMismatch` instead of drawing a picture with half of the translations.
@MainActor public enum GalleryRenderer {
    /// Bumped when the way pictures are made changes (goes into the fingerprint).
    public static let version = 1
    /// Every bitmap is made at this scale, whatever the display of the machine says.
    public static let scale: CGFloat = 2
    /// A render that has not settled by then is taken as it is (and an empty one is an error).
    static let settleLimit: Duration = .seconds(2)

    /// `en` or `pl`: the language the bundle of this process is localized to.
    public static var processLanguage: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "en"
        return String(preferred.lowercased().prefix(2))
    }

    public static func render(_ state: GalleryState, _ variant: GalleryVariant) async throws -> NSBitmapImageRep {
        let process = processLanguage
        guard variant.language == process else {
            throw GalleryError.languageMismatch(state: state.id, variant: variant.name, process: process)
        }
        let appearance = NSAppearance(named: variant.appearance.name)
        let root = GalleryRoot(content: state.make(), presentation: state.presentation, variant: variant)
        let host = SnapshotBackdropHostingView(rootView: root)
        host.appearance = appearance
        let backdrop = resolved(LintelBrand.windowBackgroundColor, appearance: appearance)
        host.backdropColor = backdrop
        host.backdropShape = Self.backdropShape(for: state.presentation)

        let width = Self.width(of: state.presentation)
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: width, height: 200), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.appearance = appearance
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        NSAnimationContext.beginGrouping()
        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        defer { NSAnimationContext.endGrouping() }

        var previous: Data?
        var stableRenders = 0
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: settleLimit)
        var latest: NSBitmapImageRep?
        // Layout and the tasks a state starts (a probe that answers, a text that loads) need a few turns of the
        // loop; the picture counts as settled when two renders in a row are the same.
        repeat {
            try await Task.sleep(for: .milliseconds(15))
            Self.spinRunLoop()
            let size = Self.size(of: host, presentation: state.presentation)
            guard size.width > 0, size.height > 0 else {
                stableRenders = 0
                continue
            }
            window.setContentSize(size)
            host.frame = NSRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try makeBitmap(size: size)
            appearance?.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            let bytes = Self.bytes(of: bitmap)
            stableRenders = (bytes == previous) ? stableRenders + 1 : 0
            previous = bytes
            latest = bitmap
        } while stableRenders < 2 && clock.now < deadline
        guard let latest, latest.pixelsWide > 0, latest.pixelsHigh > 0 else {
            throw GalleryError.emptyRender(state.id)
        }
        return latest
    }

    /// The state as a live view (the gallery window's preview): the real view in the variant's text size and
    /// appearance, in the language of the process. Not a picture: glass and system popovers draw as in the app.
    public static func liveView(_ state: GalleryState, _ variant: GalleryVariant) -> AnyView {
        AnyView(
            GalleryRoot(content: state.make(), presentation: state.presentation, variant: variant)
                .preferredColorScheme(variant.appearance == .dark ? .dark : .light))
    }

    /// The PNG of a render.
    public static func pngData(_ bitmap: NSBitmapImageRep) throws -> Data {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw GalleryError.bitmap("cannot encode a PNG")
        }
        return data
    }

    // MARK: Parts

    /// One short turn of the main run loop (a synchronous helper: `RunLoop` cannot be used from async code).
    private static func spinRunLoop() {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
    }

    /// An sRGB bitmap of exactly `scale` pixels per point: `cacheDisplay` draws the view scaled into it, so the
    /// picture does not depend on the backing scale of the machine's displays (a CI VM may report 1).
    private static func makeBitmap(size: NSSize) throws -> NSBitmapImageRep {
        let pixelsWide = Int((size.width * scale).rounded(.up))
        let pixelsHigh = Int((size.height * scale).rounded(.up))
        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .calibratedRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { throw GalleryError.bitmap("cannot allocate \(pixelsWide)×\(pixelsHigh)") }
        bitmap.size = size
        return bitmap
    }

    private static func bytes(of bitmap: NSBitmapImageRep) -> Data? {
        guard let data = bitmap.bitmapData else { return nil }
        return Data(bytes: data, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private static func resolved(_ color: NSColor, appearance: NSAppearance?) -> NSColor {
        var result = color
        appearance?.performAsCurrentDrawingAppearance {
            result = color.usingColorSpace(.sRGB) ?? color
        }
        return result
    }

    private static func width(of presentation: GalleryPresentation) -> CGFloat {
        switch presentation {
        case .window(let width, _), .sheet(let width): width
        case .popover(let width): width + 2 * GalleryRoot.popoverMargin
        case .hud: 600
        }
    }

    private static func size(of host: NSView, presentation: GalleryPresentation) -> NSSize {
        let fitting = host.fittingSize
        switch presentation {
        case .window(let width, let height):
            return NSSize(width: width, height: height ?? fitting.height)
        case .sheet(let width):
            return NSSize(width: width, height: fitting.height)
        case .popover:
            return NSSize(width: fitting.width, height: fitting.height)
        case .hud:
            return fitting
        }
    }

    private static func backdropShape(for presentation: GalleryPresentation) -> (NSRect) -> NSBezierPath {
        switch presentation {
        case .window, .sheet:
            return { NSBezierPath(rect: $0) }
        case .popover:
            // The chrome (outline, arrow) is a part of the content; the backdrop behind it is the window's.
            return { NSBezierPath(rect: $0) }
        case .hud(.capsule):
            return { SnapshotBackdropHostingView<GalleryRoot>.roundedPath($0, radius: $0.height / 2) }
        case .hud(.rounded(let radius)):
            return { SnapshotBackdropHostingView<GalleryRoot>.roundedPath($0, radius: radius) }
        }
    }
}

/// The root of a rendered state: its size, the text size, the locale and no animation.
struct GalleryRoot: View {
    let content: AnyView
    let presentation: GalleryPresentation
    let variant: GalleryVariant

    /// The space around a popover's content for the outline and the arrow.
    static let popoverMargin: CGFloat = 12

    var body: some View {
        sized
            .lintelTextSize(variant.textSize)
            .environment(\.locale, Locale(identifier: variant.language))
            .transaction { $0.disablesAnimations = true }
    }

    @ViewBuilder private var sized: some View {
        switch presentation {
        case .window(let width, let height):
            content.frame(width: width, height: height)
        case .sheet(let width):
            content.frame(width: width)
        case .popover(let width):
            PopoverChrome { content.frame(minWidth: width) }
                .padding(Self.popoverMargin)
        case .hud:
            content.fixedSize()
        }
    }
}

/// An approximation of a popover's chrome for the picture: an outline and an arrow at the top. The content is the
/// real view; the system draws its own chrome and material in the app.
struct PopoverChrome<Content: View>: View {
    @ViewBuilder let content: Content

    private static var arrow: CGFloat { 10 }
    private static var radius: CGFloat { 10 }

    var body: some View {
        content
            .background(LintelBrand.card, in: RoundedRectangle(cornerRadius: Self.radius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius).strokeBorder(LintelBrand.hairline, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                Triangle()
                    .fill(LintelBrand.card)
                    .overlay(Triangle().stroke(LintelBrand.hairline, lineWidth: 1))
                    .frame(width: Self.arrow * 2, height: Self.arrow)
                    .offset(y: -Self.arrow + 0.5)
            }
            .padding(.top, Self.arrow)
    }

    private struct Triangle: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            return path
        }
    }
}
#endif
