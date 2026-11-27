import Foundation
import LintelKit

/// Names one layer document (spec "Data Model"): a live layer of a note, or a detached overlay by its row.
enum NoteDocumentID: Hashable, Sendable {
    case live(NoteKey, layer: String)
    case detached(docID: Int64)
}

/// One `RevisionWriter` per open `NoteDocumentID`, so a note open twice (a tab and a palette or route open) is one
/// document with one buffer and every head-moving write goes through that one writer. It is also what the
/// detacher asks first: an open document is flushed and re-keyed, never deleted while its tab is open.
@MainActor
final class NoteDocumentRegistry {
    private struct Entry {
        var writer: RevisionWriter
        var item: NoteItemID
        /// Who holds the entry now: set from the registry's one counter when the entry is made and again by every
        /// `writer(for:)` that hands it out. A release forgets an entry only while its `stamp` is still the one the
        /// leave recorded (`marks(item:)`), so a writer taken after the leave, or an entry made anew after it was
        /// forgotten, is never let go by that release. Stamps never repeat, so there is no "same value again".
        var stamp: Int
        /// The tab closed but the last flush failed: the entry (and its buffered text) stays until a flush works.
        var lingering = false
    }

    private var entries: [NoteDocumentID: Entry] = [:]
    private var lastStamp = 0
    private let log: any NotesLogging

    /// Runs after a document was released: deletes the detached rows that are no longer open and have no user
    /// writing and no open comment. Set by the plugin, which owns the store.
    var cleanup: @Sendable (Set<Int64>) async -> Void = { _ in }
    /// A detach re-keyed the open documents of a note: the tab of `.live(key)` is now
    /// `.detached(key, startedAtMs:)` and shows "Recording removed".
    /// Returns `false` when no tab could be moved (it was closed, or the detached tab is already open).
    var onRekey: @MainActor (NoteKey, Int64) -> Bool = { _, _ in true }
    /// A tab closed (or the quit flush ran) while its text could not be written: the text is kept and retried.
    var onSaveFailure: @MainActor (NoteItemID) -> Void = { _ in }
    /// A deletion removed these notes' documents behind the UI's back (Also delete kept copies): their tabs close.
    var onDiscard: @MainActor (Set<NoteItemID>) -> Void = { _ in }

    init(log: any NotesLogging = OSNotesLog()) {
        self.log = log
    }

    /// The writer of a document, made by `make` the first time it is opened.
    func writer(for id: NoteDocumentID, item: NoteItemID, make: () -> RevisionWriter) -> RevisionWriter {
        if var existing = entries[id] {
            existing.stamp = nextStamp()
            existing.lingering = false
            entries[id] = existing
            return existing.writer
        }
        let writer = make()
        entries[id] = Entry(writer: writer, item: item, stamp: nextStamp())
        return writer
    }

    private func nextStamp() -> Int {
        lastStamp += 1
        return lastStamp
    }

    /// The ownership rule, in one place. A writer belongs to the registry from `writer(for:)` until it is forgotten;
    /// whoever takes it (`writer(for:)`) stamps it. Only an operation that saw the stamp it acts on may forget the
    /// entry, and only after the writer's text is in the store: `release` (a note left the screen: it forgets the
    /// entries as they were AT THE LEAVE, `marks(item:)`, read synchronously before any await), `dropIfLingering`
    /// (a flush point after a failed leave: the stamp the flush started with) and `discard*` (the user confirmed
    /// the deletion). A writer taken again after any of those started is therefore kept, and `flushAll` (hide,
    /// Settings, `deactivate()`, quit) always sees it.
    func marks(item: NoteItemID) -> [NoteDocumentID: Int] {
        var marks: [NoteDocumentID: Int] = [:]
        for (id, entry) in entries where entry.item == item { marks[id] = entry.stamp }
        return marks
    }

    func writer(for id: NoteDocumentID) -> RevisionWriter? { entries[id]?.writer }

    var documentIDs: [NoteDocumentID] { Array(entries.keys) }

    /// The open live layer documents of a note.
    func writers(forKey key: NoteKey) -> [(layer: String, writer: RevisionWriter)] {
        entries.compactMap { id, entry in
            if case .live(let entryKey, let layer) = id, entryKey == key { return (layer, entry.writer) }
            return nil
        }.sorted { $0.layer < $1.layer }
    }

    /// The notes with an open live layer document.
    var openLiveKeys: [NoteKey] {
        var seen = Set<NoteKey>()
        return entries.keys.compactMap { id -> NoteKey? in
            if case .live(let key, _) = id, seen.insert(key).inserted { return key }
            return nil
        }.sorted { $0.rawValue < $1.rawValue }
    }

    /// The rows that are open now (a document that never wrote has none).
    func openDocIDs() async -> Set<Int64> {
        var ids = Set<Int64>()
        for entry in entries.values {
            if let id = await entry.writer.docID { ids.insert(id) }
        }
        return ids
    }

    /// Writes every buffer (window close, quit, `deactivate()`). A write that fails is logged; its text stays in
    /// the writer's buffer, and the entry stays too, so the next flush point or quit tries again.
    func flushAll() async {
        for (id, entry) in Array(entries) {
            do {
                try await entry.writer.flush()
                dropIfLingering(id, entry)
            } catch {
                log.error(NotesLogEvent("flush", code: (error as? NotesError)?.code ?? "flushFailed"))
            }
        }
    }

