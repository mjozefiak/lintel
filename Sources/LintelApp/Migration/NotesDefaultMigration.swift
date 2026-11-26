import Foundation
import LintelKit

/// One-time pin of the meeting notes switch, whose default changed with issue #252 (owner decision 2026-11-24: notes
/// are written after each meeting by the model on this Mac, on by default for a new install).
///
/// `plugins.meetings.notesEnabled` is a protected settings key (`BACKWARD_COMPATIBILITY.md` §3): a missing value means
/// the default, so flipping it would silently turn automatic notes on for every install that never touched the
/// switch. Before any plugin reads it, this writes the old value `false` on an install that ran before, unless a
/// `Bool` is stored; a new install gets nothing but the marker and starts with notes on. It is a step of its own, with
/// its own marker, because `app.pluginDefaultsMigrated` (#251) is already set on installs that ran #251: reusing it
/// would skip them.
///
/// "Ran before" is decided once per launch by `AppEnvironment.pinPreviousPluginDefaults`, before #251's step writes
/// its marker and before `ranking.sqlite` is opened: the ranking file, the welcome screen's answers, or #251's marker
/// (written by every launch of a build that has #251) is there.
struct NotesDefaultMigration {
    /// `Bool`: the pin has run (on any install, new or old). Added with issue #252.
    static let migratedKey = "app.notesDefaultMigrated"

    /// The full key of `MeetingsSettings.Key.notesEnabled` (`Sources/MeetingsPlugin/MeetingsSettings.swift`), the one
    /// key this step writes; `NotesDefaultMigrationTests` checks that the two stay the same.
    static let notesEnabledKey = "plugins.meetings.notesEnabled"

    /// The effective value of the switch before #252, when nothing was stored.
    static let previousDefault = false

    enum Outcome: Equatable {
        case alreadyMigrated
        case newInstall
        /// A `Bool` was stored; it is left as it is.
        case kept
        /// The old default was written.
        case pinned
    }

    @discardableResult
    static func run(settings: any SettingsStore, isExistingInstall: Bool) -> Outcome {
        guard settings.value(forKey: migratedKey) == nil else { return .alreadyMigrated }
        defer { settings.setValue(.bool(true), forKey: migratedKey) }
        guard isExistingInstall else { return .newInstall }
        // The plugin reads only a stored `Bool` (`PluginSettings.bool`); anything else (a number or a string written
        // by hand) already meant the default, so it is pinned like a missing value.
        if case .bool = settings.value(forKey: notesEnabledKey) { return .kept }
        settings.setValue(.bool(previousDefault), forKey: notesEnabledKey)
        return .pinned
    }
}
