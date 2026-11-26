import Foundation
import GRDB
import LintelPersistence
import Testing

@testable import MeetingsPlugin

/// #295: a meeting that waits for the notes model keeps waiting across a restart and gets its notes when the model
/// arrives. A restart is `NotesServiceRig.restart()`: the service shuts down and a new one starts over the same
/// library, with an empty board. All data is synthetic.
@MainActor
@Suite struct NotesAwaitingModelRestartTests {
    private static let model = URL(filePath: "/models/llm/notes-test.gguf")

    @Test func aMeetingThatWaitedForTheModelStillWaitsAfterARestart() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        #expect(rig.service.board.snapshot.needsModel(for: id))
        #expect(try rig.store.meetingsAwaitingNotesModel() == [id])

        await rig.restart()
        // The state, the badge and the download action are back, and nothing was written.
        let snapshot = rig.service.board.snapshot
        #expect(snapshot.needsModel(for: id))
        #expect(snapshot.awaitingModel == [id])
        #expect(try rig.record(id).status == .none)
        #expect(rig.llm.calls.isEmpty)
    }

    @Test func theModelArrivingAfterARestartWritesTheNotes() async throws {
        let rig = try NotesServiceRig(modelWatchInterval: .milliseconds(20))
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        await rig.restart()
        #expect(rig.service.board.snapshot.needsModel(for: id))

        // The download finishes from any screen: the watch started by the restart finds the file by itself.
        rig.file.update { $0 = Self.model }
        #expect(await rig.wait("the notes to be written") { (try? rig.record(id).status) == .ok })
        #expect(await rig.settle())
        #expect(!rig.service.board.snapshot.needsModel(for: id))
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
        #expect(try #require(try rig.document(id).notesMarkdown).contains("Zatwierdzamy ten budżet bez zmian"))
    }

    @Test func aModelThatIsThereAtLaunchWritesTheWaitingNotesAtOnce() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())

        // The model arrived while the app was not running.
        rig.file.update { $0 = Self.model }
        await rig.restart()
        #expect(await rig.settle())
        #expect(try rig.record(id).status == .ok)
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
        #expect(!rig.service.board.snapshot.needsModel(for: id))
    }

    @Test func aWaitSurvivesSeveralRestarts() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        await rig.restart()
        await rig.restart()
        await rig.restart()
        #expect(rig.service.board.snapshot.needsModel(for: id))
        #expect(try rig.store.meetingsAwaitingNotesModel() == [id])
    }

    @Test func onlyTheMeetingsThatWaitedAreQueuedAfterARestart() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        let old = try await rig.addMeeting()
        await rig.start()
        let waiting = try await rig.addMeeting()
        rig.library.meetingReady(waiting)
        #expect(await rig.settle())
        await rig.restart()
        rig.file.update { $0 = Self.model }
        await rig.service.refreshAvailability()
        #expect(await rig.settle())
        #expect(try rig.record(waiting).status == .ok)
        // A meeting from before notes were on is not written by itself.
        #expect(try rig.record(old).status == .none)
    }

    @Test func notesSwitchedOffEndTheWaitForGood() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        #expect(try rig.store.meetingsAwaitingNotesModel() == [id])

        rig.harness.settings.setValue(.bool(false), forKey: "plugins.meetings.notesEnabled")
        await rig.service.refreshAvailability()
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
        await rig.restart()
        #expect(!rig.service.board.snapshot.needsModel(for: id))
        // Switching notes on and the model arriving later does not write that meeting by itself.
        rig.harness.settings.setValue(.bool(true), forKey: "plugins.meetings.notesEnabled")
        rig.file.update { $0 = Self.model }
        await rig.service.refreshAvailability()
        #expect(await rig.settle())
        #expect(try rig.record(id).status == .none)
    }

    @Test func notesSwitchedOffBeforeARestartAreNotWrittenAfterIt() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())

        // The switch changes while the app is not running, so no `refreshAvailability` saw it.
        rig.harness.settings.setValue(.bool(false), forKey: "plugins.meetings.notesEnabled")
        rig.file.update { $0 = Self.model }
        await rig.restart()
        #expect(await rig.settle())
        #expect(try rig.record(id).status == .none)
        #expect(rig.llm.calls.isEmpty)
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
    }

    @Test func aMeetingThatFinishedWhileNotesWereOffIsNotMarked() async throws {
        let rig = try NotesServiceRig(settings: ["plugins.meetings.notesEnabled": .bool(false)])
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
        await rig.restart()
        #expect(!rig.service.board.snapshot.needsModel(for: id))
    }

    @Test func aRegenerateOfAWaitingMeetingEndsItsWait() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        await rig.restart()

        rig.file.update { $0 = Self.model }
        rig.service.regenerate(id)
        #expect(await rig.settle())
        #expect(try rig.record(id).status == .ok)
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
    }

    @Test func aDeletedMeetingIsNotQueuedAfterARestart() async throws {
        let rig = try NotesServiceRig()
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)
        #expect(await rig.settle())
        try rig.store.deleteMeetings([id])
        rig.file.update { $0 = Self.model }
        await rig.restart()
        #expect(await rig.settle())
        #expect(rig.llm.calls.isEmpty)
        #expect(rig.service.board.snapshot.awaitingModel.isEmpty)
    }
}

