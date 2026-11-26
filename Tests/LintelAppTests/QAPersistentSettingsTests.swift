#if DEBUG
import Foundation
import LintelKit
import Testing

@testable import LintelApp

/// DEBUG-only `--qa-persistent-settings`: settings that survive a QA relaunch (`QAFileSettingsStore`), and the
/// one key that must not, because what it marks (the commands' default shortcuts) lives only in the run's
/// in-memory registrar (#300).
@Suite struct QAPersistentSettingsTests {
    private let history = PluginCommand(
        id: "clipboard.history",
        title: "Clipboard History",
        defaultShortcut: KeyShortcut(key: "v", modifiers: [.command, .shift]),
        panelMode: "clipboard"
    )

    /// Two launches on the same `--qa-data-root` with `--qa-persistent-settings`: the first stores
    /// `app.hotkey.commandDefaultsApplied` while applying the command's default, the second must apply the
    /// default again, because its registrar (and with it the stored shortcut) is new and empty.
    @Test func theSecondLaunchAppliesCommandDefaultsAgain() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "lintel-qa-shortcuts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: QAFileSettingsStore.fileName)

        let firstSettings = QAFileSettingsStore(url: url, seeded: [:])
        let first = HotkeyService(registrar: InMemoryHotkeyRegistrar(), settings: firstSettings, readOccupied: { [] })
        first.syncCommands([history]) { _ in }
        #expect(first.commandShortcut("clipboard.history")?.displayString == "⇧⌘V")
        #expect(
            firstSettings.value(forKey: SettingsKeys.commandShortcutDefaultsApplied)
                == .stringArray(["clipboard.history"]))

        let secondSettings = QAFileSettingsStore(url: url, seeded: [:])
        let second = HotkeyService(registrar: InMemoryHotkeyRegistrar(), settings: secondSettings, readOccupied: { [] })
        second.syncCommands([history]) { _ in }
        #expect(second.commandShortcut("clipboard.history")?.displayString == "⇧⌘V")
        // The marker never reaches the file, so a third launch starts clean as well.
        let third = QAFileSettingsStore(url: url, seeded: [:])
        #expect(third.value(forKey: SettingsKeys.commandShortcutDefaultsApplied) == nil)
    }

    /// A `qa-settings.json` written before the fix already holds the marker; a launch on such a folder must
    /// ignore it and apply the command defaults anyway.
    @Test func aStaleMarkerInTheFileIsIgnored() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "lintel-qa-stale-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appending(path: QAFileSettingsStore.fileName)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let stale =
            #"{"app.hotkey.commandDefaultsApplied":{"kind":"strings","strings":["clipboard.history"]}}"#
        try Data(stale.utf8).write(to: url)

        let settings = QAFileSettingsStore(url: url, seeded: [:])
        let hotkeys = HotkeyService(registrar: InMemoryHotkeyRegistrar(), settings: settings, readOccupied: { [] })
        hotkeys.syncCommands([history]) { _ in }
        #expect(hotkeys.commandShortcut("clipboard.history")?.displayString == "⇧⌘V")
    }
}
#endif
