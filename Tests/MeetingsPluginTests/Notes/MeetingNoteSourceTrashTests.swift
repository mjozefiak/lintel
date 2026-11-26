import Foundation
import LintelCore
import LintelKit
import Testing

@testable import MeetingsPlugin

private let day: TimeInterval = 86_400

private func query(_ text: String) -> NormalizedQuery {
    NormalizedQuery(raw: text, normalized: text.lowercased())
}

/// The five meetings of `LibraryRig` read through a Notes source that has a clock, a retention setting and a change
/// counter of its own.
@MainActor
private struct TrashRig {
    let rig: LibraryRig
    let now = Shared(ExportFixtures.started.addingTimeInterval(day))
    let retentionDays = Shared(0)
    let changes = Shared(0)
    let source: MeetingNoteSource

    var store: MeetingsStore {
        get throws { try rig.store }
    }

    init() async throws {
        rig = try await LibraryRig()
        let now = now
        let retentionDays = retentionDays
        let changes = changes
        source = MeetingNoteSource(
            library: rig.library, board: NotesBoard(), hub: NoteChangeHub(), regenerate: nil, openNotesModel: {},
            appName: { _ in nil }, changed: { changes.update { $0 += 1 } },
            retentionDays: { retentionDays.get() }, now: { now.get() })
    }

    func key(_ name: String) throws -> NoteKey {
        let id = try #require(rig.ids[name])
        return NoteKey(pluginID: "meetings", id: try #require(try store.meetingUUID(id: id)))
    }

    func name(of key: NoteKey) -> String? {
        rig.ids.first { (try? store.meetingUUID(id: $0.value)) == key.id }?.key
    }

    /// A meeting with a real UUID and the given status (the five of the rig are all finished).
    @discardableResult
    func insert(_ status: MeetingStatus, startedAt: Date = ExportFixtures.started) throws -> NoteKey {
        let uuid = UUID().uuidString.lowercased()
        try store.insertMeeting(uuid: uuid, startedAt: startedAt, speechModelID: "m", status: status)
        return NoteKey(pluginID: "meetings", id: uuid)
    }
}

/// The rules of `NoteSourceTrash` every conforming source follows (the Dictation and Notes suites use the same
/// scenarios under the same names).
@MainActor
@Suite("MeetingNoteSource: NoteSourceTrash contract")
struct MeetingNoteSourceTrashContractTests {
    @Test func theSourceOffersRecentlyDeletedThroughTheOptionalCapability() async throws {
        let rig = try await TrashRig()
        #expect((rig.source as any NoteSource) is any NoteSourceTrash)
    }

    @Test func aTrashedNoteLeavesTheListSearchAndCountsButStillExists() async throws {
        let rig = try await TrashRig()
        let plain = try rig.key("plain")
        let stamp = try await rig.source.trash(plain)

        let page = try await rig.source.list(matching: nil, after: nil, limit: 100)
        #expect(page.total == 4)
        #expect(!page.items.contains { $0.id == plain })
        let found = try await rig.source.list(matching: query("roadmapa"), after: nil, limit: 100)
        #expect(found.items.isEmpty)
        #expect(try await rig.source.liveCount() == 4)
        #expect(try await rig.source.trashedCount() == 1)
        #expect(try await rig.source.exists([plain]) == [plain])
        #expect(try await rig.source.trashedKeys([plain, try rig.key("notes")]) == [plain: stamp])
    }

    @Test func aTrashedNoteStillHasItsContentWithDeletedAtAndPurgeAtAndNoActions() async throws {
        let rig = try await TrashRig()
        let key = try rig.key("incomplete")
        let live = try #require(try await rig.source.content(for: key))
        #expect(live.summary.deletedAt == nil)
        #expect(!rig.source.actions(for: key).isEmpty)

        let stamp = try await rig.source.trash(key)
        let content = try #require(try await rig.source.content(for: key))
        #expect(content.summary.deletedAt == stamp)
        #expect(content.summary.purgeAt == stamp.addingTimeInterval(30 * day))
        #expect(content.summary.title == live.summary.title)
        #expect(!content.layers.isEmpty || live.layers.isEmpty)
        #expect(rig.source.actions(for: key).isEmpty)

        let withNotes = try rig.key("notes")
        let notesBefore = try #require(try await rig.source.content(for: withNotes)).layers
        try await rig.source.trash(withNotes)
        #expect(try #require(try await rig.source.content(for: withNotes)).layers == notesBefore)
    }

