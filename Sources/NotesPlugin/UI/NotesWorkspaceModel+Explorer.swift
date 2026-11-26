import Foundation
import LintelKit

/// What the explorer's list and preview need beyond the rows: the empty states, the sidebar's collection clicks and
/// the preview's "Try Again" (spec `2026-11-24-notes-explorer-main-window`, phase 3a).
extension NotesWorkspaceModel {
    /// The sentence, help line and action of an empty list, from the facts as they are right now.
    var emptyContent: ExplorerEmptyContent {
        ExplorerEmptyContent.library(
            collection: collection,
            meetingsOn: activePlugins.contains(NoteCollection.meetingPlugin),
            dictationOn: activePlugins.contains(NoteCollection.dictationPlugin),
            shortcut: environment.dictationShortcut().map(Self.display))
    }

    /// The button of an empty state.
    func perform(_ action: ExplorerEmptyContent.Action) async {
        switch action {
        case .openSettings: openSettings()
        case .searchAllNotes: await searchAllNotes()
        case .tryAgain: await perform("locked.retry")
        }
    }

    /// A click on a sidebar row: back to the list (open tabs close) and that collection.
    func showCollectionFromSidebar(_ next: NoteCollection) async {
        for tab in tabs.tabs { close(tab.id) }
        await setCollection(next)
    }

    // MARK: Writing the notes again

    /// Whether the preview's "Try Again" can write the notes: only the plugin that owns the recording can, and only
    /// while it is on (a recorder exists).
    func canRetryNotes(_ id: NoteItemID) -> Bool {
        guard let recorder = environment.liveRecorder() else { return false }
        return recorder.pluginID == id.key.pluginID
    }

    func retryNotes(_ id: NoteItemID) async {
        guard canRetryNotes(id), let recorder = environment.liveRecorder() else { return }
        do {
            try await recorder.retryNotes(id.key)
            await loadContent(id)
        } catch {
            previewRetryFailed = true
        }
    }
}
