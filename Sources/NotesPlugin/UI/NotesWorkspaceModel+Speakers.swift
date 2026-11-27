import Foundation
import LintelKit

/// Speaker name suggestions in the transcript (speaker names, step 1.6b). The answer belongs to the note's owner:
/// Yes and No go through `NoteSourceEditing` (wired like the title's rename), never into `notes.sqlite`.
extension NotesWorkspaceModel {
    /// Called with every read of a live note's content: a source that can answer gets the handler, one that cannot
    /// (or a source that stopped supporting it) gets none, so the transcript shows no suggestion.
    func wireSpeakerSuggestions(_ document: NoteDocumentModel, editable: Bool) {
        if editable {
            let id = document.id
            document.answerSpeakerSuggestion = { [weak self, weak document] speakerID, name, confirm in
                // The flag is set before the task starts, so a second click in the same moment sends nothing.
                guard let self, let document, Self.beginAnswer(document, speakerID: speakerID) else { return }
                Task {
                    await self.sendAnswer(id, document: document, speakerID: speakerID, name: name, confirm: confirm)
                }
            }
        } else {
            document.answerSpeakerSuggestion = nil
        }
        document.canEditSpeakers = editable
    }

    /// Sends Yes or No to the owner. On success the note is read again (the speaker's name, or its plain label after
    /// No); on any error nothing changes and the strip "That didn’t finish. Nothing was changed." says so. The name
    /// is never logged.
    func answerSpeakerSuggestion(
        _ id: NoteItemID, document: NoteDocumentModel, speakerID: String, name: String, confirm: Bool
    ) async {
        guard Self.beginAnswer(document, speakerID: speakerID) else { return }
        await sendAnswer(id, document: document, speakerID: speakerID, name: name, confirm: confirm)
    }

    /// Marks the answer as on its way; `false` while another one for this note still is.
    private static func beginAnswer(_ document: NoteDocumentModel, speakerID: String) -> Bool {
        guard document.answeringSpeaker == nil else { return false }
        document.answeringSpeaker = speakerID
        return true
    }

    private func sendAnswer(
        _ id: NoteItemID, document: NoteDocumentModel, speakerID: String, name: String, confirm: Bool
    ) async {
        defer { document.answeringSpeaker = nil }
        guard case .live(let key) = id else { return }
        document.actionFailed = false
        do {
            if confirm {
                try await environment.confirmSpeakerName(key, speakerID, name)
            } else {
                try await environment.rejectSpeakerName(key, speakerID, name)
            }
        } catch {
            document.actionFailed = true
            return
        }
        guard documents[id] === document else { return }
        await loadContent(id)
    }
}

extension NoteLibrary {
    /// Yes (`confirm`) or No on a speaker name suggestion, sent to the note's owner. A source that is off or cannot
    /// answer throws `NoteEditingError.unsupported`; the owner's own errors pass through.
    func answerSpeakerName(_ key: NoteKey, speakerID: String, name: String, confirm: Bool) async throws {
        guard let editing = await source(for: key) as? any NoteSourceEditing else {
            throw NoteEditingError.unsupported
        }
        if confirm {
            try await editing.confirmSpeakerName(key, speakerID: speakerID, name: name)
        } else {
            try await editing.rejectSpeakerName(key, speakerID: speakerID, name: name)
        }
    }
}
