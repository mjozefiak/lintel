import Foundation
import LintelKit
import LintelTestSupport
import Testing

@testable import DictationPlugin
@testable import LintelSpeech

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 1: the `cleanupLevel` key, the level that runs, the formatter
/// each level picks and the popup's two keys. Every sentence here is invented.
@MainActor
@Suite struct CleanupLevelSettingsTests {
    private func settings(_ values: [String: SettingValue] = [:]) -> (DictationSettings, MemorySettingsStore) {
        let store = MemorySettingsStore(values)
        return (DictationSettings(PluginSettings(pluginID: "dictation", store: store)), store)
    }

    @Test func aMissingOrUnknownLevelReadsAsStandard() {
        #expect(settings().0.cleanupLevel == .standard)
        #expect(settings(["plugins.dictation.cleanupLevel": .string("loud")]).0.cleanupLevel == .standard)
        #expect(settings(["plugins.dictation.cleanupLevel": .string("light")]).0.cleanupLevel == .light)
    }

    @Test func offHasNoEffectiveLevelWhateverTheStoredOne() {
        let (off, _) = settings(["plugins.dictation.cleanupLevel": .string("light")])
        #expect(off.mode == .raw)
        #expect(off.effectiveLevel == nil)
        #expect(!off.usesModel)
    }

    @Test func anExistingCleanupUserKeepsTodaysBehaviour() {
        let (existing, store) = settings(["plugins.dictation.mode": .string("cleanup")])
        #expect(existing.effectiveLevel == .standard)
        #expect(existing.usesModel)
        // Nothing is migrated: the level key is still absent.
        #expect(store.value(forKey: "plugins.dictation.cleanupLevel") == nil)
    }

    @Test func lightNeedsNoModelAndAStoredFullRunsAsStandard() {
        let (light, _) = settings([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("light"),
        ])
        #expect(light.effectiveLevel == .light)
        #expect(!light.usesModel)
        // A newer build wrote `full`; this one has no Full yet.
        let (full, _) = settings([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("full"),
        ])
        #expect(full.cleanupLevel == .full)
        #expect(full.effectiveLevel == .standard)
    }

    @Test func aBuildWithoutLevelsReadsOnlyTheModeKey() {
        // Rollback: the on/off choice survives, written to the key the older build reads.
        let (settings, store) = settings()
        settings.setCleanupLevel(.light)
        settings.setMode(.cleanup)
        #expect(settings.mode == .cleanup)
        #expect(store.value(forKey: "plugins.dictation.mode") == .string("cleanup"))
    }

    // MARK: The popup

    private func model(_ store: MemorySettingsStore) -> (FormattingSettingsModel, DictationSettings) {
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: store))
        return (
            FormattingSettingsModel(settings: settings, transport: ScriptedTransport(.failure(.cannotConnectToHost))),
            settings
        )
    }

    @Test func thePopupShowsTheStoredLevelAndAStoredFullAsStandard() {
        #expect(model(MemorySettingsStore()).0.choice == .off)
        #expect(model(MemorySettingsStore(["plugins.dictation.mode": .string("cleanup")])).0.choice == .standard)
        let light = MemorySettingsStore([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("light"),
        ])
        #expect(model(light).0.choice == .light)
        let full = MemorySettingsStore([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("full"),
        ])
        #expect(model(full).0.choice == .standard)
    }

    @Test func thePopupWritesBothKeysAndOffKeepsTheLevel() {
        let (model, settings) = model(MemorySettingsStore())
        model.choice = .light
        #expect(settings.mode == .cleanup)
        #expect(settings.cleanupLevel == .light)
        model.choice = .off
        #expect(settings.mode == .raw)
        // Turning it back on returns to the level it had.
        #expect(settings.cleanupLevel == .light)
        model.choice = .standard
        #expect(settings.mode == .cleanup)
        #expect(settings.cleanupLevel == .standard)
    }

    @Test func lightProbesNoServerAndOffersNoModelRows() async {
        let transport = ScriptedTransport(.failure(.cannotConnectToHost))
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore()))
        let model = FormattingSettingsModel(settings: settings, transport: transport)
        model.choice = .light
        await model.refresh()
        #expect(transport.requests.isEmpty)
        #expect(model.isCleanupOn)
        #expect(!model.usesModel)
    }

    @Test func standardLooksForServersAsBefore() async {
        let transport = ScriptedTransport(.failure(.cannotConnectToHost))
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore()))
        let model = FormattingSettingsModel(settings: settings, transport: transport)
        model.choice = .standard
        await model.refresh()
        #expect(!transport.requests.isEmpty)
        #expect(model.usesModel)
    }

    @Test func movingFromLightToStandardStartsTheLookForAModel() async {
        let transport = ScriptedTransport(.failure(.cannotConnectToHost))
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore()))
        let model = FormattingSettingsModel(settings: settings, transport: transport)
        model.choice = .light
        model.choice = .standard
        await pollUntil("a server request after switching to Standard") { !transport.requests.isEmpty }
        #expect(!transport.requests.isEmpty)
    }
}

