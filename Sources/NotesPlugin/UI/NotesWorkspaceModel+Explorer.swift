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

    /// A click on a sidebar row: the list shows that collection. Opened tabs stay open, as with the old Notes /
    /// Dictations switch: closing them would cancel a running "Ask agent" run without a word (review m3 of #348).
    /// The full-window note of phase 3b replaces the tabs and decides the way back.
    func showCollectionFromSidebar(_ next: NoteCollection) async {
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

// MARK: Keys of the list

/// A key the explorer's list acts on (spec "Keyboard and accessibility"). The view only maps a key press to one of
/// these, so what each key does is tested without SwiftUI.
enum ExplorerListKey: Sendable {
    case up
    case down
    case open
    /// ⌘⌫.
    case delete
    case escape
}

extension NotesWorkspaceModel {
    /// What a key does in the list; `false` leaves the key to the rest of the window (the editor's ⌘⌫, the window's
    /// Esc).
    func handleListKey(_ key: ExplorerListKey) -> Bool {
        switch key {
        case .up:
            moveSelection(by: -1)
            return true
        case .down:
            moveSelection(by: 1)
            return true
        case .open:
            guard let id = explorer.selection else { return false }
            open(id)
            return true
        case .delete:
            guard let id = explorer.selection, canDelete(id) else { return false }
            Task { await requestDelete(id) }
            return true
        case .escape:
            // Esc ends a search, as in the search field; without one it is not the list's key.
            guard isSearching || !searchText.isEmpty else { return false }
            Task { await clearSearch() }
            return true
        }
    }
}
