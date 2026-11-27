import Foundation
import GRDB
import LintelPersistence
import Testing

@testable import MeetingsPlugin

/// Migration `v5-speaker-names` (spec `2026-11-25-meeting-speaker-names`, Data Model): the name columns of
/// `meeting_speaker`, their backfill and the evidence table. All names are fictional.
@Suite struct SpeakerNamesMigrationTests {
    private static let earlier = [
        "v1-meetings", "v2-consent", "v3-notes-provider", "v4-notes-awaiting-model", "v4-trash",
    ]

    /// A database in the schema after `v4-trash` holding: a diarized meeting with default, own and typed labels; a
    /// `channels` meeting with its track labels; a trashed meeting.
    private func previousDatabase() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue, upTo: "v4-trash")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (id, uuid, started_at, status, speaker_mode, deleted_at) VALUES
                        (1, 'diarized', 1000, 'ready', 'diarized', NULL),
                        (2, 'channels', 2000, 'ready', 'channels', NULL),
                        (3, 'trashed', 3000, 'ready', 'diarized', 4000.5);
                    INSERT INTO meeting_speaker (id, meeting_id, label, is_self, source_channel) VALUES
                        (1, 1, 'Rozmówca 1', 0, 'system'),
                        (2, 1, 'Speaker 2', 0, 'system'),
                        (3, 1, 'Ja', 1, 'mic'),
                        (4, 1, 'Anna Testowa', 0, 'system'),
                        (5, 2, 'Ja', 1, 'mic'),
                        (6, 2, 'Inni', 0, 'system'),
                        (7, 2, 'Mówca 1', 0, 'mic'),
                        (8, 3, 'Mówca 2', 0, 'system'),
                        (9, 3, 'Marek', 0, 'system');
                    INSERT INTO meeting_segment (id, meeting_id, channel, start_ms, end_ms, speaker_id, text) VALUES
                        (1, 1, 'system', 0, 1000, 4, 'Synthetic text');
                    """)
        }
        return queue
    }

    private func speakers(_ queue: DatabaseQueue) throws -> [Int64: (label: String, isSelf: Bool, source: String)] {
        try queue.read { db in
            var result: [Int64: (String, Bool, String)] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT id, label, is_self, name_source FROM meeting_speaker") {
                result[row["id"]] = (row["label"], row["is_self"], row["name_source"])
            }
            return result
        }
    }

    @Test func theBackfillGivesSelfDefaultAndUserAndKeepsEveryLabel() throws {
        let queue = try previousDatabase()
        try MeetingsStore.migrator.migrate(queue)
        let applied = try queue.read { try MeetingsStore.migrator.appliedIdentifiers($0) }
        #expect(applied == Set(Self.earlier + ["v5-speaker-names"]))

        let rows = try speakers(queue)
        let expected: [Int64: (String, Bool, String)] = [
            1: ("Rozmówca 1", false, "default"),
            2: ("Speaker 2", false, "default"),
            3: ("Ja", true, "self"),
            4: ("Anna Testowa", false, "user"),
            5: ("Ja", true, "self"),
            6: ("Inni", false, "default"),
            7: ("Mówca 1", false, "default"),
            8: ("Mówca 2", false, "default"),
            9: ("Marek", false, "user"),
        ]
        #expect(rows.count == expected.count)
        for (id, want) in expected {
            let row = try #require(rows[id])
            #expect(row.label == want.0, "label of \(id)")
            #expect(row.isSelf == want.1, "is_self of \(id)")
            #expect(row.source == want.2, "name_source of \(id)")
        }
        let rest = try queue.read { db in
            try Row.fetchAll(db, sql: "SELECT name_status, suggested_name, rejected_names FROM meeting_speaker")
        }
        #expect(rest.allSatisfy { ($0["name_status"] as String) == "confirmed" })
        #expect(
            rest.allSatisfy { ($0["suggested_name"] as String?) == nil && ($0["rejected_names"] as String?) == nil })
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM meeting_name_evidence") } == 0)
        // The trashed meeting is still trashed and its segment still points at its speaker.
        #expect(
            try queue.read { try Double.fetchOne($0, sql: "SELECT deleted_at FROM meeting WHERE id = 3") } == 4000.5)
        #expect(try queue.read { try Int64.fetchOne($0, sql: "SELECT speaker_id FROM meeting_segment") } == 4)
    }

    @Test func aChannelsTrackTheUserRenamedIsStillDefaultAndItsOwnTrackIsSelf() throws {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue, upTo: "v4-trash")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (id, uuid, started_at, speaker_mode) VALUES (1, 'c', 1, 'channels');
                    INSERT INTO meeting_speaker (id, meeting_id, label, is_self, source_channel) VALUES
                        (1, 1, 'Zespół', 0, 'system'), (2, 1, 'Ala Testowa', 1, 'mic');
                    """)
        }
        try MeetingsStore.migrator.migrate(queue)
        let rows = try speakers(queue)
        #expect(rows[1]?.source == "default")
        #expect(rows[2]?.source == "self")
    }

    /// The generic labels are frozen in the migration's SQL; near misses are names the user typed.
    @Test(arguments: [
        ("Ja", true), ("Ja 2", true), ("Inni", true), ("Inni 3", true), ("Mówca", true), ("Mówca 1", true),
        ("Mówca 12", true), ("Rozmówca", true), ("Rozmówca 4", true), ("Speaker", true), ("Speaker 2", true),
        ("Janek", false), ("Inni ludzie", false), ("Mówca1", false), ("Mówca 1a", false), ("mówca 1", false),
        ("Mówca  1", false), ("Mówca 1 2", false), ("Speakers 2", false), ("Anna Testowa", false), ("", false),
    ])
    func theFrozenGenericRuleClassifiesLabels(label: String, generic: Bool) throws {
        let queue = try DatabaseQueue()
        let result = try queue.read { db in
            try Bool.fetchOne(
                db, sql: "SELECT \(MeetingsStore.frozenGenericLabelSQL("?"))",
                arguments: StatementArguments(Array(repeating: label, count: 11)))
        }
        #expect(result == generic)
    }

    /// The labels the code writes today must stay generic for the frozen rule; changing `SpeakerLabels` fails here
    /// and needs a new migration.
    @Test func everyLabelTheCodeWritesIsGenericForTheFrozenRule() throws {
        let queue = try DatabaseQueue()
        let labels = [SpeakerLabels.me, SpeakerLabels.others] + (1...12).map(SpeakerLabels.numbered)
        for label in labels {
            let generic = try queue.read { db in
                try Bool.fetchOne(
                    db, sql: "SELECT \(MeetingsStore.frozenGenericLabelSQL("?"))",
                    arguments: StatementArguments(Array(repeating: label, count: 11)))
            }
            #expect(generic == true, "\(label)")
        }
    }

    /// The rule is frozen: adding, removing or changing a word changes this text and needs a new migration.
    @Test func theFrozenGenericRuleIsExactlyThisSQL() {
        let words = [("Ja", 4), ("Inni", 6), ("Mówca", 7), ("Rozmówca", 10), ("Speaker", 9)]
        let numbered = words.map { "(label GLOB '\($0.0) [0-9]*' AND substr(label, \($0.1)) NOT GLOB '*[^0-9]*')" }
        #expect(
            MeetingsStore.frozenGenericLabelSQL("label")
                == "(label IN ('Ja', 'Inni', 'Mówca', 'Rozmówca', 'Speaker') OR "
                + numbered.joined(separator: " OR ") + ")")
        #expect(
            numbered[2] == "(label GLOB 'Mówca [0-9]*' AND substr(label, 7) NOT GLOB '*[^0-9]*')")
    }

    @Test func aFreshDatabaseHasTheColumnsTheirDefaultsAndTheEvidenceTable() throws {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue)
        let columns = try queue.read { try Row.fetchAll($0, sql: "PRAGMA table_info(meeting_speaker)") }
        func column(_ name: String) throws -> Row { try #require(columns.first { ($0["name"] as String) == name }) }
        #expect((try column("name_source")["dflt_value"] as String) == "'default'")
        #expect((try column("name_source")["notnull"] as Int) == 1)
        #expect((try column("name_status")["dflt_value"] as String) == "'confirmed'")
        #expect((try column("name_status")["notnull"] as Int) == 1)
        #expect((try column("suggested_name")["notnull"] as Int) == 0)
        #expect((try column("rejected_names")["notnull"] as Int) == 0)

        let keys = try queue.read { try Row.fetchAll($0, sql: "PRAGMA foreign_key_list(meeting_name_evidence)") }
        let rules = Dictionary(
            uniqueKeysWithValues: keys.map {
                ($0["from"] as String, "\($0["table"] as String) \($0["on_delete"] as String)")
            })
        #expect(
            rules == [
                "meeting_id": "meeting CASCADE", "speaker_id": "meeting_speaker SET NULL",
                "segment_id": "meeting_segment SET NULL",
            ])
        let index = try queue.read {
            try String.fetchOne(
                $0, sql: "SELECT sql FROM sqlite_master WHERE name = 'meeting_name_evidence_on_meeting_id'")
        }
        #expect(index?.lowercased().contains("on meeting_name_evidence(meeting_id)") == true)
    }

    @Test func theMigrationIsRegisteredLastAfterTrash() {
        #expect(MeetingsStore.migrator.migrations == Self.earlier + ["v5-speaker-names"])
    }

    /// The rollback note: an older build, whose migrator has never heard of `v5-speaker-names`, opens the migrated
    /// database read-write (Meetings has no "newer migration" read-only rule; GRDB ignores an applied migration it
    /// does not know) and its writes, which never name the new columns, keep working.
    @Test func anOlderBuildThatDoesNotKnowTheMigrationStillOpensAndWritesTheDatabase() throws {
        let queue = try previousDatabase()
        try MeetingsStore.migrator.migrate(queue)
        var older = DatabaseMigrator()
        for name in Self.earlier {
            older.registerMigration(name) { _ in Issue.record("an applied migration ran again") }
        }
        try older.migrate(queue)
        try queue.write { db in
            // The older build's own statements: a new speaker and a rename.
            try db.execute(
                sql:
                    "INSERT INTO meeting_speaker (meeting_id, label, is_self, source_channel) VALUES (1, 'Mówca 5', 0, 'mic')"
            )
            try db.execute(sql: "UPDATE meeting_speaker SET label = 'Ewa' WHERE id = 1")
        }
        let rows = try speakers(queue)
        #expect(rows.count == 10)
        #expect(rows[1]?.label == "Ewa")
        // The older rename does not mark the name as the user's (the residual risk of a downgrade).
        #expect(rows[1]?.source == "default")
        #expect(rows.values.contains { $0.label == "Mówca 5" && $0.source == "default" })
    }
}
