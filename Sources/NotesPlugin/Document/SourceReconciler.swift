import Foundation
import LintelKit

/// Keeps overlays honest about their source (spec "Source reconciliation", "Detaching"): per-layer `version`
/// compare for the documents that are open, and the detach sweep. Any throw from a source means "unknown":
/// nothing is reconciled, nothing is detached.
final class SourceReconciler: Sendable {
    enum OpenResult: Sendable, Equatable {
        /// The source did not answer (off, locked, slow, no source): nothing changed.
        case unavailable
        /// The recording is gone or was recreated: its overlays were detached.
        case detached
        case reconciled([String: RevisionWriter.Reconciliation])
    }

    /// How often the sweep runs after the one on source activation.
    static let sweepInterval: Duration = .seconds(600)

    private let store: NotesStore
    private let library: NoteLibrary
    private let detacher: any OverlayDetacher
    private let registry: NoteDocumentRegistry
    private let clock: any Clock<Duration>
    private let budget: Duration
    private let now: @Sendable () -> Date
    private let log: any NotesLogging
    private let trash: NoteTrashSweep
    /// Told when the purge removed manual notes from Recently deleted (Notes' own `TrashSource` change stream).
    private let trashChanged: @Sendable () -> Void

    init(
        store: NotesStore, library: NoteLibrary, detacher: any OverlayDetacher, registry: NoteDocumentRegistry,
        clock: any Clock<Duration> = ContinuousClock(), budget: Duration = SourceFanOut.defaultBudget,
        now: @escaping @Sendable () -> Date = { Date() }, log: any NotesLogging = OSNotesLog(),
        trashChanged: @escaping @Sendable () -> Void = {}
    ) {
        self.store = store
        self.library = library
        self.detacher = detacher
        self.registry = registry
        self.clock = clock
        self.budget = budget
        self.now = now
        self.log = log
        self.trashChanged = trashChanged
        trash = NoteTrashSweep(store: store, library: library, clock: clock, budget: budget, log: log)
    }

    /// A note was opened (or its source said it changed): reads its content once, detaches overlays written
    /// against another recording BEFORE any seed or write, then reconciles each overlaid layer by its own version.
    @discardableResult
    func reconcile(_ key: NoteKey) async -> OpenResult {
        // Only a note with an overlay needs its content read here.
        let documents: [DocumentRecord]
        do {
            documents = try store.liveDocuments(key: key)
        } catch {
            return .unavailable
        }
        guard !documents.isEmpty else { return .reconciled([:]) }
        guard let source = await library.source(for: key) else { return .unavailable }
        let outcome = await SourceFanOut.call(budget: budget, clock: clock) { try await source.content(for: key) }
        let content: NoteContent
        switch outcome {
        case .value(let value):
            guard let value else { return await detach(key, reason: .sourceGone) }
            content = value
        case .failed, .timedOut, .cancelled:
            return .unavailable
        }
        let started = NoteTime.milliseconds(content.summary.startedAt)
        if documents.contains(where: { $0.sourceStartedAtMs.map { $0 != started } ?? false }) {
            return await detach(key, reason: .startedAtChanged(sourceStartedAtMs: started))
        }
        var results: [String: RevisionWriter.Reconciliation] = [:]
        for document in documents {
            guard let layer = content.layers.first(where: { $0.id == document.layer }) else { continue }
            let writer =
                await registry.writer(for: .live(key, layer: document.layer))
                ?? RevisionWriter(store: store, target: .existing(docID: document.id), clock: clock, now: now, log: log)
            do {
                results[document.layer] = try await writer.reconcile(layer: layer)
            } catch {
                log.error(
                    NotesLogEvent(
                        "reconcile", code: (error as? NotesError)?.code ?? "reconcileFailed", key: key.rawValue))
            }
        }
        return .reconciled(results)
    }

    private func detach(_ key: NoteKey, reason: OverlayDetachReason) async -> OpenResult {
        do {
            try await detacher.detach(key, reason: reason)
            return .detached
        } catch {
            log.error(NotesLogEvent("detach", code: (error as? NotesError)?.code ?? "detachFailed", key: key.rawValue))
            return .unavailable
        }
    }

    /// A `makeChanges()` event: only the notes with an open document are read, so 1000 overlays and 50 events cost
    /// at most one `content(for:)` per open note and event. Every other overlay is reconciled when opened
    /// (`source_version_seen` is persisted, so nothing is missed).
    func reconcileOpenDocuments() async {
        for key in await registry.openLiveKeys { await reconcile(key) }
    }

    /// The trash sweep alone (`NoteTrashSweep.run`): what a source's `makeChanges()` event triggers, so a note
    /// deleted in the launcher's panel leaves Notes' search without waiting for the next full sweep.
    @discardableResult
    func trashSweep() async -> NoteTrashSweep.Result {
        await trash.run()
    }

    /// The trash sweep (marks and clears the overlays of notes their owner trashed or restored), then the detach
    /// sweep (`exists` in batches of 500, only through an open source; a gone key whose overlays carry a mark is
    /// deleted, never kept as a copy), the removal of folder entries whose key is gone, and the persistent delete
    /// of detached rows that are neither kept nor open. With `purgesTrash` the manual notes trashed 30 days ago or
    /// more are purged too. Returns the keys it detached or deleted.
    @discardableResult
    func sweep(purgesTrash: Bool = false) async -> [NoteKey] {
        await trash.run()
        let detached = await library.sweep()
        await trash.removeGoneFolderEntries()
        do {
            let retention = try store.applyRetentionReporting(
                excluding: await registry.openDocIDs(), now: now(), purgesTrash: purgesTrash)
            if !retention.purged.isEmpty {
                log.notice(NotesLogEvent("trashPurge", count: retention.purged.count))
                trashChanged()
            }
        } catch {
            log.error(NotesLogEvent("sweep", code: (error as? NotesError)?.code ?? "sweepFailed"))
        }
        return detached
    }

    /// Runs on source activation, then every 10 minutes on the injected clock, until cancelled. The first sweep
    /// never purges Recently deleted: the purge runs from the second one on (10 minutes after activation), so the
    /// trash sweep has marked the overlays first (notes explorer spec, Deletion lifecycle).
    func runSweeps(every interval: Duration = SourceReconciler.sweepInterval) async {
        var first = true
        while !Task.isCancelled {
            await sweep(purgesTrash: !first)
            first = false
            do { try await clock.sleep(for: interval) } catch { return }
        }
    }
}