    private func dropIfLingering(_ id: NoteDocumentID, _ flushed: Entry) {
        guard let current = entries[id], current.lingering, current.stamp == flushed.stamp else { return }
        entries[id] = nil
    }

    /// A note left the screen (`NotesWorkspaceModel.dropPreview`, also when the full window gave it up or an agent
    /// run on a note nobody looks at ended): writes and forgets every document of `item` as it is now. Callers that
    /// await something before the release (the pad's flush, an earlier release) take `marks(item:)` at the leave
    /// and call `release(marks:)`.
    func release(item: NoteItemID) async {
        await release(marks: marks(item: item))
    }

    /// Flushes the documents of the marks, forgets them, then runs the deferred delete of detached rows. A document
    /// whose flush fails is NOT forgotten (its text would be lost): it lingers, is retried by the next flush point
    /// or quit, and `onSaveFailure` says so. A document taken again after its mark (a note opened again while the
    /// leave still wrote) has another stamp and is kept, before or during the flush: its new holder writes it.
    func release(marks: [NoteDocumentID: Int]) async {
        guard !marks.isEmpty else { return }
        for (id, mark) in marks.sorted(by: { "\($0.key)" < "\($1.key)" }) {
            guard let entry = entries[id], entry.stamp == mark else { continue }
            do {
                try await entry.writer.flush(closingSession: true)
                if let now = entries[id], now.stamp == mark { entries[id] = nil }
            } catch {
                log.error(NotesLogEvent("flush", code: (error as? NotesError)?.code ?? "flushFailed"))
                if var now = entries[id], now.stamp == mark {
                    now.lingering = true
                    entries[id] = now
                    onSaveFailure(now.item)
                }
            }
        }
        await cleanup(await openDocIDs())
    }

    /// A deletion removed the documents of `item`: their writers are forgotten WITHOUT writing (the text is deleted
    /// with them, after the user confirmed it) and their timers and retries stop.
    func discard(item: NoteItemID) {
        for (id, entry) in entries where entry.item == item {
            entry.writer.discardPending()
            entries[id] = nil
        }
    }

    /// Erase Notes Data: every writer is forgotten WITHOUT writing (the user confirmed the erase), and the tabs
    /// are told through `onDiscard`.
    func discardAll() {
        var items = Set<NoteItemID>()
        for entry in entries.values {
            entry.writer.discardPending()
            items.insert(entry.item)
        }
        entries = [:]
        if !items.isEmpty { onDiscard(items) }
    }

    /// The same for documents named by row (the kept copies of one owner); their tabs are told through `onDiscard`.
    func discard(docIDs: Set<Int64>) async {
        var items = Set<NoteItemID>()
        for (id, entry) in Array(entries) {
            guard let docID = await entry.writer.docID, docIDs.contains(docID) else { continue }
            entry.writer.discardPending()
            entries[id] = nil
            items.insert(entry.item)
        }
        if !items.isEmpty { onDiscard(items) }
    }

    /// After a detach: the open documents of the key move to `.detached(docID)` (their writers keep their rows, so
    /// typed text lands in the detached document); a live document that had no row yet is retired, because the
    /// snapshot it would seed from belongs to the recording that is gone. When no tab could be moved (it is gone,
    /// or the detached tab exists already) the moved writers are released at once instead of living on unowned.
    func rekey(key: NoteKey, moved: [DetachedRow]) async {
        let started = moved.compactMap(\.startedAtMs).first ?? 0
        var movedIDs: [NoteDocumentID] = []
        for row in moved {
            guard let entry = entries.removeValue(forKey: .live(key, layer: row.layer)) else { continue }
            let id = NoteDocumentID.detached(docID: row.docID)
            entries[id] = Entry(
                writer: entry.writer, item: .detached(key, startedAtMs: started), stamp: entry.stamp)
            movedIDs.append(id)
        }
        for id in entries.keys {
            if case .live(let entryKey, _) = id, entryKey == key, let entry = entries.removeValue(forKey: id) {
                entry.writer.retire()
            }
        }
        guard !moved.isEmpty else { return }
        if !onRekey(key, started) {
            await release(
                marks: Dictionary(
                    uniqueKeysWithValues: movedIDs.compactMap { id in entries[id].map { (id, $0.stamp) } }))
        }
    }
}

/// The one place that detaches an overlay (merge, open and sweep): asks the registry first, flushes the open
/// documents of the key, moves every live row of the key to `detached` in one transaction, re-keys the open
/// documents, and then deletes what no longer needs to live ("detach means delete" for an overlay without user
/// writing and without an open comment; an open document is deleted only after its tab closes). Rows that carry a
/// Recently deleted mark (the owner trashed the note) are deleted instead, never kept as a copy, and their writers
/// are discarded once the rows are gone.
struct RegistryOverlayDetacher: OverlayDetacher {
    let store: NotesStore
    let registry: NoteDocumentRegistry

    func detach(_ key: NoteKey, reason: OverlayDetachReason) async throws {
        for (_, writer) in await registry.writers(forKey: key) { try await writer.flush() }
        let (moved, deleted) = try store.detachOrDeleteTrashed(key)
        if !deleted.isEmpty { await registry.discard(docIDs: Set(deleted)) }
        await registry.rekey(key: key, moved: moved)
        try store.deleteUnkeptDetached(excluding: await registry.openDocIDs())
    }
}
