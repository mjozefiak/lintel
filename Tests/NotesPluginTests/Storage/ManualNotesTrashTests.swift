import Foundation
import GRDB
import LintelKit
import Synchronization
import Testing

@testable import NotesPlugin

/// Notes' own Recently deleted for manual notes (`ManualNotesTrash`, a `TrashSource`): the contract scenarios of
/// `MeetingNoteSourceTrashContractTests` and `DictationNoteSourceTrashTests`, under the same names where they apply.
/// A manual note is never busy (no recording, no processing) and a `TrashSource` has no `content(for:)`, so those
/// two scenarios have no counterpart here. All data is synthetic.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct ManualNotesTrashTests {
    /// A store, a `ManualNotesTrash` over it on an injected clock, and a count of change announcements.
    @MainActor
    final class Rig {
        let harness: NotesHarness
        let store: NotesStore
        /// Shared with the source's closures.
        final class Shared: Sendable {
            let clock = Mutex(Date(timeIntervalSince1970: 1_800_000_000))
            let discarded = Mutex<Set<Int64>>([])
        }

        let changes = TrashChangeBroadcaster()
        let shared = Shared()
        var source: ManualNotesTrash!

        init() throws {
            harness = try NotesHarness()
            store = try harness.openStore()
            let store = store
            let shared = shared
            source = ManualNotesTrash(
                store: { store }, now: { shared.clock.withLock { $0 } }, changes: changes,
                discard: { ids in shared.discarded.withLock { $0.formUnion(ids) } })
        }

        var now: Date { shared.clock.withLock { $0 } }
        var discarded: Set<Int64> { shared.discarded.withLock { $0 } }
        func advance(_ seconds: TimeInterval) { shared.clock.withLock { $0 = $0.addingTimeInterval(seconds) } }

        /// A manual note with a title; returns its id (the key's raw value).
        @discardableResult
        func note(_ id: String, title: String? = nil, body: String = "synthetic body") throws -> String {
            try store.insertDocument(.manual(id, body: body, title: title ?? id))
            return "notes:\(id)"
        }
    }

    private let day: TimeInterval = 24 * 60 * 60

    @Test func theSourceIsNotesWithTitlesShown() throws {
        let rig = try Rig()
        #expect(rig.source.id == "notes")
        #expect(!rig.source.hidesContent)
    }

    @Test func aTrashedNoteLeavesTheListSearchAndCountsButStillExists() async throws {
        let rig = try Rig()
        let id = try rig.note("a", title: "Budget", body: "quarterly budget")
        try rig.note("b")
        try await rig.source.trash([id])
        #expect(try rig.store.manualOverlays().map(\.key.rawValue) == ["notes:b"])
        #expect(try rig.store.search("budget").isEmpty)
        #expect(try await rig.source.liveCount() == 1)
        #expect(try await rig.source.trashedCount() == 1)
        #expect(try rig.store.existingManualKeys([NoteKey(pluginID: "notes", id: "a")]).count == 1)
        #expect(try rig.store.exportRows().map(\.key.rawValue) == ["notes:b"])
    }

    @Test func trashOfAMissingNoteIsSkippedAndOfATrashedOneIsANoOpWithTheSameStamp() async throws {
        let rig = try Rig()
        let id = try rig.note("a")
        try await rig.source.trash(["notes:missing", "meetings:a", "not a key"])
        #expect(try await rig.source.trashedCount() == 0)
        try await rig.source.trash([id])
        let first = try await rig.source.trashed(after: nil, limit: 10).items.map(\.deletedAt)
        rig.advance(60)
        try await rig.source.trash([id])
        #expect(try await rig.source.trashed(after: nil, limit: 10).items.map(\.deletedAt) == first)
    }

    @Test func restoreOfALiveNoteIsANoOpAndAPartialBatchReturnsTheKeysThatAreGone() async throws {
        let rig = try Rig()
        let a = try rig.note("a")
        let b = try rig.note("b")
        #expect(try await rig.source.restore([a]).isEmpty)
        #expect(try await rig.source.liveCount() == 2)
        try await rig.source.trash([a, b])
        try await rig.source.deleteNow([b])
        let gone = try await rig.source.restore([a, b, "meetings:x"])
        #expect(gone == [b, "meetings:x"])
        #expect(try await rig.source.liveCount() == 1)
        #expect(try await rig.source.trashedCount() == 0)
    }

    @Test func trashedPagesNewestDeletedFirstWithDeletedAtAndPurgeAtOnEveryRow() async throws {
        let rig = try Rig()
        for id in ["a", "b", "c"] { try rig.note(id, title: "Title \(id)") }
        try await rig.source.trash(["notes:a"])
        rig.advance(10)
        try await rig.source.trash(["notes:b"])
        rig.advance(10)
        try await rig.source.trash(["notes:c"])
        let first = try await rig.source.trashed(after: nil, limit: 2)
        #expect(first.items.map(\.id) == ["notes:c", "notes:b"])
        #expect(first.items.map(\.title) == ["Title c", "Title b"])
        #expect(first.total == 3)
        for item in first.items {
            #expect(item.purgeAt == item.deletedAt.addingTimeInterval(30 * day))
        }
        let next = try #require(first.next)
        let second = try await rig.source.trashed(after: next, limit: 2)
        #expect(second.items.map(\.id) == ["notes:a"])
        #expect(second.next == nil)
    }

    /// Spec step 1.4: `trashAll` then `restoreBatch` restores exactly that batch and not a note deleted before it.
    @Test func trashAllThenRestoreBatchRestoresExactlyThatBatchAndNotANoteDeletedBeforeIt() async throws {
        let rig = try Rig()
        let earlier = try rig.note("earlier")
        try rig.note("x")
        try rig.note("y")
        try await rig.source.trash([earlier])
        rig.advance(60)
        let batch = try await rig.source.trashAll(at: rig.now)
        #expect(batch.moved == 2)
        #expect(batch.stayed == 0)
        rig.advance(60)
        let later = try rig.note("later")
        try await rig.source.trash([later])

        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 2)
        #expect(Set(try rig.store.manualOverlays().map(\.key.rawValue)) == ["notes:x", "notes:y"])
        #expect(Set(try await rig.source.trashed(after: nil, limit: 10).items.map(\.id)) == [earlier, later])
        // A second restore of the same batch finds nothing.
        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 0)
    }

    @Test func aSingleTrashNeverReusesABatchStamp() async throws {
        let rig = try Rig()
        try rig.note("a")
        let single = try rig.note("b")
        try rig.store.trashManualNotes([NoteKey(pluginID: "notes", id: "a")], at: rig.now)
        try await rig.source.trash([single])  // the same clock time as the batch stamp above
        let stamps = try await rig.source.trashed(after: nil, limit: 10).items
        #expect(Set(stamps.map(\.deletedAt)).count == 2)
        let microseconds = stamps.map { TrashStamp.micros($0.deletedAt) }.sorted()
        #expect(microseconds[1] - microseconds[0] == 1)
        #expect(try await rig.source.restoreBatch(deletedAt: rig.now) == 1)
        #expect(try rig.store.manualOverlays().map(\.key.rawValue) == ["notes:a"])
    }

    @Test func aStampReadBackAfterReopeningTheDatabaseEqualsTheOneWritten() async throws {
        let harness = try NotesHarness()
        let first = harness.opener()
        first.open()
        let store = try #require(first.store)
        try store.insertDocument(.manual("a"))
        try store.insertDocument(.manual("b"))
        // A time with a fraction finer than a microsecond: the stamp is rounded, and the batch still matches.
        let at = Date(timeIntervalSince1970: 1_800_000_123.456_789_4)
        #expect(try store.trashAllManualNotes(at: at) == 2)
        first.close()

        let second = harness.opener()
        second.open()
        let reopened = try #require(second.store)
        let page = try reopened.trashedManualNotes(after: nil, limit: 10)
        #expect(page.allSatisfy { TrashStamp.micros($0.deletedAt) == TrashStamp.micros(at) })
        #expect(try reopened.restoreManualBatch(deletedAt: at) == 2)
        #expect(try reopened.manualNoteCounts() == (live: 2, trashed: 0))
    }

    @Test func trashAndRestoreProcessMoreThanFiveHundredIdsInChunks() async throws {
        let rig = try Rig()
        let ids = (0..<1_203).map { "n\($0)" }
        try rig.store.write { db in
            for id in ids {
                try NotesStore.insertDocument(.manual(id), in: db)
            }
        }
        let all = ids.map { "notes:\($0)" }
        try await rig.source.trash(all)
        #expect(try await rig.source.trashedCount() == 1_203)
        #expect(try await rig.source.restore(all + ["notes:gone"]) == ["notes:gone"])
        #expect(try await rig.source.liveCount() == 1_203)
        try await rig.source.deleteNow(all)
        #expect(try await rig.source.liveCount() == 0)
    }

    @Test func deleteNowIsPermanentWorksOnATrashedNoteAndRemovesItsFolderEntry() async throws {
        let rig = try Rig()
        let id = try rig.note("a")
        try rig.note("b")
        try rig.store.write { db in
            try db.execute(
                sql: "INSERT INTO note_folder (id, uuid, name, created_at, sort) VALUES (1, 'f', 'Clients', 1, 1)")
            try db.execute(sql: "INSERT INTO note_folder_entry (key, folder_id, added_at) VALUES ('notes:a', 1, 1)")
        }
        let docID = try #require(try rig.store.liveDocument(key: NoteKey(pluginID: "notes", id: "a"), layer: "body")).id
        try await rig.source.trash([id])
        try await rig.source.deleteNow([id])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try rig.store.existingManualKeys([NoteKey(pluginID: "notes", id: "a")]).isEmpty)
        #expect(try rig.store.folderEntryKeys().isEmpty)
        #expect(rig.discarded == [docID])
        #expect(try await rig.source.restore([id]) == [id])
    }

    @Test func theChangeStreamIsToldAfterTrashRestoreTrashAllRestoreBatchDeleteAndPurge() async throws {
        let rig = try Rig()
        let told = CountLatch()
        let stream = rig.source.makeChanges()
        let watcher = Task {
            for await _ in stream { told.increment() }
        }
        defer { watcher.cancel() }
        let id = try rig.note("a")
        try await rig.source.trash([id])
        await told.wait(atLeast: 1)
        try await rig.source.restore([id])
        await told.wait(atLeast: 2)
        let batch = try await rig.source.trashAll(at: rig.now)
        await told.wait(atLeast: 3)
        try await rig.source.restoreBatch(deletedAt: batch.deletedAt)
        await told.wait(atLeast: 4)
        try await rig.source.deleteNow([id])
        await told.wait(atLeast: 5)
        // The purge (the sweep's retention) tells the same broadcaster; `finishAll` ends every stream.
        rig.changes.signal()
        await told.wait(atLeast: 6)
        rig.changes.finishAll()
        await watcher.value
    }

    // MARK: The 30-day purge

    @Test func aTrashedManualNoteIsPurgedThirtyDaysAfterItWasDeletedWithItsFolderEntryAndNotBefore() async throws {
        let rig = try Rig()
        let id = try rig.note("a")
        try rig.note("b")
        try rig.store.write { db in
            try db.execute(
                sql: "INSERT INTO note_folder (id, uuid, name, created_at, sort) VALUES (1, 'f', 'Clients', 1, 1)")
            try db.execute(sql: "INSERT INTO note_folder_entry (key, folder_id, added_at) VALUES ('notes:a', 1, 1)")
        }
        try await rig.source.trash([id])
        let deleted = rig.now
        // The store open and the first sweep never purge.
        #expect(try rig.store.applyRetention(now: deleted.addingTimeInterval(31 * day)) == 0)
        #expect(try rig.store.applyRetention(now: deleted.addingTimeInterval(30 * day - 1), purgesTrash: true) == 0)
        #expect(try await rig.source.trashedCount() == 1)
        let purged = try rig.store.applyRetentionReporting(now: deleted.addingTimeInterval(30 * day), purgesTrash: true)
        #expect(purged.purged == [NoteKey(pluginID: "notes", id: "a")])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.liveCount() == 1)
        #expect(try rig.store.folderEntryKeys().isEmpty)
    }

    @Test func aPurgeWaitsWhileTheNoteIsOpen() async throws {
        let rig = try Rig()
        let id = try rig.note("a")
        let docID = try #require(try rig.store.liveDocument(key: NoteKey(pluginID: "notes", id: "a"), layer: "body")).id
        try await rig.source.trash([id])
        let later = rig.now.addingTimeInterval(40 * day)
        #expect(try rig.store.applyRetention(excluding: [docID], now: later, purgesTrash: true) == 0)
        #expect(try rig.store.applyRetention(now: later, purgesTrash: true) == 1)
    }

    @Test func theOverlaysOfOtherOwnersAreNeverPurgedOnNotesClock() throws {
        let rig = try Rig()
        let overlay = try rig.store.insertDocument(.overlay("m1"))
        try rig.store.markOverlaysTrashed([NoteKey(pluginID: "meetings", id: "m1"): Date(timeIntervalSince1970: 0)])
        #expect(try rig.store.applyRetention(now: rig.now, purgesTrash: true) == 0)
        #expect(try rig.store.document(id: overlay.docID) != nil)
    }

    // MARK: Guards

    @Test func aDatabaseFromANewerLintelRefusesEveryMove() async throws {
        let harness = try NotesHarness()
        let first = harness.opener()
        first.open()
        let store = try #require(first.store)
        try store.insertDocument(.manual("a"))
        try store.write { db in try db.execute(sql: "INSERT INTO grdb_migrations(identifier) VALUES ('v3-future')") }
        first.close()
        let opener = harness.opener()
        opener.open()
        let reopened = try #require(opener.store)
        let source = ManualNotesTrash(store: { reopened }, changes: TrashChangeBroadcaster())
        await #expect(throws: NotesError.schemaNewer) { try await source.trash(["notes:a"]) }
        await #expect(throws: NotesError.schemaNewer) { _ = try await source.trashAll(at: Date()) }
        #expect(try await source.liveCount() == 1)
    }

    @Test func theHiddenReadOnlyKeyDoesNotBlockAMoveToRecentlyDeleted() async throws {
        let harness = try NotesHarness()
        let store = try harness.openStore()
        try store.insertDocument(.manual("a"))
        harness.settingsStore.setValue(.bool(true), forKey: "plugins.notes.readOnly")
        #expect(throws: NotesError.readOnly) { try store.insertDocument(.manual("b")) }
        let source = ManualNotesTrash(store: { store }, changes: TrashChangeBroadcaster())
        try await source.trash(["notes:a"])
        #expect(try await source.trashedCount() == 1)
    }

    /// The lazy-store rule: Recently deleted on a fresh profile answers 0 and empty pages, and every move is a no-op,
    /// without a Keychain lookup or a file.
    @Test func aFreshProfileAnswersNothingWithoutAKeychainItemOrAFile() async throws {
        let storage = FileManager.default.temporaryDirectory.appending(
            path: "lintel-notes-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: storage) }
        let keychain = CountingKeychain()
        let plugin = NotesPlugin(context: makeContext(storage: storage, keychain: keychain))
        try await plugin.activate()
        let source = try #require(plugin.trashSources.first)
        #expect(plugin.trashSources.count == 1)
        #expect(source.id == "notes")
        #expect(try await source.liveCount() == 0)
        #expect(try await source.trashedCount() == 0)
        #expect(try await source.trashed(after: nil, limit: 10).items.isEmpty)
        try await source.trash(["notes:a"])
        #expect(try await source.restore(["notes:a"]) == ["notes:a"])
        #expect(try await source.trashAll(at: Date()).moved == 0)
        #expect(try await source.restoreBatch(deletedAt: Date()) == 0)
        await plugin.deactivate()
        #expect(keychain.calls == 0)
        #expect(!FileManager.default.fileExists(atPath: storage.path))
    }
}
