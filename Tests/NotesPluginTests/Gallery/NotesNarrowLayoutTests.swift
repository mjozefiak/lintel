#if DEBUG
import AppKit
import Foundation
import LintelUI
import SwiftUI
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

    /// The section as `NotesSectionView` builds it in a narrow window with no tab open: a strip, the stacked list and
    /// preview, the status bar. A window that is short for the text size must scroll, not cut the bars off.
    private struct SectionProbe: View {
        let model: NotesWorkspaceModel
        let strip: NotesWorkspaceModel.Strip

        var body: some View {
            VStack(spacing: 0) {
                NoteStripView(strip: strip, model: model).environment(\.notesCompact, true)
                NoteStackedExplorer(model: model)
                NotesStatusBar(model: model).environment(\.notesCompact, true)
            }
            .background(LintelBrand.windowBackground)
            .task {
                model.prepareCollection(.all)
                await model.refresh()
                let id = NoteItemID.live(NotesQAFixtures.failedID)
                model.select(row: id)
                await model.loadPreview(id)
            }
        }
    }

    private static let longStrip = NotesWorkspaceModel.Strip(
        id: "locked", tone: .error,
        text: "Lintel can’t read the key to your notes. Nothing was deleted. Unlock your login keychain and try again.",
        actions: [.init(id: "locked.retry", title: "Try again, once the keychain is unlocked")])

    @Test("a short window at the largest text size loses nothing: the strip, list, preview and status bar stay whole")
    func shortWindowKeepsEveryEdgeClean() async throws {
        let extraLarge = GalleryVariant(appearance: .light, textSize: .extraLarge, language: "en")
        for height in [420.0, 600.0] {
            let state = GalleryState(
                id: "narrow-section-\(Int(height))", summary: "test only",
                presentation: GalleryPresentation.window(width: 254, height: height), variants: [extraLarge]
            ) {
                AnyView(
                    SectionProbe(model: galleryModel(NotesExplorerGalleryCase(canRetry: true)), strip: Self.longStrip))
            }
            let bitmap = try await GalleryRenderer.render(state, extraLarge)
            let problem = Self.inkInMargins(bitmap, margin: 8, rows: 4)
            #expect(problem == nil, "height \(height): \(problem ?? "")")
        }
    }

    @Test("the list keeps room for its heading and a row, and leaves the preview the rest")
    func listHeightShare() {
        for scale in [1.0, 1.5] {
            for available in [300.0, 470.0, 560.0, 900.0] {
                let list = NoteStackedExplorer.listHeight(available: available, textScale: scale)
                #expect(list <= available)
                #expect(list <= 240 * scale)
                #expect(list >= min(available, 150 * scale))
            }
        }
    }

    /// A description of the first pixel in the left or right margin that differs from the margin's background, or
    /// `nil` when both margins are clean. A rule that runs across the whole row (the hairline between the list and
    /// the preview) is not ink.
    private static func inkInMargins(_ bitmap: NSBitmapImageRep, margin: Int, rows: Int = 0) -> String? {
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
        // The top and bottom rows (when asked): cut-off text reaches them, a bar or a gap does not.
        for y in Array(0..<rows) + Array((height - rows)..<height) where rows > 0 {
            for x in 1..<width where !close(rgb(x, y), rgb(0, y)) { return "ink at x=\(x) y=\(y) of \(height)" }
        }
        for y in 0..<height {
            // A bar (a tinted strip, the status bar) runs edge to edge in its own colour: that colour is the row's
            // background, ink is whatever differs from it in the margins.
            let edge = rgb(0, y)
            let isBar = close(edge, rgb(width - 1, y))
            if !isBar && !close(edge, background) { return "ink at x=0 y=\(y)" }
            let rowBackground = isBar ? edge : background
            for x in 0..<margin where !close(rgb(x, y), rowBackground) { return "ink at x=\(x) y=\(y)" }
            for x in (width - margin)..<width where !close(rgb(x, y), rowBackground) {
                return "ink at x=\(x) y=\(y) of \(width)"
            }
        }
        return nil
    }
}
#endif
