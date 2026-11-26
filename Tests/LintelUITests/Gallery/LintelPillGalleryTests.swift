#if DEBUG
import AppKit
import Testing

@testable import LintelUI

/// The pill's gallery scene (minimal HUD spec, Phase 1): every variant of the family is there, every state draws in
/// both CI appearances, the Reduce Motion pictures differ from the moving ones, and the widest pictures stay within the
/// width limit. The pictures themselves are compared by the app bundle in CI.
@MainActor
@Suite(.serialized)
struct LintelPillGalleryTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
    private static let darkM = GalleryVariant(appearance: .dark, textSize: .medium, language: "en")

    private var scene: GalleryScene? { LintelUIGallery.scenes.first { $0.id == "ui.pill" } }

    @Test func theSceneIsValidAndHasEveryVariantOfTheFamily() throws {
        let scene = try #require(scene)
        #expect(GalleryScene.validationProblems(LintelUIGallery.scenes).isEmpty)
        let ids = Set(scene.states.map(\.id))
        for id in [
            "live-wave", "live-wave-hover", "live-clock", "live-clock-hover", "working", "working-hover",
            "message-done", "message-undo", "prompt", "prompt-hover", "live-wave-amber-dot", "live-clock-amber-dot",
            "reduced-motion-live", "reduced-motion-working", "increased-contrast",
        ] {
            #expect(ids.contains(id), "the pill scene has no state \(id)")
        }
        // The owner's sheet has the L size too; CI compares only its subset.
        for state in scene.states {
            #expect(state.sheetVariants.contains { $0.textSize == .large }, "\(state.id)")
            #expect(state.variants == GalleryVariant.ciSubset, "\(state.id)")
        }
    }

    @Test func theOwnersSheetAddsLargeOnlyWhenAStateAsks() {
        #expect(GalleryVariant.sheetMatrix(includesLarge: false) == GalleryVariant.fullMatrix)
        let withLarge = GalleryVariant.sheetMatrix(includesLarge: true)
        #expect(withLarge.count == 16 && Set(withLarge).isSuperset(of: GalleryVariant.fullMatrix))
        #expect(withLarge.filter { $0.textSize == .large }.count == 4)
    }

    private func picture(_ id: String, _ variant: GalleryVariant) async throws -> NSBitmapImageRep {
        let state = try #require(scene?.states.first { $0.id == id }, "\(id)")
        return try await GalleryRenderer.render(state, variant)
    }

    @Test func everyStateDrawsRealContentInBothAppearances() async throws {
        let states = try #require(scene).states
        for state in states {
            for variant in [Self.lightM, Self.darkM] {
                let bitmap = try await GalleryRenderer.render(state, variant)
                let bytes = try #require(GalleryPixels(bitmap)?.bytes)
                var distinct = Set<UInt32>()
                for index in stride(from: 0, to: bytes.count - 3, by: 12) {
                    distinct.insert(
                        UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]))
                }
                #expect(distinct.count > 3, "\(state.id) \(variant.name) drew a blank picture")
            }
        }
    }

    @Test func reduceMotionAndHoverChangeThePicture() async throws {
        let pairs = [
            ("live-wave", "reduced-motion-live"), ("working", "reduced-motion-working"),
            ("live-wave", "live-wave-hover"), ("live-clock", "live-clock-hover"), ("prompt", "prompt-hover"),
            ("live-clock", "increased-contrast"), ("live-wave", "live-wave-amber-dot"),
        ]
        for (first, second) in pairs {
            let one = try await picture(first, Self.lightM)
            let two = try await picture(second, Self.lightM)
            #expect(GalleryPixels(one)?.bytes != GalleryPixels(two)?.bytes, "\(first) and \(second) are the same")
        }
    }

    /// The width limit at M: 380 pt, 500 pt while hovered (the widest hovered pill of the spec is the suggestion).
    @Test func theWidestPicturesStayWithinTheLimit() async throws {
        for (id, expanded) in [
            ("message-widest", false), ("live-clock-widest", false), ("message-undo", false),
            ("live-wave-fallback-line", false), ("prompt-long-name", false), ("prompt-hover", true),
            ("live-clock-amber-dot-hover", true),
        ] {
            let bitmap = try await picture(id, Self.lightM)
            #expect(bitmap.size.width <= PillMetrics.maxWidth(.medium, expanded: expanded) + 0.5, "\(id)")
            #expect(abs(bitmap.size.height - PillMetrics.height(.medium)) < 0.5, "\(id): one line")
        }
    }
}
#endif
