import Foundation
import LintelKit
import LintelSpeech
import Testing

@testable import DictationPlugin

/// Spec `2026-11-04-lintel-main-window`, step 3.3: the HUD's model problems lead to `PluginContext.openModels`
/// (the speech model), the microphone problem to Settings; and the "in use" check the Formatting card uses today
/// is the one the Models pane gets through `modelUsage`.
@MainActor
@Suite struct DictationModelRoutingTests {
    @Test func theModelProblemsOpenModelsAndTheMicrophoneOpensSettings() {
        let model = HUDModel()
        var settings = 0
        var models = 0
        model.onOpenSettings = { settings += 1 }
        model.onOpenModels = { models += 1 }
        // The pill's one button of each problem, pressed the way the pill reports it.
        func press(_ state: HUDState) {
            guard let action = state.pill()?.action else {
                Issue.record("no button for \(state)")
                return
            }
            model.perform(action.id)
        }
        for problem in [HUDState.Problem.modelMissing, .modelUnavailable, .modelFailedToLoad] {
            let before = (settings, models)
            press(.problem(problem))
            #expect(settings == before.0 && models == before.1 + 1)
        }
        press(.problem(.microphoneDenied))
        #expect(settings == 1 && models == 3)
    }

    /// Dictation's "in use" sources, each with the token that must be in `modelUsage`'s `isInUse`. Only the Models
    /// pane removes a model (step 6.3b removed the Formatting card's Remove), and it asks `isInUse`.
    static let inUseSources: [(usage: ModelKind, usageToken: String)] = [(.llm, "builtInLLM.isInUse()")]

    @Test func todaysInUseSourcesAreWiredIntoModelUsage() throws {
        let harness = try DictationHarness()
        defer { harness.tearDown() }
        let plugin = DictationPlugin(context: harness.context)
        // The runtime the formatter loads is the one `modelUsage` asks.
        let formatting = try #require(Mirror(reflecting: plugin).descendant("formattingModel") as AnyObject?)
        let cardRuntime = try #require(Mirror(reflecting: formatting).descendant("runtime") as? KeepWarmRuntime)
        let usageRuntime = try #require(Mirror(reflecting: plugin).descendant("builtInLLM") as? KeepWarmRuntime)
        #expect(cardRuntime === usageRuntime)

        let plugins = try Self.read("Sources/DictationPlugin/DictationPlugin.swift")
        let usageBody = try #require(
            plugins.range(of: "public var modelUsage").map { String(plugins[$0.lowerBound...]) })
        for source in Self.inUseSources {
            #expect(usageBody.contains("isInUse: { await \(source.usageToken) }"), "\(source.usage)")
            #expect(plugin.modelUsage.contains { $0.kind == source.usage })
        }
    }

    private static let root: URL = {
        var url = URL(filePath: #filePath).deletingLastPathComponent()
        while url.path != "/", !FileManager.default.fileExists(atPath: url.appending(path: "Package.swift").path) {
            url = url.deletingLastPathComponent()
        }
        return url
    }()

    private static func read(_ path: String) throws -> String {
        try String(contentsOf: root.appending(path: path), encoding: .utf8)
    }
}
