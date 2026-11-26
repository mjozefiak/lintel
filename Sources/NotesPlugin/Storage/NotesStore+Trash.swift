import Foundation
import GRDB
import LintelCore
import LintelKit

/// One manual note in Recently deleted. Holds the title: never logged.
struct TrashedManualNote: Sendable, Equatable {
    var key: NoteKey
    var title: String?
    var deletedAt: Date
}

/// Recently deleted in `notes.sqlite` (notes explorer spec, Deletion lifecycle):
///
/// - Manual notes: Notes is their owner, so they are trashed, restored and purged here (`ManualNotesTrash`).
/// - Recorded notes: the owner (Meetings, Dictation) trashes the note; the trash sweep (`NoteTrashSweep`) marks the
///   key's live overlays with the owner's time and clears the mark when the owner restores it. A marked overlay is
///   never detached as a kept copy: once the owner purges the note, its marked overlays are deleted
///   (`detachOrDeleteTrashed`).
///
/// Trash writes go through `writeMaintenance`: a database from a newer Lintel refuses them, the hidden
/// `plugins.notes.readOnly` does not (it never blocks a delete, and a move to Recently deleted replaces one).
/// Titles and text are never logged.
extension NotesStore {
    /// My notes of a recorded note: its own layer on the recorded note's key, written only by `human`.
    static let mineLayer = "mine"

    /// Keys per statement, the contract's batch size.
    static let trashChunk = 500

    private static let manualCondition = "source_plugin_id = 'notes'"
    /// The live layer documents of a recorded note (the ones the owner's trash marks).
    private static let recordedLiveCondition = "source_plugin_id != 'notes' AND source_state IS NOT 'detached'"

    private static func chunks(_ keys: [NoteKey]) -> [[String]] {
        stride(from: 0, to: keys.count, by: trashChunk).map { start in
            keys[start..<min(start + trashChunk, keys.count)].map(\.rawValue)
        }
    }

    // MARK: Manual notes

