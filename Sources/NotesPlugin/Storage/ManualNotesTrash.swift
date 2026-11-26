import Foundation
import LintelKit
import Synchronization

/// One change stream per subscriber, told after every trash, restore, permanent delete and purge of Notes' own
/// manual notes; every stream finishes on `finishAll()` (the plugin's `deactivate()`).
final class TrashChangeBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<Void>.Continuation]>([:])

    func makeStream() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        return stream
    }

    func signal() {
        for continuation in continuations.withLock({ Array($0.values) }) { continuation.yield() }
    }

    func finishAll() {
        let all = continuations.withLock { all -> [AsyncStream<Void>.Continuation] in
            defer { all = [:] }
            return Array(all.values)
        }
        for continuation in all { continuation.finish() }
    }
}

/// Recently deleted for Notes' own manual notes (notes explorer spec, API Contracts): Notes is their owner, so it
/// contributes this `TrashSource` ("Notes", `hidesContent == false`) through `NotesPlugin.trashSources`, and the
/// shell's counts, Delete my data and Delete everything reach the manual notes without importing Notes.
///
/// - Ids are the note keys' raw values (`notes:<uuid>`); an id that is not a manual note's key is skipped like a
///   missing one. A manual note is never busy.
/// - The lazy-store rule holds: with no library (a fresh profile) the counts are 0, the pages empty and every call a
///   no-op; nothing creates the Keychain item or `notes.sqlite`.
/// - A database from a newer Lintel refuses every move (`NotesError.schemaNewer`); the hidden `readOnly` setting
///   does not, as it never blocks a delete.
/// - Titles are returned only in the pages; nothing here logs a title, a text or a key.
struct ManualNotesTrash: TrashSource {
    let id = "notes"
    let title = LocalizedStringResource("Notes", comment: "Recently Deleted: the heading of Notes' own notes")

    /// The store, only when a library exists (never opened or created here otherwise).
    let store: @MainActor @Sendable () -> NotesStore?
    let now: @Sendable () -> Date
    let changes: TrashChangeBroadcaster
    /// Forgets the open writers of documents a permanent delete removed (after the rows are gone).
    let discard: @MainActor @Sendable (Set<Int64>) async -> Void

    init(
        store: @escaping @MainActor @Sendable () -> NotesStore?, now: @escaping @Sendable () -> Date = { Date() },
        changes: TrashChangeBroadcaster, discard: @escaping @MainActor @Sendable (Set<Int64>) async -> Void = { _ in }
    ) {
        self.store = store
        self.now = now
        self.changes = changes
        self.discard = discard
    }

    private static let kindLabel = LocalizedStringResource(
        "Note", comment: "Recently Deleted: what a manual note is, shown next to its title")

    /// The manual-note keys among `ids`, in order, without repeats.
    private static func keys(_ ids: [String]) -> [NoteKey] {
        var seen = Set<NoteKey>()
        return ids.compactMap { raw in
            guard let key = NoteKey(rawValue: raw), key.pluginID == NotesStore.manualPluginID,
                seen.insert(key).inserted
            else { return nil }
            return key
        }
    }

    func liveCount() async throws -> Int {
        guard let store = await store() else { return 0 }
        return try store.manualNoteCounts().live
    }

    func trashedCount() async throws -> Int {
        guard let store = await store() else { return 0 }
        return try store.manualNoteCounts().trashed
    }

    /// Cursor: `<deleted_at micros>|<key>` of the last row of the previous page.
    func trashed(after: String?, limit: Int) async throws -> TrashPage {
        guard let store = await store() else { return TrashPage() }
        let cursor = after.flatMap(Self.cursor)
        let size = max(1, limit)
        let rows = try store.trashedManualNotes(after: cursor, limit: size + 1)
        let page = Array(rows.prefix(size))
        let items = page.map { row in
            TrashedItem(
                id: row.key.rawValue, kindLabel: Self.kindLabel, title: row.title, deletedAt: row.deletedAt,
                purgeAt: TrashStamp.purgeAt(deletedAt: row.deletedAt))
        }
        let next = rows.count > size ? page.last.map { "\(TrashStamp.micros($0.deletedAt))|\($0.key.rawValue)" } : nil
        return TrashPage(items: items, next: next, total: try store.manualNoteCounts().trashed)
    }

    private static func cursor(_ text: String) -> (micros: Int64, key: String)? {
        guard let bar = text.firstIndex(of: "|"), let micros = Int64(text[..<bar]) else { return nil }
        return (micros, String(text[text.index(after: bar)...]))
    }

    func trash(_ ids: [String]) async throws {
        let keys = Self.keys(ids)
        guard !keys.isEmpty, let store = await store() else { return }
        if try store.trashManualNotes(keys, at: now()) != nil { changes.signal() }
    }

    @discardableResult
    func restore(_ ids: [String]) async throws -> Set<String> {
        let keys = Self.keys(ids)
        let foreign = Set(ids).subtracting(keys.map(\.rawValue))
        guard !keys.isEmpty, let store = await store() else { return Set(ids) }
        let gone = try store.restoreManualNotes(keys)
        changes.signal()
        return foreign.union(gone.map(\.rawValue))
    }

    func deleteNow(_ ids: [String]) async throws {
        let keys = Self.keys(ids)
        guard !keys.isEmpty, let store = await store() else { return }
        let removed = try store.deleteManualNotes(keys)
        guard !removed.isEmpty else { return }
        await discard(Set(removed))
        changes.signal()
    }

    func trashAll(at deletedAt: Date) async throws -> TrashBatch {
        let stamp = TrashStamp.date(micros: TrashStamp.micros(deletedAt))
        guard let store = await store() else { return TrashBatch(deletedAt: stamp, moved: 0, stayed: 0) }
        let moved = try store.trashAllManualNotes(at: deletedAt)
        if moved > 0 { changes.signal() }
        return TrashBatch(deletedAt: stamp, moved: moved, stayed: 0)
    }

    func restoreBatch(deletedAt: Date) async throws -> Int {
        guard let store = await store() else { return 0 }
        let restored = try store.restoreManualBatch(deletedAt: deletedAt)
        if restored > 0 { changes.signal() }
        return restored
    }

    func makeChanges() -> AsyncStream<Void> { changes.makeStream() }
}
