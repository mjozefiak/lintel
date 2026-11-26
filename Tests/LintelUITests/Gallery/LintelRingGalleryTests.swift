#if DEBUG
import AppKit
import Testing

@testable import LintelUI

/// The ring's gallery scene (notes explorer spec, step 2.1): ids, summaries, that every state draws in both CI
/// appearances, and that the states differ. The pictures themselves are compared by the app bundle in CI.
@MainActor
@Suite(.serialized)
struct LintelRingGalleryTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
    private static let darkM = GalleryVariant(appearance: .dark, textSize: .medium, language: "en")

    @Test func theSceneIsValidAndHasTheFiveWindowStates() {
        let scenes = LintelUIGallery.scenes
        #expect(GalleryScene.validationProblems(scenes).isEmpty, "\(GalleryScene.validationProblems(scenes))")
        let ids = Set(scenes.flatMap { $0.states.map(\.id) })
        for id in ["idle", "listening", "warning", "processing", "processing-unknown", "error", "reduced-motion"] {
            #expect(ids.contains(id), "the ring scene has no state \(id)")
        }
    }

    @Test func everyStateDrawsRealContentAndTheStatesDiffer() async throws {
        let states = try #require(LintelUIGallery.scenes.first).states
        var pictures: [String: [UInt8]] = [:]
        for state in states {
            for variant in [Self.lightM, Self.darkM] {
                let bitmap = try await GalleryRenderer.render(state, variant)
                let bytes = try #require(GalleryPixels(bitmap)?.bytes)
                var distinct = Set<UInt32>()
                for index in stride(from: 0, to: bytes.count - 3, by: 28) {
                    distinct.insert(
                        UInt32(bytes[index]) << 16 | UInt32(bytes[index + 1]) << 8 | UInt32(bytes[index + 2]))
                }
                #expect(distinct.count > 3, "\(state.id) \(variant.name) drew a blank picture")
                if variant == Self.lightM { pictures[state.id] = Array(bytes) }
            }
        }
        let ids = Array(pictures.keys).sorted()
        for (index, first) in ids.enumerated() {
            for second in ids[(index + 1)...] {
                #expect(pictures[first] != pictures[second], "\(first) and \(second) draw the same picture")
            }
        }
    }

    @Test func aStatePictureIsTheSameEveryTime() async throws {
        let state = try #require(LintelUIGallery.scenes.first?.states.first { $0.id == "listening" })
        let first = try await GalleryRenderer.render(state, Self.lightM)
        let second = try await GalleryRenderer.render(state, Self.lightM)
        #expect(GalleryPixels(first)?.bytes == GalleryPixels(second)?.bytes)
    }
}
#endif
