import Foundation
import LintelKit

/// My notes (spec step 3.5): the pad of a meeting's `mine` layer in the preview's My notes tab and in the full
/// window's "My notes" segment. One pad per document; it is written at every save point: leaving the tab, another
/// note, "‹ All notes", hiding the window and quitting (the registry's `flushAll`).
extension NotesWorkspaceModel {
    /// Makes the pad of a loaded meeting the first time My notes is shown. A note you wrote has none (its text is
    /// already yours), nor has a dictation; a kept copy of a removed recording shows its My notes as they were.
    func prepareMyNotes(_ document: NoteDocumentModel) {
        guard document.myNotes == nil, document.phase == .loaded, Self.isMeeting(document), !document.isManual,
            let content = document.content
        else { return }
        let text = document.mineMarkdown ?? ""
        switch document.id {
        case .detached:
            document.myNotes = MyNotesPad(text: text, session: nil, readOnlyReason: .recordingRemoved)
        case .live:
            let session = environment.makeMineSession(content)
            let reason: MyNotesPad.ReadOnlyReason? =
                session == nil ? (environment.notesReadOnly ? .readOnly : .unavailable) : nil
            document.myNotes = MyNotesPad(text: text, session: session, readOnlyReason: reason)
        }
    }

    /// After a read: the pad is made when My notes is on screen (the preview's tab or the full window's segment).
    func prepareMyNotesIfShown(_ document: NoteDocumentModel) {
        let inPreview = explorer.selection == document.id && previewTab == .mine && openedID != document.id
        if document.showsMine || inPreview { prepareMyNotes(document) }
    }

    /// A save point that keeps the pad (another tab, "‹ All notes").
    func flushMyNotes(_ document: NoteDocumentModel) {
        guard let pad = document.myNotes else { return }
        Task { await pad.flush() }
    }

    /// The note left the screen: what is typed is written and the writer is let go.
    func closeMyNotes(_ document: NoteDocumentModel) {
        guard let pad = document.myNotes, case .live(let key) = document.id else { return }
        document.myNotes = nil
        let release = environment.releaseWriter
        Task {
            await pad.flush(closingSession: true)
            await release(.live(key, layer: NotesStore.mineLayer))
        }
    }

    /// The full window's "My notes" segment. The editor of a layer ends first (it writes what is typed).
    func showMyNotes(_ document: NoteDocumentModel) {
        guard !document.showsMine else { return }
        if document.isEditing { document.leaveEditing() }
        if document.compare != nil { document.setCompare(nil) }
        document.showsMine = true
        prepareMyNotes(document)
    }

    /// A layer of the full window's switch: leaving My notes is a save point.
    func showLayer(_ layerID: String, of document: NoteDocumentModel) {
        if document.showsMine {
            flushMyNotes(document)
            document.showsMine = false
        }
        document.selectLayer(layerID)
    }

    /// "Try Now" on the pad's failed strip.
    func retryMyNotes(_ document: NoteDocumentModel) async {
        await document.myNotes?.retry()
    }

    /// The text Copy Markdown and Save .md take: My notes while it is on screen, else the layer.
    func shownMarkdown(_ document: NoteDocumentModel) -> String? {
        document.showsMine ? document.myNotes?.text : document.markdown
    }
}
