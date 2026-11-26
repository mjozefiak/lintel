import Foundation
import GRDB
import LintelCore

/// A read-only snapshot of one meeting: what the meeting window shows and `MarkdownExporter` writes.
struct MeetingDocument: Sendable, Equatable {
    struct Speaker: Sendable, Equatable, Identifiable {
        var id: Int64
        var label: String
        var isSelf: Bool
        var channel: AudioChannel
        /// Where the shown name came from and how sure the store is of it (`v5-speaker-names`); `nil` for a value
        /// this build does not know. Only the window and the Notes source read them; the export never does.
        var nameSource: NameSource? = .default
        var nameStatus: SpeakerNameStatus? = .confirmed
        /// The name waiting for the user's yes or no ("Marek?"); never part of the transcript or the notes.
        var suggestedName: String? = nil

        /// The suggestion to show: only while the row really waits for one, and only with visible text.
        var pendingSuggestion: String? {
            guard nameStatus == .suggested, let name = suggestedName.map(MeetingEdits.visible), !name.isEmpty
            else { return nil }
            return name
        }

        /// An automatic name the store is sure of (`applied`), shown without a mark.
        var isAppliedName: Bool {
            guard nameStatus == .applied else { return false }
            switch nameSource {
            case .platform, .calendar, .transcript: return true
            case .user, .me, .default, nil: return false
            }
        }
    }

    struct Segment: Sendable, Equatable, Identifiable {
        var id: Int64
        var channel: AudioChannel
        var startMs: Int
        var endMs: Int
        var speakerID: Int64?
        var text: String
    }

    var id: Int64
    var uuid: String
    var startedAt: Date
    var durationMs: Int
    var title: String?
    var status: MeetingStatus
    var speakerMode: SpeakerMode
    var audioState: AudioState
    var notesMarkdown: String?
    var notesStatus: NotesStatus
    var notesDroppedCount: Int
    var speakers: [Speaker]
    var segments: [Segment]
    /// The speech model the recording was made with (Details in the Notes workspace).
    var speechModelID: String? = nil
    /// When the recorder copied the consent sentence from the HUD; `nil` if never (MEET-1.6).
    var consentTextCopiedAt: Date? = nil
    /// The provider that wrote the notes and the exact model it reported (`notes_provider*`); `nil` for the
    /// built-in model and for notes never written by a provider.
    var notesProvider: String? = nil
    var notesProviderModel: String? = nil
    /// When the meeting moved to Recently deleted; `nil` for a live one. Only a read that asked for trashed
    /// meetings (`includingTrashed`) can return a document with it set.
    var deletedAt: Date? = nil

    func speaker(id: Int64?) -> Speaker? {
        guard let id else { return nil }
        return speakers.first { $0.id == id }
    }
}

enum MeetingActionError: Error, Equatable {
    /// The meeting is being recorded or processed; deleting it would pull the data from under the session.
    case active
    /// The audio spool folder could not be removed; the meeting was left as it was.
    case spoolNotRemoved
}

extension MeetingsStore {
    /// The whole meeting for the window and the export; `nil` when it does not exist, and for one in Recently
    /// deleted unless `includingTrashed` (only the Notes source asks: a note in Recently deleted still has its
    /// content).
    func loadDocument(id: Int64, includingTrashed: Bool = false) throws -> MeetingDocument? {
        try loadDocument(where: "id = ?", argument: id, includingTrashed: includingTrashed)
    }

    /// The same by the meeting's public `uuid` (the Notes workspace's key `meetings:<uuid>`).
    func loadDocument(uuid: String, includingTrashed: Bool = false) throws -> MeetingDocument? {
        try loadDocument(where: "uuid = ?", argument: uuid, includingTrashed: includingTrashed)
    }

