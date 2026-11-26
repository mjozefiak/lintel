import Foundation
import LintelKit
import LintelProviders
import Testing

@testable import DictationPlugin

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 5: the `provider` source, its two keys and the source × level
/// table. Every value here is invented.
@MainActor
@Suite struct ProviderSourceSettingsTests {
    private static let sonnet = DictationSettings.ProviderSelection(provider: .claudeCode, model: "sonnet")

    private func settings(_ values: [String: SettingValue] = [:]) -> DictationSettings {
        DictationSettings(
            PluginSettings(pluginID: "dictation", store: MemorySettingsStore(values)), offersFull: true)
    }

    private func chosen(
        source: String = "provider", model: String? = "sonnet", server: Bool = false
    ) -> DictationSettings {
        var values: [String: SettingValue] = [
            "plugins.dictation.mode": .string("cleanup"),
            "plugins.dictation.llmSource": .string(source),
            "plugins.dictation.provider": .string("claude-code"),
        ]
        if let model { values["plugins.dictation.providerModel"] = .string(model) }
        if server {
            values["plugins.dictation.llmEndpoint"] = .string("http://127.0.0.1:11434")
            values["plugins.dictation.llmModel"] = .string("qwen")
        }
        return settings(values)
    }

    // MARK: The two keys

    @Test func noProviderIsChosenByDefault() {
        #expect(settings().providerSelection == nil)
        #expect(settings(["plugins.dictation.llmSource": .string("provider")]).llmSource == .provider)
    }

    @Test func aChosenProviderWithoutAModelUsesTheDescriptorsDefault() throws {
        let selection = try #require(chosen(model: nil).providerSelection)
        #expect(selection == Self.sonnet)
        #expect(selection.historyMark == "cli:claude-code/sonnet")
        #expect(chosen(model: "").providerSelection == Self.sonnet)
    }

    @Test func theOtherListedModelsAreChosenAsTheyAre() throws {
        let opus = try #require(chosen(model: "opus").providerSelection)
        #expect(opus.historyMark == "cli:claude-code/opus")
        #expect(chosen(model: "fable").providerSelection?.model == "fable")
    }

    @Test func aModelThePickerDoesNotOfferIsNotChosen() {
        // Haiku is hidden (not measured) and a typed id is never a guess.
        #expect(chosen(model: "haiku").providerSelection == nil)
        #expect(chosen(model: "claude-3-opus").providerSelection == nil)
        #expect(chosen(model: "--dangerously-skip-permissions").providerSelection == nil)
    }

