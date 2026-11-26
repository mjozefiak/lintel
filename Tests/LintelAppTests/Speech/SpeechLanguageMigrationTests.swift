import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// Spec `2026-11-23-automatic-language-detection`, Data Model and step 2.3: the one-time move of
/// `plugins.meetings.speechLanguage` and `plugins.dictation.speechLanguage` into `app.speech.languages`.
@Suite struct SpeechLanguageMigrationTests {
    private static let meetings = SpeechLanguageMigration.meetingsLanguageKey
    private static let dictation = SpeechLanguageMigration.dictationLanguageKey
    private static let marker = SettingsKeys.speechLegacyLanguageMigrated

    private func run(
        _ store: InMemorySettingsStore, preferred: [String] = ["de-DE", "en-US"]
    ) -> SpeechLanguageMigration.Outcome {
        SpeechLanguageMigration.run(settings: store, preferredLanguages: { preferred })
    }

    private func current(_ store: InMemorySettingsStore, preferred: [String] = ["de-DE", "en-US"])
        -> SpeechLanguageSelection
    {
        HostSpeechLanguageSettings(store: store, hub: SpeechLanguageChangeHub(), preferredLanguages: { preferred })
            .current()
    }

    /// The old keys stay out of the rest of the app: the plugins' settings types no longer declare them.
    @Test func theOldKeysAreThePluginsFormerKeys() {
        #expect(Self.meetings == "plugins.meetings.speechLanguage")
        #expect(Self.dictation == "plugins.dictation.speechLanguage")
        #expect(Self.marker == "app.speech.legacyLanguageMigrated")
    }

    @Test func aSetMarkerChangesNothing() {
        let store = InMemorySettingsStore([
            Self.marker: .bool(true), Self.meetings: .string("en"), Self.dictation: .string("pl"),
        ])
        #expect(run(store) == .alreadyMigrated)
        #expect(store.value(forKey: Self.meetings) == .string("en"))
        #expect(store.value(forKey: Self.dictation) == .string("pl"))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == nil)
    }

    @Test func aFreshInstallGetsOnlyTheMarkerAndStaysDerivedAndAutomatic() {
        let store = InMemorySettingsStore()
        #expect(run(store) == .nothingToMove)
        #expect(store.value(forKey: Self.marker) == .bool(true))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == nil)
        #expect(store.value(forKey: SettingsKeys.speechLanguageMode) == nil)
        #expect(current(store) == SpeechLanguageSelection(mode: .automatic, languages: ["de", "en"], isDerived: true))
    }

    @Test(arguments: [SpeechLanguageMigration.meetingsLanguageKey, SpeechLanguageMigration.dictationLanguageKey])
    func oneKeyComesFirstThenTheMacsLanguages(_ key: String) {
        let store = InMemorySettingsStore([key: .string("en")])
        #expect(run(store, preferred: ["de-DE", "en-GB", "fr"]) == .moved(["en", "de", "fr"]))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["en", "de", "fr"]))
        #expect(store.value(forKey: Self.meetings) == nil)
        #expect(store.value(forKey: Self.dictation) == nil)
        #expect(store.value(forKey: Self.marker) == .bool(true))
        // The mode is not written (D1): a former Whisper pin is a prior, not a pin.
        #expect(store.value(forKey: SettingsKeys.speechLanguageMode) == nil)
        #expect(current(store).mode == .automatic)
        #expect(!current(store).isDerived)
    }

    @Test func bothKeysEqualGiveOneEntry() {
        let store = InMemorySettingsStore([Self.meetings: .string("pl"), Self.dictation: .string("pl")])
        #expect(run(store, preferred: ["en-US"]) == .moved(["pl", "en"]))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["pl", "en"]))
    }

    @Test func bothKeysDifferentPutMeetingsFirst() {
        let store = InMemorySettingsStore([Self.meetings: .string("en"), Self.dictation: .string("pl")])
        #expect(run(store, preferred: ["pl-PL", "uk"]) == .moved(["en", "pl", "uk"]))
        #expect(store.value(forKey: Self.meetings) == nil)
        #expect(store.value(forKey: Self.dictation) == nil)
    }

