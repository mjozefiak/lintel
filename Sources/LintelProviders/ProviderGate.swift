import Foundation

/// Which queue a request waits in. The slot of the gate is one per provider AND lane, so work of one lane never waits
/// for the other (spec `2026-11-25-dictation-cleanup-levels`, A15): a whole-transcript meeting-notes run can hold the
/// `background` slot for minutes, and a dictation chunk must not wait behind it. Neither lane cancels the other.
public enum ProviderLane: String, Sendable, Hashable, CaseIterable {
    /// Work nobody waits for with a key held down: meeting notes, status probes of a background consumer. The default,
    /// so a consumer written before lanes keeps its behaviour.
    case background
    /// Work the user waits for right after releasing a key: dictation.
    case interactive
}

/// One request at a time per provider and lane, first in, first out (spec: `ProviderGate`). Two lanes, so at most one
/// process of each runs at the same time.
public actor ProviderGate {
    public static let shared = ProviderGate()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }

    private struct Key: Hashable {
        let provider: ProviderID
        let lane: ProviderLane
    }

    private var busy: Set<Key> = []
    private var waiters: [Key: [Waiter]] = [:]

    public init() {}

    /// Runs `body` when the provider is free in this lane. A cancelled task leaves the queue without running `body`.
    func withSlot<T: Sendable>(
        _ provider: ProviderID, lane: ProviderLane = .background, _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let key = Key(provider: provider, lane: lane)
        try await acquire(key)
        defer { release(key) }
        try Task.checkCancellation()
        return try await body()
    }

    var queuedCount: Int { waiters.values.reduce(0) { $0 + $1.count } }

    private func acquire(_ key: Key) async throws {
        try Task.checkCancellation()
        if !busy.contains(key) {
            busy.insert(key)
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters[key, default: []].append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(key, id) }
        }
    }

    private func cancelWaiter(_ key: Key, _ id: UUID) {
        guard let index = waiters[key]?.firstIndex(where: { $0.id == id }) else { return }
        let waiter = waiters[key]?.remove(at: index)
        waiter?.continuation.resume(throwing: CancellationError())
    }

    private func release(_ key: Key) {
        if var queue = waiters[key], !queue.isEmpty {
            let next = queue.removeFirst()
            waiters[key] = queue
            next.continuation.resume()  // the slot passes on; `busy` stays set
        } else {
            busy.remove(key)
        }
    }
}
