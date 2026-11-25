import AppKit
import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// Spec `2026-11-23-automatic-language-detection`, step 2.1: `HostSpeechLanguageSettings` over `app.speech.*`.
@Suite struct HostSpeechLanguageSettingsTests {
    private func settings(
        _ values: [String: SettingValue] = [:], preferred: [String] = ["pl-PL", "en-US"]
    ) -> (HostSpeechLanguageSettings, InMemorySettingsStore) {
        let store = InMemorySettingsStore(values)
        return (
            HostSpeechLanguageSettings(store: store, hub: SpeechLanguageChangeHub(), preferredLanguages: { preferred }),
            store
        )
    }

    private static let keys = [
        SettingsKeys.speechLanguageMode, SettingsKeys.speechLanguages, SettingsKeys.speechSingleLanguage,
        SettingsKeys.speechLegacyLanguageMigrated,
    ]

    @Test func theKeysHaveTheirSpecNames() {
        #expect(
            Self.keys == [
                "app.speech.languageMode", "app.speech.languages", "app.speech.singleLanguage",
                "app.speech.legacyLanguageMigrated",
            ])
    }

    // MARK: Derived list

    @Test func aFreshInstallReadsTheMacsLanguagesAndWritesNothing() {
        let (host, store) = settings()
        #expect(host.current() == SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true))
        for key in Self.keys {
            #expect(store.value(forKey: key) == nil, "\(key) was written by a read")
        }
    }

    @Test func theDerivedListKeepsTheLanguageSubtagAliasesAndOrderWithoutDuplicates() {
        let derived = HostSpeechLanguageSettings.derivedLanguages(from: [
            "zh-Hans-CN", "nb-NO", "en-GB", "nn", "en-US", "pl_PL",
        ])
        #expect(derived == ["zh", "no", "en", "pl"])
    }

    @Test func theDerivedListDropsLanguagesOutsideTheCatalog() {
        #expect(HostSpeechLanguageSettings.derivedLanguages(from: ["xx-YY", "de-CH", "qaa"]) == ["de"])
    }

    @Test func theDerivedListIsEnglishWhenNothingMatches() {
        #expect(HostSpeechLanguageSettings.derivedLanguages(from: []) == ["en"])
        #expect(HostSpeechLanguageSettings.derivedLanguages(from: ["xx", "qaa-Latn"]) == ["en"])
    }

    @Test func theDerivedListIsCappedAtTen() {
        let preferred = ["en", "de", "fr", "es", "it", "pt", "nl", "sv", "pl", "cs", "uk", "ru"]
        #expect(HostSpeechLanguageSettings.derivedLanguages(from: preferred) == Array(preferred.prefix(10)))
    }

    // MARK: Validation on read

    @Test func unknownStoredCodesAreDroppedDuplicatesRemovedAndTheListCapped() {
        let stored = ["pl", "xx", "en", "pl", "uk", "de", "fr", "es", "it", "pt", "nl", "sv", "cs"]
        let (host, _) = settings([SettingsKeys.speechLanguages: .stringArray(stored)])
        let selection = host.current()
        #expect(selection.languages == ["pl", "en", "uk", "de", "fr", "es", "it", "pt", "nl", "sv"])
        #expect(selection.isDerived == false)
    }

    @Test func anEmptyStoredListReadsAsDerived() {
        let (host, _) = settings([SettingsKeys.speechLanguages: .stringArray([])], preferred: ["uk-UA"])
        #expect(host.current() == SpeechLanguageSelection(mode: .automatic, languages: ["uk"], isDerived: true))
    }

    @Test func aStoredListOfOnlyUnknownCodesReadsAsDerived() {
        let (host, _) = settings([SettingsKeys.speechLanguages: .stringArray(["xx", "pl-PL"])], preferred: ["de"])
        #expect(host.current() == SpeechLanguageSelection(mode: .automatic, languages: ["de"], isDerived: true))
    }

    @Test func aStoredValueOfAnotherTypeReadsAsDerived() {
        let (host, _) = settings([SettingsKeys.speechLanguages: .string("pl")], preferred: ["en"])
        #expect(host.current().isDerived)
        #expect(host.current().languages == ["en"])
    }

    @Test func anUnknownModeReadsAsAutomatic() {
        for value: SettingValue in [.string("pinned"), .string(""), .bool(true), .string("Single")] {
            let (host, _) = settings([
                SettingsKeys.speechLanguageMode: value, SettingsKeys.speechSingleLanguage: .string("pl"),
            ])
            #expect(host.current().mode == .automatic)
        }
    }

    @Test func singleModeReadsTheStoredLanguage() {
        let (host, _) = settings([
            SettingsKeys.speechLanguageMode: .string("single"), SettingsKeys.speechSingleLanguage: .string("uk"),
            SettingsKeys.speechLanguages: .stringArray(["pl", "uk"]),
        ])
        #expect(
            host.current() == SpeechLanguageSelection(mode: .single("uk"), languages: ["pl", "uk"], isDerived: false))
    }

    @Test func singleModeWithAnUnknownOrMissingLanguageFallsBackToTheFirstListedLanguage() {
        let (unknown, _) = settings([
            SettingsKeys.speechLanguageMode: .string("single"), SettingsKeys.speechSingleLanguage: .string("xx"),
            SettingsKeys.speechLanguages: .stringArray(["uk", "pl"]),
        ])
        #expect(unknown.current().mode == .single("uk"))
        let (missing, _) = settings([SettingsKeys.speechLanguageMode: .string("single")], preferred: ["de-DE"])
        #expect(missing.current().mode == .single("de"))
    }

    // MARK: Update

    @Test func anEditedListIsStoredValidated() {
        let (host, store) = settings()
        host.update(SpeechLanguageSelection(mode: .automatic, languages: ["uk", "xx", "uk", "pl"], isDerived: false))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["uk", "pl"]))
        #expect(store.value(forKey: SettingsKeys.speechLanguageMode) == .string("auto"))
        #expect(host.current() == SpeechLanguageSelection(mode: .automatic, languages: ["uk", "pl"], isDerived: false))
    }

    @Test func anUpdateStoresAtMostTenLanguages() {
        let (host, store) = settings()
        let many = ["en", "de", "fr", "es", "it", "pt", "nl", "sv", "pl", "cs", "uk", "ru"]
        host.update(SpeechLanguageSelection(mode: .automatic, languages: many, isDerived: false))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(Array(many.prefix(10))))
    }

    @Test func aDerivedOrEmptyListRemovesTheStoredOne() {
        for selection in [
            SpeechLanguageSelection(mode: .automatic, languages: ["pl"], isDerived: true),
            SpeechLanguageSelection(mode: .automatic, languages: [], isDerived: false),
            SpeechLanguageSelection(mode: .automatic, languages: ["xx"], isDerived: false),
        ] {
            let (host, store) = settings([SettingsKeys.speechLanguages: .stringArray(["uk"])], preferred: ["de"])
            host.update(selection)
            #expect(store.value(forKey: SettingsKeys.speechLanguages) == nil)
            #expect(host.current() == SpeechLanguageSelection(mode: .automatic, languages: ["de"], isDerived: true))
        }
    }

    @Test func singleModeStoresTheModeAndTheLanguage() {
        let (host, store) = settings()
        host.update(SpeechLanguageSelection(mode: .single("en"), languages: ["pl", "en"], isDerived: true))
        #expect(store.value(forKey: SettingsKeys.speechLanguageMode) == .string("single"))
        #expect(store.value(forKey: SettingsKeys.speechSingleLanguage) == .string("en"))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == nil)
        #expect(
            host.current() == SpeechLanguageSelection(mode: .single("en"), languages: ["pl", "en"], isDerived: true))
    }

    @Test func singleModeWithAnUnknownLanguageStoresNoLanguage() {
        let (host, store) = settings([SettingsKeys.speechSingleLanguage: .string("pl")])
        host.update(SpeechLanguageSelection(mode: .single("xx"), languages: ["uk", "pl"], isDerived: false))
        #expect(store.value(forKey: SettingsKeys.speechSingleLanguage) == nil)
        #expect(host.current().mode == .single("uk"))
    }

    @Test func goingBackToAutomaticKeepsTheSingleLanguageForLater() {
        let (host, store) = settings([
            SettingsKeys.speechLanguageMode: .string("single"), SettingsKeys.speechSingleLanguage: .string("en"),
        ])
        host.update(SpeechLanguageSelection(mode: .automatic, languages: ["pl", "en"], isDerived: true))
        #expect(host.current().mode == .automatic)
        #expect(store.value(forKey: SettingsKeys.speechSingleLanguage) == .string("en"))
    }

    // MARK: Changes

    @Test func everyReadOfChangesIsANewStreamAndBothConsumersAreNotified() async {
        let hub = SpeechLanguageChangeHub()
        let host = HostSpeechLanguageSettings(store: InMemorySettingsStore(), hub: hub, preferredLanguages: { ["en"] })
        var first = host.changes.makeAsyncIterator()
        var second = host.changes.makeAsyncIterator()
        #expect(hub.streamCount == 2)
        host.update(SpeechLanguageSelection(mode: .automatic, languages: ["pl"], isDerived: false))
        #expect(await first.next() != nil)
        #expect(await second.next() != nil)
    }

    @Test func anUpdateThatChangesNothingDoesNotNotify() async {
        let hub = SpeechLanguageChangeHub()
        let host = HostSpeechLanguageSettings(store: InMemorySettingsStore(), hub: hub, preferredLanguages: { ["en"] })
        let stream = host.changes
        host.update(host.current())
        // A signal in the buffer would be returned even after the cancel; without one the stream ends with `nil`.
        let pending = Task {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        pending.cancel()
        #expect(await pending.value == nil)
    }

    @Test func aFinishedConsumerIsForgotten() async {
        let hub = SpeechLanguageChangeHub()
        let host = HostSpeechLanguageSettings(store: InMemorySettingsStore(), hub: hub, preferredLanguages: { ["en"] })
        let stream = host.changes
        #expect(hub.streamCount == 1)
        let task = Task {
            for await _ in stream {}
        }
        task.cancel()
        await task.value
        #expect(hub.streamCount == 0)
    }

    // MARK: Wiring

    @MainActor @Test func everyPluginContextSharesTheOneSetting() async throws {
        let name = "lintel-speech-languages-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.appending(path: name, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = AppEnvironment(
            dataRoot: root,
            cachesRoot: root.appending(path: "Caches", directoryHint: .isDirectory),
            settings: InMemorySettingsStore(),
            keychain: InMemoryKeychainClient(),
            pasteboardName: NSPasteboard.Name(name),
            usage: InMemoryUsageRecorder(),
            registersGlobalHotkeys: false
        )
        let manifests = PluginRegistry.all.map { $0.manifest }
        let dictation = try #require(manifests.first { $0.id == "dictation" })
        let meetings = try #require(manifests.first { $0.id == "meetings" })
        let dictationContext = environment.makeContext(for: dictation)
        let meetingsContext = environment.makeContext(for: meetings)
        var listener = dictationContext.speechLanguages.changes.makeAsyncIterator()

        meetingsContext.speechLanguages.update(
            SpeechLanguageSelection(mode: .single("uk"), languages: ["uk", "pl"], isDerived: false))

        #expect(await listener.next() != nil)
        #expect(
            dictationContext.speechLanguages.current()
                == SpeechLanguageSelection(mode: .single("uk"), languages: ["uk", "pl"], isDerived: false))
        #expect(environment.settings.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["uk", "pl"]))
    }
}
