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

    private var elsewhere: NoteItemID { .live(NoteKey(pluginID: "meetings", id: "elsewhere")) }

    /// The meeting chosen again after another note, with its My notes tab on screen: a new document and a new pad.
    private func comeBack(_ r: ReconRig, _ model: NotesWorkspaceModel) async throws -> MyNotesPad {
        let id = NoteItemID.live(r.key)
        model.select(row: id)
        await model.loadPreview(id)
        model.selectPreviewTab(.mine)
        return try #require(model.previewDocument?.myNotes)
    }

    private func setReadOnly(_ r: ReconRig, _ on: Bool) {
        r.rig.harness.settingsStore.setValue(.bool(on), forKey: "plugins.notes.readOnly")
    }

    /// Fires the writer's retry of a failed write (2 s on the manual clock).
    private func fireRetry(_ r: ReconRig) async {
        await waitUntil { r.rig.clock.sleeperCount > 0 }
        r.rig.clock.advance(by: .seconds(2))
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

    // MARK: Coming back after a failed or running save (review M1)

    @Test func afterAFailedSaveComingBackShowsTheUnsavedTextAndTheNextKeystrokeKeepsIt() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        try r.store.close()
        type(pad, "unsaved words")
        await pad.flush()
        #expect(pad.saveFailed)
        // Another note: the close's flush fails again and the writer lingers with the text.
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        let again = try await comeBack(r, model)
        #expect(again !== pad)
        let writer = try #require(again.session?.writer)
        #expect(writer === pad.session?.writer)
        #expect(writer.hasPendingText)
        // The pad shows the text the writer still holds, says it is not saved, and typing extends it.
        #expect(again.text == "unsaved words")
        #expect(again.saveFailed)
        #expect(again.isSaving)
        type(again, "unsaved words, and more")
        #expect(writer.latestText == "unsaved words, and more")
    }

    @Test func whenTheRetryLandsAfterComingBackThePadKeepsTheTextItWrote() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "first")
        await pad.flush()
        #expect(try mine(r)?.body == "first")
        type(pad, "first, then unsaved")
        setReadOnly(r, true)
        await pad.flush()
        #expect(pad.saveFailed)
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        setReadOnly(r, false)
        // The heads are read before the retry: the store still says "first".
        let again = try await comeBack(r, model)
        #expect(again.text == "first, then unsaved")
        await fireRetry(r)
        await waitUntil { !again.isSaving && !again.saveFailed }
        #expect(try mine(r)?.body == "first, then unsaved")
        type(again, "first, then unsaved, then typed")
        await again.flush()
        #expect(try mine(r)?.body == "first, then unsaved, then typed")
    }

    @Test func whenTheRetryLandsBeforeComingBackThePadShowsTheWrittenText() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "written while away")
        setReadOnly(r, true)
        await pad.flush()
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        setReadOnly(r, false)
        await fireRetry(r)
        await waitUntil { !pad.saveFailed }
        #expect(try mine(r)?.body == "written while away")
        let again = try await comeBack(r, model)
        #expect(again.text == "written while away")
        #expect(!again.saveFailed && !again.isSaving)
        type(again, "written while away!")
        await again.flush()
        #expect(try mine(r)?.body == "written while away!")
    }

    // MARK: A flush that forgets the writer between the read and My notes (re-review M1b)

    /// Types "first" (written), then "first, then unsaved" while Notes is read-only (the write fails), leaves for
    /// another note and comes back on the Notes tab: the heads read now still say "first".
    @discardableResult
    private func failThenComeBackOnNotes(_ r: ReconRig, _ model: NotesWorkspaceModel) async throws -> MyNotesPad {
        let pad = try await showMine(r, model)
        // The flush point below forgets this writer: the rig stops its timers at the end.
        r.rig.adopt(try #require(pad.session?.writer))
        type(pad, "first")
        await pad.flush()
        #expect(try mine(r)?.body == "first")
        type(pad, "first, then unsaved")
        setReadOnly(r, true)
        await pad.flush()
        #expect(pad.saveFailed)
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        let id = NoteItemID.live(r.key)
        model.select(row: id)
        await model.loadPreview(id)
        #expect(model.previewTab == .notes)
        #expect(model.previewDocument?.mineMarkdown == "first")
        return pad
    }

    @Test func aFlushAllWhileAwayFromMyNotesThenMyNotesShowsTheTextItWrote() async throws {
        let r = try ReconRig()
        let model = model(r)
        try await failThenComeBackOnNotes(r, model)
        // Hiding the window (or Settings, or `deactivate()`) writes the lingering text and forgets the writer.
        setReadOnly(r, false)
        await r.registry.flushAll()
        #expect(try mine(r)?.body == "first, then unsaved")
        #expect(r.registry.writer(for: .live(r.key, layer: NotesStore.mineLayer)) == nil)
        model.selectPreviewTab(.mine)
        let again = try #require(model.previewDocument?.myNotes)
        #expect(again.text == "first, then unsaved")
        #expect(!again.saveFailed && !again.isSaving)
        // The first keystroke extends the text instead of replacing it.
        type(again, again.text + "!")
        await again.flush()
        #expect(try mine(r)?.body == "first, then unsaved!")
    }

    @Test func theWritersOwnRetryThenAFlushAllWhileAwayThenMyNotesShowsTheTextItWrote() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await failThenComeBackOnNotes(r, model)
        setReadOnly(r, false)
        // The writer's retry lands while Notes is shown; the next flush point forgets the lingering writer.
        await fireRetry(r)
        await waitUntil { !pad.saveFailed }
        #expect(try mine(r)?.body == "first, then unsaved")
        await r.registry.flushAll()
        #expect(r.registry.writer(for: .live(r.key, layer: NotesStore.mineLayer)) == nil)
        model.selectPreviewTab(.mine)
        let again = try #require(model.previewDocument?.myNotes)
        #expect(again.text == "first, then unsaved")
        type(again, again.text + ", then typed")
        await again.flush()
        #expect(try mine(r)?.body == "first, then unsaved, then typed")
    }

    @Test func comingBackWhileTheCloseStillWritesShowsTheTypedText() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "quick")
        // Back at once, while the close's write may still run: the pad starts from the writer's text, or from the
        // head read in the same turn once the writer was let go.
        model.select(row: elsewhere)
        let again = try await comeBack(r, model)
        #expect(again.text == "quick")
        type(again, "quick!")
        await again.flush()
        #expect(try mine(r)?.body == "quick!")
    }

    // MARK: Read-only and Try Now (review m2)

    @Test func notesReadOnlyBlocksThePadThroughItsSession() async throws {
        let r = try ReconRig()
        let model = model(r)
        setReadOnly(r, true)
        let pad = try await showMine(r, model)
        let session = try #require(pad.session)
        #expect(session.block == .readOnly)
        #expect(pad.readOnlyReason == .readOnly)
        type(pad, "x")
        #expect(pad.text.isEmpty)
        await pad.flush()
        #expect(try mine(r) == nil)
    }

    @Test func notesReadOnlyTurnedOnWhileThePadIsOpenStopsTypingAndOffLetsItAgain() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        #expect(pad.isEditable)
        setReadOnly(r, true)
        #expect(pad.readOnlyReason == .readOnly)
        type(pad, "ignored")
        #expect(pad.text.isEmpty)
        setReadOnly(r, false)
        #expect(pad.isEditable)
        type(pad, "allowed again")
        await pad.flush()
        #expect(try mine(r)?.body == "allowed again")
    }

    @Test func tryNowAfterAFailureWritesTheTextAndTheStripGoes() async throws {
        let r = try ReconRig()
        let model = model(r)
        let pad = try await showMine(r, model)
        type(pad, "kept for Try Now")
        setReadOnly(r, true)
        await pad.flush()
        await waitUntil { pad.saveFailed }
        #expect(pad.isSaving)
        setReadOnly(r, false)
        let document = try #require(model.previewDocument)
        await model.retryMyNotes(document)
        await waitUntil { !pad.saveFailed }
        #expect(!pad.isSaving)
        #expect(pad.text == "kept for Try Now")
        #expect(try mine(r)?.body == "kept for Try Now")
    }
}
