import Foundation
import GRDB

/// The speakers' names and their evidence (migration `v5-speaker-names`, spec `2026-11-25-meeting-speaker-names`,
/// Data Model). A name the user gave (`user`), the user's own speaker (`self`) and a name the user confirmed are
/// never overwritten by a resolution; the guard is in the SQL `WHERE`, so no caller can skip it. Names, quotes and
/// transcript text never reach a log.
extension MeetingsStore {
    enum SpeakerNamesError: Error, Equatable {
        /// A resolution may only write automatic names: `user` and `self` are written by the user's own actions
        /// (`renameSpeaker`, `confirmSuggestedName`, `markSelf`), and `confirmed` only goes with `default` (a
        /// speaker reset to its default label).
        case notAnAutomaticName
    }

    /// One speaker's name as the store holds it.
    struct SpeakerNameState: Equatable, Sendable {
        let speakerID: Int64
        let label: String
        let isSelf: Bool
        /// `nil` for a value this build does not know (written by a newer one); such a row is never overwritten.
        let source: NameSource?
        let status: SpeakerNameStatus?
        let suggestedName: String?
        /// The names the user refused for this cluster ("To nie Marek"), oldest first.
        let rejectedNames: [String]
    }

    /// One row of `meeting_name_evidence`: ids instead of the pure layer's labels and indexes (`NameEvidence`). The
    /// quote is not stored; `segmentID` points at it.
    struct StoredNameEvidence: Equatable, Sendable {
        var speakerID: Int64?
        var source: NameSource
        var name: String
        var kind: NameEvidenceKind?
        var segmentID: Int64?
        var startMs: Int?
        var endMs: Int?
        var strength: Double
    }

    /// What a resolution writes for one speaker: the label shown (the name for `applied`, the default label for
    /// `suggested` and for a speaker left without a name), its source and status and the waiting suggestion.
    struct SpeakerNameUpdate: Equatable, Sendable {
        var speakerID: Int64
        var label: String
        var source: NameSource
        var status: SpeakerNameStatus
        var suggestedName: String?

        var isAutomatic: Bool {
            switch source {
            case .user, .me: false
            case .default: true
            case .platform, .calendar, .transcript: status != .confirmed
            }
        }
    }

    /// The SQL test of a speaker row a resolution may overwrite: not the user's own speaker, a known automatic
    /// source, and either no name yet (`default`) or an automatic result (`applied`, `suggested`). Everything else
    /// (`user`, `self`, a confirmed name, a value from a newer build) is left alone.
    static let overwritableSpeakerNameSQL = """
        is_self = 0
        AND name_source IN ('default', 'platform', 'calendar', 'transcript')
        AND (name_source = 'default' OR name_status IN ('applied', 'suggested'))
        """

    // MARK: Reading

