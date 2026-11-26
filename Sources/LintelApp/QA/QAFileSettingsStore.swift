#if DEBUG
import Foundation
import LintelKit
import Synchronization

/// DEBUG-only (`--qa-persistent-settings`): QA settings that survive a relaunch, kept in a JSON file inside the QA
/// data root. Never the defaults domain. Values given on the command line (`seeded`) are applied on top of what the
/// file holds, at every launch.
nonisolated final class QAFileSettingsStore: SettingsStore {
    static let fileName = "qa-settings.json"

    /// Keys that never survive a relaunch. `app.hotkey.commandDefaultsApplied` marks commands whose default
    /// shortcut was stored once; in QA mode the shortcuts themselves live only in the run's in-memory registrar
    /// (`HotkeyService`), so a second launch must apply the defaults again instead of trusting the marker (#300).
    /// The key still works within one launch; it is just never written to or read back from the file.
    static let ephemeralKeys: Set<String> = [SettingsKeys.commandShortcutDefaultsApplied]

    private struct Stored: Codable {
        var kind: String
        var bool: Bool?
        var integer: Int?
        var string: String?
        var strings: [String]?

        init(_ value: SettingValue) {
            switch value {
            case .bool(let value): (kind, bool) = ("bool", value)
            case .integer(let value): (kind, integer) = ("integer", value)
            case .string(let value): (kind, string) = ("string", value)
            case .stringArray(let value): (kind, strings) = ("strings", value)
            }
        }

        var value: SettingValue? {
            switch kind {
            case "bool": bool.map(SettingValue.bool)
            case "integer": integer.map(SettingValue.integer)
            case "string": string.map(SettingValue.string)
            case "strings": strings.map(SettingValue.stringArray)
            default: nil
            }
        }
    }

    private let url: URL
    private let values: Mutex<[String: SettingValue]>

    init(url: URL, seeded: [String: SettingValue]) {
        self.url = url
        var loaded: [String: SettingValue] = [:]
        if let data = try? Data(contentsOf: url),
            let stored = try? JSONDecoder().decode([String: Stored].self, from: data)
        {
            for (key, entry) in stored where !Self.ephemeralKeys.contains(key) { loaded[key] = entry.value }
        }
        for (key, value) in seeded { loaded[key] = value }
        values = Mutex(loaded)
        persist(loaded)
    }

    func value(forKey key: String) -> SettingValue? {
        values.withLock { $0[key] }
    }

    func setValue(_ value: SettingValue?, forKey key: String) {
        let snapshot = values.withLock { values -> [String: SettingValue] in
            values[key] = value
            return values
        }
        persist(snapshot)
    }

    private func persist(_ snapshot: [String: SettingValue]) {
        let stored = snapshot.filter { !Self.ephemeralKeys.contains($0.key) }.mapValues(Stored.init)
        guard let data = try? JSONEncoder().encode(stored) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
#endif
