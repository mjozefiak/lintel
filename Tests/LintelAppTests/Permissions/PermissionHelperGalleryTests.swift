#if DEBUG
import AppKit
import Foundation
import LintelUI
import Testing

@testable import LintelApp

/// The gallery scene of the floating permission helper (`docs/design-gallery.md`, "Adding a scene"). The pictures are
/// compared by the app bundle in CI, not here: only the app bundle has the accent colour and the string catalog.
/// There are no goldens in the repository yet; they come after the owner approves the sheet.
@MainActor
@Suite(.serialized)
struct PermissionHelperGalleryTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
    private static let darkM = GalleryVariant(appearance: .dark, textSize: .medium, language: "en")

    @Test func theSceneIsValidAndHasTheFourStatesOfTheSpec() {
        let scenes = ShellGallery.galleryScenes
        #expect(GalleryScene.validationProblems(scenes).isEmpty, "\(GalleryScene.validationProblems(scenes))")
        #expect(scenes.map(\.id) == [PermissionHelperGallery.sceneID])
        #expect(
            scenes.first?.states.map(\.id) == ["drag-tile", "turn-on-switch", "allowed", "beside-lintel"])
    }

    @Test func theCatalogHasTheShellGroupLast() throws {
        let groups = GalleryCatalog.groups
        let last = try #require(groups.last)
        #expect(last.id == GalleryCatalog.shellGroupID)
        #expect(last.scenes.map(\.id) == [PermissionHelperGallery.sceneID])
        #expect(GalleryCatalog.scenes(matching: PermissionHelperGallery.sceneID).count == 1)
        #expect(GalleryScene.validationProblems(GalleryCatalog.scenes).isEmpty)
    }

    @Test func everyStateDrawsRealContentInTheCIAppearances() async throws {
        let scene = try #require(ShellGallery.galleryScenes.first)
        for state in scene.states {
            for variant in state.variants where variant.language == "en" {
                let bitmap = try await GalleryRenderer.render(state, variant)
                #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(state.id) is empty")
                #expect(Self.distinctColours(bitmap) > 3, "\(state.id) \(variant.name) drew a blank picture")
            }
        }
    }

    @Test func aStateDrawsTheSameTwiceAndTheStatesDifferFromOneAnother() async throws {
        let scene = try #require(ShellGallery.galleryScenes.first)
        var pictures: [String: String] = [:]
        for state in scene.states {
            let first = GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
            let second = GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
            #expect(first == second, "\(state.id) draws differently the second time")
            pictures[state.id] = first
        }
        #expect(Set(pictures.values).count == pictures.count, "two states draw the same picture")
    }

    @Test func lightAndDarkDrawDifferently() async throws {
        let state = try #require(ShellGallery.galleryScenes.first?.states.first)
        let light = GalleryGoldens.sha256(
            try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
        let dark = GalleryGoldens.sha256(
            try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.darkM)))
        #expect(light != dark)
    }

    private static func distinctColours(_ bitmap: NSBitmapImageRep) -> Int {
        guard let data = bitmap.bitmapData else { return 0 }
        var seen = Set<UInt32>()
        let count = bitmap.pixelsWide * bitmap.pixelsHigh
        let stride = max(1, count / 4000)
        var index = 0
        while index < count {
            let p = data + index * 4
            seen.insert(UInt32(p[0]) << 16 | UInt32(p[1]) << 8 | UInt32(p[2]))
            index += stride
        }
        return seen.count
    }
}
#endif