    @Test func trashOfARecordingOrProcessingOrHeldNoteThrowsBusyAndChangesNothing() async throws {
        let rig = try await TrashRig()
        let recording = try rig.insert(.recording)
        let processing = try rig.insert(.processing)
        let held = try rig.key("notes")
        rig.rig.library.registerLive(meetingID: try #require(rig.rig.ids["notes"]))
        let before = rig.changes.get()
        for key in [recording, processing, held] {
            await #expect(throws: NoteSourceError.busy) { try await rig.source.trash(key) }
        }
        #expect(try await rig.source.trashedCount() == 0)
        #expect(rig.changes.get() == before)
    }

    @Test func trashOfAMissingNoteThrowsNotFoundAndOfATrashedOneIsANoOpWithTheSameStamp() async throws {
        let rig = try await TrashRig()
        await #expect(throws: NoteSourceError.notFound) {
            try await rig.source.trash(NoteKey(pluginID: "meetings", id: "no-such-meeting"))
        }
        let key = try rig.key("stale")
        let stamp = try await rig.source.trash(key)
        let changes = rig.changes.get()
        rig.now.update { $0 = $0.addingTimeInterval(day) }
        #expect(try await rig.source.trash(key) == stamp)
        #expect(rig.changes.get() == changes)
        #expect(try await rig.source.trashedCount() == 1)
    }

    @Test func restoreOfALiveNoteIsANoOpAndAPartialBatchReturnsTheKeysThatAreGone() async throws {
        let rig = try await TrashRig()
        let trashed = try rig.key("plain")
        let purged = try rig.key("failed")
        let live = try rig.key("notes")
        try await rig.source.trash(trashed)
        try await rig.source.trash(purged)
        try await rig.source.delete(purged)
        let foreign = NoteKey(pluginID: "dictation", id: "x")
        let unknown = NoteKey(pluginID: "meetings", id: "never-existed")

        let missing = try await rig.source.restore([trashed, live, purged, foreign, unknown])
        #expect(missing == [purged, foreign, unknown])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.liveCount() == 4)
        #expect(try await rig.source.restore([live]).isEmpty)
    }

    @Test func trashedPagesNewestDeletedFirstWithDeletedAtAndPurgeAtOnEveryRow() async throws {
        let rig = try await TrashRig()
        var stamps: [String: Date] = [:]
        for name in ["plain", "stale", "failed"] {
            stamps[name] = try await rig.source.trash(try rig.key(name))
            rig.now.update { $0 = $0.addingTimeInterval(60) }
        }
        let first = try await rig.source.trashed(after: nil, limit: 2)
        #expect(first.total == 3)
        #expect(first.items.compactMap { rig.name(of: $0.id) } == ["failed", "stale"])
        let next = try #require(first.next)
        let second = try await rig.source.trashed(after: next, limit: 2)
        #expect(second.items.compactMap { rig.name(of: $0.id) } == ["plain"])
        #expect(second.next == nil)
        for item in first.items + second.items {
            let name = try #require(rig.name(of: item.id))
            #expect(item.deletedAt == stamps[name])
            #expect(item.purgeAt == item.deletedAt?.addingTimeInterval(30 * day))
        }
    }

    @Test func purgeAtIsTheEarlierOfThirtyDaysAfterTheDeleteAndTheRetentionLimit() async throws {
        let rig = try await TrashRig()
        let key = try rig.key("notes")
        let started = ExportFixtures.started
        let stamp = try await rig.source.trash(key)
        // Unlimited (0) or a long limit: thirty days after the delete.
        for days in [0, 90] {
            rig.retentionDays.update { $0 = days }
            let summary = try #require(try await rig.source.content(for: key)).summary
            #expect(summary.purgeAt == stamp.addingTimeInterval(30 * day))
        }
        // A 7-day limit counted from the start of the meeting ends sooner.
        rig.retentionDays.update { $0 = 7 }
        let page = try await rig.source.trashed(after: nil, limit: 10)
        #expect(page.items.first?.purgeAt == started.addingTimeInterval(7 * day))
    }