/// Migration `v4-notes-awaiting-model` (#295): one additive column, default 0.
@Suite struct NotesAwaitingModelMigrationTests {
    @Test func aDatabaseFromBeforeTheMigrationKeepsItsRowsAndReadsNotWaiting() throws {
        let queue = try DatabaseQueue()
        let migrator = MeetingsStore.migrator
        try migrator.migrate(queue, upTo: "v3-notes-provider")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO meeting (uuid, started_at, title, status, notes_markdown, notes_status)
                    VALUES ('old', 1000, 'Synthetic title', 'ready', '- Synthetic point', 'ok')
                    """)
        }
        try migrator.migrate(queue)
        let row = try #require(
            try queue.read {
                try Row.fetchOne(
                    $0, sql: "SELECT title, notes_markdown, notes_status, notes_awaiting_model FROM meeting")
            })
        #expect((row["title"] as String) == "Synthetic title")
        #expect((row["notes_markdown"] as String) == "- Synthetic point")
        #expect((row["notes_status"] as String) == "ok")
        #expect((row["notes_awaiting_model"] as Int) == 0)
        try migrator.migrate(queue)
    }

    /// `BACKWARD_COMPATIBILITY.md` section 2: a build from before the migration opens the database and loses nothing.
    @Test func anOlderBuildOpensTheNewerDatabaseAndLosesNothing() throws {
        let queue = try DatabaseQueue()
        try MeetingsStore.migrator.migrate(queue)
        try queue.write {
            try $0.execute(
                sql: """
                    INSERT INTO meeting (uuid, started_at, status, notes_awaiting_model)
                    VALUES ('newer', 1000, 'ready', 1)
                    """)
        }
        var older = DatabaseMigrator()
        for name in ["v1-meetings", "v2-consent", "v3-notes-provider"] { older.registerMigration(name) { _ in } }
        try older.migrate(queue)
        try queue.write { db in
            try db.execute(sql: "INSERT INTO meeting (uuid, started_at, status) VALUES ('older', 2000, 'ready')")
            try db.execute(sql: "UPDATE meeting SET notes_status = 'ok' WHERE uuid = 'newer'")
        }
        let rows = try queue.read {
            try Row.fetchAll($0, sql: "SELECT uuid, notes_awaiting_model AS w FROM meeting ORDER BY uuid")
        }
        #expect(rows.map { $0["w"] as Int } == [1, 0])
    }

    @Test func theMarkIsOnlyForReadyMeetingsAndIsClearedPerMeetingOrForAll() throws {
        let directory = try TemporaryDirectory()
        defer { withExtendedLifetime(directory) {} }
        let store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: testKeys())
        let when = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.insertMeeting(uuid: "a", startedAt: when, speechModelID: "m", status: .ready)
        let second = try store.insertMeeting(
            uuid: "b", startedAt: when.addingTimeInterval(60), speechModelID: "m", status: .ready)
        let live = try store.insertMeeting(uuid: "c", startedAt: when, speechModelID: "m", status: .recording)
        for id in [second, first, live] { try store.markNotesAwaitingModel(id) }
        #expect(try store.meetingsAwaitingNotesModel() == [first, second])
        try store.clearNotesAwaitingModel(first)
        #expect(try store.meetingsAwaitingNotesModel() == [second])
        try store.clearNotesAwaitingModel()
        #expect(try store.meetingsAwaitingNotesModel().isEmpty)
    }
}
