import Foundation
import LintelKit
import Testing

@testable import WindowsPlugin

/// Issue #71: a grant given while Lintel runs clears the plugin's own banner without waiting for an activation.
@Suite(.timeLimit(.minutes(1))) struct TrustGrantBannerTests {
    @MainActor @Test func theBannerInputsAreReadAgainAfterAccessibilityIsGranted() async throws {
        let harness = try WindowsHarness()
        defer { harness.tearDown() }
        let permissions = ScriptedPermissions(granted: false)
        let plugin = WindowsPlugin(
            context: harness.context(
                windows: FakeWindowClient(windows: [makeWindow(1)]), permissions: permissions,
                clock: VirtualClock(autoAdvance: true)),
            hud: RecordingHUD(), activationCenter: NotificationCenter())
        try await plugin.activate()
        await plugin.paneModel.refresh()
        #expect(plugin.paneModel.status.trusted == false)

        permissions.set(true)
        // The runtime's own read (its poll or an activation) notices the grant.
        let runtime = try #require(plugin.runtime)
        runtime.trust.refresh()
        for _ in 0..<400 where plugin.paneModel.status.trusted == false {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(plugin.paneModel.status.trusted)
        await plugin.deactivate()
    }
}
