#if DEBUG
import AppKit
import Foundation
import LintelUI
import Testing

@testable import DictationPlugin

/// The scenes of `DictationPlugin` for the design gallery (`docs/design-gallery.md`, "Adding a scene"): ids, summaries,
/// that every state draws, and that the goldens in the shared folder match the states. The pictures are compared by the
/// app bundle in CI (`ci.yml`), not here: only the app bundle has the accent colour and the compiled string catalog.
@MainActor
@Suite(.serialized)
struct DictationGalleryTests {
    private static let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")
    private static let prefix = "dictation."

    private static let goldens: URL = {
        var url = URL(filePath: #filePath).deletingLastPathComponent()
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
            url = url.deletingLastPathComponent()
        }
        return url.appending(path: "Tests/MeetingsPluginTests/Gallery/Goldens", directoryHint: .isDirectory)
    }()

    @Test("ids are unique and well formed, every state has a summary, the states exist")
    func scenesAreValid() {
        let scenes = DictationPlugin.galleryScenes
        #expect(GalleryScene.validationProblems(scenes).isEmpty, "\(GalleryScene.validationProblems(scenes))")
        #expect(scenes.map(\.id) == ["dictation.tidy-up", "dictation.hud-pills"])
        let tidyUp = Set(scenes.first { $0.id == "dictation.tidy-up" }?.states.map(\.id) ?? [])
        #expect(tidyUp == ["off", "light", "standard", "full", "full-small-model", "standard-dimmed"])
        // The HUD pills (minimal HUD, Phase 2): every state of the dictation HUD that has a pill, the three looks.
        let pills = Set(scenes.first { $0.id == "dictation.hud-pills" }?.states.map(\.id) ?? [])
        #expect(
            pills.isSuperset(of: ["recording", "recording-hover", "recording-loading-model", "finishing", "pasted"]))
        #expect(pills.isSuperset(of: ["reduced-motion-recording", "increased-contrast-recording"]))
        #expect(pills.isSuperset(of: ["recording-microphone-fallback", "recording-microphone-fallback-collapsed"]))
    }

    @Test("every state draws real content in the CI appearances")
    func everyStateDraws() async throws {
        for scene in DictationPlugin.galleryScenes {
            for state in scene.states {
                for variant in state.variants where variant.language == "en" {
                    let bitmap = try await GalleryRenderer.render(state, variant)
                    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "\(state.id) is empty")
                    #expect(Self.hasContent(bitmap), "\(state.id) \(variant.name) drew a blank picture")
                }
            }
        }
    }

    @Test("a state is made fresh each time, and the states differ from one another")
    func statesAreIndependent() async throws {
        let states = try #require(DictationPlugin.galleryScenes.first { $0.id == "dictation.tidy-up" }).states
        var first: [String: String] = [:]
        for state in states {
            let bitmap = try await GalleryRenderer.render(state, Self.lightM)
            first[state.id] = GalleryGoldens.sha256(try GalleryRenderer.pngData(bitmap))
        }
        for state in states {
            let again = GalleryGoldens.sha256(
                try GalleryRenderer.pngData(try await GalleryRenderer.render(state, Self.lightM)))
            #expect(first[state.id] == again, "\(state.id) draws differently the second time")
        }
        #expect(Set(first.values).count == first.count, "two states draw the same picture")
    }

    @Test("no golden image of this plugin belongs to a state that no longer exists, and every state has its goldens")
    func goldensMatchTheStates() throws {
        let expected = GalleryGoldens.expectedFiles(DictationPlugin.galleryScenes)
        let root = Self.goldens.standardizedFileURL.path + "/"
        let walker = FileManager.default.enumerator(at: Self.goldens, includingPropertiesForKeys: nil)
        let present = Set(
            (walker?.compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "png" }
                .map { String($0.standardizedFileURL.path.dropFirst(root.count)) }
                .filter { $0.hasPrefix(Self.prefix) })
        #expect(
            present.subtracting(expected).isEmpty, "delete these goldens: \(present.subtracting(expected).sorted())")
        #expect(expected.subtracting(present).isEmpty, "missing goldens: \(expected.subtracting(present).sorted())")
    }

    private static func hasContent(_ bitmap: NSBitmapImageRep) -> Bool {
        guard let data = bitmap.bitmapData else { return false }
        let count = bitmap.pixelsWide * bitmap.pixelsHigh
        var distinct = Set<UInt32>()
        for index in stride(from: 0, to: count, by: 7) {
            let base = index * 4
            distinct.insert(UInt32(data[base]) << 16 | UInt32(data[base + 1]) << 8 | UInt32(data[base + 2]))
            if distinct.count > 8 { return true }
        }
        return false
    }
}
#endif