    @Test func anUnknownProviderIsNotChosen() {
        #expect(
            settings([
                "plugins.dictation.provider": .string("other-cli"),
                "plugins.dictation.providerModel": .string("sonnet"),
            ]).providerSelection == nil)
        #expect(settings(["plugins.dictation.provider": .string("")]).providerSelection == nil)
    }

    @Test func settingAndClearingTheProviderWritesBothKeysAndOnlyThose() {
        let store = MemorySettingsStore()
        let dictation = DictationSettings(PluginSettings(pluginID: "dictation", store: store))
        dictation.setProvider(.init(provider: .claudeCode, model: "opus"))
        #expect(store.value(forKey: "plugins.dictation.provider") == .string("claude-code"))
        #expect(store.value(forKey: "plugins.dictation.providerModel") == .string("opus"))
        #expect(dictation.providerSelection?.model == "opus")
        // The source is a separate key: choosing the provider is the pane's job, not this setter's.
        #expect(store.value(forKey: "plugins.dictation.llmSource") == nil)
        dictation.clearProvider()
        #expect(store.value(forKey: "plugins.dictation.provider") == nil)
        #expect(store.value(forKey: "plugins.dictation.providerModel") == nil)
        #expect(dictation.providerSelection == nil)
    }

    @Test func theProviderIsNotInheritedFromMeetings() {
        let dictation = settings([
            "plugins.meetings.notesProvider": .string("claude-code"),
            "plugins.meetings.notesProviderModel": .string("opus"),
        ])
        #expect(dictation.providerSelection == nil)
    }

    // MARK: Source × level

    /// The whole table, one row per source and level, with both levels offered (the shipped constant).
    @Test func theSourceByLevelTable() throws {
        let selection = Self.sonnet
        // (source, server set, built-in installed, level) -> the source that runs
        let rows: [(String, Bool, Bool, DictationSettings.CleanupLevel, DictationSettings.EffectiveSource)] = [
            ("builtIn", false, true, .light, .none),
            ("builtIn", false, true, .standard, .builtIn),
            ("builtIn", false, false, .full, .builtIn),
            ("server", true, false, .light, .none),
            ("server", true, false, .standard, .server),
            ("server", true, true, .full, .server),
            ("provider", false, false, .light, .none),
            ("provider", false, false, .standard, .provider(selection)),
            ("provider", true, true, .full, .provider(selection)),
        ]
        for (source, server, installed, level, expected) in rows {
            let dictation = chosen(source: source, server: server)
            #expect(
                dictation.effectiveSource(for: level, builtInInstalled: installed) == expected,
                "\(source) at \(level)")
        }
    }

    @Test func aLevelTheProviderDoesNotServeRunsLocallyAndTheChoiceStays() throws {
        let onlyStandard: Set<DictationSettings.CleanupLevel> = [.standard]
        // Full falls back to the built-in model when it is installed, ...
        #expect(
            chosen(server: true).effectiveSource(for: .full, builtInInstalled: true, offered: onlyStandard)
                == .builtIn)
        // ... else to the user's server, ...
        #expect(
            chosen(server: true).effectiveSource(for: .full, builtInInstalled: false, offered: onlyStandard)
                == .server)
        // ... else nothing runs (the text is pasted as heard).
        #expect(
            chosen().effectiveSource(for: .full, builtInInstalled: false, offered: onlyStandard) == .none)
        // The level the provider serves still goes out.
        #expect(
            chosen().effectiveSource(for: .standard, builtInInstalled: true, offered: onlyStandard)
                == .provider(Self.sonnet))
        // Nothing is rewritten: the stored source is still the provider.
        let dictation = chosen(server: true)
        _ = dictation.effectiveSource(for: .full, builtInInstalled: true, offered: onlyStandard)
        #expect(dictation.llmSource == .provider)
    }

    @Test func aProviderSourceWithoutAUsableChoiceRunsLocallyAtEveryLevel() {
        // The stored source says provider, but no provider (or a model that is not offered) is chosen.
        let none = settings([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.llmSource": .string("provider"),
        ])
        #expect(none.effectiveSource(for: .standard, builtInInstalled: true) == .builtIn)
        #expect(none.effectiveSource(for: .standard, builtInInstalled: false) == .none)
        let haiku = chosen(model: "haiku", server: true)
        #expect(haiku.effectiveSource(for: .standard, builtInInstalled: false) == .server)
    }

    @Test func theShippedConstantOffersStandardAndFullButNotLight() {
        #expect(ProviderLevels.offered == [.standard, .full])
        #expect(!ProviderLevels.offered.contains(.light))
    }

    @Test func theReleaseLimitsAreFourAndSixSecondsAndLocalSourcesHaveNone() {
        #expect(ProviderLevels.releaseDeadline(for: .standard) == .seconds(4))
        #expect(ProviderLevels.releaseDeadline(for: .full) == .seconds(6))
        #expect(ProviderLevels.releaseDeadline(for: .light) == nil)
    }

    // MARK: The pieces the rest of the plugin reads

    @Test func theHistoryRecordsTheProviderMarkOrTheLocalModelThatRan() {
        #expect(
            DictationPlugin.formatterModel(settings: chosen(model: "opus"), builtInInstalled: true)
                == "cli:claude-code/opus")
        // The stored source is the provider, but Light runs no model.
        let light = settings([
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string("light"),
            "plugins.dictation.llmSource": .string("provider"), "plugins.dictation.provider": .string("claude-code"),
        ])
        #expect(DictationPlugin.formatterModel(settings: light, builtInInstalled: true) == nil)
    }

    @Test func aReleaseDeadlineOnlyForTheProviderAtAnOfferedLevel() {
        #expect(DictationPlugin.releaseDeadline(settings: chosen(), builtInInstalled: true) == .seconds(4))
        #expect(
            DictationPlugin.releaseDeadline(
                settings: settings([
                    "plugins.dictation.mode": .string("cleanup"),
                    "plugins.dictation.cleanupLevel": .string("full"),
                    "plugins.dictation.llmSource": .string("provider"),
                    "plugins.dictation.provider": .string("claude-code"),
                ]), builtInInstalled: true) == .seconds(6))
        #expect(
            DictationPlugin.releaseDeadline(settings: chosen(source: "builtIn"), builtInInstalled: true) == nil)
        #expect(
            DictationPlugin.releaseDeadline(settings: chosen(source: "server", server: true), builtInInstalled: true)
                == nil)
    }
}

/// The history keeps `cli:<provider>/<model>` for a dictation tidied by a provider; Notes shows where the text went.
@Suite struct ProviderHistoryMarkTests {
    @Test func theNotesDetailNamesTheCompanyAndTheModel() {
        #expect(DictationNoteMapping.providerDetail("cli:claude-code/sonnet") == "Claude · sonnet")
        #expect(DictationNoteMapping.providerDetail("cli:claude-code/opus") == "Claude · opus")
    }

    @Test func aLocalModelOrAnUnknownMarkIsNotAProviderDetail() {
        #expect(DictationNoteMapping.providerDetail("qwen2.5-7b") == nil)
        #expect(DictationNoteMapping.providerDetail("cli:other-cli/x") == nil)
        #expect(DictationNoteMapping.providerDetail("cli:claude-code") == nil)
        #expect(DictationNoteMapping.providerDetail("") == nil)
    }
}
