import Foundation
import GRDB
import LintelKit
import Synchronization
import Testing

@testable import NotesPlugin

/// The trash sweep (notes explorer spec, Deletion lifecycle, step 1.4): marks, search guard, purge and folder entries.
/// All data is synthetic.
@MainActor
@Suite(.finishesRigs, .timeLimit(.minutes(1))) struct NoteTrashSweepTests {
    /// A `ReconRig` whose meetings source has Recently deleted.
    @MainActor
    final class TrashRig {
        let r: ReconRig
        let owner: TrashingNoteSource
        let sweep: NoteTrashSweep

        init() throws {
            r = try ReconRig()
            owner = TrashingNoteSource(r.source)
            r.box.sources = [owner]
            sweep = NoteTrashSweep(store: r.store, library: r.library, clock: r.rig.clock, log: r.rig.log)
        }

        var store: NotesStore { r.store }
        var key: NoteKey { r.key }

        /// The `deleted_at` of every live document of the key, in microseconds (`nil` = live).
        func marks(_ key: NoteKey? = nil) throws -> [Int64?] {
            try store.read { db in
                try Row.fetchAll(
                    db,
                    sql: """
                        SELECT deleted_at FROM note_doc WHERE key = ? AND source_state IS NOT 'detached' ORDER BY id
                        """, arguments: [(key ?? self.key).rawValue]
                ).map { ($0["deleted_at"] as Double?).map(TrashStamp.micros(column:)) }
            }
        }

        func documents(_ key: NoteKey? = nil) throws -> Int {
            try store.read { db in
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM note_doc WHERE key = ?", arguments: [(key ?? self.key).rawValue])
                    ?? 0
            }
        }
    }

    private let deletedAt = Date(timeIntervalSince1970: 1_800_000_500.25)

    // MARK: Search

    @Test func aKeyTrashedByItsOwnerHidesItsOverlaysFromSearchBeforeAndAfterTheSweep() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        t.r.publish([layer])
        try await t.r.editedOverlay(layer, text: "budget review with the team")
        let hits = try t.store.search("budget")
        #expect(hits.count == 1)
        #expect(await t.sweep.visibleHits(hits) == hits)

        // The owner trashed the note in the launcher's panel; the sweep has not run yet.
        t.owner.trashed = [t.key: deletedAt]
        #expect(try t.store.search("budget").count == 1)
        #expect(await t.sweep.visibleHits(try t.store.search("budget")).isEmpty)
        #expect(t.owner.trashedKeysCalls.last == [t.key])  // one call for the page

        // After the sweep the index itself has dropped it.
        let result = await t.sweep.run()
        #expect(result.marked == 1)
        #expect(try t.store.search("budget").isEmpty)
        #expect(try t.marks() == [TrashStamp.micros(deletedAt)])

        // Restored by its owner: back in search after the next sweep.
        t.owner.trashed = [:]
        #expect(await t.sweep.run().cleared == 1)
        #expect(try t.store.search("budget").count == 1)
        #expect(try t.marks() == [nil])
    }

    @Test func aSourceThatCannotAnswerKeepsItsHitsAndItsMarks() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        try await t.r.editedOverlay(layer, text: "budget")
        t.owner.trashed = [t.key: deletedAt]
        t.owner.trashedKeysBehavior = .throwsError
        let hits = try t.store.search("budget")
        #expect(await t.sweep.visibleHits(hits) == hits)
        #expect(await t.sweep.run() == NoteTrashSweep.Result())
        #expect(try t.marks() == [nil])
    }

    @Test func detachedHitsAndManualNotesAreNeverAskedAbout() async throws {
        let t = try TrashRig()
        try t.store.insertDocument(.manual("a", body: "budget one"))
        try t.store.insertDocument(.overlay("old", body: "budget two", state: .detached))
        let hits = try t.store.search("budget")
        #expect(hits.count == 2)
        #expect(await t.sweep.visibleHits(hits) == hits)
        #expect(t.owner.trashedKeysCalls.isEmpty)
    }

    // MARK: Marks

    @Test func theSweepMarksEveryLiveLayerMineIncludedWithTheOwnersTimeAndLeavesDetachedRows() async throws {
        let t = try TrashRig()
        try t.store.insertDocument(.overlay("m1", layer: "notes"))
        try t.store.insertDocument(.overlay("m1", layer: "transcript", author: "stt"))
        try t.store.insertDocument(.overlay("m1", layer: NotesStore.mineLayer, author: "human"))
        let old = try t.store.insertDocument(.overlay("m1", layer: "notes", startedAtMs: 5, state: .detached))
        t.owner.trashed = [t.key: deletedAt]
        #expect(await t.sweep.run().marked == 3)
        let micros = TrashStamp.micros(deletedAt)
        #expect(try t.marks() == [micros, micros, micros])
        let detachedMark = try t.store.read { db in
            try Double?.fetchOne(db, sql: "SELECT deleted_at FROM note_doc WHERE id = ?", arguments: [old.docID])
        }
        #expect(detachedMark == .some(nil))
        // A second sweep with the same answer changes nothing.
        #expect(await t.sweep.run() == NoteTrashSweep.Result())
    }

    @Test func aMarkIsClearedOnlyAfterTheOwnerSaysTheNoteExists() async throws {
        let t = try TrashRig()
        try t.store.insertDocument(.overlay("m1"))
        t.owner.trashed = [t.key: deletedAt]
        await t.sweep.run()
        // Not trashed any more, but `exists` cannot answer: the mark stays.
        t.owner.trashed = [:]
        t.r.source.existsBehavior = .throwsError
        #expect(await t.sweep.run().cleared == 0)
        // Not trashed and gone (purged): the mark stays too, for the purge to delete the overlays.
        t.r.source.existsBehavior = .answers
        t.r.source.existing = []
        #expect(await t.sweep.run().cleared == 0)
        #expect(try t.marks() == [TrashStamp.micros(deletedAt)])
        // Not trashed and present: restored.
        t.r.source.existing = nil
        #expect(await t.sweep.run().cleared == 1)
    }

    @Test func aSourceWithoutRecentlyDeletedClearsAStaleMarkOfANoteItStillHas() async throws {
        let t = try TrashRig()
        t.r.box.sources = [t.r.source]
        await t.r.library.refreshSources()
        try t.store.insertDocument(.overlay("m1"))
        try t.store.markOverlaysTrashed([t.key: deletedAt])
        #expect(await t.sweep.run().cleared == 1)
        #expect(try t.marks() == [nil])
    }

    @Test func trashedKeysIsAskedInBatchesOfFiveHundred() async throws {
        let t = try TrashRig()
        try t.store.write { db in
            for index in 0..<1_001 { _ = try NotesStore.insertDocument(.overlay("k\(index)"), in: db) }
        }
        await t.sweep.run()
        #expect(t.owner.trashedKeysCalls.map(\.count) == [500, 500, 1])
    }

    // MARK: Purge, retention and exists

    @Test func anOwnerPurgeOfAMarkedKeyDeletesTheOverlaysAndCreatesNoKeptCopy() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        t.r.publish([layer])
        try await t.r.editedOverlay(layer, text: "my own words")  // user writing: today it would be kept
        try t.store.insertDocument(.overlay("m1", layer: NotesStore.mineLayer, author: "human"))
        t.owner.trashed = [t.key: deletedAt]
        await t.r.reconciler.sweep()
        #expect(try t.marks().allSatisfy { $0 != nil })

        // 30 days later the owner purges the note: it is gone from `exists` and from its trash.
        t.owner.trashed = [:]
        t.r.source.existing = []
        t.r.source.contents = [:]
        #expect(await t.r.reconciler.sweep() == [t.key])
        #expect(try t.documents() == 0)
        #expect(try t.store.detachedOverlays().isEmpty)
        #expect(try t.store.keptCopyCount(owner: "meetings") == 0)
    }

    @Test func ownerRetentionOfALiveKeyKeepsTodaysKeptCopyRule() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        t.r.publish([layer])
        try await t.r.editedOverlay(layer, text: "my own words")
        // Retention by age removed the live note: it was never trashed, so its overlays were never marked.
        t.r.source.existing = []
        #expect(await t.r.reconciler.sweep() == [t.key])
        #expect(try t.store.detachedOverlays().map(\.key) == [t.key])
        #expect(try t.store.keptCopyCount(owner: "meetings") == 1)
    }

    @Test func aDetachOnOpenOfAGoneMarkedNoteDeletesItsOverlaysToo() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        t.r.publish([layer])
        try await t.r.editedOverlay(layer, text: "my own words")
        try t.store.markOverlaysTrashed([t.key: deletedAt])
        t.r.source.contents = [:]
        #expect(await t.r.reconciler.reconcile(t.key) == .detached)
        #expect(try t.documents() == 0)
    }

    /// `NoteSource.exists`: a trashed note still exists, and its content is still there, so neither the open-time
    /// reconcile nor the sweep detaches its overlays.
    @Test func aTrashedSourceStillExistsSoItsOverlaysAreNeverDetached() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        t.r.publish([layer])
        let doc = try await t.r.editedOverlay(layer, text: "my own words")
        t.owner.trashed = [t.key: deletedAt]
        let opened = await t.r.reconciler.reconcile(t.key)
        #expect(opened != .detached)
        #expect(await t.r.reconciler.sweep().isEmpty)
        #expect(try t.store.document(id: doc.id)?.sourceState == .present)
        #expect(try t.store.detachedOverlays().isEmpty)
        #expect(try t.marks() == [TrashStamp.micros(deletedAt)])
    }

    @Test func aMarkedOverlayIsNoKeptRowNoKeptCopyAndNotExported() async throws {
        let t = try TrashRig()
        let layer = t.r.rig.layer("notes", id: "notes", version: "n1")
        try await t.r.editedOverlay(layer, text: "my own words")
        #expect(try t.store.keptOverlays(excludingPlugins: []).count == 1)
        try t.store.markOverlaysTrashed([t.key: deletedAt])
        #expect(try t.store.keptOverlays(excludingPlugins: []).isEmpty)
        #expect(try t.store.keptCopyCount(owner: "meetings") == 0)
        #expect(try t.store.exportRows().isEmpty)
        // The listing of a key the owner shows keeps its overlays (the owner decides; the sweep clears the mark).
        #expect(try t.store.liveOverlays(for: [t.key]).count == 1)
    }

    // MARK: Folder entries

    @Test func theSweepRemovesTheFolderEntriesOfGoneKeysAndKeepsTrashedAndUnknownOnes() async throws {
        let t = try TrashRig()
        try t.store.insertDocument(.manual("a"))
        let keys = [
            "meetings:m1", "meetings:gone", "meetings:trashed", "notes:a", "notes:b", "dictation:x",
        ]
        try t.store.write { db in
            try db.execute(
                sql: "INSERT INTO note_folder (id, uuid, name, created_at, sort) VALUES (1, 'f', 'Clients', 1, 1)")
            for key in keys {
                try db.execute(
                    sql: "INSERT INTO note_folder_entry (key, folder_id, added_at) VALUES (?, 1, 1)", arguments: [key])
            }
        }
        t.r.source.existing = [Fixtures.key("meetings", "m1"), Fixtures.key("meetings", "trashed")]
        t.owner.trashed = [Fixtures.key("meetings", "trashed"): deletedAt]
        await t.r.reconciler.sweep()
        // `dictation` has no source here (off): unknown, kept. `notes:b` has no document: gone.
        #expect(
            Set(try t.store.folderEntryKeys().map(\.rawValue))
                == ["meetings:m1", "meetings:trashed", "notes:a", "dictation:x"])
    }

    // MARK: The loop

    @Test func theFirstSweepNeverPurgesAndTheOneTenMinutesLaterDoesAndAnnouncesIt() async throws {
        let t = try TrashRig()
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        try t.store.insertDocument(.manual("a"))
        try t.store.trashManualNotes([NoteKey(pluginID: "notes", id: "a")], at: now.addingTimeInterval(-40 * 86_400))
        let told = CountLatch()
        let reconciler = SourceReconciler(
            store: t.store, library: t.r.library, detacher: t.r.detacher, registry: t.r.registry,
            clock: t.r.rig.clock, now: { now }, log: t.r.rig.log, trashChanged: { told.increment() })
        let task = Task { await reconciler.runSweeps() }
        await t.r.rig.clock.waitForSleeps(1)
        #expect(try t.store.manualNoteCounts() == (live: 0, trashed: 1))
        #expect(told.count == 0)
        t.r.rig.clock.advance(by: .seconds(600))
        await told.wait(atLeast: 1)
        #expect(try t.store.manualNoteCounts() == (live: 0, trashed: 0))
        task.cancel()
        await task.value
    }
}
