import Foundation
import LintelKit

/// The explorer's collections (spec `2026-11-24-notes-explorer-main-window`, phase 3a): All notes, Meetings and
/// Dictations, the rows of the sidebar's Notes block. A collection filters one list; it is not a place a note lives.
/// Classification only reads the plugin id and the kind that the contract already carries, so no plugin is imported
/// and the contract is untouched.
///
/// - `all` has no filter: meetings, dictations, manual notes and kept copies.
/// - `meetings` is what a `meetings` source owns (or a note of kind `meeting`), kept copies of meetings included;
///   manual notes are only in `all` (spec Q15).
/// - `dictations` is what a `dictation` source owns (or a note of kind `dictation`).
///
/// The raw value is what `plugins.notes.explorer.collection` stores; an unknown value (a later release's `folder:<id>`
/// included) reads as `all` (`init(stored:)`).
enum NoteCollection: String, Sendable, CaseIterable, Equatable {
    case all
    case meetings
    case dictations

    /// The plugin whose recordings are dictations.
    static let dictationPlugin: PluginID = "dictation"
    /// The plugin whose recordings are meetings.
    static let meetingPlugin: PluginID = "meetings"

    /// What `plugins.notes.explorer.collection` holds; missing, empty or unknown reads as `all`.
    init(stored: String?) {
        self = stored.flatMap(NoteCollection.init(rawValue:)) ?? .all
    }

    /// Whether a note with this key and kind is listed in this collection.
    func contains(key: NoteKey, kind: NoteKind? = nil) -> Bool {
        switch self {
        case .all: true
        case .dictations: kind == .dictation || key.pluginID == Self.dictationPlugin
        case .meetings: kind == .meeting || key.pluginID == Self.meetingPlugin
        }
    }

    func contains(_ id: NoteItemID) -> Bool { contains(key: id.key) }

    func contains(_ row: NoteRow) -> Bool { contains(key: row.id.key, kind: row.summary.kind) }

    /// Whether the source with this plugin id is listed in this collection.
    func includesSource(_ id: PluginID) -> Bool {
        switch self {
        case .all: true
        case .dictations: id == Self.dictationPlugin
        case .meetings: id == Self.meetingPlugin
        }
    }

    /// A note that a dictation source owns, or of kind dictation.
    static func isDictation(key: NoteKey, kind: NoteKind? = nil) -> Bool {
        NoteCollection.dictations.contains(key: key, kind: kind)
    }

    static func isDictation(_ id: NoteItemID) -> Bool { isDictation(key: id.key) }

    static func isDictation(_ row: NoteRow) -> Bool { isDictation(key: row.id.key, kind: row.summary.kind) }
}

/// How many notes each sidebar row shows. `nil` for a collection whose count could not be read (its source did not
/// answer): the model then keeps the last count it knew instead of showing a wrong 0.
struct NoteCollectionCounts: Sendable, Equatable {
    var all: Int?
    var meetings: Int?
    var dictations: Int?

    func count(of collection: NoteCollection) -> Int? {
        switch collection {
        case .all: all
        case .meetings: meetings
        case .dictations: dictations
        }
    }

    mutating func set(_ value: Int?, for collection: NoteCollection) {
        switch collection {
        case .all: all = value
        case .meetings: meetings = value
        case .dictations: dictations = value
        }
    }

    /// Fills what this value does not know from `previous`.
    func filling(from previous: NoteCollectionCounts) -> NoteCollectionCounts {
        NoteCollectionCounts(
            all: all ?? previous.all, meetings: meetings ?? previous.meetings,
            dictations: dictations ?? previous.dictations)
    }
}
