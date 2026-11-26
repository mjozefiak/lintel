#if DEBUG
import AppKit
import LintelKit
import LintelUI

/// DEBUG only: the scenes of the design gallery, found through `PluginRegistry.all` (the one place that knows the concrete
/// plugins): a plugin type that conforms to `GalleryProviding` brings its scenes. Scenes of the shell itself come
/// with its own screens (spec `2026-11-23-swiftui-design-gallery`, phase 5).
@MainActor enum GalleryCatalog {
    struct Group: Identifiable {
        let id: String
        let title: String
        let scenes: [GalleryScene]
    }

    static var groups: [Group] {
        PluginRegistry.all.compactMap { type in
            guard let provider = type as? any GalleryProviding.Type else { return nil }
            let scenes = provider.galleryScenes
            guard !scenes.isEmpty else { return nil }
            return Group(
                id: type.manifest.id.rawValue, title: String(localized: type.manifest.displayName), scenes: scenes)
        }
    }

    static var scenes: [GalleryScene] { groups.flatMap(\.scenes) }

    /// `sceneID` limits the catalog to one scene; `nil` is all of them.
    static func scenes(matching sceneID: String?) -> [GalleryScene] {
        guard let sceneID else { return scenes }
        return scenes.filter { $0.id == sceneID }
    }
}

/// `--qa-gallery-export`, `--qa-gallery-compare` and `--qa-gallery-record`: draw and quit, with a nonzero exit code when
/// something differs or fails. Nothing of the app starts (no plugin, no data root, no window); the same
/// `GalleryRenderer` and `GalleryGoldens` (the plugins' tests use the renderer too) do the work. Logs only state names and counts.
@MainActor enum GalleryBatch {
    /// The language the batch draws: the one asked for, which must be the language of this process.
    static func language(_ options: QAOptions) -> Result<String, GalleryBatchError> {
        let process = GalleryRenderer.processLanguage
        if let asked = options.galleryLanguage, asked != process {
            return .failure(.languageMismatch(asked: asked, process: process))
        }
        return .success(process)
    }

    /// Runs the mode of `options`; the return value is the process's exit code.
    static func run(_ options: QAOptions) async -> Int32 {
        let language: String
        switch Self.language(options) {
        case .success(let value): language = value
        case .failure(let error):
            report("\(error)")
            return EX_USAGE
        }
        let scenes = GalleryCatalog.scenes(matching: options.galleryScene)
        if scenes.isEmpty {
            report("no gallery scene\(options.galleryScene.map { " named \($0)" } ?? "")")
            return EX_DATAERR
        }
        let environment = ProcessInfo.processInfo.environment
        do {
            if let folder = options.galleryExport {
                let count = try await export(scenes, language: language, to: folder)
                report("exported \(count) pictures (\(language))")
                return EX_OK
            }
            if let folder = options.galleryRecord {
                let count = try await GalleryGoldens.record(
                    scenes: scenes, language: language, directory: folder, runID: environment["LINTEL_GALLERY_RUN"])
                report("recorded \(count) pictures (\(language))")
                return EX_OK
            }
            if let folder = options.galleryCompare {
                let artifacts = environment["LINTEL_SNAPSHOT_ARTIFACTS"].flatMap {
                    $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory)
                }
                let result = await GalleryGoldens.compare(
                    scenes: scenes, language: language, directory: folder, artifacts: artifacts)
                if let reason = result.notCompared {
                    report(reason)
                    return 1
                }
                for failure in result.failures { report(failure) }
                report("compared \(result.compared) pictures (\(language)), \(result.failures.count) failures")
                return result.failures.isEmpty && result.compared > 0 ? EX_OK : 1
            }
        } catch {
            report("\(error)")
            return 1
        }
        return EX_USAGE
    }

    /// The full matrix in `language`, `<folder>/<scene>/<state>/<variant>.png`.
    private static func export(_ scenes: [GalleryScene], language: String, to folder: URL) async throws -> Int {
        var count = 0
        for scene in scenes {
            for state in scene.states {
                let directory = folder.appending(path: "\(scene.id)/\(state.id)", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                // What the owner approves, next to the pictures: the contact sheet shows it (spec: `summary`).
                try Data(state.summary.utf8).write(to: directory.appending(path: "summary.txt"))
                let caveat = state.presentation.caveat ?? ""
                try Data(caveat.utf8).write(to: directory.appending(path: "caveat.txt"))
                for variant in GalleryVariant.fullMatrix where variant.language == language {
                    let bitmap = try await GalleryRenderer.render(state, variant)
                    try GalleryRenderer.pngData(bitmap).write(to: directory.appending(path: "\(variant.name).png"))
                    count += 1
                }
            }
        }
        return count
    }

    private static func report(_ line: String) {
        FileHandle.standardError.write(Data(("gallery: " + line + "\n").utf8))
    }
}

enum GalleryBatchError: Error, CustomStringConvertible {
    case languageMismatch(asked: String, process: String)

    var description: String {
        switch self {
        case .languageMismatch(let asked, let process):
            "language \(asked) was asked for but this process runs in \(process); start it with -AppleLanguages \"(\(asked))\" from the app bundle"
        }
    }
}
#endif
