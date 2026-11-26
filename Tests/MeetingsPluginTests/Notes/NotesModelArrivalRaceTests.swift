import Foundation
import LintelTestSupport
import Testing

@testable import MeetingsPlugin

/// #308: the notes model can arrive while the job that waited for it is saving that wait. The arrival is not a
/// duplicate of the running job, so the meeting must be written again right after it, and its wait must stay on
/// disk until then. All data is synthetic.
@MainActor
@Suite struct NotesModelArrivalRaceTests {
    private static let model = URL(filePath: "/models/llm/notes-test.gguf")

    @Test func aModelThatArrivesWhileTheWaitIsSavedStillWritesTheNotes() async throws {
        let marks = CountLatch()
        let releaseMark = Latch()
        let llmCalls = CountLatch()
        let releaseLLM = Latch()
        let rig = try NotesServiceRig(
            handler: { _, messages, _ in
                if llmCalls.increment() == 1 { _ = await releaseLLM.wait() }
                return .done(NotesFake.answer(messages))
            },
            markAwaiting: { store, id in
                // The job is saving its wait: the test lets the model arrive in exactly this window.
                if marks.increment() == 1 { _ = await releaseMark.wait() }
                await AwaitingMarker.mark(store, id)
            })
        rig.file.update { $0 = nil }
        await rig.start()
        let id = try await rig.addMeeting()
        rig.library.meetingReady(id)

        #expect(await marks.wait(atLeast: 1, guard: .seconds(10), "the wait to be saved"))
        rig.file.update { $0 = Self.model }
        await rig.service.refreshAvailability()
        #expect(rig.service.board.snapshot.awaitingModel.isEmpty)
        releaseMark.open()

        // The arrival was not dropped as a duplicate: the meeting is written again right after the job, and its
        // wait is still on disk while that run has not finished.
        #expect(await llmCalls.wait(atLeast: 1, guard: .seconds(10), "the meeting to be written again"))
        #expect(try rig.store.meetingsAwaitingNotesModel() == [id])
        releaseLLM.open()

        #expect(await rig.settle())
        #expect(try rig.record(id).status == .ok)
        #expect(try rig.store.meetingsAwaitingNotesModel().isEmpty)
        #expect(!rig.service.board.snapshot.needsModel(for: id))
        #expect(try #require(try rig.document(id).notesMarkdown).contains("Zatwierdzamy ten budżet bez zmian"))
    }
}
