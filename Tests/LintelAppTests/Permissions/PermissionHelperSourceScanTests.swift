import Foundation
import Testing

/// What the helper may read and who may start it (spec 2026-11-24, Risks: Window reading; section 3).
@Suite struct PermissionHelperSourceScanTests {
    private static let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private static func swiftFiles(in folder: String) throws -> [URL] {
        let url = root.appending(path: folder, directoryHint: .isDirectory)
        let walker = try #require(FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil))
        return walker.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private static func text(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

    /// Code without comment lines, so a sentence that explains what is NOT read does not trip the scan.
    private static func code(_ url: URL) throws -> String {
        try text(url).split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    }

    /// Names that would read what a window is called, which app a window belongs to by name, or what is on the
    /// screen: each one needs the Screen Recording permission or leaks what the user is doing.
    static let forbidden = [
        "kCGWindowName", "kCGWindowOwnerName", "localizedName", "CGWindowListCreateImage", "ScreenCaptureKit",
        "CGDisplayCreateImage",
    ]

    @Test func thePermissionsFolderNeverReadsWindowNamesOrTheScreen() throws {
        let files = try Self.swiftFiles(in: "Sources/LintelApp/Permissions")
        #expect(files.contains { $0.lastPathComponent == "PermissionHelperPanel.swift" })
        for file in files {
            let code = try Self.code(file)
            for name in Self.forbidden {
                #expect(!code.contains(name), "\(file.lastPathComponent) uses \(name)")
            }
        }
    }

    @Test func theWindowListKeepsOnlyThePidTheBoundsAndTheLayer() throws {
        let list = try Self.code(Self.root.appending(path: "Sources/LintelApp/Permissions/SystemWindowList.swift"))
        // The positive control: the scan above is not vacuous.
        for key in ["kCGWindowOwnerPID", "kCGWindowBounds", "kCGWindowLayer", "kCGWindowIsOnscreen"] {
            #expect(list.contains(key), "SystemWindowList no longer reads \(key)")
        }
        let keys = list.matches(of: /kCGWindow\w+/).map { String($0.output) }
        #expect(Set(keys) == ["kCGWindowOwnerPID", "kCGWindowBounds", "kCGWindowLayer", "kCGWindowIsOnscreen"])
    }

    /// Other features read the window list for their own reasons (the Windows plugin's lookup); inside the folder of
    /// the helper there is one reader, which strips the names.
    @Test func inThePermissionsFolderOnlySystemWindowListCallsTheWindowListApi() throws {
        for file in try Self.swiftFiles(in: "Sources/LintelApp/Permissions") {
            let code = try Self.code(file)
            if file.lastPathComponent == "SystemWindowList.swift" {
                #expect(code.contains("CGWindowListCopyWindowInfo"))
            } else {
                #expect(!code.contains("CGWindowListCopyWindowInfo"), "\(file.lastPathComponent) reads the window list")
            }
        }
    }

    /// The helper is built but not wired: no Allow button, banner or `PermissionGrantService.allow` starts it. The
    /// step that wires it (after the owner approves the gallery sheet) deletes this test on purpose.
    @Test func nothingStartsTheHelperYet() throws {
        let owners: Set<String> = [
            "PermissionHelperPanel.swift", "PermissionHelperController.swift", "PermissionHelperGeometry.swift",
        ]
        for file in try Self.swiftFiles(in: "Sources") where !owners.contains(file.lastPathComponent) {
            let code = try Self.code(file)
            for name in ["PermissionHelperPresenter", "PermissionHelperPanel", "PermissionHelperController"] {
                #expect(!code.contains(name), "\(file.lastPathComponent) uses \(name): the helper is not wired yet")
            }
        }
    }
}