/// What each level picks when a dictation starts, and that Light never reaches a model.
@Suite struct CleanupLevelFormatterTests {
    private func settings(_ values: [String: SettingValue] = [:]) -> DictationSettings {
        DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore(values)))
    }

    @Test func theHistoryModelIsNilForLightAndOffAndTheModelsNameAtStandard() {
        // Off and Light run no model, so nothing is recorded (empty column, never a fake name).
        #expect(DictationPlugin.formatterModel(settings: settings()) == nil)
        #expect(
            DictationPlugin.formatterModel(
                settings: settings([
                    "plugins.dictation.mode": .string("cleanup"),
                    "plugins.dictation.cleanupLevel": .string("light"),
                    "plugins.dictation.llmSource": .string("builtIn"),
                ])) == nil)
        // Standard records the model that ran: the built-in model's id, or the server's model name.
        #expect(
            DictationPlugin.formatterModel(
                settings: settings([
                    "plugins.dictation.mode": .string("cleanup"),
                    "plugins.dictation.llmSource": .string("builtIn"),
                ])) == LLMModelCatalog.defaultModel.id)
        #expect(
            DictationPlugin.formatterModel(
                settings: settings([
                    "plugins.dictation.mode": .string("cleanup"),
                    "plugins.dictation.llmSource": .string("server"),
                    "plugins.dictation.llmModel": .string("qwen"),
                ])) == "qwen")
    }

    private func pick(_ values: [String: SettingValue]) async -> (
        formatter: (any TextFormatter)?, transport: ScriptedTransport, runtime: ScriptedRuntime
    ) {
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore(values)))
        let transport = ScriptedTransport(.content("Zadzwonię jutro."))
        let runtime = ScriptedRuntime()
        await runtime.script(answer: "Zadzwonię jutro.")
        let warm = KeepWarmRuntime(
            runtime: runtime, modelURL: URL(fileURLWithPath: "/models/test.gguf"), keepWarm: { .seconds(60) })
        let formatter = DictationPlugin.formatter(
            settings: settings, transport: transport, builtIn: warm,
            logger: .init(subsystem: "com.lintelapp.tests", category: "dictation"))
        return (formatter, transport, runtime)
    }

    @Test func offHasNoFormatter() async {
        #expect(await pick([:]).formatter == nil)
        #expect(await pick(["plugins.dictation.cleanupLevel": .string("light")]).formatter == nil)
    }

    @Test(arguments: ["builtIn", "server"])
    func lightIsTheRulesWhateverTheSource(source: String) async throws {
        let picked = await pick([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("light"),
            "plugins.dictation.llmSource": .string(source),
            "plugins.dictation.llmEndpoint": .string("http://127.0.0.1:11434"),
            "plugins.dictation.llmModel": .string("qwen"),
        ])
        let formatter = try #require(picked.formatter)
        #expect(formatter is LightCleaner)
        // A whole dictation worth of calls: nothing reaches the server, the model or the lease.
        await formatter.prepare()
        let result = try await formatter.format(chunk: "Yyy, zadzwonię jutro.", previousContext: "Poprzednie zdanie.")
        #expect(result == FormatResult(text: "Zadzwonię jutro.", outcome: .formatted))
        #expect(picked.transport.requests.isEmpty)
        #expect(await picked.runtime.loads == 0)
        #expect(await picked.runtime.requests.isEmpty)
    }

    @Test func standardAndAStoredFullUseTheSourcesModel() async throws {
        for level in [nil, "standard", "full"] {
            var values: [String: SettingValue] = [
                "plugins.dictation.mode": .string("cleanup"),
                "plugins.dictation.llmSource": .string("builtIn"),
            ]
            if let level { values["plugins.dictation.cleanupLevel"] = .string(level) }
            #expect(try #require(await pick(values).formatter) is BuiltInFormatter)
            values["plugins.dictation.llmSource"] = .string("server")
            #expect(try #require(await pick(values).formatter) is LocalLLMFormatter)
        }
    }

    @Test func aLightSessionMakesNoCallToTheModelOrTheServer() async throws {
        let picked = await pick([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("light"),
            "plugins.dictation.llmSource": .string("builtIn"),
        ])
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 5),
            vad: RangeVAD([AudioFormat.sampleRate..<(2 * AudioFormat.sampleRate)]), engine: FillerEngine(),
            formatter: picked.formatter, modelFolder: URL(filePath: "/tmp/none"))
        try await session.start()
        try await Task.sleep(for: .milliseconds(100))
        let output = try await session.finish()
        #expect(output.rawText == "Eee, segment 1.")
        #expect(output.text == "Segment 1.")
        #expect(output.formatting.chunks == 1)
        #expect(output.formatting.fellBack == 0)
        #expect(picked.transport.requests.isEmpty)
        #expect(await picked.runtime.loads == 0)
        #expect(await picked.runtime.requests.isEmpty)
    }

    @Test func theVocabularyWordsAreProtectedWhileTheVocabularyIsOn() throws {
        let store = MemorySettingsStore()
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: store))
        let directory = FileManager.default.temporaryDirectory.appending(path: "lintel-light-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocabulary = VocabularyStore(directory: directory)
        try vocabulary.save([.init(term: "Eee", aliases: ["yhm system"])])
        let words = DictationPlugin.protectedWords(settings: settings, vocabulary: vocabulary)
        #expect(Set(words()) == ["Eee", "yhm system"])
        settings.setVocabularyEnabled(false)
        #expect(words().isEmpty)
    }
}

/// An engine whose every segment starts with a hesitation.
private final class FillerEngine: SpeechEngine, @unchecked Sendable {
    var isLoaded: Bool { true }
    func load(modelFolder: URL) async throws {}
    func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
        TranscriptSegment(text: "Eee, segment \(Int((samples.first ?? 0) * 100 + 0.5)).")
    }
    func unload() async {}
}
