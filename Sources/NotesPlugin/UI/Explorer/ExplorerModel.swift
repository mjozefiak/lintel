import Foundation
import LintelKit
import Observation

/// What the notes explorer has chosen (spec `2026-11-24-notes-explorer-main-window`, phase 3a): the collection of the
/// sidebar, how many notes each one holds, and which row is selected (the preview shows it). It replaces the old
/// Notes / Dictations switch. The list itself (rows, paging, search) stays with `NotesWorkspaceModel`, which owns one
/// of these.
///
/// Selecting a row is not opening a note: a selection drives the preview, `open` makes a tab (the full note).
@MainActor @Observable
final class ExplorerModel {
    /// What the sidebar highlights and the list shows.
    private(set) var collection: NoteCollection
    /// The numbers beside the sidebar rows: browse counts, kept while a search is on (a search's totals are hit
    /// counts, never these).
    private(set) var counts = NoteCollectionCounts()
    /// The row the preview shows; `nil` when there is none (an empty list, nothing chosen yet).
    private(set) var selection: NoteItemID?

    @ObservationIgnored private let settings: PluginSettings?
    /// The order of the list when the selection was last reconciled, so a row that leaves can hand the selection to
    /// its neighbour.
    @ObservationIgnored private var lastOrder: [NoteItemID] = []

    /// - Parameter settings: where the collection is read from and written to (`plugins.notes.explorer.collection`);
    ///   `nil` keeps it in memory (tests, QA, the gallery).
    init(settings: PluginSettings? = nil, collection: NoteCollection? = nil) {
        self.settings = settings
        self.collection =
            collection ?? NoteCollection(stored: settings?.string(NotesSettingsKey.explorerCollection))
    }

    /// Switches the collection. Only a user's choice is `persist`ed: a route that opens a note of another collection
    /// moves the list to All notes without rewriting the setting.
    @discardableResult
    func setCollection(_ next: NoteCollection, persist: Bool) -> Bool {
        guard next != collection else { return false }
        collection = next
        if persist { settings?.set(next.rawValue, for: NotesSettingsKey.explorerCollection) }
        return true
    }

    /// Sets the counts a read found; one that could not be read keeps the last number.
    func setCounts(_ next: NoteCollectionCounts) {
        counts = next.filling(from: counts)
    }

    func select(_ id: NoteItemID?) {
        if selection != id { selection = id }
    }

    /// After the list was read again: the selection stays while its row is still listed; a row that left (deleted,
    /// a search, another collection) hands the selection to the row that took its place, else to the one before it,
    /// else to the first; an empty list selects nothing. Returns the new selection.
    @discardableResult
    func reconcile(order: [NoteItemID]) -> NoteItemID? {
        let previousOrder = lastOrder
        lastOrder = order
        guard !order.isEmpty else {
            selection = nil
            return nil
        }
        if let selection, order.contains(selection) { return selection }
        selection = Self.successor(of: selection, was: previousOrder, now: order) ?? order.first
        return selection
    }

    /// The row that takes the place of `id` that left: the first one after it in the old order that is still listed,
    /// else the nearest one before it; `nil` when `id` was not in the old order or none of them is left.
    private static func successor(of id: NoteItemID?, was old: [NoteItemID], now order: [NoteItemID]) -> NoteItemID? {
        guard let id, let index = old.firstIndex(of: id) else { return nil }
        let listed = Set(order)
        if let next = old[(index + 1)...].first(where: { listed.contains($0) }) { return next }
        return old[..<index].last(where: { listed.contains($0) })
    }

    /// The next (or previous) row in the list for the arrow keys; stays on the last (first) row at the ends.
    func neighbour(of id: NoteItemID?, in order: [NoteItemID], step: Int) -> NoteItemID? {
        guard !order.isEmpty else { return nil }
        guard let id, let index = order.firstIndex(of: id) else { return step >= 0 ? order.first : order.last }
        return order[min(max(index + step, 0), order.count - 1)]
    }
}
