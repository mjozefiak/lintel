#if DEBUG
import Foundation
import LintelUI
import Testing

@testable import MeetingsPlugin

/// What the gallery tests of this target share: the folder of golden PNGs (in the source tree: `record` writes into
/// it) and the environment the CI steps set.
enum GalleryTestSupport {
    static let goldens = TestPaths.repoRoot.appending(
        path: "Tests/MeetingsPluginTests/Gallery/Goldens", directoryHint: .isDirectory)

    /// `LINTEL_SNAPSHOTS`: `compare`, `compare-anyway` or `record`. Unset: the snapshot tests do not run.
    static var mode: String? {
        ProcessInfo.processInfo.environment["LINTEL_SNAPSHOTS"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `LINTEL_SNAPSHOT_ARTIFACTS`: where `actual.png` and `diff.png` of a failure go.
    static var artifacts: URL? {
        ProcessInfo.processInfo.environment["LINTEL_SNAPSHOT_ARTIFACTS"].flatMap {
            $0.isEmpty ? nil : URL(filePath: $0, directoryHint: .isDirectory)
        }
    }

    static var isCI: Bool { ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" }

    @MainActor static var scenes: [GalleryScene] { MeetingsPlugin.galleryScenes }
}
#endif
