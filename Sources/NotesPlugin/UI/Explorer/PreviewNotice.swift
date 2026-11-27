import Foundation
import LintelKit

/// The tab of a meeting's preview (spec "Layout"): Notes, My notes, Transcript. It belongs to the preview, not to the
/// document's shown layer, so the Notes tab stays on (and says what is missing) when the meeting has no notes yet.
enum PreviewTab: String, Sendable, CaseIterable {
    case notes
    case mine
    case transcript

    /// The layer the tab shows; My notes has none in this phase (read-only help text until the editor).
    var layerID: String? {
        switch self {
        case .notes: "notes"
        case .mine: nil
        case .transcript: NoteDocumentModel.transcriptLayerID
        }
    }
}

/// What the Notes tab of a meeting's preview says in place of the notes (spec "States table", Preview: meeting).
/// Pure, so every state is tested without a view.
enum PreviewNotice: Equatable, Sendable {
    /// "Lintel couldn't write the notes…", with Try Again only when a recorder can write them again.
    case failed(canRetry: Bool)
    /// The notes wait for a download: Download opens Models.
    case needsModel
    /// The working ring and "Lintel is writing the notes."
    case writing
    /// A finished meeting without notes: "Notes are off for this meeting.", with Write Notes when a recorder can.
    case notesOff(canWrite: Bool)
    /// Any other meeting without a notes layer (recording, interrupted, …): the document's "no text yet" line,
    /// never the transcript under the Notes tab.
    case noText

    /// - Parameters:
    ///   - tab: the preview's tab; only Notes can carry a notice.
    ///   - state: the meeting's state as the source reports it.
    ///   - hasNotes: whether the note has a `notes` layer.
    ///   - canRetry: whether a recorder of the note's plugin exists (`NotesWorkspaceModel.canRetryNotes`).
    static func make(tab: PreviewTab, state: NoteState?, hasNotes: Bool, canRetry: Bool) -> PreviewNotice? {
        guard tab == .notes else { return nil }
        switch state {
        case .failed?: return .failed(canRetry: canRetry)
        case .needsModel?: return .needsModel
        case .writing?, .processing?: return .writing
        default:
            guard !hasNotes else { return nil }
            return state == .ready ? .notesOff(canWrite: canRetry) : .noText
        }
    }
}
