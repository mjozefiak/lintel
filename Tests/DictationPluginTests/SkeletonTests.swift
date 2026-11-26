import Testing

@testable import DictationPlugin
@testable import LintelKit

@Suite @MainActor struct SkeletonTests {
    @Test func theManifestIsOnByDefaultAndStable() {
        let manifest = DictationPlugin.manifest
        #expect(manifest.id == "dictation")
        #expect(manifest.defaultEnabled)
        #expect(manifest.order > 30)
    }
}

@Suite @MainActor struct PluginContractTests {
    @Test func theRecordCommandDeliversKeyPhasesAndNeedsTheMicrophone() throws {
        let harness = try DictationHarness()
        defer { harness.tearDown() }
        let plugin = DictationPlugin(context: harness.context)
        let command = try #require(plugin.commands.first)
        #expect(command.id == "dictation.record")
        #expect(command.onKeyEvent != nil)
        // Owner decision 7 of the onboarding spec: ⌥ Space for a new install, ⌃⌥D as the shell's fallback.
        #expect(command.defaultShortcut == KeyShortcut(key: " ", modifiers: .option))
        #expect(command.fallbackShortcut == KeyShortcut(key: "d", modifiers: [.control, .option]))
        #expect(plugin.requiredPermissions == [.microphone, .accessibility])
    }
}