    private func loadDocument(where condition: String, argument: any DatabaseValueConvertible, includingTrashed: Bool)
        throws -> MeetingDocument?
    {
        try read { db in
            guard
                let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM meeting WHERE \(condition)\(includingTrashed ? "" : " AND deleted_at IS NULL")",
                    arguments: [argument])
            else {
                return nil
            }
            let id: Int64 = row["id"]
            let speakers = try Row.fetchAll(
                db, sql: "SELECT * FROM meeting_speaker WHERE meeting_id = ? ORDER BY id", arguments: [id]
            ).map { row in
                MeetingDocument.Speaker(
                    id: row["id"], label: row["label"], isSelf: (row["is_self"] as Int) != 0,
                    channel: AudioChannel(rawValue: row["source_channel"]) ?? .mic,
                    nameSource: (row["name_source"] as String?).flatMap(NameSource.init(rawValue:)),
                    nameStatus: (row["name_status"] as String?).flatMap(SpeakerNameStatus.init(rawValue:)),
                    suggestedName: row["suggested_name"])
            }
            let segments = try Row.fetchAll(
                db, sql: "SELECT * FROM meeting_segment WHERE meeting_id = ? ORDER BY start_ms, id", arguments: [id]
            ).map { row in
                MeetingDocument.Segment(
                    id: row["id"], channel: AudioChannel(rawValue: row["channel"]) ?? .mic,
                    startMs: row["start_ms"], endMs: row["end_ms"], speakerID: row["speaker_id"],
                    text: row["text"])
            }
            return MeetingDocument(
                id: id, uuid: row["uuid"], startedAt: Date(timeIntervalSince1970: row["started_at"]),
                durationMs: row["duration_ms"], title: row["title"],
                status: MeetingStatus(rawValue: row["status"]) ?? .failed,
                speakerMode: SpeakerMode(rawValue: row["speaker_mode"]) ?? .none,
                audioState: AudioState(rawValue: row["audio_state"]) ?? .deleted,
                notesMarkdown: row["notes_markdown"],
                notesStatus: NotesStatus(rawValue: row["notes_status"]) ?? .none,
                notesDroppedCount: row["notes_dropped_count"], speakers: speakers, segments: segments,
                speechModelID: row["speech_model_id"],
                consentTextCopiedAt: (row["consent_text_copied_at"] as Int64?).map {
                    Date(timeIntervalSince1970: TimeInterval($0))
                },
                notesProvider: row["notes_provider"], notesProviderModel: row["notes_provider_model"],
                deletedAt: (row["deleted_at"] as Double?).map(TrashStamp.date(column:)))
        }
    }

    /// Sets the title of a meeting; a blank title (also one of invisible characters only) clears it (the
    /// library shows the date instead). The title is not part of the notes text, so the notes stay current.
    func renameMeeting(_ id: Int64, title: String) throws {
        let cleaned = MarkdownText.cleaned(title, keepNewlines: false)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        try setTitle(id, title: cleaned.isEmpty ? nil : cleaned)
    }

    /// Deletes a meeting (its speakers and segments go with it) and its audio spool folder, if one is left.
    ///
    /// One write transaction: the row is deleted only while the meeting is not `recording` or `processing`
    /// (so a "Dokończ" that claimed it a moment ago wins and nothing is lost), the spool folder is removed
    /// next and the transaction commits only when the folder is really gone. If it cannot be removed the
    /// whole delete is rolled back (`spoolNotRemoved`): the meeting stays, with its audio, and the user can
    /// try again. A spool folder without a row (a crash in between) is swept by `OrphanSpoolSweep`.
    /// Returns false when the meeting does not exist.
    @discardableResult
    func deleteMeeting(_ id: Int64, spool: any SpoolMaintenance) throws -> Bool {
        defer { pruneCaptureCounters() }
        return try write { db in
            guard
                let uuid = try String.fetchOne(
                    db, sql: "SELECT uuid FROM meeting WHERE id = ?", arguments: [id])
            else { return false }
            try db.execute(
                sql: "DELETE FROM meeting WHERE id = ? AND status NOT IN ('recording', 'processing')",
                arguments: [id])
            guard db.changesCount == 1 else { throw MeetingActionError.active }
            _ = spool.removeSpools(forMeetings: [uuid])
            if spool.hasSpool(forMeeting: uuid) { throw MeetingActionError.spoolNotRemoved }
            return true
        }
    }

    /// The `uuid` of every meeting row (what `OrphanSpoolSweep` compares the spool folders with).
    func allMeetingUUIDs() throws -> Set<String> {
        try read { db in Set(try String.fetchAll(db, sql: "SELECT uuid FROM meeting")) }
    }
}
