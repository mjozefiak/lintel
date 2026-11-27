import Foundation
import LintelKit
import Synchronization
import Testing

@testable import NotesPlugin

/// Spec step 3.5: My notes, the user's own pad on a meeting's `mine` layer, in the preview's tab and in the full
/// window. The store and the writer are the real ones; the clock is manual, so the 1 s debounce never fires on
/// its own and every write below comes from a save point.
@MainActor
@Suite(.finishesRigs, .timeLimit(.minutes(1))) struct MyNotesTests {
    /// How many times the section asked for the store (the lazy-store rule: not before the first character).
    private final class Opens: Sendable {
        private let count = Mutex(0)
        var value: Int { count.withLock { $0 } }
        func add() { count.withLock { $0 += 1 } }
    }

    private func model(_ r: ReconRig, exists: Bool = true, opens: Opens = Opens()) -> NotesWorkspaceModel {
        var environment = NotesWorkspaceModel.Environment(library: r.library, pasteboard: RecordingPasteboard())
        environment.registry = r.registry
        let store = r.store
        environment.overlayHeads = { item in (try? NoteOverlayContent.heads(for: item, in: store)) ?? [] }
        environment.installWriting(
            store: {
                opens.add()
                return store
            }, registry: r.registry, settings: r.rig.harness.settings, clock: r.rig.clock, exists: { exists })
        return NotesWorkspaceModel(environment: environment)
    }

    /// The meeting selected with its My notes tab on screen, the pad made.
    private func showMine(_ r: ReconRig, _ model: NotesWorkspaceModel) async throws -> MyNotesPad {
        r.publish([r.rig.layer("Ship it.", id: "notes", version: "n1")])
        await model.refresh()
        let id = NoteItemID.live(r.key)
        model.select(row: id)
        await model.loadPreview(id)
        model.selectPreviewTab(.mine)
        return try #require(model.previewDocument?.myNotes)
    }

    private func type(_ pad: MyNotesPad, _ text: String) {
        pad.edit(NoteEditorEdit(text: text, range: 0..<text.utf16.count, changeInLength: text.utf16.count))
    }

    private func mine(_ r: ReconRig) throws -> RevisionRecord? {
        guard let document = try r.store.liveDocument(key: r.key, layer: NotesStore.mineLayer) else { return nil }
        return try r.store.headRevision(of: document.id)
    }

    @Test func theEmptyPadCreatesNothingAndTheFirstCharacterWritesTheUsersText() async throws {
        let r = try ReconRig()
        let opens = Opens()
        let model = model(r, exists: false, opens: opens)
        let pad = try await showMine(r, model)
        #expect(pad.isEditable)
        #expect(pad.text.isEmpty)
        // Showing the pad opens nothing and writes nothing.
        #expect(opens.value == 0)
        #expect(try mine(r) == nil)
        // Typing and deleting it again writes nothing either.
        type(pad, "")
        await pad.flush()
        #expect(try mine(r) == nil)
        type(pad, "Ask Ola about the budget")
        #expect(pad.isSaving)
        await pad.flush()
        let head = try #require(try mine(r))
        #expect(head.body == "Ask Ola about the budget")
        #expect(head.author == "human")
        #expect(!pad.isSaving)
        #expect(opens.value > 0)
    }

    @Test func choosingAnotherNoteWritesWhatWasTyped() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "follow up")
        model.select(row: .live(NoteKey(pluginID: "meetings", id: "elsewhere")))
        // The pad says when everything typed is written (the store itself is not observable).
        await waitUntil { !pad.isSaving }
        #expect(try mine(r)?.body == "follow up")
    }

    @Test func leavingTheTabWritesAndTheNextReadShowsTheText() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "mine only")
        model.selectPreviewTab(.notes)
        await waitUntil { !pad.isSaving }
        #expect(try mine(r)?.body == "mine only")
        // The Notes layer is untouched by My notes.
        #expect(try r.store.liveDocument(key: r.key, layer: "notes") == nil)
        // A fresh section (the app opened again) shows the text in the pad.
        let again = self.model(r)
        let shown = try await showMine(r, again)
        #expect(shown.text == "mine only")
    }

    @Test func theTextSurvivesQuittingThroughTheRegistrysFlush() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "typed just before quitting")
        // `deactivate()` and hiding the window flush every writer; nothing else ran.
        await r.registry.flushAll()
        #expect(try mine(r)?.body == "typed just before quitting")
    }

    @Test func aFailedWriteKeepsTheTextAndShowsTheStrip() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        try r.store.close()
        type(pad, "not lost")
        await pad.flush()
        #expect(pad.saveFailed)
        #expect(pad.text == "not lost")
        #expect(MyNotesEditor.failedStrip.text == "Your notes weren’t saved. Lintel keeps trying.")
        #expect(MyNotesEditor.failedStrip.actions.map(\.id) == ["mine.retry"])
    }

    @Test func withNotesReadOnlyThePadSaysSoAndTypingIsIgnored() async throws {
        let r = try ReconRig()
        var environment = NotesWorkspaceModel.Environment(library: r.library, pasteboard: RecordingPasteboard())
        environment.notesReadOnly = true
        let model = NotesWorkspaceModel(environment: environment)
        let pad = try await showMine(r, model)
        #expect(pad.readOnlyReason == .readOnly)
        type(pad, "x")
        #expect(pad.text.isEmpty)
        #expect(MyNotesEditor.line(.readOnly) == "Notes are read-only on this Mac, so My notes can’t be changed now.")
    }

    @Test func aDictationAndANoteYouWroteHaveNoMyNotes() async throws {
        let r = try ReconRig()
        let model = model(r)
        let manual = try r.store.createManualNote(now: Date(timeIntervalSince1970: 100))
        await model.refresh()
        model.select(row: .live(manual))
        await model.loadPreview(.live(manual))
        model.selectPreviewTab(.mine)
        #expect(model.previewDocument?.myNotes == nil)
    }

    // MARK: The full window

    @Test func theFullWindowShowsMyNotesAsASegmentAfterTheNotes() async throws {
        let r = try ReconRig()
        let model = model(r)
        r.publish([
            r.rig.layer("Ship it.", id: "notes", version: "n1"),
            r.rig.layer("segment", id: "transcript", version: "t1", author: .stt),
        ])
        await model.refresh()
        let id = NoteItemID.live(r.key)
        model.open(id)
        await model.loadContent(id)
        let document = try #require(model.currentDocument)
        #expect(LayerSwitch.segments(of: document) == ["notes", nil, "transcript"])
        model.showMyNotes(document)
        #expect(document.showsMine)
        // No pen on My notes: it is always a pad, never the layer editor.
        #expect(!model.canEdit(document))
        let pad = try #require(document.myNotes)
        type(pad, "from the full window")
        // Copy takes what is on screen.
        model.copyMarkdown()
        #expect(model.feedback == .copied)
        // Another segment is a save point; "‹ All notes" then shows the preview on the tab that was on screen.
        model.showLayer("transcript", of: document)
        await waitUntil { !pad.isSaving }
        #expect(try mine(r)?.body == "from the full window")
        model.showMyNotes(document)
        model.closeFullWindow()
        #expect(model.previewTab == .mine)
        #expect(model.previewDocument?.myNotes === pad)
    }

    @Test func aRevisionOfTheNotesNeverTouchesMyNotes() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "my own line")
        await pad.flush()
        let before = try #require(try mine(r))
        // The notes layer gets a new agent revision (what a revise run writes); My notes keeps its head.
        let notes = try r.rig.seededDocument(r.rig.layer("Ship it.", id: "notes", version: "n1"))
        let writer = r.rig.writer(.existing(docID: notes.id))
        let head = try #require(try r.store.headRevision(of: notes.id))
        _ = try await writer.appendApplied(author: .agent, body: "Ship it on Friday.", expectingHead: head.id)
        let after = try #require(try mine(r))
        #expect(after.id == before.id && after.body == "my own line" && after.author == "human")
    }
}
