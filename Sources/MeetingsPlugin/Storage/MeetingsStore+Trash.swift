import Foundation
import GRDB
import LintelCore

/// Meetings' retention limit on top of the shared stamp rule (`LintelCore.TrashStamp`).
extension TrashStamp {
    /// When a row deleted at `deletedAt` is gone for good: the earlier of 30 days after the delete and the row's
    /// retention limit (`startedAt` + `retentionDays`; 0 keeps everything, so only the 30 days count).
    static func purgeAt(deletedAt: Date, startedAt: Date, retentionDays: Int) -> Date {
        purgeAt(deletedAt: deletedAt, limitStart: startedAt, retentionDays: retentionDays)
    }
}

/// Recently deleted for the meetings library: the owner's half of the notes explorer's Deletion lifecycle.
/// A trashed row keeps everything (transcript, notes, speakers, FTS rows, spool, kept recording) until the purge,
/// so a restore brings the audio back; the reads the user sees filter `deleted_at IS NULL` (`MeetingsStore+
/// Library`, `+Recovery`, `+Notes`, the two searches). Nothing here logs a title or text.
extension MeetingsStore {
    /// What `trash(uuid:...)` did.
    enum TrashOutcome: Equatable, Sendable {
        /// The row moved now, with this stamp.
        case trashed(Date)
        /// The row was in Recently deleted already (a no-op), with its stamp.
        case alreadyTrashed(Date)
        /// The meeting is being recorded, processed or finished; nothing changed.
        case busy
        /// There is no such meeting.
        case missing
    }

    /// Moves one meeting to Recently deleted in one transaction. The row moves only while it is not `recording`
    /// or `processing` and not in `protected` (a session or "Dokończ" holds it), so a "Dokończ" that claimed it a
    /// moment ago wins, exactly like `deleteMeeting`. A single trash never reuses another row's stamp (a bulk
    /// move's batch stamp): on a clash the stamp is moved on by 1 µs.
    func trash(uuid: String, at now: Date, protected: Set<Int64> = []) throws -> TrashOutcome {
        try write { db in
            guard
                let row = try Row.fetchOne(
                    db, sql: "SELECT id, status, deleted_at FROM meeting WHERE uuid = ?", arguments: [uuid])
            else { return .missing }
            if let existing = row["deleted_at"] as Double? { return .alreadyTrashed(TrashStamp.date(column: existing)) }
            let id: Int64 = row["id"]
            let status = MeetingStatus(rawValue: row["status"]) ?? .failed
            if status.isActive || protected.contains(id) { return .busy }
            var micros = TrashStamp.micros(now)
            while try Bool.fetchOne(
                db,
                sql:
                    "SELECT EXISTS (SELECT 1 FROM meeting WHERE deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?)",
                arguments: [micros]) == true
            {
                micros += 1
            }
            try db.execute(
                sql: """
                    UPDATE meeting SET deleted_at = ?
                    WHERE id = ? AND deleted_at IS NULL AND status NOT IN ('recording', 'processing')
                    """,
                arguments: [TrashStamp.column(micros: micros), id])
            guard db.changesCount == 1 else { return .busy }
            return .trashed(TrashStamp.date(micros: micros))
        }
    }

    /// What one bulk move did.
    struct TrashAllResult: Equatable, Sendable {
        var moved: Int
        /// Live meetings that stayed because they are being recorded, processed or finished.
        var stayed: Int
    }

    /// Moves every live meeting that is not busy to Recently deleted, all stamped `at` (rounded to the
    /// microsecond: the stamp is the batch). One transaction.
    func trashAll(at: Date, protected: Set<Int64> = []) throws -> TrashAllResult {
        let value = TrashStamp.column(micros: TrashStamp.micros(at))
        return try write { db in
            let rows = try Row.fetchAll(db, sql: "SELECT id, status FROM meeting WHERE deleted_at IS NULL")
            var moved = 0
            for row in rows {
                let id: Int64 = row["id"]
                let status = MeetingStatus(rawValue: row["status"]) ?? .failed
                guard !status.isActive, !protected.contains(id) else { continue }
                try db.execute(
                    sql: """
                        UPDATE meeting SET deleted_at = ?
                        WHERE id = ? AND deleted_at IS NULL AND status NOT IN ('recording', 'processing')
                        """,
                    arguments: [value, id])
                moved += db.changesCount
            }
            return TrashAllResult(moved: moved, stayed: rows.count - moved)
        }
    }

