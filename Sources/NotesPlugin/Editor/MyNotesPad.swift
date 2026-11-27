import Foundation
import LintelKit
import Observation

/// My notes of one recorded note (spec step 3.5): the text of its `mine` layer and the session that writes it.
/// Only the user writes here; nothing of Lintel's (the notes, a revise run, the source) ever changes it. The row in
/// `notes.sqlite` is created by the first character the user types (the writer seeds it lazily), and what is
/// typed is written 1 s later and at every save point (another note, Back, hiding the window, quitting). A write
/// that fails keeps the text in the pad and in the writer's buffer; the writer keeps trying and "Try Now" asks it
/// at once.
@MainActor @Observable
final class MyNotesPad {
    /// Why the pad cannot be typed in. Each one is said in words above the text.
    enum ReadOnlyReason: Equatable, Sendable {
        /// `plugins.notes.readOnly`, or a store that refuses writes (a newer database).
        case readOnly
        /// No library can be opened (a Keychain problem) or nothing can write here.
        case unavailable
        /// The recording is gone and this is the copy Lintel kept: shown as it was, never changed.
        case recordingRemoved
    }

    private(set) var text: String
    /// Something typed waits to be written.
    private(set) var isSaving = false
    let session: NoteEditingSession?
    private let fixedReason: ReadOnlyReason?
    #if DEBUG
    /// Gallery: a pad that shows the failed state, or takes typing, without a store.
    private var galleryFailed = false
    private var galleryEditable = false
    #endif

    init(text: String, session: NoteEditingSession?, readOnlyReason: ReadOnlyReason? = nil) {
        self.text = text
        self.session = session
        fixedReason = readOnlyReason
        // A writer that outlived an earlier pad (a failed write lingers in the registry) still holds the text.
        isSaving = session?.writer.hasPendingText ?? false
        session?.writer.setWrittenHandler { [weak self] in
            Task { @MainActor in self?.writtenAll() }
        }
    }

    /// The last write failed; the text is still in the pad and the writer retries it.
    var saveFailed: Bool {
        #if DEBUG
        if galleryFailed { return true }
        #endif
        return session?.saveFailed ?? false
    }

    var readOnlyReason: ReadOnlyReason? {
        #if DEBUG
        if galleryEditable { return nil }
        #endif
        if let fixedReason { return fixedReason }
        guard let session else { return .unavailable }
        return session.isEditable ? nil : .readOnly
    }

    var isEditable: Bool { readOnlyReason == nil }

    /// An edit of the whole text. Ignored while the pad is read-only.
    func edit(_ edit: NoteEditorEdit) {
        guard isEditable, let session else { return }
        text = edit.text
        isSaving = true
        session.handle(edit)
    }

    /// A save point (focus lost, another note, Back, hiding the window).
    func flush(closingSession: Bool = false) async {
        guard let session else { return }
        _ = await session.flush(closingSession: closingSession)
        if !session.writer.hasPendingText { isSaving = false }
    }

    /// "Try Now" on the failed strip.
    func retry() async { await flush() }

    private func writtenAll() {
        if !(session?.writer.hasPendingText ?? false) { isSaving = false }
    }

    #if DEBUG
    /// Gallery: an editable pad, with the saving line or the failed strip, without a writer.
    func showForGallery(saving: Bool, failed: Bool) {
        isSaving = saving
        galleryFailed = failed
        galleryEditable = true
    }
    #endif
}
