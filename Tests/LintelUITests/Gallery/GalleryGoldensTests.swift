#if DEBUG
import AppKit
import SwiftUI
import Testing

@testable import LintelUI

/// `GalleryGoldens.record` and `compare` with synthetic scenes (a colour each): the file layout, the manifest, what
/// recording one scene leaves alone, and the single "not compared" line when there is no manifest.
@MainActor
struct GalleryGoldensTests {
    private let lightM = GalleryVariant(appearance: .light, textSize: .medium, language: "en")

    private func scene(_ id: String, _ states: [(String, Color)]) -> GalleryScene {
        GalleryScene(
            id: id, title: id,
            states: states.map { stateID, color in
                GalleryState(
                    id: stateID, summary: "A colour", presentation: .window(width: 80, height: 40),
                    variants: [lightM]
                ) { AnyView(color) }
            })
    }

    private func withFolder(_ body: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appending(
            path: "gallery-goldens-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await body(folder)
    }

    private func exists(_ folder: URL, _ name: String) -> Bool {
        FileManager.default.fileExists(atPath: folder.appending(path: name).path)
    }

    @Test("without a goldens.json nothing is compared, with one clear line")
    func noManifestIsOneMessage() async throws {
        try await withFolder { folder in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let report = await GalleryGoldens.compare(
                scenes: [scene("a", [("one", .red), ("two", .blue)])], language: "en", directory: folder,
                artifacts: nil)
            #expect(report.notCompared?.contains("goldens.json") == true)
            #expect(report.failures.isEmpty)
            #expect(report.compared == 0)
            #expect(!report.passed)
        }
    }

    @Test("a recorded folder compares clean, and a changed state fails by name")
    func recordThenCompare() async throws {
        try await withFolder { folder in
            let before = [scene("a", [("one", .red), ("two", .blue)])]
            let written = try await GalleryGoldens.record(
                scenes: before, language: "en", directory: folder, runID: "42")
            #expect(written == 2)
            #expect(exists(folder, "a/one@light-m-en.png"))
            #expect(GalleryGoldens.loadManifest(in: folder)?.recordRun == "42")
            let clean = await GalleryGoldens.compare(
                scenes: before, language: "en", directory: folder, artifacts: nil)
            #expect(clean.passed && clean.compared == 2)
            let changed = [scene("a", [("one", .red), ("two", .green)])]
            let report = await GalleryGoldens.compare(
                scenes: changed, language: "en", directory: folder, artifacts: nil)
            #expect(report.failures.count == 1)
            #expect(report.failures.first?.contains("a/two") == true)
        }
    }

    @Test("recording one scene keeps the goldens of the others")
    func recordingOneSceneKeepsTheOthers() async throws {
        try await withFolder { folder in
            let a = scene("a", [("one", .red)])
            let b = scene("b", [("one", .blue)])
            try await GalleryGoldens.record(scenes: [a, b], language: "en", directory: folder, runID: nil)
            try await GalleryGoldens.record(scenes: [a], language: "en", directory: folder, runID: nil)
            #expect(exists(folder, "b/one@light-m-en.png"))
            #expect(GalleryGoldens.loadManifest(in: folder)?.files.keys.contains("b/one@light-m-en.png") == true)
        }
    }

    @Test("a state that is gone loses its golden, in the language being recorded only")
    func aRemovedStateLosesItsGolden() async throws {
        try await withFolder { folder in
            try await GalleryGoldens.record(
                scenes: [scene("a", [("one", .red), ("two", .blue)])], language: "en", directory: folder, runID: nil)
            // A picture of the other language is not this recording's to delete.
            let other = folder.appending(path: "a/one@light-xl-pl.png")
            try Data([1]).write(to: other)
            try await GalleryGoldens.record(
                scenes: [scene("a", [("one", .red)])], language: "en", directory: folder, runID: nil)
            #expect(exists(folder, "a/one@light-m-en.png"))
            #expect(!exists(folder, "a/two@light-m-en.png"))
            #expect(exists(folder, "a/one@light-xl-pl.png"))
            #expect(GalleryGoldens.loadManifest(in: folder)?.files.keys.contains("a/two@light-m-en.png") == false)
        }
    }
}
#endif
