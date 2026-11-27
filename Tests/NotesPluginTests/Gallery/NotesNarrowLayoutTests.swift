#if DEBUG
import AppKit
import Foundation
import LintelUI
import Testing

@testable import NotesPlugin

/// Owner decision on #348 (Q16): in a window tiled to about 310 pt (a tiling window manager ignores the minimum
/// size) the notes explorer wraps and stacks; nothing is cut off. A cut-off text reaches the edge of the picture, so
/// the outer margins of every narrow state must stay empty.
@MainActor
@Suite(.serialized)
struct NotesNarrowLayoutTests {
    private static let variants = [
        GalleryVariant(appearance: .light, textSize: .medium, language: "en"),
        GalleryVariant(appearance: .light, textSize: .extraLarge, language: "en"),
        GalleryVariant(appearance: .dark, textSize: .medium, language: "en"),
    ]

    private static var narrowStates: [GalleryState] {
        NotesPlugin.galleryScenes.flatMap(\.states).filter { $0.id.hasPrefix("narrow-") }
    }

    @Test("the narrow states exist: the failed notice and the stacked list over the preview")
    func narrowStatesExist() {
        #expect(Set(Self.narrowStates.map(\.id)) == ["narrow-failed", "narrow-stacked"])
    }

    @Test("nothing reaches the outer margins of a narrow picture")
    func marginsStayEmpty() async throws {
        for state in Self.narrowStates {
            for variant in Self.variants {
                let bitmap = try await GalleryRenderer.render(state, variant)
                let problem = Self.inkInMargins(bitmap, margin: 8)
                #expect(problem == nil, "\(state.id) \(variant.name): \(problem ?? "")")
            }
        }
    }

    /// A description of the first pixel in the left or right margin that differs from the margin's background, or
    /// `nil` when both margins are clean. A rule that runs across the whole row (the hairline between the list and
    /// the preview) is not ink.
    private static func inkInMargins(_ bitmap: NSBitmapImageRep, margin: Int) -> String? {
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return [-1, -1, -1] }
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        }
        func close(_ a: [Int], _ b: [Int]) -> Bool { zip(a, b).allSatisfy { abs($0 - $1) <= 6 } }
        // The background is the colour most of the left edge has.
        var counts: [[Int]: Int] = [:]
        for y in 0..<height { counts[rgb(0, y), default: 0] += 1 }
        guard let background = counts.max(by: { $0.value < $1.value })?.key else { return "no pixels" }
        for y in 0..<height {
            let isRule = close(rgb(0, y), rgb(width / 2, y)) && close(rgb(0, y), rgb(width - 1, y))
            if isRule { continue }
            for x in 0..<margin where !close(rgb(x, y), background) { return "ink at x=\(x) y=\(y)" }
            for x in (width - margin)..<width where !close(rgb(x, y), background) {
                return "ink at x=\(x) y=\(y) of \(width)"
            }
        }
        return nil
    }
}
#endif
