import Foundation
import LintelKit
import LintelPersistence
import Testing

@testable import LintelApp

private final class LegacyDefaultsDouble: DefaultsAccess {
    private var values: [String: Any] = [:]
    func object(forKey defaultName: String) -> Any? { values[defaultName] }
    func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value }
}

/// The 2026-11-24 defaults (Dictation and Meetings on, Apps, Files and Clipboard off) and the one-time pin that keeps
/// every earlier install's switches as they were (`BACKWARD_COMPATIBILITY.md` §3).
@MainActor
@Suite struct PluginDefaultsMigrationTests {
    private static let newDefaults: [PluginID: Bool] = [
        "apps": false, "files": false, "clipboard": false, "dictation": true, "meetings": true, "notes": true,
        "windows": false,
    ]
    private static let oldDefaults: [PluginID: Bool] = [
        "apps": true, "files": true, "clipboard": true, "dictation": false, "meetings": false, "notes": true,
        "windows": false,
    ]

    private func enabled(_ host: PluginHost) -> [PluginID: Bool] {
        Dictionary(uniqueKeysWithValues: host.entries.map { ($0.manifest.id, host.isEnabled($0.manifest.id)) })
    }

    @Test func everyRegisteredPluginHasTheNewDefault() {
        let manifests = PluginRegistry.all.map { $0.manifest }
        #expect(Dictionary(uniqueKeysWithValues: manifests.map { ($0.id, $0.defaultEnabled) }) == Self.newDefaults)
    }

    @Test func theTableListsExactlyThePluginsWhoseDefaultFlipped() {
        let manifests = Dictionary(uniqueKeysWithValues: PluginRegistry.all.map { ($0.manifest.id, $0.manifest) })
        for entry in PluginDefaultsMigration.previousDefaults {
            #expect(manifests[entry.id]?.defaultEnabled == !entry.enabled, "\(entry.id) did not flip")
        }
        let flipped = Self.oldDefaults.filter { Self.newDefaults[$0.key] != $0.value }.map { $0.key }
        #expect(Set(PluginDefaultsMigration.previousDefaults.map { $0.id }) == Set(flipped))
    }