    @Test func theListIsCappedAtTen() {
        let store = InMemorySettingsStore([Self.meetings: .string("en"), Self.dictation: .string("pl")])
        let preferred = ["de", "fr", "es", "it", "pt", "nl", "sv", "da", "fi", "cs", "sk"]
        guard case .moved(let languages) = run(store, preferred: preferred) else {
            Issue.record("nothing moved")
            return
        }
        #expect(languages == ["en", "pl", "de", "fr", "es", "it", "pt", "nl", "sv", "da"])
    }

    /// A Mac whose languages the catalog does not list derives English, which then is not repeated.
    @Test func theDerivedEnglishIsNotRepeated() {
        let store = InMemorySettingsStore([Self.meetings: .string("en")])
        #expect(run(store, preferred: ["xx-YY"]) == .moved(["en"]))
    }

    @Test func aListTheUserAlreadyHasWinsAndTheOldKeysAreStillRemoved() {
        let store = InMemorySettingsStore([
            Self.meetings: .string("en"), Self.dictation: .string("pl"),
            SettingsKeys.speechLanguages: .stringArray(["uk", "de"]),
        ])
        #expect(run(store) == .listAlreadyPresent)
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["uk", "de"]))
        #expect(store.value(forKey: Self.meetings) == nil)
        #expect(store.value(forKey: Self.dictation) == nil)
        #expect(store.value(forKey: Self.marker) == .bool(true))
    }

    /// A stored list the host reads as derived (empty, or nothing in the catalog) is not the user's own list.
    @Test(arguments: [SettingValue.stringArray([]), .stringArray(["xx"]), .string("pl")])
    func aListTheHostCannotReadIsReplaced(_ value: SettingValue) {
        let store = InMemorySettingsStore([Self.meetings: .string("pl"), SettingsKeys.speechLanguages: value])
        #expect(run(store, preferred: ["en"]) == .moved(["pl", "en"]))
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == .stringArray(["pl", "en"]))
    }

    /// Nothing else wrote the old keys, but a value set by hand that is not a catalog code carried no choice
    /// (the plugins read it as `pl`): it is removed without becoming a language.
    @Test(arguments: [SettingValue.string("auto"), .string(""), .integer(1), .stringArray(["en"])])
    func aValueThatIsNoLanguageIsRemovedAndNotMoved(_ value: SettingValue) {
        let store = InMemorySettingsStore([Self.meetings: value])
        #expect(run(store) == .nothingToMove)
        #expect(store.value(forKey: Self.meetings) == nil)
        #expect(store.value(forKey: SettingsKeys.speechLanguages) == nil)
        #expect(store.value(forKey: Self.marker) == .bool(true))
    }

    /// Rollback and upgrade again (spec Data Model): a value an older build writes after the marker is set is
    /// never migrated; it stays an unread key and the shared list the user has wins.
    @Test func aKeyWrittenByAnOlderBuildAfterTheMarkerStaysUnread() {
        let store = InMemorySettingsStore([Self.meetings: .string("pl")])
        #expect(run(store, preferred: ["en"]) == .moved(["pl", "en"]))
        // The older build writes its language again.
        store.setValue(.string("en"), forKey: Self.meetings)
        store.setValue(.string("en"), forKey: Self.dictation)
        #expect(run(store, preferred: ["en"]) == .alreadyMigrated)
        #expect(store.value(forKey: Self.meetings) == .string("en"))
        #expect(store.value(forKey: Self.dictation) == .string("en"))
        #expect(current(store).languages == ["pl", "en"])
    }

    /// Wired into the launch: `pinPreviousPluginDefaults` runs it on a new install too.
    @MainActor
    @Test func theLaunchRunsIt() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: "lintel-speech-migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemorySettingsStore([Self.dictation: .string("en")])
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: store, fileManager: .default)
        #expect(store.value(forKey: Self.marker) == .bool(true))
        #expect(store.value(forKey: Self.dictation) == nil)
        guard case .stringArray(let languages) = store.value(forKey: SettingsKeys.speechLanguages) else {
            Issue.record("no list written")
            return
        }
        #expect(languages.first == "en")
    }
}
