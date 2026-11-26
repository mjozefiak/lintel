import Foundation
import GRDB
import LintelKit
import Testing

@testable import NotesPlugin

/// Migration `v2-explorer` (notes explorer spec, Data Model): `note_doc.deleted_at`, the folder tables, the view that
/// leaves trashed documents out and the `note_fts_trash` trigger. All data is synthetic.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct NotesExplorerMigrationTests {
    private static func columns(_ db: Database, _ table: String) throws -> [String: Row] {
        var result: [String: Row] = [:]
        for row in try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))") { result[row["name"]] = row }
        return result
    }

    @Test func aFreshDatabaseHasDeletedAtTheFolderTablesAndTheTrashTrigger() throws {
        let queue = try DatabaseQueue()
        try NotesStore.migrator.migrate(queue)
        try queue.read { (db: Database) throws in
            let doc = try #require(try Self.columns(db, "note_doc")["deleted_at"])
            #expect((doc["type"] as String) == "REAL")
            #expect((doc["notnull"] as Int) == 0)
            let folder = try Self.columns(db, "note_folder")
            #expect(Set(folder.keys) == ["id", "uuid", "name", "created_at", "sort"])
            #expect(folder.values.filter { ($0["notnull"] as Int) == 1 }.count == 4)
            let entry = try Self.columns(db, "note_folder_entry")
            #expect(Set(entry.keys) == ["key", "folder_id", "added_at"])
            #expect((entry["key"]?["pk"] as Int?) == 1)
            let objects = Set(try String.fetchAll(db, sql: "SELECT name FROM sqlite_master"))
            #expect(objects.isSuperset(of: ["note_fts_trash", "note_doc_deleted", "note_doc_live", "note_fts_source"]))
            let index = try #require(
                try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'note_doc_deleted'"))
            #expect(index.lowercased().contains("where deleted_at is not null"))
        }
    }

    @Test func aV1DatabaseWithARowInEveryTableMigratesAndKeepsItsRowsLiveAndSearchable() throws {
        let queue = try DatabaseQueue()
        let migrator = NotesStore.migrator
        try migrator.migrate(queue, upTo: "v1-notes")
        let v1 = NotesStore(database: queue)
        let manual = try v1.insertDocument(.manual("a", body: "zażółć łąka", title: "Synthetic title"))
        let overlay = try v1.insertDocument(.overlay("m1", body: "overlay text"))
        try v1.appendRevision(
            NewNoteRevision(
                docID: overlay.docID, author: "human", state: .proposed, body: "a proposal",
                now: Date(timeIntervalSince1970: 200)))
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO note_comment (doc_id, thread_id, author, created_at, body, anchor_revision_id,
                        anchor_start, anchor_end, anchor_block_hash, anchor_quote)
                    VALUES (?, 1, 'human', 1, 'synthetic comment', ?, 0, 4, 'h', 'body')
                    """, arguments: [manual.docID, manual.revisionID])
        }
        // The v1 triggers filled the index (this build's own queries need the v2 column, so it is read directly).
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM note_fts") } == 2)

        try migrator.migrate(queue)
        #expect(try queue.read { try migrator.appliedIdentifiers($0) } == ["v1-notes", "v2-explorer"])
        let store = NotesStore(database: queue)
        try queue.read { (db: Database) throws in
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_doc") == 2)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_doc WHERE deleted_at IS NOT NULL") == 0)
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_revision") == 3)
            #expect(try String.fetchOne(db, sql: "SELECT body FROM note_comment") == "synthetic comment")
            #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_folder") == 0)
        }
        #expect(try store.manualOverlays().map(\.title) == ["Synthetic title"])
        #expect(try store.liveOverlays(for: [NoteKey(pluginID: "meetings", id: "m1")]).count == 1)
        // The index built before the migration still answers, and the triggers still follow a change.
        #expect(try store.search("laka").map(\.docID) == [manual.docID])
        #expect(try store.search("overlay").map(\.docID) == [overlay.docID])
        try store.setTitleOverride(key: NoteKey(pluginID: "notes", id: "a"), title: "Renamed", now: Date())
        #expect(try store.search("renamed").map(\.docID) == [manual.docID])
        #expect(try store.manualNoteCounts() == (live: 1, trashed: 0))
    }

    @Test func aBuildThatKnowsOnlyV1SeesTheMigratedDatabaseAsNewer() throws {
        let queue = try DatabaseQueue()
        try NotesStore.migrator.migrate(queue)
        let applied = try queue.read { try NotesStore.migrator.appliedIdentifiers($0) }
        // The rule `NotesStore.open` applies: an applied migration the build does not know makes it read-only.
        #expect(!applied.isSubset(of: ["v1-notes"]))
    }

    // MARK: The index and Recently deleted

    @Test func aTrashedDocumentLeavesTheIndexAndARestoredOneComesBack() throws {
        let harness = try NotesHarness()
        let store = try harness.openStore()
        let doc = try store.insertDocument(.manual("a", body: "quarterly budget", title: "Plan"))
        let key = NoteKey(pluginID: "notes", id: "a")
        #expect(try store.search("budget").map(\.docID) == [doc.docID])

        try store.trashManualNotes([key], at: Date(timeIntervalSince1970: 1_000))
        #expect(try store.search("budget").isEmpty)
        #expect(try store.search("plan").isEmpty)
        #expect(try ftsRows(store) == 0)

        try store.restoreManualNotes([key])
        #expect(try store.search("budget").map(\.docID) == [doc.docID])
        #expect(try store.search("plan").map(\.docID) == [doc.docID])
    }

    @Test func aTrashedDocumentIsNotIndexedAgainByATitleChangeOrANewRevision() throws {
        let harness = try NotesHarness()
        let store = try harness.openStore()
        let doc = try store.insertDocument(.manual("a", body: "first body"))
        let key = NoteKey(pluginID: "notes", id: "a")
        try store.trashManualNotes([key], at: Date(timeIntervalSince1970: 1_000))
        try store.setTitleOverride(key: key, title: "Fresh title", now: Date())
        try store.appendRevision(
            NewNoteRevision(
                docID: doc.docID, author: "human", state: .applied, body: "second body", now: Date(),
                expectedHeadID: doc.revisionID))
        #expect(try store.search("fresh").isEmpty)
        #expect(try store.search("second").isEmpty)
        #expect(try ftsRows(store) == 0)
        // Restored, it is indexed as it is now.
        try store.restoreManualNotes([key])
        #expect(try store.search("second").map(\.docID) == [doc.docID])
        #expect(try store.search("first").isEmpty)
        #expect(try store.search("fresh").map(\.docID) == [doc.docID])
    }

    @Test func aRebuildFromTheViewNeverIndexesATrashedDocument() throws {
        let harness = try NotesHarness()
        let store = try harness.openStore()
        try store.insertDocument(.manual("a", body: "kept words"))
        try store.insertDocument(.manual("b", body: "trashed words"))
        try store.trashManualNotes([NoteKey(pluginID: "notes", id: "b")], at: Date(timeIntervalSince1970: 1_000))
        try store.write { db in
            try db.execute(sql: "DELETE FROM note_fts")
            try db.execute(sql: "INSERT INTO note_fts(rowid, title, body) SELECT id, title, body FROM note_fts_source")
        }
        #expect(try store.search("words").count == 1)
        #expect(try store.search("trashed").isEmpty)
    }

    @Test func deletingAFolderRemovesItsEntriesButNoNote() throws {
        let harness = try NotesHarness()
        let store = try harness.openStore()
        try store.insertDocument(.manual("a"))
        try store.write { db in
            try db.execute(
                sql: "INSERT INTO note_folder (id, uuid, name, created_at, sort) VALUES (1, 'f-1', 'Clients', 1, 1)")
            try db.execute(sql: "INSERT INTO note_folder_entry (key, folder_id, added_at) VALUES ('notes:a', 1, 1)")
        }
        // One folder per key.
        #expect(throws: DatabaseError.self) {
            try store.write { db in
                try db.execute(
                    sql: "INSERT INTO note_folder (id, uuid, name, created_at, sort) VALUES (2, 'f-2', 'Other', 1, 2)")
                try db.execute(sql: "INSERT INTO note_folder_entry (key, folder_id, added_at) VALUES ('notes:a', 2, 1)")
            }
        }
        try store.write { db in try db.execute(sql: "DELETE FROM note_folder WHERE id = 1") }
        #expect(try store.folderEntryKeys().isEmpty)
        #expect(try store.manualOverlays().count == 1)
    }

    private func ftsRows(_ store: NotesStore) throws -> Int {
        try store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note_fts") ?? 0 }
    }
}
