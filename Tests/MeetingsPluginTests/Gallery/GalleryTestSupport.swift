#if DEBUG
import Foundation
import LintelUI
import Testing

@testable import MeetingsPlugin

/// What the gallery tests of this target share: the folder of golden PNGs (in the source tree: the gallery-goldens
/// workflow writes into it) and the plugin's scenes. The pictures are compared by the app bundle in CI (`ci.yml`), not
/// here: only the app bundle has the accent colour and the compiled string catalog the owner approves.
enum GalleryTestSupport {
    static let goldens = TestPaths.repoRoot.appending(
        path: "Tests/MeetingsPluginTests/Gallery/Goldens", directoryHint: .isDirectory)

    @MainActor static var scenes: [GalleryScene] { MeetingsPlugin.galleryScenes }
}
#endif
