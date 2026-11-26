import Foundation
import LintelKit

/// The trash sweep (notes explorer spec, Deletion lifecycle): keeps the overlays of recorded notes in step with
/// their owner's Recently deleted, without ever loading a note.
///
/// - `run()`: for the keys that have live overlays it asks each owner that conforms to `NoteSourceTrash` which of
///   them are trashed (`trashedKeys`, batches of 500, each under the per-source budget), marks their overlays with
///   the owner's `deleted_at` (every layer, `mine` included) and clears the mark of a marked key the owner says is
///   not trashed, but only after a positive `exists`: a mark is never cleared for a key that is gone, so the
///   purge that follows deletes its overlays instead of keeping them as a copy (`detachOrDeleteTrashed`). A source
///   that does not conform trashes nothing, so its marks are cleared the same way. A source that is off, throws or
///   does not answer decides nothing.
/// - `visibleHits(_:)`: the guard between a panel delete and the next sweep, one `trashedKeys` call per source and
///   result page, so a note the owner trashed never shows up in a Notes search. A source that cannot answer keeps
///   its hits (unknown is never "trashed", as everywhere in the library).
/// - `removeGoneFolderEntries()`: a folder entry whose key is gone (its owner's `exists`, in batches of 500, or no
///   document of a manual note) is removed; an entry of a trashed note stays, so a restore puts it back in its
///   folder.
///
/// Logs carry codes and counts only, never a key's text, a title or a note.
struct NoteTrashSweep: Sendable {
    struct Result: Sendable, Equatable {
        /// Documents newly marked deleted.
        var marked = 0
        /// Documents whose mark was cleared (the owner restored the note).
        var cleared = 0
    }

    let store: NotesStore
    let library: NoteLibrary
    var clock: any Clock<Duration> = ContinuousClock()
    var budget: Duration = SourceFanOut.defaultBudget
    var log: any NotesLogging = OSNotesLog()

    private static let batch = NotesStore.trashChunk

    private static func batches(_ keys: [NoteKey]) -> [[NoteKey]] {
        stride(from: 0, to: keys.count, by: batch).map { Array(keys[$0..<min($0 + batch, keys.count)]) }
    }

    private static func byPlugin(_ keys: [NoteKey]) -> [(PluginID, [NoteKey])] {
        Dictionary(grouping: keys, by: \.pluginID).sorted { $0.key < $1.key }
    }

    @discardableResult
    func run() async -> Result {
        let keys: [NoteKey]
        let marked: Set<NoteKey>
        do {
            keys = try store.liveOverlayKeys()
            marked = try store.markedOverlayKeys()
        } catch {
            log.error(NotesLogEvent("trashSweep", code: (error as? NotesError)?.code ?? "trashSweepUnreadable"))
            return Result()
        }
        var result = Result()
        for (_, pluginKeys) in Self.byPlugin(keys) {
            guard let first = pluginKeys.first, let source = await library.source(for: first) else { continue }
            guard let trashed = await trashedKeys(pluginKeys, of: source) else { continue }
            let restored = pluginKeys.filter { marked.contains($0) && trashed[$0] == nil }
            let existing = await existingKeys(restored, of: source) ?? []
            do {
                result.marked += try store.markOverlaysTrashed(trashed)
                result.cleared += try store.clearOverlayTrashMarks(restored.filter(existing.contains))
            } catch {
                log.error(NotesLogEvent("trashSweep", code: (error as? NotesError)?.code ?? "trashSweepFailed"))
            }
        }
        if result.marked > 0 || result.cleared > 0 {
            log.notice(NotesLogEvent("trashSweep", count: result.marked + result.cleared))
        }
        return result
    }

    /// The hits a search may show: a live overlay hit of a recorded note the owner says is trashed is left out.
    func visibleHits(_ hits: [NoteSearchHit]) async -> [NoteSearchHit] {
        let asked = hits.filter { !$0.isDetached && $0.key.pluginID != NotesStore.manualPluginID }.map(\.key)
        var hidden = Set<NoteKey>()
        for (_, pluginKeys) in Self.byPlugin(Array(Set(asked))) {
            guard let first = pluginKeys.first, let source = await library.source(for: first),
                let trashed = await trashedKeys(pluginKeys, of: source)
            else { continue }
            hidden.formUnion(trashed.keys)
        }
        guard !hidden.isEmpty else { return hits }
        return hits.filter { $0.isDetached || !hidden.contains($0.key) }
    }

    /// Removes the folder entries of keys that are gone. Returns how many went.
    @discardableResult
    func removeGoneFolderEntries() async -> Int {
        let keys: [NoteKey]
        do {
            keys = try store.folderEntryKeys()
        } catch {
            log.error(NotesLogEvent("folderSweep", code: (error as? NotesError)?.code ?? "folderSweepUnreadable"))
            return 0
        }
        guard !keys.isEmpty else { return 0 }
        var gone: [NoteKey] = []
        for (plugin, pluginKeys) in Self.byPlugin(keys) {
            if plugin == NotesStore.manualPluginID {
                guard let existing = try? store.existingManualKeys(pluginKeys) else { continue }
                gone += pluginKeys.filter { !existing.contains($0) }
                continue
            }
            guard let first = pluginKeys.first, let source = await library.source(for: first),
                let existing = await existingKeys(pluginKeys, of: source)
            else { continue }
            gone += pluginKeys.filter { !existing.contains($0) }
        }
        do {
            return try store.deleteFolderEntries(gone)
        } catch {
            log.error(NotesLogEvent("folderSweep", code: (error as? NotesError)?.code ?? "folderSweepFailed"))
            return 0
        }
    }

    // MARK: Asking the owner

    /// The owner's `deleted_at` of each trashed key; empty for a source without Recently deleted, `nil` when the
    /// source did not answer (unknown).
    private func trashedKeys(_ keys: [NoteKey], of source: any NoteSource) async -> [NoteKey: Date]? {
        guard let trash = source as? any NoteSourceTrash else { return [:] }
        var found: [NoteKey: Date] = [:]
        for part in Self.batches(keys) {
            let outcome = await SourceFanOut.call(budget: budget, clock: clock) { try await trash.trashedKeys(part) }
            guard case .value(let answer) = outcome else { return nil }
            for (key, date) in answer where part.contains(key) { found[key] = date }
        }
        return found
    }

    /// The keys the owner still has; `nil` when it did not answer.
    private func existingKeys(_ keys: [NoteKey], of source: any NoteSource) async -> Set<NoteKey>? {
        var found = Set<NoteKey>()
        for part in Self.batches(keys) {
            let outcome = await SourceFanOut.call(budget: budget, clock: clock) { try await source.exists(part) }
            guard case .value(let answer) = outcome else { return nil }
            found.formUnion(answer)
        }
        return found
    }
}
