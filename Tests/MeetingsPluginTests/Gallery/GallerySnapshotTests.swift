#if DEBUG
import AppKit
import LintelUI
import Testing

/// The golden-image test of this plugin's gallery scenes (spec `2026-11-23-swiftui-design-gallery`): every state in the CI
/// subset of variants in the language of this process (`en`: `swift test` runs in the test runner's bundle, which
/// has no Polish catalog; the `pl` pictures are compared by the app bundle, `--qa-gallery-compare`).
///
/// It runs only with `LINTEL_SNAPSHOTS` set, so the main `swift test` step is not longer by it:
/// - `compare` (CI): fails on a difference. A golden recorded under another renderer fingerprint (macOS build,
///   Xcode) fails with one message instead of dozens of diffs. Without `LINTEL_GALLERY_XCODE` the comparison is
///   skipped: a local Mac is not the runner, and its text drawing differs.
/// - `compare-anyway`: compares whatever the fingerprint says.
/// - `record`: writes the PNGs and `goldens.json` (the `gallery-goldens.yml` workflow; an agent never records to make
///   a test pass: the PR then needs "Golden changes" and `needs-qa`).
@MainActor
@Suite(
    .enabled(if: GalleryTestSupport.mode != nil, "set LINTEL_SNAPSHOTS=compare|record to run the gallery snapshots"),
    .serialized)
struct GallerySnapshotTests {
    @Test("the goldens match the pictures drawn now")
    func compare() async throws {
        let mode = try #require(GalleryTestSupport.mode)
        let language = GalleryRenderer.processLanguage
        if mode == "record" {
            let written = try await GalleryGoldens.record(
                scenes: GalleryTestSupport.scenes, language: language, directory: GalleryTestSupport.goldens,
                runID: ProcessInfo.processInfo.environment["LINTEL_GALLERY_RUN"])
            print("GALLERY recorded \(written) pictures (\(language))")
            return
        }
        let fingerprint = GalleryFingerprint.current
        if mode == "compare", fingerprint.xcode == nil {
            try Test.cancel(
                "LINTEL_GALLERY_XCODE is not set: this is not the CI renderer, the comparison is skipped")
        }
        let report = await GalleryGoldens.compare(
            scenes: GalleryTestSupport.scenes, language: language, directory: GalleryTestSupport.goldens,
            artifacts: GalleryTestSupport.artifacts, ignoringFingerprint: mode == "compare-anyway")
        if let reason = report.notCompared {
            if GalleryTestSupport.isCI {
                Issue.record("\(reason)")
            } else {
                try Test.cancel("\(reason) (locally the comparison is skipped)")
            }
            return
        }
        #expect(report.compared > 0, "no gallery state was compared")
        for failure in report.failures { Issue.record("\(failure)") }
        print("GALLERY compared \(report.compared) pictures (\(language)), \(report.failures.count) failures")
    }
}
#endif
