import Foundation
import LintelKit
import LintelPersistence
import Testing

@testable import LintelApp

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
    /// The welcome screen shows the steps of the enabled plugins (`AppCoordinator` hands it the active ones): the core
    /// steps on a new install, no Full Disk Access step while Files is off, and the old steps on an old install.
    private func welcomePages(_ env: TestEnvironment) -> [String] {
        let host = env.makeHost(PluginRegistry.all)
        let steps = host.entries.filter { host.isEnabled($0.manifest.id) }.flatMap { $0.plugin.onboardingSteps }
        let hotkeys = HotkeyService(registrar: InMemoryHotkeyRegistrar(), settings: env.settings, readOccupied: { [] })
        let controller = OnboardingController(hotkeys: hotkeys, settings: AppSettings(store: env.settings)) { steps }
        controller.activatesApp = false
        return controller.pendingPages.map { $0.id }
    }

    @Test func aNewInstallsWelcomeScreenShowsTheCoreStepsAndNoFullDiskAccess() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: false)
        #expect(welcomePages(env) == ["intro", "shortcut", "dictation.setup", "meetings.setup", "done"])
    }

    @Test func anOldInstallStillGetsTheStepsOfItsOldPlugins() throws {
        let env = try TestEnvironment()
        defer { env.tearDown() }
        PluginDefaultsMigration.run(settings: env.settings, isExistingInstall: true)
        #expect(welcomePages(env) == ["intro", "shortcut", "files.fullDiskAccess", "clipboard.intro", "done"])
    }
}