    /// Moves these manual notes to Recently deleted, all with one stamp, and returns it (`nil` when none moved: a
    /// missing key is skipped, a trashed one is left as it is). The stamp never lands on another manual note's stamp
    /// (a bulk move's batch): on a clash it moves on by 1 µs.
    @discardableResult
    func trashManualNotes(_ keys: [NoteKey], at now: Date) throws -> Date? {
        guard !keys.isEmpty else { return nil }
        return try writeMaintenance { db in
            var micros = TrashStamp.micros(now)
            while try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS (SELECT 1 FROM note_doc WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL
                        AND \(TrashStamp.microsSQL) = ?)
                    """,
                arguments: [micros]) == true
            {
                micros += 1
            }
            var moved = 0
            for part in Self.chunks(keys) {
                var values: [any DatabaseValueConvertible] = [TrashStamp.column(micros: micros)]
                values += part
                try db.execute(
                    sql: """
                        UPDATE note_doc SET deleted_at = ?
                        WHERE \(Self.manualCondition) AND deleted_at IS NULL
                            AND key IN (\(databaseQuestionMarks(count: part.count)))
                        """,
                    arguments: StatementArguments(values))
                moved += db.changesCount
            }
            return moved > 0 ? TrashStamp.date(micros: micros) : nil
        }
    }

    /// Moves every live manual note to Recently deleted, all stamped exactly `at` (rounded to the microsecond: the
    /// stamp is the batch). Returns how many notes moved.
    @discardableResult
    func trashAllManualNotes(at: Date) throws -> Int {
        let value = TrashStamp.column(micros: TrashStamp.micros(at))
        return try writeMaintenance { db in
            let count =
                try Int.fetchOne(
                    db,
                    sql:
                        "SELECT COUNT(DISTINCT key) FROM note_doc WHERE \(Self.manualCondition) AND deleted_at IS NULL"
                ) ?? 0
            try db.execute(
                sql: "UPDATE note_doc SET deleted_at = ? WHERE \(Self.manualCondition) AND deleted_at IS NULL",
                arguments: [value])
            return count
        }
    }

    /// Puts these manual notes back and returns the keys the store no longer has (purged or deleted for good). A
    /// live note is a no-op.
    @discardableResult
    func restoreManualNotes(_ keys: [NoteKey]) throws -> Set<NoteKey> {
        guard !keys.isEmpty else { return [] }
        return try writeMaintenance { db in
            var found = Set<String>()
            for part in Self.chunks(keys) {
                let marks = databaseQuestionMarks(count: part.count)
                found.formUnion(
                    try String.fetchAll(
                        db,
                        sql: "SELECT DISTINCT key FROM note_doc WHERE \(Self.manualCondition) AND key IN (\(marks))",
                        arguments: StatementArguments(part)))
                try db.execute(
                    sql: """
                        UPDATE note_doc SET deleted_at = NULL
                        WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL AND key IN (\(marks))
                        """,
                    arguments: StatementArguments(part))
            }
            return Set(keys.filter { !found.contains($0.rawValue) })
        }
    }

    /// Puts back exactly the manual notes stamped `deletedAt` (to the microsecond); returns how many came back.
    @discardableResult
    func restoreManualBatch(deletedAt: Date) throws -> Int {
        let micros = TrashStamp.micros(deletedAt)
        return try writeMaintenance { db in
            let count =
                try Int.fetchOne(
                    db,
                    sql: """
                        SELECT COUNT(DISTINCT key) FROM note_doc
                        WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?
                        """, arguments: [micros]) ?? 0
            try db.execute(
                sql: """
                    UPDATE note_doc SET deleted_at = NULL
                    WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?
                    """, arguments: [micros])
            return count
        }
    }

    /// How many manual notes are live and how many are in Recently deleted.
    func manualNoteCounts() throws -> (live: Int, trashed: Int) {
        try read { db in
            let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT COUNT(DISTINCT CASE WHEN deleted_at IS NULL THEN key END) AS live,
                        COUNT(DISTINCT CASE WHEN deleted_at IS NOT NULL THEN key END) AS trashed
                    FROM note_doc WHERE \(Self.manualCondition)
                    """)
            return (row?["live"] ?? 0, row?["trashed"] ?? 0)
        }
    }

    /// One page of trashed manual notes, newest-deleted first (ties by key, descending). `after` is the last row of
    /// the previous page.
    func trashedManualNotes(after: (micros: Int64, key: String)?, limit: Int) throws -> [TrashedManualNote] {
        try read { db in
            var sql = """
                SELECT key, MAX(title_override) AS title, MAX(deleted_at) AS deleted_at,
                    MAX(\(TrashStamp.microsSQL)) AS micros
                FROM note_doc WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL GROUP BY key
                """
            var arguments: [any DatabaseValueConvertible] = []
            if let after {
                sql += " HAVING micros < ? OR (micros = ? AND key < ?)"
                arguments += [after.micros, after.micros, after.key]
            }
            sql += " ORDER BY micros DESC, key DESC LIMIT ?"
            arguments.append(max(0, limit))
            return try Row.fetchAll(db, sql: sql, arguments: StatementArguments(arguments)).compactMap { row in
                let raw: String = row["key"]
                guard let key = NoteKey(rawValue: raw) else { return nil }
                let micros: Int64 = row["micros"]
                return TrashedManualNote(key: key, title: row["title"], deletedAt: TrashStamp.date(micros: micros))
            }
        }
    }

    /// Deletes these manual notes for good (Delete Now, Empty Recently deleted), trashed or not, with their folder
    /// entries. Returns the document ids that went, so the open writers are discarded after the rows are gone.
    @discardableResult
    func deleteManualNotes(_ keys: [NoteKey]) throws -> [Int64] {
        guard !keys.isEmpty else { return [] }
        return try writeMaintenance { db in
            var ids: [Int64] = []
            for part in Self.chunks(keys) {
                let marks = databaseQuestionMarks(count: part.count)
                ids += try Int64.fetchAll(
                    db, sql: "SELECT id FROM note_doc WHERE \(Self.manualCondition) AND key IN (\(marks))",
                    arguments: StatementArguments(part))
                try db.execute(
                    sql: "DELETE FROM note_doc WHERE \(Self.manualCondition) AND key IN (\(marks))",
                    arguments: StatementArguments(part))
                try db.execute(
                    sql: "DELETE FROM note_folder_entry WHERE key IN (\(marks))", arguments: StatementArguments(part))
            }
            return ids
        }
    }

    /// The 30-day purge of manual notes (Notes is their owner): every manual note trashed at or before
    /// `now - 30 days`, unless one of its documents is open (it goes once closed), with its folder entry. Returns the
    /// purged keys.
    @discardableResult
    func purgeTrashedManualNotes(now: Date, excluding openDocIDs: Set<Int64> = []) throws -> [NoteKey] {
        let cutoff = TrashStamp.micros(now.addingTimeInterval(-TrashStamp.retention))
        return try writeMaintenance { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, key FROM note_doc
                    WHERE \(Self.manualCondition) AND deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) <= ?
                    """, arguments: [cutoff])
            var byKey: [String: [Int64]] = [:]
            for row in rows { byKey[row["key"], default: []].append(row["id"]) }
            var purged: [NoteKey] = []
            for (raw, ids) in byKey.sorted(by: { $0.key < $1.key }) where ids.allSatisfy({ !openDocIDs.contains($0) }) {
                try db.execute(sql: "DELETE FROM note_doc WHERE \(Self.manualCondition) AND key = ?", arguments: [raw])
                try db.execute(sql: "DELETE FROM note_folder_entry WHERE key = ?", arguments: [raw])
                if let key = NoteKey(rawValue: raw) { purged.append(key) }
            }
            return purged
        }
    }

    // MARK: Overlays of recorded notes (the trash sweep)

    /// The keys whose live overlays carry a Recently deleted mark.
    func markedOverlayKeys() throws -> Set<NoteKey> {
        try read { db in
            Set(
                try String.fetchAll(
                    db,
                    sql: """
                        SELECT DISTINCT key FROM note_doc WHERE \(Self.recordedLiveCondition) AND deleted_at IS NOT NULL
                        """
                ).compactMap { NoteKey(rawValue: $0) })
        }
    }

    /// Marks the live overlays of each key (every layer, `mine` included) with the owner's `deleted_at`. Returns
    /// how many documents changed.
    @discardableResult
    func markOverlaysTrashed(_ stamps: [NoteKey: Date]) throws -> Int {
        guard !stamps.isEmpty else { return 0 }
        return try writeMaintenance { db in
            var changed = 0
            for (key, date) in stamps.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                let micros = TrashStamp.micros(date)
                try db.execute(
                    sql: """
                        UPDATE note_doc SET deleted_at = ?
                        WHERE key = ? AND \(Self.recordedLiveCondition)
                            AND (deleted_at IS NULL OR \(TrashStamp.microsSQL) != ?)
                        """,
                    arguments: [TrashStamp.column(micros: micros), key.rawValue, micros])
                changed += db.changesCount
            }
            return changed
        }
    }

    /// Clears the mark of these keys' live overlays (the owner restored them). Returns how many documents changed.
    @discardableResult
    func clearOverlayTrashMarks(_ keys: [NoteKey]) throws -> Int {
        guard !keys.isEmpty else { return 0 }
        return try writeMaintenance { db in
            var changed = 0
            for part in Self.chunks(keys) {
                try db.execute(
                    sql: """
                        UPDATE note_doc SET deleted_at = NULL
                        WHERE \(Self.recordedLiveCondition) AND deleted_at IS NOT NULL
                            AND key IN (\(databaseQuestionMarks(count: part.count)))
                        """,
                    arguments: StatementArguments(part))
                changed += db.changesCount
            }
            return changed
        }
    }

    /// The live overlays of a key that carry a Recently deleted mark: the ones a detach deletes.
    func trashedLiveOverlayIDs(of key: NoteKey) throws -> [Int64] {
        try read { db in
            try Int64.fetchAll(
                db,
                sql: """
                    SELECT id FROM note_doc WHERE key = ? AND \(Self.recordedLiveCondition) AND deleted_at IS NOT NULL
                    ORDER BY id
                    """, arguments: [key.rawValue])
        }
    }

    /// The one detach of a recorded key's live rows, in ONE transaction with `alongside`: rows that carry a
    /// Recently deleted mark are DELETED (an overlay marked deleted is never turned into a kept copy), the rest
    /// move to `detached` as before. Returns both, so the registry discards the writers of the deleted rows and
    /// re-keys the moved ones.
    @discardableResult
    func detachOrDeleteTrashed(
        _ key: NoteKey, alongside: (Database, [DetachedRow]) throws -> Void = { _, _ in }
    ) throws -> (moved: [DetachedRow], deleted: [Int64]) {
        try writeMaintenance { db in
            let deleted = try Self.deleteMarkedOverlays(of: key, in: db)
            let moved = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, layer, source_started_at_ms FROM note_doc
                    WHERE key = ? AND \(Self.recordedLiveCondition) ORDER BY id
                    """, arguments: [key.rawValue]
            ).map { DetachedRow(docID: $0["id"], layer: $0["layer"], startedAtMs: $0["source_started_at_ms"]) }
            try db.execute(
                sql: "UPDATE note_doc SET source_state = 'detached' WHERE key = ? AND \(Self.recordedLiveCondition)",
                arguments: [key.rawValue])
            try alongside(db, moved)
            return (moved, deleted)
        }
    }

    static func deleteMarkedOverlays(of key: NoteKey, in db: Database) throws -> [Int64] {
        let ids = try Int64.fetchAll(
            db,
            sql: """
                SELECT id FROM note_doc WHERE key = ? AND \(recordedLiveCondition) AND deleted_at IS NOT NULL
                ORDER BY id
                """, arguments: [key.rawValue])
        for id in ids { try db.execute(sql: "DELETE FROM note_doc WHERE id = ?", arguments: [id]) }
        return ids
    }

    // MARK: Folder entries

    /// Every key that is in a folder.
    func folderEntryKeys() throws -> [NoteKey] {
        try read { db in
            try String.fetchAll(db, sql: "SELECT key FROM note_folder_entry ORDER BY key").compactMap {
                NoteKey(rawValue: $0)
            }
        }
    }

    /// Manual notes among `keys` that still have a document (in Recently deleted or not).
    func existingManualKeys(_ keys: [NoteKey]) throws -> Set<NoteKey> {
        guard !keys.isEmpty else { return [] }
        return try read { db in
            var found = Set<NoteKey>()
            for part in Self.chunks(keys) {
                found.formUnion(
                    try String.fetchAll(
                        db,
                        sql: """
                            SELECT DISTINCT key FROM note_doc
                            WHERE \(Self.manualCondition) AND key IN (\(databaseQuestionMarks(count: part.count)))
                            """, arguments: StatementArguments(part)
                    ).compactMap { NoteKey(rawValue: $0) })
            }
            return found
        }
    }

    /// Removes the folder entries of keys that are gone. Returns how many went.
    @discardableResult
    func deleteFolderEntries(_ keys: [NoteKey]) throws -> Int {
        guard !keys.isEmpty else { return 0 }
        return try writeMaintenance { db in
            var removed = 0
            for part in Self.chunks(keys) {
                try db.execute(
                    sql: "DELETE FROM note_folder_entry WHERE key IN (\(databaseQuestionMarks(count: part.count)))",
                    arguments: StatementArguments(part))
                removed += db.changesCount
            }
            return removed
        }
    }
}
