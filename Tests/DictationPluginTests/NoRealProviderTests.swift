import Foundation
import LintelKit
import LintelProviders
import Testing

@testable import DictationPlugin

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 5: no test of the plugin looks for or starts a real provider CLI
/// (the owner's Mac may have a logged-in Claude Code). The harness installs `DictationProviders.quiet`.
@MainActor
@Suite(.serialized) struct NoRealProviderTests {
    @Test func aPluginWithTheProviderChosenStartsNoRealProcess() async throws {
        let before = ProviderSystem.realProcessesStarted
        let harness = try DictationHarness(settings: [
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.llmSource": .string("provider"),
            "plugins.dictation.provider": .string("claude-code"),
        ])
        let plugin = DictationPlugin(context: harness.context)
        try await plugin.activate()
        _ = plugin.settingsPane()
        await plugin.formattingModel.refresh()
        await plugin.formattingModel.checkProviderAgain()
        #expect(ProviderSystem.realProcessesStarted == before)
        #expect(!DictationProviders.liveWasUsed)
    }
}
