import Foundation
import GRDB

/// How `dictation_entry.deleted_at` is written and compared (notes explorer spec, Deletion lifecycle).
///
/// The column is a REAL in Unix seconds. A bulk move stamps every row with one value and `restoreBatch` finds
/// the batch by equality, so one conversion rules every write and every comparison: the time is rounded to a
/// whole microsecond, stored as `micros / 1e6` and compared through `CAST(ROUND(deleted_at * 1e6) AS INTEGER)`.
/// A stamp read back after the database is reopened therefore equals the one written. (Meetings has the same
/// rule in its own copy: plugins never import each other.)
enum TrashStamp {
    /// How long a row stays in Recently deleted.
    static let retention: TimeInterval = 30 * 24 * 60 * 60

    /// The SQL expression that reads a stamp column as whole microseconds.
    static let microsSQL = "CAST(ROUND(deleted_at * 1000000) AS INTEGER)"

    static func micros(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000_000).rounded())
    }

    /// The value the column holds for these microseconds.
    static func column(micros: Int64) -> Double { Double(micros) / 1_000_000 }

    static func micros(column: Double) -> Int64 { Int64((column * 1_000_000).rounded()) }

    static func date(micros: Int64) -> Date { Date(timeIntervalSince1970: column(micros: micros)) }

    static func date(column: Double) -> Date { date(micros: micros(column: column)) }

    /// When an entry deleted at `deletedAt` is gone for good: the earlier of 30 days after the delete and the
    /// entry's retention limit (`createdAt` + `retentionDays`; 0 means no limit, so only the 30 days count).
    static func purgeAt(deletedAt: Date, createdAt: Date, retentionDays: Int) -> Date {
        let thirty = deletedAt.addingTimeInterval(retention)
        guard retentionDays > 0 else { return thirty }
        return min(thirty, createdAt.addingTimeInterval(Double(retentionDays) * 24 * 60 * 60))
    }
}

/// Recently deleted for the dictation history: the owner's half of the notes explorer's Deletion lifecycle.
/// A trashed entry keeps its row and its full-text entry until the purge; the reads the user sees filter
/// `deleted_at IS NULL` (`DictationStore+Access`). Dictation is never recording or processing, so nothing here is
/// ever busy. Nothing here logs text.
extension DictationStore {
    /// What `trash(id:at:)` did.
    enum TrashOutcome: Equatable, Sendable {
        /// The entry moved now, with this stamp.
        case trashed(Date)
        /// The entry was in Recently deleted already (a no-op), with its stamp.
        case alreadyTrashed(Date)
        /// There is no such entry.
        case missing
    }

