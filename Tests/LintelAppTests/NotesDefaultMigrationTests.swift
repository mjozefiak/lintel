import Foundation
import LintelKit
import LintelPersistence
import Testing

@testable import LintelApp
@testable import MeetingsPlugin

/// Issue #252: automatic meeting notes are on by default for a new install, and the one-time pin that keeps every
/// earlier install's switch as it was (`BACKWARD_COMPATIBILITY.md` §3).
@MainActor
@Suite struct NotesDefaultMigrationTests {
    private static let key = NotesDefaultMigration.notesEnabledKey

    private func notesEnabled(_ store: InMemorySettingsStore) -> Bool {
        MeetingsSettings(PluginSettings(pluginID: "meetings", store: store)).notesEnabled
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "lintel-notes-default-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func theKeyIsTheOneTheMeetingsPluginReads() {
        let settings = PluginSettings(pluginID: "meetings", store: InMemorySettingsStore())
        #expect(settings.key(MeetingsSettings.Key.notesEnabled) == Self.key)
        #expect(MeetingsSettings.defaultNotesEnabled == !NotesDefaultMigration.previousDefault)
    }

    @Test func aNewInstallGetsNotesOnAndOnlyTheMarker() {
        let store = InMemorySettingsStore()
        #expect(NotesDefaultMigration.run(settings: store, isExistingInstall: false) == .newInstall)
        #expect(store.value(forKey: NotesDefaultMigration.migratedKey) == .bool(true))
        #expect(store.value(forKey: Self.key) == nil)
        #expect(notesEnabled(store))
    }

    @Test func anOldInstallWithNothingStoredKeepsNotesOff() {
        let store = InMemorySettingsStore()
        #expect(notesEnabled(store), "without the pin the new default would apply")
        #expect(NotesDefaultMigration.run(settings: store, isExistingInstall: true) == .pinned)
        #expect(store.value(forKey: Self.key) == .bool(false))
        #expect(!notesEnabled(store))
    }

    @Test(arguments: [true, false])
    func aStoredChoiceIsNeverChanged(_ stored: Bool) {
        let store = InMemorySettingsStore([Self.key: .bool(stored)])
        #expect(NotesDefaultMigration.run(settings: store, isExistingInstall: true) == .kept)
        #expect(store.value(forKey: Self.key) == .bool(stored))
        #expect(notesEnabled(store) == stored)
    }

    /// `PluginSettings.bool` reads only a stored `Bool`, so a number or a string (written by hand) meant the old
    /// default `false` before the change and must mean it after.
    @Test(arguments: [SettingValue.integer(1), .string("YES"), .stringArray(["true"])])
    func aValueThePluginCannotReadIsPinnedLikeAMissingOne(_ value: SettingValue) {
        let store = InMemorySettingsStore([Self.key: value])
        #expect(NotesDefaultMigration.run(settings: store, isExistingInstall: true) == .pinned)
        #expect(store.value(forKey: Self.key) == .bool(false))
    }

    @Test func itRunsOnce() {
        let fresh = InMemorySettingsStore()
        NotesDefaultMigration.run(settings: fresh, isExistingInstall: false)
        // The second launch looks like an old install (the ranking file and #251's marker exist now).
        #expect(NotesDefaultMigration.run(settings: fresh, isExistingInstall: true) == .alreadyMigrated)
        #expect(fresh.value(forKey: Self.key) == nil)

        let old = InMemorySettingsStore()
        NotesDefaultMigration.run(settings: old, isExistingInstall: true)
        old.setValue(.bool(true), forKey: Self.key)  // the user turned notes on afterwards
        #expect(NotesDefaultMigration.run(settings: old, isExistingInstall: true) == .alreadyMigrated)
        #expect(old.value(forKey: Self.key) == .bool(true))
    }

    /// Both steps run on one launch. #251's step marks a new install on its first launch; that marker must not make
    /// the notes step take the same launch for an old install.
    @Test func aNewInstallsFirstAndSecondLaunchKeepNotesOn() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: store, fileManager: .default)
        #expect(store.value(forKey: PluginDefaultsMigration.migratedKey) == .bool(true))
        #expect(store.value(forKey: NotesDefaultMigration.migratedKey) == .bool(true))
        #expect(store.value(forKey: Self.key) == nil)
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: store, fileManager: .default)
        #expect(store.value(forKey: Self.key) == nil)
        #expect(notesEnabled(store))
    }

    @Test func anInstallThatRanBeforeIsPinnedAtLaunch() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        let store = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: store, fileManager: .default)
        #expect(store.value(forKey: Self.key) == .bool(false))
    }

    /// An install that already ran #251 (its marker is stored) ran before this build, even without a ranking file or
    /// welcome answers.
    @Test func anInstallThatRanTheEarlierPinIsAnOldInstall() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = InMemorySettingsStore([PluginDefaultsMigration.migratedKey: .bool(true)])
        AppEnvironment.pinPreviousPluginDefaults(dataRoot: root, settings: store, fileManager: .default)
        #expect(store.value(forKey: Self.key) == .bool(false))
        // #251's own step saw its marker and changed nothing.
        #expect(store.value(forKey: SettingsKeys.pluginEnabled("apps")) == nil)
    }

    @Test func aQARunWithInMemorySettingsIsANewInstall() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: root.appending(path: UsageRepository.fileName))
        let volatile = InMemorySettingsStore()
        AppEnvironment.pinPreviousPluginDefaults(
            dataRoot: root, settings: volatile, fileManager: .default, settingsPersist: false)
        #expect(volatile.value(forKey: Self.key) == nil)
        #expect(volatile.value(forKey: NotesDefaultMigration.migratedKey) == .bool(true))
    }
}
