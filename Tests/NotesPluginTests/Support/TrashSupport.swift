import Foundation
import LintelKit
import Synchronization

@testable import NotesPlugin

/// A note source with Recently deleted: `ScriptedNoteSource` for everything a `NoteSource` does, plus a scripted
/// trash (`trashed`, the owner's `deleted_at` per key) and a record of the `trashedKeys` batches Notes asked for.
final class TrashingNoteSource: NoteSourceTrash, Sendable {
    private struct State {
        var trashed: [NoteKey: Date] = [:]
        var trashedKeysCalls: [[NoteKey]] = []
        var trashedKeysBehavior: ScriptedNoteSource.Behavior = .answers
        var liveCountAnswer = 0
        var liveCountBehavior: ScriptedNoteSource.Behavior = .answers
    }

    let inner: ScriptedNoteSource
    private let state = Mutex(State())

    init(_ inner: ScriptedNoteSource) { self.inner = inner }

    var pluginID: PluginID { inner.pluginID }

    /// The owner's Recently deleted: key → its `deleted_at`.
    var trashed: [NoteKey: Date] {
        get { state.withLock { $0.trashed } }
        set { state.withLock { $0.trashed = newValue } }
    }
    var trashedKeysBehavior: ScriptedNoteSource.Behavior {
        get { state.withLock { $0.trashedKeysBehavior } }
        set { state.withLock { $0.trashedKeysBehavior = newValue } }
    }
    var trashedKeysCalls: [[NoteKey]] { state.withLock { $0.trashedKeysCalls } }
    /// What `liveCount()` answers (the owner's `COUNT … WHERE deleted_at IS NULL`), and how.
    var liveCountAnswer: Int {
        get { state.withLock { $0.liveCountAnswer } }
        set { state.withLock { $0.liveCountAnswer = newValue } }
    }
    var liveCountBehavior: ScriptedNoteSource.Behavior {
        get { state.withLock { $0.liveCountBehavior } }
        set { state.withLock { $0.liveCountBehavior = newValue } }
    }

    func list(matching: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage {
        try await inner.list(matching: matching, after: after, limit: limit)
    }
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { try await inner.exists(keys) }
    func content(for key: NoteKey) async throws -> NoteContent? { try await inner.content(for: key) }
    func delete(_ key: NoteKey) async throws { try await inner.delete(key) }
    func actions(for key: NoteKey) -> [NoteSourceAction] { inner.actions(for: key) }
    func makeChanges() -> AsyncStream<Void> { inner.makeChanges() }

    @discardableResult
    func trash(_ key: NoteKey) async throws -> Date {
        let now = Date()
        state.withLock { $0.trashed[key] = $0.trashed[key] ?? now }
        return state.withLock { $0.trashed[key] ?? now }
    }
    func trashAll(at deletedAt: Date) async throws -> TrashBatch {
        TrashBatch(deletedAt: deletedAt, moved: 0, stayed: 0)
    }
    @discardableResult
    func restore(_ keys: [NoteKey]) async throws -> Set<NoteKey> {
        state.withLock { state in for key in keys { state.trashed[key] = nil } }
        return []
    }
    func restoreBatch(deletedAt: Date) async throws -> Int { 0 }
    func liveCount() async throws -> Int {
        switch liveCountBehavior {
        case .answers: return liveCountAnswer
        case .throwsError: throw ScriptedError()
        case .hangs:
            try await Task.sleep(for: .seconds(3600))
            return liveCountAnswer
        }
    }
    func trashedCount() async throws -> Int { trashed.count }
    func trashed(after: NoteCursor?, limit: Int) async throws -> NotePage { NotePage() }

    func trashedKeys(_ keys: [NoteKey]) async throws -> [NoteKey: Date] {
        let (behavior, trashed) = state.withLock { state -> (ScriptedNoteSource.Behavior, [NoteKey: Date]) in
            state.trashedKeysCalls.append(keys)
            return (state.trashedKeysBehavior, state.trashed)
        }
        switch behavior {
        case .throwsError: throw ScriptedError()
        case .hangs:
            try await Task.sleep(for: .seconds(3600))
            throw ScriptedError()
        case .answers: return trashed.filter { keys.contains($0.key) }
        }
    }
}
