#if DEBUG
import AppKit
import CryptoKit

/// `goldens.json`: what a folder of golden PNGs was recorded under (spec `2026-11-23-swiftui-design-gallery`, Data Model).
public struct GalleryGoldenManifest: Codable, Equatable, Sendable {
    public struct Threshold: Codable, Equatable, Sendable {
        public var channel: Int
        public var share: Double
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var width: Int
        public var height: Int
        public var sha256: String
    }

    public var version: Int
    public var fingerprint: GalleryFingerprint
    /// The `gallery-goldens.yml` run whose sheet the owner approved.
    public var recordRun: String?
    public var threshold: Threshold
    /// `<scene>/<state>@<variant>.png` → size and hash.
    public var files: [String: Entry]

    public static let currentVersion = 1
}

/// DEBUG only: compares and records golden PNGs for gallery scenes. The tests of a plugin and the app's
/// `--qa-gallery-compare` / `--qa-gallery-record` both use it, so an `en` picture made by `swift test` and a `pl`
/// picture made by the app bundle go through the same renderer, diff and file layout.
@MainActor public enum GalleryGoldens {
    public static let manifestName = "goldens.json"

    /// `meetings.notes-provider/local@light-m-en.png`.
    public static func fileName(scene: GalleryScene, state: GalleryState, variant: GalleryVariant) -> String {
        "\(scene.id)/\(state.id)@\(variant.name).png"
    }

    /// The files a set of scenes should have in `language`: every state in the variants it names for it.
    public static func expectedFiles(_ scenes: [GalleryScene], language: String? = nil) -> Set<String> {
        var names = Set<String>()
        for scene in scenes {
            for state in scene.states {
                for variant in state.variants where language == nil || variant.language == language {
                    names.insert(fileName(scene: scene, state: state, variant: variant))
                }
            }
        }
        return names
    }

    public static func loadManifest(in directory: URL) -> GalleryGoldenManifest? {
        guard let data = try? Data(contentsOf: directory.appending(path: manifestName)) else { return nil }
        return try? JSONDecoder().decode(GalleryGoldenManifest.self, from: data)
    }

    public struct Report: Sendable {
        public var compared = 0
        public var failures: [String] = []
        /// Why nothing was compared (an unknown or changed fingerprint), or `nil`.
        public var notCompared: String?

        public var passed: Bool { failures.isEmpty && notCompared == nil }
    }

    /// Draws every state in the variants of `language` and compares each picture with the golden of that name. A
    /// difference over the manifest's threshold, a missing golden or a different size is a failure with the state's
    /// name. `artifacts` gets `actual.png` (and `diff.png`) of every failure: `<scene>/<state>@<variant>/`, and the
    /// fingerprint the run had.
    public static func compare(
        scenes: [GalleryScene], language: String, directory: URL, artifacts: URL?, ignoringFingerprint: Bool = false
    ) async -> Report {
        var report = Report()
        let current = GalleryFingerprint.current
        let manifest = loadManifest(in: directory)
        if let artifacts { writeFingerprint(current, to: artifacts) }
        if let manifest, !ignoringFingerprint, let reason = manifest.fingerprint.mismatch(comparedTo: current) {
            report.notCompared =
                "renderer fingerprint changed (\(reason)): run gallery-goldens.yml and record the goldens again"
            return report
        }
        let channel = UInt8(clamping: manifest?.threshold.channel ?? Int(GalleryDiff.defaultChannelTolerance))
        let share = manifest?.threshold.share ?? GalleryDiff.defaultShareLimit
        for scene in scenes {
            for state in scene.states {
                for variant in state.variants where variant.language == language {
                    let name = fileName(scene: scene, state: state, variant: variant)
                    let label = "\(scene.id)/\(state.id) \(variant.name)"
                    let actual: NSBitmapImageRep
                    do {
                        actual = try await GalleryRenderer.render(state, variant)
                    } catch {
                        report.failures.append("\(label): \(error)")
                        continue
                    }
                    report.compared += 1
                    let golden = directory.appending(path: name)
                    guard let data = try? Data(contentsOf: golden), let goldenRep = NSBitmapImageRep(data: data) else {
                        report.failures.append("\(label): golden \(name) is missing; record the goldens")
                        save(actual, diff: nil, label: "\(scene.id)/\(state.id)@\(variant.name)", to: artifacts)
                        continue
                    }
                    let (result, diff) = GalleryDiff.compare(actual, goldenRep, channelTolerance: channel)
                    if !result.passes(shareLimit: share) {
                        let how =
                            result.sizeMatches
                            ? String(
                                format: "%.3f%% of the pixels differ (limit %.3f%%)", result.differingShare * 100,
                                share * 100)
                            : "the size differs from the golden"
                        report.failures.append("\(label): \(how)")
                        save(actual, diff: diff, label: "\(scene.id)/\(state.id)@\(variant.name)", to: artifacts)
                    }
                }
            }
        }
        return report
    }

    /// Draws every state in the variants of `language` and writes the PNGs and `goldens.json`. Pictures of the
    /// other language already in the folder are kept when they were recorded under the same fingerprint; files of
    /// `language` that no state names any more are deleted. Returns the number of pictures written.
    @discardableResult
    public static func record(
        scenes: [GalleryScene], language: String, directory: URL, runID: String?
    ) async throws -> Int {
        let fileManager = FileManager.default
        let current = GalleryFingerprint.current
        var manifest = loadManifest(in: directory)
        // Pictures made under another fingerprint are not mixed with these.
        if let existing = manifest, existing.fingerprint.mismatch(comparedTo: current) != nil { manifest = nil }
        var next =
            manifest
            ?? GalleryGoldenManifest(
                version: GalleryGoldenManifest.currentVersion, fingerprint: current, recordRun: nil,
                threshold: .init(
                    channel: Int(GalleryDiff.defaultChannelTolerance), share: GalleryDiff.defaultShareLimit),
                files: [:])
        next.fingerprint = current
        if let runID { next.recordRun = runID }
        let suffix = "-\(language).png"
        let wanted = expectedFiles(scenes, language: language)
        for stale in next.files.keys where stale.hasSuffix(suffix) && !wanted.contains(stale) {
            next.files[stale] = nil
            try? fileManager.removeItem(at: directory.appending(path: stale))
        }
        var written = 0
        for scene in scenes {
            for state in scene.states {
                for variant in state.variants where variant.language == language {
                    let bitmap = try await GalleryRenderer.render(state, variant)
                    let data = try GalleryRenderer.pngData(bitmap)
                    let name = fileName(scene: scene, state: state, variant: variant)
                    let url = directory.appending(path: name)
                    try fileManager.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: url, options: .atomic)
                    next.files[name] = .init(
                        width: bitmap.pixelsWide, height: bitmap.pixelsHigh, sha256: sha256(data))
                    written += 1
                }
            }
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(next).write(to: directory.appending(path: manifestName), options: .atomic)
        return written
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func save(_ actual: NSBitmapImageRep, diff: NSBitmapImageRep?, label: String, to artifacts: URL?) {
        guard let artifacts else { return }
        let folder = artifacts.appending(path: label, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? GalleryRenderer.pngData(actual).write(to: folder.appending(path: "actual.png"))
        if let diff { try? GalleryRenderer.pngData(diff).write(to: folder.appending(path: "diff.png")) }
    }

    private static func writeFingerprint(_ fingerprint: GalleryFingerprint, to artifacts: URL) {
        try? FileManager.default.createDirectory(at: artifacts, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(fingerprint).write(to: artifacts.appending(path: "fingerprint.json"))
    }
}
#endif
