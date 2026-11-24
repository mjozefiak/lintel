import Foundation
import LintelKit
import LintelPersistence

/// One-time pin of the plugin switches whose default changed on 2026-11-24 (owner decision: Dictation and Meetings
/// are the core and on by default; Apps, Files and Clipboard are add-ons and off by default).
///
/// `plugins.<id>.enabled` is a protected settings key (`BACKWARD_COMPATIBILITY.md` §3): a missing value means
/// `manifest.defaultEnabled`, so flipping a default would silently switch plugins on or off for every install that
/// never touched the switch. Before the host reads any switch, this writes the old default for each flipped plugin
/// that has no stored value, but only on an install that ran before. A new install gets nothing but the marker, so
/// it starts with the new defaults, and the marker keeps its second launch from being mistaken for an old install.
/// A stored value is never changed.
struct PluginDefaultsMigration {
    /// `Bool`: the pin has run (on any install, new or old). Added with the 2026-11-24 defaults.
    static let migratedKey = "app.pluginDefaultsMigrated"

    /// The effective value of each flipped plugin's switch before 2026-11-24, when nothing was stored. Windows (off)
    /// and Notes (always on) did not change and are not listed.
    static let previousDefaults: [(id: PluginID, enabled: Bool)] = [
        ("apps", true),
        ("files", true),
        ("clipboard", true),
        ("dictation", false),
        ("meetings", false),
    ]

    enum Outcome: Equatable {
        case alreadyMigrated
        case newInstall
        /// The plugin ids whose old default was written.
        case pinned([PluginID])
    }

    /// Whether this install ran before: `ranking.sqlite` exists (every launch since v0.1 creates it before the host
    /// starts) or the welcome screen was already answered. Read before this launch creates the ranking file.
    static func isExistingInstall(dataRoot: URL, settings: any SettingsStore, fileManager: FileManager) -> Bool {
        if fileManager.fileExists(atPath: dataRoot.appending(path: UsageRepository.fileName).path) {
            return true
        }
        return settings.value(forKey: SettingsKeys.onboardingShortcutCompleted) != nil
            || settings.value(forKey: SettingsKeys.onboardingCompletedSteps) != nil
    }

    @discardableResult
    static func run(settings: any SettingsStore, isExistingInstall: Bool) -> Outcome {
        guard settings.value(forKey: migratedKey) == nil else { return .alreadyMigrated }
        defer { settings.setValue(.bool(true), forKey: migratedKey) }
        guard isExistingInstall else { return .newInstall }
        var pinned: [PluginID] = []
        for entry in previousDefaults {
            let key = SettingsKeys.pluginEnabled(entry.id)
            guard settings.value(forKey: key) == nil else { continue }
            settings.setValue(.bool(entry.enabled), forKey: key)
            pinned.append(entry.id)
        }
        return .pinned(pinned)
    }
}