    @Test func trashAllMovesEveryLiveNoteExceptBusyOnesWithOneStampAndRestoreBatchPutsBackOnlyThatBatch() async throws {
        let rig = try await TrashRig()
        let earlier = try rig.key("failed")
        let earlierStamp = try await rig.source.trash(earlier)
        let recording = try rig.insert(.recording)
        let at = ExportFixtures.started.addingTimeInterval(2 * day)

        let batch = try await rig.source.trashAll(at: at)
        #expect(batch.moved == 4)
        #expect(batch.stayed == 1)
        #expect(batch.deletedAt == at)
        #expect(try await rig.source.liveCount() == 1)
        #expect(try await rig.source.exists([recording]) == [recording])
        let stamps = try await rig.source.trashedKeys([earlier, try rig.key("notes"), try rig.key("plain")])
        #expect(stamps[earlier] == earlierStamp)
        #expect(stamps[try rig.key("notes")] == batch.deletedAt)
        #expect(stamps[try rig.key("plain")] == batch.deletedAt)

        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 4)
        #expect(try await rig.source.liveCount() == 5)
        #expect(try await rig.source.trashedCount() == 1)
        // The stamp is the batch: nothing is left of it.
        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 0)
    }

    @Test func aSingleTrashNeverReusesABatchStamp() async throws {
        let rig = try await TrashRig()
        let at = ExportFixtures.started.addingTimeInterval(3 * day)
        #expect(try await rig.source.trashAll(at: at).moved == 5)
        let newcomer = try rig.insert(.ready)
        rig.now.update { $0 = at }
        let stamp = try await rig.source.trash(newcomer)
        #expect(stamp != at)
        #expect(try await rig.source.restoreBatch(deletedAt: at) == 5)
        #expect(try await rig.source.trashedKeys([newcomer]) == [newcomer: stamp])
    }

    @Test func trashedKeysAndRestoreProcessMoreThanFiveHundredKeysInChunks() async throws {
        let rig = try await TrashRig()
        let uuids = (0..<1_100).map { "bulk-\($0)" }
        try rig.store.write { db in
            for (index, uuid) in uuids.enumerated() {
                try db.execute(
                    sql: "INSERT INTO meeting (uuid, started_at, status) VALUES (?, ?, 'ready')",
                    arguments: [uuid, 1_000 + index])
            }
        }
        let keys = uuids.map { NoteKey(pluginID: "meetings", id: $0) }
        let edges = [0, 499, 500, 501, 999, 1_000, 1_099].map { keys[$0] }
        for key in edges { try await rig.source.trash(key) }

        let stamps = try await rig.source.trashedKeys(keys + [NoteKey(pluginID: "meetings", id: "unknown")])
        #expect(Set(stamps.keys) == Set(edges))
        let gone = NoteKey(pluginID: "meetings", id: "gone")
        #expect(try await rig.source.restore(keys + [gone]) == [gone])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.trashedKeys(keys).isEmpty)
    }

    @Test func deleteIsPermanentAndWorksOnATrashedNote() async throws {
        let rig = try await TrashRig()
        let key = try rig.key("stale")
        try await rig.source.trash(key)
        try await rig.source.delete(key)
        #expect(try await rig.source.content(for: key) == nil)
        #expect(try await rig.source.exists([key]).isEmpty)
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.restore([key]) == [key])
    }

    @Test func theChangeStreamIsToldAfterTrashRestoreTrashAllAndRestoreBatch() async throws {
        let rig = try await TrashRig()
        let key = try rig.key("plain")
        var seen = rig.changes.get()
        func announced() -> Bool {
            defer { seen = rig.changes.get() }
            return rig.changes.get() > seen
        }
        try await rig.source.trash(key)
        #expect(announced())
        try await rig.source.restore([key])
        #expect(announced())
        let at = ExportFixtures.started.addingTimeInterval(day)
        try await rig.source.trashAll(at: at)
        #expect(announced())
        try await rig.source.restoreBatch(deletedAt: at)
        #expect(announced())
        // A read changes nothing.
        _ = try await rig.source.trashed(after: nil, limit: 10)
        #expect(!announced())
    }
}