    /// What `restoreReporting(uuids:)` did.
    struct RestoreResult: Sendable, Equatable {
        /// The `uuid`s that no longer exist.
        var missing: Set<String> = []
        /// How many rows left Recently deleted now (a live one, or one already restored, does not count).
        var restored = 0
    }

    /// Puts these meetings back (a live one is left alone) and returns the `uuid`s that no longer exist. Takes
    /// any number of ids; the caller's chunking (500) only bounds a transaction.
    @discardableResult
    func restore(uuids: [String]) throws -> Set<String> {
        try restoreReporting(uuids: uuids).missing
    }

    /// `restore(uuids:)` that also says how many rows it actually put back, so a source announces a change only
    /// when something changed.
    func restoreReporting(uuids: [String]) throws -> RestoreResult {
        guard !uuids.isEmpty else { return RestoreResult() }
        return try write { db in
            var result = RestoreResult()
            for uuid in uuids {
                let exists =
                    try Bool.fetchOne(
                        db, sql: "SELECT EXISTS (SELECT 1 FROM meeting WHERE uuid = ?)", arguments: [uuid]) ?? false
                guard exists else {
                    result.missing.insert(uuid)
                    continue
                }
                try db.execute(
                    sql: "UPDATE meeting SET deleted_at = NULL WHERE uuid = ? AND deleted_at IS NOT NULL",
                    arguments: [uuid])
                result.restored += db.changesCount
            }
            return result
        }
    }

    /// Puts back every meeting whose stamp is exactly this batch's (to the microsecond) and that still exists.
    /// Returns how many came back; a row deleted earlier or later is never touched.
    func restoreBatch(deletedAt: Date) throws -> Int {
        let micros = TrashStamp.micros(deletedAt)
        return try write { db in
            try db.execute(
                sql: """
                    UPDATE meeting SET deleted_at = NULL
                    WHERE deleted_at IS NOT NULL AND \(TrashStamp.microsSQL) = ?
                    """,
                arguments: [micros])
            return db.changesCount
        }
    }

    func trashedCount() throws -> Int {
        try read { db in try Int.fetchOne(db, sql: "SELECT count(*) FROM meeting WHERE deleted_at IS NOT NULL") ?? 0 }
    }

    /// Where a page of `trashedEntries` starts: after the row with this stamp (whole microseconds) and id.
    struct TrashPosition: Sendable, Equatable {
        var micros: Int64
        var id: Int64
    }

    /// The rows in Recently deleted, newest-deleted first, each with `deletedAt` (`id` descending breaks ties).
    func trashedEntries(after: TrashPosition? = nil, limit: Int) throws -> [MeetingLibraryEntry] {
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
                    SELECT \(Self.entryColumns(withTaskCount: true)) FROM meeting WHERE deleted_at IS NOT NULL \(cursor)
                    ORDER BY deleted_at DESC, id DESC LIMIT :limit
                    """,
                arguments: arguments
            ).map(Self.entry(from:))
        }
    }

    /// Which of these meetings are in Recently deleted, each with its stamp. Reads two columns, never a row's text.
    func trashedStamps(uuids: [String]) throws -> [String: Date] {
        guard !uuids.isEmpty else { return [:] }
        let marks = uuids.map { _ in "?" }.joined(separator: ", ")
        return try read { db in
            var result: [String: Date] = [:]
            for row in try Row.fetchAll(
                db,
                sql: "SELECT uuid, deleted_at FROM meeting WHERE uuid IN (\(marks)) AND deleted_at IS NOT NULL",
                arguments: StatementArguments(uuids))
            {
                result[row["uuid"]] = TrashStamp.date(column: row["deleted_at"])
            }
            return result
        }
    }

    /// Deletes the meetings that moved to Recently deleted before `cutoff` (the caller passes now - 30 days) and
    /// returns their `uuid`s, so the caller removes their spool and kept recording. Rows deleted since stay.
    @discardableResult
    func purgeTrashed(olderThan cutoff: Date, excluding: Set<Int64> = []) throws -> [String] {
        defer { pruneCaptureCounters() }
        return try write { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT id, uuid FROM meeting
                    WHERE deleted_at IS NOT NULL AND deleted_at < ? AND status NOT IN ('recording', 'processing')
                    """,
                arguments: [cutoff.timeIntervalSince1970]
            ).filter { !excluding.contains($0["id"] as Int64) }
            for row in rows {
                try db.execute(sql: "DELETE FROM meeting WHERE id = ?", arguments: [row["id"] as Int64])
            }
            return rows.map { $0["uuid"] as String }
        }
    }
}
