import Foundation
import GRDB
import LintelPersistence
import Testing

@testable import MeetingsPlugin

/// Migration `v4-trash` (notes explorer spec, Data Model): `meeting.deleted_at` and a partial index. All data is
/// synthetic. A previous-schema database with a row in every table is migrated and read back.
@Suite struct TrashMigrationTests {
    @Test func aFreshDatabaseHasTheNullableDeletedAtColumnAndThePartialIndex() throws {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue)
        let columns = try queue.read { try Row.fetchAll($0, sql: "PRAGMA table_info(meeting)") }
        let column = try #require(columns.first { ($0["name"] as String) == "deleted_at" })
        #expect((column["type"] as String) == "REAL")
        #expect((column["notnull"] as Int) == 0)
        #expect((column["dflt_value"] as String?) == nil)
        let index = try #require(
            try queue.read {
                try Row.fetchOne(
                    $0, sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'meeting_deleted'")
            })
        let definition = (index["sql"] as String).lowercased()
        #expect(definition.contains("on meeting(deleted_at)"))
        #expect(definition.contains("where deleted_at is not null"))
        try queue.write {
            try $0.execute(sql: "INSERT INTO meeting (uuid, started_at, status) VALUES ('n', 1, 'ready')")
        }
        #expect(try queue.read { try Double?.fetchOne($0, sql: "SELECT deleted_at FROM meeting") } == .some(nil))
    }

    @Test func aDatabaseFromBeforeTheMigrationKeepsEveryTableAndReadsEveryMeetingAsLive() throws {
        let queue = try DatabaseQueue()
        let migrator = MeetingsStore.migrator
        try migrator.migrate(queue, upTo: "v4-notes-awaiting-model")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (id, uuid, started_at, title, status, audio_state, notes_markdown, notes_status,
                        notes_provider, notes_awaiting_model)
                    VALUES (1, 'old-a', 1000, 'Synthetic title', 'ready', 'kept', 'Synthetic notes', 'ok', 'claude-code', 0),
                        (2, 'old-b', 2000, NULL, 'incomplete', 'spool', NULL, 'none', NULL, 1)
                    """)
            try db.execute(
                sql:
                    "INSERT INTO meeting_speaker (id, meeting_id, label, is_self, source_channel) VALUES (1, 1, 'Anna', 0, 'system')"
            )
            try db.execute(
                sql: """
                    INSERT INTO meeting_segment (id, meeting_id, channel, start_ms, end_ms, speaker_id, text)
                    VALUES (1, 1, 'system', 0, 1000, 1, 'Synthetic zażółć text')
                    """)
        }
        try migrator.migrate(queue)
        #expect(
            try queue.read { try migrator.appliedIdentifiers($0) }
                == ["v1-meetings", "v2-consent", "v3-notes-provider", "v4-notes-awaiting-model", "v4-trash"])

        let store = MeetingsStore(database: queue)
        // Every value survived and every row is live.
        let rows = try queue.read {
            try Row.fetchAll(
                $0, sql: "SELECT uuid, title, notes_provider, deleted_at FROM meeting ORDER BY id")
        }
        #expect(rows.map { $0["uuid"] as String } == ["old-a", "old-b"])
        #expect((rows[0]["title"] as String) == "Synthetic title")
        #expect((rows[0]["notes_provider"] as String) == "claude-code")
        #expect(rows.allSatisfy { ($0["deleted_at"] as Double?) == nil })
        #expect(try store.meetingCount() == 2)
        #expect(try store.speakerCount(meetingID: 1) == 1)
        #expect(try store.segmentCount(meetingID: 1) == 1)
        // The full-text indexes built before the migration still find the rows, through the filtered reads.
        #expect(try store.searchSegments("zazolc", limit: 5) == [1])
        #expect(try store.searchNotes("notes", limit: 5) == [1])
        let entries = try store.libraryEntries(matching: nil, filter: .all, limit: 10)
        #expect(entries.map(\.uuid) == ["old-b", "old-a"])
        #expect(entries.allSatisfy { $0.deletedAt == nil })
        #expect(try store.trashedCount() == 0)
    }

    @Test func theMigrationIsRegisteredAfterEveryEarlierOne() {
        let names = MeetingsStore.migrator.migrations
        #expect(names.last == "v4-trash")
        #expect(
            names.firstIndex(of: "v4-notes-awaiting-model") == names.index(before: names.index(before: names.endIndex)))
    }

    /// The rollback note: an older build, whose migrator has never heard of `v4-trash`, opens the migrated database
    /// without an error and without touching it (GRDB ignores an applied migration it does not know).
    @Test func anOlderBuildThatDoesNotKnowTheMigrationStillOpensTheDatabase() throws {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue)
        try queue.write {
            try $0.execute(
                sql: "INSERT INTO meeting (uuid, started_at, status, deleted_at) VALUES ('trashed', 1, 'ready', 5.5)")
        }
        var older = DatabaseMigrator()
        for name in ["v1-meetings", "v2-consent", "v3-notes-provider", "v4-notes-awaiting-model"] {
            older.registerMigration(name) { _ in Issue.record("an applied migration ran again") }
        }
        try older.migrate(queue)
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM meeting") } == 1)
        // The column is untouched: the older build never names it, so it reads the row as a live one.
        #expect(try queue.read { try Double.fetchOne($0, sql: "SELECT deleted_at FROM meeting") } == 5.5)
    }
}