/// The fields Meetings fills for the explorer: `taskCount`, `liveSince` and `writer`.
@MainActor
@Suite("MeetingNoteSource: explorer fields")
struct MeetingNoteSourceExplorerFieldTests {
    @Test func taskCountCountsTheChecklistItemsTheComposerWritesAndNothingElse() async throws {
        let rig = try await TrashRig()
        let tasks = (1...3).map {
            NotesPoint(id: "t\($0)", kind: .task, timeMs: 1_000, quote: "q", text: "Send offer \($0).", person: "A")
        }
        let decision = NotesPoint(id: "d", kind: .decision, timeMs: 1_000, quote: "q", text: "[x] Ship it [link](x)")
        let verdict = NotesGuard.ReduceVerdict(
            decisions: [decision], tasks: tasks, questions: [], summary: nil, summaryReplaced: false, rejectedIDs: 0)
        let markdown = NotesComposer.markdown(verdict: verdict, participants: ["Anna"], labels: .english)
        let withTasks = try rig.key("notes")
        try rig.store.setNotes(try #require(rig.rig.ids["notes"]), markdown: markdown, status: .ok)

        let page = try await rig.source.list(matching: nil, after: nil, limit: 100)
        let byName = Dictionary(
            uniqueKeysWithValues: page.items.compactMap { item in rig.name(of: item.id).map { ($0, item) } })
        #expect(byName["notes"]?.taskCount == 3)
        // No tasks, no notes: no count (the row shows none).
        #expect(byName["plain"]?.taskCount == nil)
        #expect(byName["stale"]?.taskCount == nil)
        let content = try #require(try await rig.source.content(for: withTasks))
        #expect(content.summary.taskCount == 3)
    }

    @Test func liveSinceIsTheStartOfARecordedOrProcessedNoteAndNilForAFinishedOne() async throws {
        let rig = try await TrashRig()
        let started = ExportFixtures.started.addingTimeInterval(-3_600)
        let recording = try rig.insert(.recording, startedAt: started)
        let processing = try rig.insert(.processing, startedAt: started.addingTimeInterval(-60))
        let page = try await rig.source.list(matching: nil, after: nil, limit: 100)
        let byKey = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
        #expect(byKey[recording]?.liveSince == started)
        #expect(byKey[recording]?.state == .recording)
        #expect(byKey[processing]?.liveSince == started.addingTimeInterval(-60))
        #expect(byKey[processing]?.state == .processing)
        #expect(byKey[try rig.key("notes")]?.liveSince == nil)
    }

    @Test func theNotesLayerNamesItsWriterFromTheMeetingsOwnRecord() async throws {
        let rig = try await TrashRig()
        let id = try #require(rig.rig.ids["notes"])
        let key = try rig.key("notes")
        func writer() async throws -> NoteWriter? {
            try await rig.source.content(for: key)?.layers.first { $0.id == "notes" }?.writer
        }
        func set(provider: String?, status: String) throws {
            try rig.store.write { db in
                try db.execute(
                    sql: "UPDATE meeting SET notes_provider = ?, notes_status = ? WHERE id = ?",
                    arguments: [provider, status, id])
            }
        }
        // The built-in model leaves `notes_provider` NULL.
        try set(provider: nil, status: "ok")
        #expect(try await writer() == .thisMac)
        try set(provider: nil, status: "partial")
        #expect(try await writer() == .thisMac)
        try set(provider: nil, status: "stale")
        #expect(try await writer() == .thisMac)
        // The id the notes job stores for Claude Code is `claude-code`.
        try set(provider: "claude-code", status: "ok")
        #expect(try await writer() == .claude)
        // A provider this build does not know, and notes that failed or are being written: no footer.
        try set(provider: "future-provider", status: "ok")
        #expect(try await writer() == nil)
        try set(provider: nil, status: "failed")
        #expect(try await writer() == nil)
        // The transcript layer never has one.
        #expect(try await rig.source.content(for: key)?.layers.first { $0.id == "transcript" }?.writer == nil)
        // No notes at all.
        let plain = try #require(try await rig.source.content(for: try rig.key("plain")))
        #expect(plain.layers.allSatisfy { $0.writer == nil })
    }
}
