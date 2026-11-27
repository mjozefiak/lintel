import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

@MainActor
@Suite(.finishesRigs, .timeLimit(.minutes(1))) struct NotesEditingWiringTests {
    private func model(_ r: ReconRig) -> NotesWorkspaceModel {
        var environment = NotesWorkspaceModel.Environment(library: r.library, pasteboard: RecordingPasteboard())
        environment.registry = r.registry
        let store = r.store
        environment.overlayHeads = { item in (try? NoteOverlayContent.heads(for: item, in: store)) ?? [] }
        let model = NotesWorkspaceModel(environment: environment)
        r.registry.onRekey = { [weak model] key, started in
            model?.rekeyDetached(key: key, startedAtMs: started) ?? false
        }
        return model
    }

    // MARK: The full window

    @Test func aDetachReKeysTheOpenNoteAndARouteToTheNewRowOpensIt() async throws {
        let r = try ReconRig()
        let layers = [
            r.rig.layer("agent notes", id: "notes", version: "n1"),
            r.rig.layer("segment", id: "transcript", version: "t1", author: .stt),
        ]
        let doc = try await r.editedOverlay(layers[0], text: "my notes")
        r.publish(layers)
        let model = model(r)
        model.open(.live(r.key))
        await model.loadContent(.live(r.key))
        let started = NoteTime.milliseconds(r.rig.started)
        let detached = NoteItemID.detached(r.key, startedAtMs: started)
        // Reconciliation on open reads the same note; the overlay head is what the document shows.
        #expect(model.documents[.live(r.key)]?.layers.first { $0.id == "notes" }?.markdown == "my notes")
        r.source.existing = []
        await r.reconciler.sweep()
        #expect(model.currentID == detached)
        #expect(model.explorer.selection == detached)
        #expect(model.documents[.live(r.key)] == nil)
        // The detached copy shows only its overlaid layers, never the source's text for a layer without one.
        await waitUntil { model.documents[detached]?.phase == .loaded }
        let shown = try #require(model.documents[detached])
        #expect(shown.layers.map(\.id) == ["notes"])
        #expect(shown.layers.first?.markdown == "my notes")
        // The recreated note's row 1 has the same key: another identity, opened in its place.
        model.open(.live(r.key))
        #expect(model.currentID == .live(r.key))
        _ = doc
    }

    @Test func aDetachedCopyNeverReadsTheSource() async throws {
        let r = try ReconRig()
        let doc = try await r.editedOverlay(r.rig.layer("old", version: "n1"), text: "kept")
        try r.store.detachReportingRows(r.key)
        let model = model(r)
        let item = NoteItemID.detached(r.key, startedAtMs: NoteTime.milliseconds(r.rig.started))
        r.publish([r.rig.layer("SOURCE TEXT", version: "n9")])
        model.open(item)
        await model.loadContent(item)
        #expect(r.source.contentCalls == 0)
        #expect(model.documents[item]?.layers.first?.markdown == "kept")
        _ = doc
    }

    // MARK: Registry and closing

    @Test func closingATabWritesTheBufferAndForgetsTheDocument() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent"))
        let writer = r.registry.writer(for: .live(r.key, layer: "notes"), item: .live(r.key)) {
            r.rig.writer(.existing(docID: doc.id))
        }
        writer.submit("typed")
        await r.registry.release(item: .live(r.key))
        #expect(try r.rig.head(doc.id).body == "typed")
        #expect(r.registry.documentIDs.isEmpty)
    }

    // MARK: Leaving a note releases its writers (re-review m4)

    /// The meeting selected and read, with a writer on its Notes layer (an edit, Restore, a comment or a revision).
    private func selectedWithLayerWriter(
        _ r: ReconRig, _ model: NotesWorkspaceModel, item: NoteItemID? = nil, docID: Int64
    ) async -> RevisionWriter {
        let id = item ?? .live(r.key)
        await model.refresh()
        model.select(row: id)
        await model.loadPreview(id)
        let documentID: NoteDocumentID =
            if case .detached = id { .detached(docID: docID) } else { .live(r.key, layer: "notes") }
        return r.registry.writer(for: documentID, item: id) { r.rig.writer(.existing(docID: docID)) }
    }

    private var elsewhere: NoteItemID { .live(NoteKey(pluginID: "meetings", id: "elsewhere")) }

    @Test func choosingAnotherNoteWritesTheLayerWritersAndForgetsThem() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        r.publish([r.rig.layer("agent", id: "notes", version: "n1")])
        let model = model(r)
        let writer = await selectedWithLayerWriter(r, model, docID: doc.id)
        writer.submit("typed, not written yet")
        #expect(r.registry.openLiveKeys == [r.key])
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        // Written first, then forgotten: the reconciler and the detached-row cleanup no longer count it as open.
        #expect(try r.rig.head(doc.id).body == "typed, not written yet")
        #expect(r.registry.writer(for: .live(r.key, layer: "notes")) == nil)
        #expect(r.registry.openLiveKeys.isEmpty)
    }

    @Test func aLayerWriterWhoseWriteFailsStaysWithItsText() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        r.publish([r.rig.layer("agent", id: "notes", version: "n1")])
        let model = model(r)
        let writer = await selectedWithLayerWriter(r, model, docID: doc.id)
        try r.rig.failNextInsert(body: "kept")
        writer.submit("kept")
        model.select(row: elsewhere)
        await model.awaitRelease(.live(r.key))
        #expect(r.registry.writer(for: .live(r.key, layer: "notes")) === writer)
        #expect(writer.hasPendingText)
        try r.rig.clearFault()
        await r.registry.flushAll()
        #expect(try r.rig.head(doc.id).body == "kept")
        #expect(r.registry.writer(for: .live(r.key, layer: "notes")) == nil)
    }

    @Test func leavingADetachedCopyReleasesItsWriterToo() async throws {
        let r = try ReconRig()
        let doc = try await r.editedOverlay(r.rig.layer("old", version: "n1"), text: "kept")
        try r.store.detachReportingRows(r.key)
        let model = model(r)
        let item = NoteItemID.detached(r.key, startedAtMs: NoteTime.milliseconds(r.rig.started))
        let writer = await selectedWithLayerWriter(r, model, item: item, docID: doc.id)
        writer.submit("kept, and more")
        model.select(row: elsewhere)
        await model.awaitRelease(item)
        #expect(try r.rig.head(doc.id).body == "kept, and more")
        #expect(r.registry.documentIDs.isEmpty)
    }

    // MARK: The editing session

    @Test func theSessionRefusesToSeedWhileTheSourceIsStillWorking() throws {
        let r = try ReconRig()
        for state in [NoteState.recording, .processing, .writing(done: 1, of: 2)] {
            let content = r.rig.content(layers: [r.rig.layer("text")], state: state)
            #expect(
                NoteEditingSession.make(
                    content: content, layerID: "notes", store: r.store, registry: r.registry, readOnly: false) == nil)
        }
    }

    @Test func aLayerThatAlreadyHasAnOverlayStaysEditableInAnyState() throws {
        let r = try ReconRig()
        try r.rig.seededDocument(r.rig.layer("text"))
        let content = r.rig.content(layers: [r.rig.layer("text")], state: .writing(done: 1, of: 2))
        let session = NoteEditingSession.make(
            content: content, layerID: "notes", store: r.store, registry: r.registry, readOnly: false)
        #expect(session?.isEditable == true)
    }

    // MARK: The layer editor starts from the writer's text (review p1 of #360)

    /// The editor of the layer made again, over the note as it was read (`agent`), like the pen after coming back.
    private func editorAgain(_ r: ReconRig, readWith text: String = "agent") throws -> NoteEditingSession {
        let content = r.rig.content(layers: [r.rig.layer(text, version: "n1")])
        return try #require(
            NoteEditingSession.make(
                content: content, layerID: "notes", store: r.store, registry: r.registry, readOnly: false))
    }

    @Test func aFailedSaveThenComingBackStartsTheEditorFromTheUnsavedText() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        let id = NoteDocumentID.live(r.key, layer: "notes")
        let writer = r.registry.writer(for: id, item: .live(r.key)) { r.rig.writer(.existing(docID: doc.id)) }
        try r.rig.failNextInsert(body: "typed")
        writer.submit("typed")
        await r.registry.release(item: .live(r.key))  // leaving the note: the write fails, the writer lingers
        #expect(writer.hasPendingText)
        // Back on the note, read with the old head: the editor must not start from "agent".
        let session = try editorAgain(r)
        #expect(session.writer === writer)
        #expect(session.startText == "typed")
    }

    @Test func aFlushPointWhileAwayThenComingBackStartsTheEditorFromTheHeadItWrote() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        let id = NoteDocumentID.live(r.key, layer: "notes")
        let writer = r.registry.writer(for: id, item: .live(r.key)) { r.rig.writer(.existing(docID: doc.id)) }
        try r.rig.failNextInsert(body: "typed")
        writer.submit("typed")
        await r.registry.release(item: .live(r.key))
        // The note is read again with the old head ("agent"); hiding the window then writes and forgets the writer.
        try r.rig.clearFault()
        await r.registry.flushAll()
        #expect(try r.rig.head(doc.id).body == "typed")
        #expect(r.registry.writer(for: id) == nil)
        #expect(try editorAgain(r).startText == "typed")
    }

    @Test func textNotWrittenYetIsTheStartTextAndWrittenTextIsTheSameAsTheHead() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        let id = NoteDocumentID.live(r.key, layer: "notes")
        let writer = r.registry.writer(for: id, item: .live(r.key)) { r.rig.writer(.existing(docID: doc.id)) }
        writer.submit("typed")
        #expect(try editorAgain(r).startText == "typed")  // buffered, not written yet
        try await writer.flush()
        #expect(try editorAgain(r).startText == "typed")  // written: the head says the same
    }

    @Test func aHeadMovedWithoutTypingIsTheStartTextNotTheOlderTypedText() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent", version: "n1"))
        let id = NoteDocumentID.live(r.key, layer: "notes")
        let writer = r.registry.writer(for: id, item: .live(r.key)) { r.rig.writer(.existing(docID: doc.id)) }
        writer.submit("typed")
        try await writer.flush()
        // Restore, Apply or an agent revision moves the head; the writer's last typed text is old by now.
        let other = r.rig.writer(.existing(docID: doc.id))
        other.submit("restored")
        try await other.flush()
        let session = try editorAgain(r, readWith: "restored")
        #expect(session.startText == "restored")
    }

    @Test func aLayerNeverWrittenStartsFromTheNoteAsRead() throws {
        let r = try ReconRig()
        let session = try editorAgain(r, readWith: "source text")
        #expect(session.startText == nil)  // the editor takes the layer's Markdown
    }

    @Test func theReadOnlyKeyBlocksTheSessionAndNothingIsWritten() async throws {
        let r = try ReconRig()
        let content = r.rig.content(layers: [r.rig.layer("text")])
        let session = try #require(
            NoteEditingSession.make(
                content: content, layerID: "notes", store: r.store, registry: r.registry, readOnly: true))
        #expect(!session.isEditable)
        session.handle(NoteEditorEdit(text: "typed", range: 0..<5, changeInLength: 5))
        #expect(!session.writer.hasPendingText)
        #expect(await session.flush() == .nothing)
        #expect(try r.store.liveDocument(key: r.key, layer: "notes") == nil)
    }

    @Test func theEditorReportsEditsToTheWriterAndFreezesTheRenderedLayer() async throws {
        let r = try ReconRig()
        let layer = r.rig.layer("rendered", version: "v1")
        let content = r.rig.content(layers: [layer])
        let document = NoteDocumentModel(id: .live(r.key))
        document.apply(content)
        let session = try #require(
            NoteEditingSession.make(
                content: content, layerID: "notes", store: r.store, registry: r.registry, model: document,
                readOnly: false)
        )
        document.startEditing(session)
        let controller = NoteEditorController(pasteboard: RecordingPasteboard())
        session.attach(to: controller)
        #expect(!controller.isReadOnly)
        controller.onEdit(NoteEditorEdit(text: "rendered, typed", range: 8..<15, changeInLength: 7))
        // The source changes after the first keystroke: the view keeps the frozen layer.
        document.apply(r.rig.content(layers: [r.rig.layer("changed by the source", version: "v2")]))
        #expect(document.selectedLayer?.markdown == "rendered")
        #expect(document.selectedLayer?.version == "v1")
        let outcome = await session.flush()
        let docID = try #require(outcome.docIDOfSeed)
        #expect(try r.store.revisions(of: docID).first?.body == "rendered")  // seeded from what was rendered
        #expect(try r.rig.head(docID).body == "rendered, typed")
        controller.onFocusChange(false)  // blur is a save point and must not throw
    }

    @Test func aSaveThatFailsKeepsTheTextForTheRetry() async throws {
        let r = try ReconRig()
        let doc = try r.rig.seededDocument(r.rig.layer("agent"))
        let session = NoteEditingSession(
            documentID: .live(r.key, layer: "notes"), writer: r.rig.writer(.existing(docID: doc.id)), model: nil,
            block: nil)
        try r.rig.failNextInsert(body: "boom")
        session.handle(NoteEditorEdit(text: "boom", range: 0..<4, changeInLength: 4))
        _ = await session.flush()
        #expect(session.saveFailed)
        try r.rig.clearFault()
        await session.retry()
        #expect(!session.saveFailed)
        #expect(try r.rig.head(doc.id).body == "boom")
    }

    @Test func theReadOnlySettingIsReadAtEveryEditNotOnlyWhenTheSessionIsMade() async throws {
        let r = try ReconRig()
        let content = r.rig.content(layers: [r.rig.layer("rendered")])
        let flag = ReadOnlyFlag()
        let made = NoteEditingSession.make(
            content: content, layerID: "notes", store: r.store, registry: r.registry, readOnly: false,
            readOnlyNow: { flag.value })
        let session = try #require(made)
        let controller = NoteEditorController(pasteboard: RecordingPasteboard())
        session.attach(to: controller)
        #expect(session.isEditable)
        flag.value = true
        #expect(!session.isEditable)
        session.handle(NoteEditorEdit(text: "typed", range: 0..<5, changeInLength: 5))
        #expect(!session.writer.hasPendingText)
        #expect(controller.isReadOnly)
        flag.value = false
        #expect(session.isEditable)
    }

    @Test func layersUnfreezeOnceTheEditorIsNotOpen() throws {
        let r = try ReconRig()
        let document = NoteDocumentModel(id: .live(r.key))
        document.apply(r.rig.content(layers: [r.rig.layer("rendered", version: "v1")]))
        document.freezeLayer("notes")
        // A head move (Restore, Apply, reconcile) with no editor open: the layer shows the new head.
        document.apply(r.rig.content(layers: [r.rig.layer("restored", version: "v2")]))
        #expect(document.selectedLayer?.markdown == "restored")
        #expect(document.frozenLayers.isEmpty)
    }
}

private final class ReadOnlyFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
