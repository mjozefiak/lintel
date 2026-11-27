import AppKit
import Foundation
import LintelUI
import SwiftUI
import Testing

@testable import LintelApp

/// The window of the floating helper (spec 2026-11-24, "Floating helper panel"): it must stay above System Settings
/// on every Space and never take the focus from it. Each property below is the one that breaks that if it changes.
@Suite struct PermissionHelperPanelTests {
    private func panel() -> PermissionHelperPanel {
        PermissionHelperPanel(bundleURL: URL(filePath: "/Applications/Lintel.app")) { AnyView(Color.clear) }
    }

    @Test func itIsANonActivatingFloatingPanel() {
        let panel = panel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.isFloatingPanel)
        #expect(panel.level == .floating)
    }

    @Test func itStaysWhileAnotherAppIsActive() {
        // NSPanel hides on deactivation by default; System Settings is the active app the whole time.
        #expect(!panel().hidesOnDeactivate)
    }

    @Test func itJoinsEverySpaceAndFullScreenSpaces() {
        let behavior = panel().collectionBehavior
        #expect(behavior.contains(.canJoinAllSpaces))
        #expect(behavior.contains(.fullScreenAuxiliary))
    }

    @Test func itNeverBecomesKeyOrMain() {
        let panel = panel()
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
    }

    @Test func itIsTransparentSoTheCardDrawsItsOwnCorners() {
        let panel = panel()
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
    }

    @Test func itIsAsWideAsTheCardAndTheAllowedStateIsTheSmallest() {
        let panel = panel()
        let drag = panel.size(for: .dragTile)
        let toggle = panel.size(for: .turnOnSwitch)
        let allowed = panel.size(for: .allowed)
        for size in [drag, toggle, allowed] {
            #expect(size.width == PermissionHelperLayout.width)
        }
        #expect(drag.height > toggle.height)
        #expect(toggle.height > allowed.height)
    }

    @Test func closingDropsTheCallbacksAndHidesIt() {
        let panel = panel()
        panel.onDone = {}
        panel.onShowInFinder = {}
        panel.close()
        #expect(panel.onDone == nil)
        #expect(panel.onShowInFinder == nil)
        #expect(!panel.isVisible)
    }
}
