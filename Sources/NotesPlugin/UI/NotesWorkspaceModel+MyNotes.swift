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
        let stored = document.mineMarkdown ?? ""
        switch document.id {
        case .detached:
            document.myNotes = MyNotesPad(text: stored, session: nil, readOnlyReason: .recordingRemoved)
        case .live:
            let session = environment.makeMineSession(content)
            let reason: MyNotesPad.ReadOnlyReason? =
                session == nil ? (environment.notesReadOnly ? .readOnly : .unavailable) : nil
            // The note's heads can be older than the text typed last (a write that failed and lingers, a retry or
            // a flush that landed after they were read): the session's text is the newest (`makeMine`), and the
            // next keystroke would otherwise replace what was typed.
            let text = session?.startText ?? stored
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

    /// The note left the screen (`dropPreview`): My notes are written, then every writer of the note (My notes and
    /// the layers that were edited, restored, commented on or revised) is written and let go
    /// (`NoteDocumentRegistry.release(item:)`), so the reconciler and the deferred delete of detached rows no longer
    /// count the note as open. A writer whose write fails stays in the registry with its text.
    /// Leaves of one note run one after the other; `awaitRelease` waits for them. A read does not need to: My notes
    /// start from the writer's text or a head read in the same turn as the writer (`makeMine`).
    func releaseDocuments(_ document: NoteDocumentModel) {
        let id = document.id
        let pad = document.myNotes
        document.myNotes = nil
        let registry = environment.registry
        let previous = documentReleases[id]
        let token = UUID()
        let task = Task {
            await previous?.task.value
            await pad?.flush(closingSession: true)
            await registry?.release(item: id)
        }
        documentReleases[id] = (token, task)
        Task {
            await task.value
            if documentReleases[id]?.token == token { documentReleases[id] = nil }
        }
    }

    /// Waits until the writers of a note that left the screen are written and let go (`releaseDocuments`).
    func awaitRelease(_ id: NoteItemID) async {
        await documentReleases[id]?.task.value
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