    /// Moves one entry to Recently deleted in one transaction. A single trash never reuses another row's stamp (a
    /// bulk move's batch stamp): on a clash the stamp is moved on by 1 µs.
    @discardableResult
    func trash(id: Int64, at now: Date) throws -> TrashOutcome {
        try write { db in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT deleted_at FROM dictation_entry WHERE id = ?", arguments: [id])
            else { return .missing }
            if let existing = row["deleted_at"] as Double? { return .alreadyTrashed(TrashStamp.date(column: existing)) }
            var micros = TrashStamp.micros(now)
            while try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS (SELECT 1 FROM dictation_entry
                        WHERE deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?)
                    """,
                arguments: [micros]) == true
            {
                micros += 1
            }
            try db.execute(
                sql: "UPDATE dictation_entry SET deleted_at = ? WHERE id = ? AND deleted_at IS NULL",
                arguments: [TrashStamp.column(micros: micros), id])
            return .trashed(TrashStamp.date(micros: micros))
        }
    }

    /// Moves every live entry to Recently deleted, all stamped `at` (rounded to the microsecond: the stamp is
    /// the batch). One transaction. Returns how many moved.
    func trashAll(at: Date) throws -> Int {
        let value = TrashStamp.column(micros: TrashStamp.micros(at))
        return try write { db in
            try db.execute(
                sql: "UPDATE dictation_entry SET deleted_at = ? WHERE deleted_at IS NULL", arguments: [value])
            return db.changesCount
        }
    }

    /// Puts these entries back (a live one is left alone) and returns the ids that no longer exist. Takes any
    /// number of ids; the caller's chunking (500) only bounds a transaction.
    @discardableResult
    func restore(ids: [Int64]) throws -> Set<Int64> {
        guard !ids.isEmpty else { return [] }
        return try write { db in
            var missing = Set<Int64>()
            for id in ids {
                let exists =
                    try Bool.fetchOne(
                        db, sql: "SELECT EXISTS (SELECT 1 FROM dictation_entry WHERE id = ?)", arguments: [id])
                    ?? false
                guard exists else {
                    missing.insert(id)
                    continue
                }
                try db.execute(
                    sql: "UPDATE dictation_entry SET deleted_at = NULL WHERE id = ? AND deleted_at IS NOT NULL",
                    arguments: [id])
            }
            return missing
        }
    }

    /// Puts back every entry whose stamp is exactly this batch's (to the microsecond) and that still exists.
    /// Returns how many came back; an entry deleted earlier or later is never touched.
    func restoreBatch(deletedAt: Date) throws -> Int {
        let micros = TrashStamp.micros(deletedAt)
        return try write { db in
            try db.execute(
                sql: """
                    UPDATE dictation_entry SET deleted_at = NULL
                    WHERE deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?
                    """,
                arguments: [micros])
            return db.changesCount
        }
    }

    /// The entries the history shows (not in Recently deleted).
    func liveCount() throws -> Int {
        try read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM dictation_entry WHERE deleted_at IS NULL") ?? 0
        }
    }

    func trashedCount() throws -> Int {
        try read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM dictation_entry WHERE deleted_at IS NOT NULL") ?? 0
        }
    }

    /// Where a page of `trashedEntries` starts: after the row with this stamp (whole microseconds) and id.
    struct TrashPosition: Sendable, Equatable {
        var micros: Int64
        var id: Int64
    }

    /// The entries in Recently deleted, newest-deleted first, each with `deletedAt` (`id` descending breaks ties).
    func trashedEntries(after: TrashPosition? = nil, limit: Int) throws -> [DictationEntry] {
        try read { db in
            var arguments: StatementArguments = ["limit": max(0, limit)]
            var cursor = ""
            if let after {
                cursor = "AND (\(TrashStamp.microsSQL) < :micros OR (\(TrashStamp.microsSQL) = :micros AND id < :id))"
                arguments += ["micros": after.micros, "id": after.id]
            }
            return try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM dictation_entry WHERE deleted_at IS NOT NULL \(cursor)
                    ORDER BY deleted_at DESC, id DESC LIMIT :limit
                    """,
                arguments: arguments
            ).compactMap(Self.entry(_:))
        }
    }

    /// Which of these entries are in Recently deleted, each with its stamp. Reads two columns, never the text.
    func trashedStamps(ids: [Int64]) throws -> [Int64: Date] {
        guard !ids.isEmpty else { return [:] }
        let marks = ids.map { _ in "?" }.joined(separator: ", ")
        return try read { db in
            var result: [Int64: Date] = [:]
            for row in try Row.fetchAll(
                db,
                sql: "SELECT id, deleted_at FROM dictation_entry WHERE id IN (\(marks)) AND deleted_at IS NOT NULL",
                arguments: StatementArguments(ids))
            {
                result[row["id"]] = TrashStamp.date(column: row["deleted_at"])
            }
            return result
        }
    }

    /// Deletes the entries that moved to Recently deleted before `cutoff` (the caller passes now - 30 days) and
    /// returns how many. Entries deleted since stay.
    @discardableResult
    func purgeTrashed(olderThan cutoff: Date) throws -> Int {
        try write { db in
            try db.execute(
                sql: "DELETE FROM dictation_entry WHERE deleted_at IS NOT NULL AND deleted_at < ?",
                arguments: [cutoff.timeIntervalSince1970])
            return db.changesCount
        }
    }
}