    @Test func aNewInstallGetsTheNewDefaultsAndOnlyTheMarker() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        #expect(PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: false) == .newInstall)
        #expect(env.settings.value(forKey: PluginDefaultsMigration.migratedKey) == .bool(true))
        for id in Self.newDefaults.keys {
            #expect(env.settings.value(forKey: SettingsKeys.pluginEnabled(id)) == nil)
        }
        #expect(enabled(env.makeHost(PluginRegistry.all)) == Self.newDefaults)
    }

    @Test func anOldInstallWithNothingStoredKeepsTheOldBehaviour() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        let outcome = PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true)
        #expect(outcome == .pinned(["apps", "files", "clipboard", "dictation", "meetings"]))
        #expect(enabled(env.makeHost(PluginRegistry.all)) == Self.oldDefaults)
    }

    @Test func aStoredChoiceIsNeverChanged() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        env.settings.setValue(.bool(false), forKey: SettingsKeys.pluginEnabled("apps"))
        env.settings.setValue(.bool(true), forKey: SettingsKeys.pluginEnabled("dictation"))
        let outcome = PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true)
        #expect(outcome == .pinned(["files", "clipboard", "meetings"]))
        var expected = Self.oldDefaults
        expected["apps"] = false
        expected["dictation"] = true
        #expect(enabled(env.makeHost(PluginRegistry.all)) == expected)
    }

    @Test func itRunsOnceSoANewInstallsSecondLaunchKeepsTheNewDefaults() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: false)
        // The second launch looks like an old install (the ranking file and the welcome answers exist now).
        #expect(PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true) == .alreadyMigrated)
        #expect(enabled(env.makeHost(PluginRegistry.all)) == Self.newDefaults)
    }

    @Test func anEarlierLaunchIsRecognisedByTheRankingFileOrTheWelcomeAnswers() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "lintel-defaults-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        func existing(_ settings: InMemorySettingsStore) -> Bool {
            PluginDefaultsMigration.isExistingInstall(dataRoot: root, settings: settings, fileManager: fileManager)
        }
        #expect(!existing(InMemorySettingsStore()))
        #expect(existing(InMemorySettingsStore([SettingsKeys.onboardingShortcutCompleted: .bool(true)])))
        let answered = InMemorySettingsStore([SettingsKeys.onboardingCompletedSteps: .stringArray(["files.access"])])
        #expect(existing(answered))
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        #expect(existing(InMemorySettingsStore()))
    }

    @Test func launchPinsBeforeTheRankingFileIsCreated() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "lintel-defaults-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        let fresh = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: fresh, fileManager: fileManager)
        #expect(fresh.value(forKey: SettingsKeys.pluginEnabled("apps")) == nil)
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        let old = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: old, fileManager: fileManager)
        #expect(old.value(forKey: SettingsKeys.pluginEnabled("apps")) == .bool(true))
        #expect(old.value(forKey: SettingsKeys.pluginEnabled("meetings")) == .bool(false))
    }

    /// `PluginHost.isEnabled` reads only a stored `Bool`, so a number or a string under the key (written by hand)
    /// meant the old default before the change and must mean it after.
    @Test func aStoredValueTheHostCannotReadIsPinnedLikeAMissingOne() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        env.settings.setValue(.integer(1), forKey: SettingsKeys.pluginEnabled("apps"))
        env.settings.setValue(.string("YES"), forKey: SettingsKeys.pluginEnabled("meetings"))
        #expect(enabled(env.makeHost(PluginRegistry.all))["apps"] == false, "the host ignores a stored number")
        let outcome = PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true)
        #expect(outcome == .pinned(["apps", "files", "clipboard", "dictation", "meetings"]))
        #expect(enabled(env.makeHost(PluginRegistry.all)) == Self.oldDefaults)
    }

    /// An install from the Pounce era: `LegacyDataMigration` moves its folder (with `ranking.sqlite`) and copies its
    /// settings first, so the pin sees an install that ran before and keeps a switch the user had stored.
    @Test func aPounceEraInstallIsAnExistingInstallAfterTheLegacyMove() throws {
        let fileManager = FileManager.default
        let support = fileManager.temporaryDirectory.appending(path: "lintel-defaults-\(UUID().uuidString)")
        let legacy = support.appending(path: LegacyDataMigration.legacyFolderName, directoryHint: .isDirectory)
        try fileManager.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: support) }
        try Data().write(to: legacy.appending(path: UsageRepository.fileName))
        let root = support.appending(path: LegacyDataMigration.currentFolderName, directoryHint: .isDirectory)
        #expect(LegacyDataMigration().migrateFolder(legacy: legacy, current: root) == .moved)
        // What `migrateDefaults` copied from the old domain: the user had switched Clipboard off.
        let settings = InMemorySettingsStore([SettingsKeys.pluginEnabled("clipboard"): .bool(false)])
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: settings, fileManager: fileManager)
        #expect(settings.value(forKey: SettingsKeys.pluginEnabled("apps")) == .bool(true))
        #expect(settings.value(forKey: SettingsKeys.pluginEnabled("files")) == .bool(true))
        #expect(settings.value(forKey: SettingsKeys.pluginEnabled("clipboard")) == .bool(false))
        #expect(settings.value(forKey: SettingsKeys.pluginEnabled("dictation")) == .bool(false))
        #expect(settings.value(forKey: SettingsKeys.pluginEnabled("meetings")) == .bool(false))
    }

    /// When the folder could not be moved, the copied welcome answers alone still mark the install as an old one.
    @Test func aPounceEraInstallWhoseFolderDidNotMoveIsRecognisedByItsCopiedSettings() throws {
        let defaults = LegacyDefaultsDouble()
        LegacyDataMigration().migrateDefaults(
            legacy: [SettingsKeys.onboardingShortcutCompleted: true, "unrelated": 1], into: defaults)
        let copied = UserDefaultsSettingsStore.settingValue(
            from: defaults.object(forKey: SettingsKeys.onboardingShortcutCompleted))
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "lintel-defaults-\(UUID().uuidString)")
        let settings = InMemorySettingsStore([SettingsKeys.onboardingShortcutCompleted: try #require(copied)])
        #expect(defaults.object(forKey: "unrelated") == nil)
        #expect(PluginDefaultsMigration.isExistingInstall(dataRoot: root, settings: settings, fileManager: fileManager))
    }

    /// The order in both launch paths is the invariant the pin depends on: after the legacy move and copy, before
    /// `openRanking` creates the ranking file. A source scan, because `live()` works on the real folders.
    @Test func bothLaunchPathsPinAfterTheLegacyMoveAndBeforeTheRankingFileIsOpened() throws {
        let file = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/LintelApp/AppEnvironment.swift")
        let source = try String(contentsOf: file, encoding: .utf8)
        func body(from start: String, to end: String) throws -> Substring {
            let from = try #require(source.range(of: start))
            let until = try #require(source.range(of: end, range: from.upperBound..<source.endIndex))
            return source[from.lowerBound..<until.lowerBound]
        }
        func position(_ text: String, in body: Substring) throws -> Substring.Index {
            try #require(body.range(of: text), "\(text) is missing").lowerBound
        }
        let live = try body(from: "static func live(", to: "static func qa(")
        let legacy = try position("LegacyDataMigration(fileManager: fileManager).run(", in: live)
        let livePin = try position("pinPreviousPluginDefaults(", in: live)
        let liveRanking = try position("openRanking(in: root)", in: live)
        #expect(legacy < livePin && livePin < liveRanking)
        let qa = try body(from: "static func qa(", to: "static func qaFileIndexSettings(")
        #expect(try position("pinPreviousPluginDefaults(", in: qa) < position("openRanking(in: root)", in: qa))
    }

    /// QA settings are in memory unless the run keeps them, so a second run on the same data root is still a new
    /// install; with `--qa-persistent-settings` a data root that ran before is an old one.
    @Test func aQARunIsAnOldInstallOnlyWhenItKeepsItsSettings() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appending(path: "lintel-defaults-\(UUID().uuidString)")
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        let volatile = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(
            dataRoot: root, settings: volatile, fileManager: fileManager, settingsPersist: false)
        #expect(volatile.value(forKey: SettingsKeys.pluginEnabled("apps")) == nil)
        #expect(volatile.value(forKey: PluginDefaultsMigration.migratedKey) == .bool(true))
        let kept = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(
            dataRoot: root, settings: kept, fileManager: fileManager, settingsPersist: true)
        #expect(kept.value(forKey: SettingsKeys.pluginEnabled("apps")) == .bool(true))
    }

    /// The welcome screen shows the steps of the enabled plugins and the Shortcut page only while one of them searches
    /// (`AppCoordinator` hands it the active ones): on a new install the core steps without the Shortcut page and
    /// without the Full Disk Access step, on an old install the old pages.
    private func welcomePages(_ env: TestEnvironment) -> [String] {
        let host = env.makeHost(PluginRegistry.all)
        let enabled = host.entries.filter { host.isEnabled($0.manifest.id) }.map { $0.plugin }
        let steps = enabled.flatMap { $0.onboardingSteps }
        let hotkeys = HotkeyService(registrar: InMemoryHotkeyRegistrar(), settings: env.settings, readOccupied: { [] })
        let controller = OnboardingController(hotkeys: hotkeys, settings: AppSettings(store: env.settings)) { steps }
        controller.activatesApp = false
        let searches = enabled.contains { !$0.searchSources.isEmpty }
        controller.launcherIsActive = { searches }
        return controller.pendingPages.map { $0.id }
    }

    @Test func aNewInstallsWelcomeScreenShowsTheCoreStepsWithoutTheShortcutOrFullDiskAccess() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: false)
        #expect(welcomePages(env) == ["intro", "dictation.setup", "meetings.setup", "done"])
    }

    @Test func anOldInstallStillGetsTheStepsOfItsOldPlugins() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true)
        #expect(welcomePages(env) == ["intro", "shortcut", "files.fullDiskAccess", "clipboard.intro", "done"])
    }
}
