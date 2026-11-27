import Foundation
import Testing

/// A button wrapped in `.accessibilityElement(children: .ignore)` loses its own press action: the new element has
/// only what the modifiers give it. The sidebar rows had none, so VoiceOver, Voice Control and Switch Control could
/// not switch a collection or open Settings (QA of #348, M-A). SwiftUI builds its accessibility tree only while an
/// assistive client is attached, so a unit test cannot press the element (an `NSHostingView` in a test reports no
/// children); this scan keeps every shared component that does it honest, and the QA build checks the press itself
/// through System Events (`perform action "AXPress"`).
@Suite struct SidebarRowAccessibilityTests {
    private var root: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    @Test("a component that hides a button's own element gives the new element the press action")
    func ignoredButtonsKeepThePress() throws {
        let folder = root.appending(path: "Sources/LintelUI/Components", directoryHint: .isDirectory)
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasSuffix(".swift") }
        var checked: [String] = []
        for name in names {
            let source = try String(contentsOf: folder.appending(path: name), encoding: .utf8)
            guard source.contains("Button("), source.contains(".accessibilityElement(children: .ignore)") else {
                continue
            }
            checked.append(name)
            #expect(source.contains(".accessibilityAction { action() }"), "\(name) has no press action")
        }
        #expect(checked.contains("SidebarRow.swift"))
    }
}