    /// The name state of every speaker of the meeting, in id order.
    func speakerNameStates(meetingID: Int64) throws -> [SpeakerNameState] {
        try read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, label, is_self, name_source, name_status, suggested_name, rejected_names
                    FROM meeting_speaker WHERE meeting_id = ? ORDER BY id
                    """,
                arguments: [meetingID]
            ).map { row in
                SpeakerNameState(
                    speakerID: row["id"], label: row["label"], isSelf: row["is_self"],
                    source: NameSource(rawValue: row["name_source"]),
                    status: SpeakerNameStatus(rawValue: row["name_status"]),
                    suggestedName: row["suggested_name"],
                    rejectedNames: Self.decodeNames(row["rejected_names"]))
            }
        }
    }

    /// The evidence stored for the meeting, in the order it was written. A row with a source this build does not
    /// know is left out.
    func nameEvidence(meetingID: Int64) throws -> [StoredNameEvidence] {
        try read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT speaker_id, source, name, kind, segment_id, start_ms, end_ms, strength
                    FROM meeting_name_evidence WHERE meeting_id = ? ORDER BY id
                    """,
                arguments: [meetingID]
            ).compactMap { row -> StoredNameEvidence? in
                guard let source = NameSource(rawValue: row["source"]) else { return nil }
                return StoredNameEvidence(
                    speakerID: row["speaker_id"], source: source, name: row["name"],
                    kind: (row["kind"] as String?).flatMap(NameEvidenceKind.init(rawValue:)),
                    segmentID: row["segment_id"], startMs: row["start_ms"], endMs: row["end_ms"],
                    strength: row["strength"])
            }
        }
    }

    // MARK: Writing

    /// Writes a resolution in one transaction: each update goes to its speaker only when the row may be
    /// overwritten (`overwritableSpeakerNameSQL`), `rejected_names` is never touched, and the meeting's evidence
    /// is replaced by `evidence` (a speaker or segment id of another meeting is stored as NULL). When a label
    /// changed and the meeting has notes (or notes being written), they become `stale`, like after a rename.
    /// Returns the ids of the speakers that were written.
    @discardableResult
    func saveSpeakerNames(_ updates: [SpeakerNameUpdate], evidence: [StoredNameEvidence], meetingID: Int64) throws
        -> Set<Int64>
    {
        guard updates.allSatisfy(\.isAutomatic) else { throw SpeakerNamesError.notAnAutomaticName }
        return try write { db in
            var written: Set<Int64> = []
            var labelChanged = false
            for update in updates {
                let oldLabel = try String.fetchOne(
                    db, sql: "SELECT label FROM meeting_speaker WHERE id = ? AND meeting_id = ?",
                    arguments: [update.speakerID, meetingID])
                try db.execute(
                    sql: """
                        UPDATE meeting_speaker
                        SET label = ?, name_source = ?, name_status = ?, suggested_name = ?
                        WHERE id = ? AND meeting_id = ? AND \(Self.overwritableSpeakerNameSQL)
                        """,
                    arguments: [
                        update.label, update.source.rawValue, update.status.rawValue, update.suggestedName,
                        update.speakerID, meetingID,
                    ])
                guard db.changesCount > 0 else { continue }
                written.insert(update.speakerID)
                if oldLabel != update.label { labelChanged = true }
            }
            try db.execute(sql: "DELETE FROM meeting_name_evidence WHERE meeting_id = ?", arguments: [meetingID])
            for item in evidence {
                try db.execute(
                    sql: """
                        INSERT INTO meeting_name_evidence
                            (meeting_id, speaker_id, source, name, kind, segment_id, start_ms, end_ms, strength)
                        VALUES (
                            ?, (SELECT id FROM meeting_speaker WHERE id = ? AND meeting_id = ?), ?, ?, ?,
                            (SELECT id FROM meeting_segment WHERE id = ? AND meeting_id = ?), ?, ?, ?)
                        """,
                    arguments: [
                        meetingID, item.speakerID, meetingID, item.source.rawValue, item.name, item.kind?.rawValue,
                        item.segmentID, meetingID, item.startMs, item.endMs, item.strength,
                    ])
            }
            if labelChanged { try Self.markNotesStale(meetingID: meetingID, in: db) }
            return written
        }
    }

    /// "Tak" on a suggestion: the suggested name becomes the label, the user's own (`user`, `confirmed`, so no
    /// resolution overwrites it; where it came from stays in the evidence), and the notes become `stale`, like
    /// after a rename. Only when the speaker still suggests `name` (the screen may be older than the row).
    /// Returns false when it does not.
    @discardableResult
    func confirmSuggestedName(speakerID: Int64, name: String) throws -> Bool {
        try write { db in
            try db.execute(
                sql: """
                    UPDATE meeting_speaker
                    SET label = suggested_name, name_source = 'user', name_status = 'confirmed', suggested_name = NULL
                    WHERE id = ? AND name_status = 'suggested' AND suggested_name IS NOT NULL AND suggested_name = ?
                    """,
                arguments: [speakerID, name])
            guard db.changesCount > 0 else { return false }
            guard
                let meetingID = try Int64.fetchOne(
                    db, sql: "SELECT meeting_id FROM meeting_speaker WHERE id = ?", arguments: [speakerID])
            else { return true }
            try Self.markNotesStale(meetingID: meetingID, in: db)
            return true
        }
    }

    /// "Nie" on a suggestion: the name joins the cluster's `rejected_names` (once, whatever its case) and the
    /// speaker is left without a name (`default`, the label unchanged). The notes stay current: they never used a
    /// suggestion. Only when the speaker still suggests `name`; returns false when it does not.
    @discardableResult
    func rejectSuggestedName(speakerID: Int64, name: String) throws -> Bool {
        try write { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT rejected_names FROM meeting_speaker
                        WHERE id = ? AND name_status = 'suggested' AND suggested_name IS NOT NULL
                            AND suggested_name = ?
                        """,
                    arguments: [speakerID, name])
            else { return false }
            var rejected = Self.decodeNames(row["rejected_names"])
            if !rejected.contains(where: { $0.lowercased() == name.lowercased() }) { rejected.append(name) }
            try db.execute(
                sql: """
                    UPDATE meeting_speaker
                    SET name_source = 'default', name_status = 'confirmed', suggested_name = NULL, rejected_names = ?
                    WHERE id = ?
                    """,
                arguments: [Self.encodeNames(rejected), speakerID])
            return true
        }
    }

    // MARK: Helpers

    private static func markNotesStale(meetingID: Int64, in db: Database) throws {
        try db.execute(
            sql: """
                UPDATE meeting SET notes_status = 'stale'
                WHERE id = ? AND (notes_markdown IS NOT NULL OR notes_status = 'running')
                """,
            arguments: [meetingID])
    }

    /// `rejected_names` is a JSON array of strings; NULL or anything else reads as no names.
    static func decodeNames(_ json: String?) -> [String] {
        guard let data = json?.data(using: .utf8),
            let names = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return names
    }

    static func encodeNames(_ names: [String]) -> String {
        guard let data = try? JSONEncoder().encode(names), let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
    }
}
