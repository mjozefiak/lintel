import Foundation
import LintelKit
import Synchronization
import Testing

@testable import NotesPlugin

/// The trash sweeps live as long as the plugin is active, not as long as the Notes section is on screen (notes
/// explorer spec, Deletion lifecycle: "Notes' trash sweep runs at activation"; PR #329 review, M1). None of these
/// tests builds the workspace. All data is synthetic.
@MainActor
@Suite(.timeLimit(.minutes(1))) struct TrashSweepLifetimeTests {
    private final class Flag: Sendable {
        private let state: Mutex<Bool>
        init(_ value: Bool) { state = Mutex(value) }
        var value: Bool {
            get { state.withLock { $0 } }
            set { state.withLock { $0 = newValue } }
        }
    }

    private let key = NoteKey(pluginID: "meetings", id: "m1")
    private let deletedAt = Date(timeIntervalSince1970: 1_800_000_500)

    private final class Rig {
        let harness: NotesHarness
        let clock = ManualClock()
        let passes = CountLatch()
        let owner = TrashingNoteSource(ScriptedNoteSource("meetings"))
        let plugin: NotesPlugin
        /// Whether the owner's plugin is active: what `PluginContext.noteSources` hands out, with no signal when it
        /// changes (the shell's signal can come before a subscriber exists).
        private let active: Flag

        /// A plugin over the harness's storage directory (an existing library when the test opened the store first).
        @MainActor
        init(sources: Bool = true) throws {
            harness = try NotesHarness()
            let owner = owner
            let active = Flag(sources)
            self.active = active
            plugin = NotesPlugin(
                context: makeContext(
                    storage: harness.directory, settings: harness.settingsStore, keychain: harness.keychain,
                    noteSources: { active.value ? [owner] : [] }, clock: clock))
        }

        func activateOwner() { active.value = true }
    }

    private func rig(sources: Bool = true) throws -> Rig { try Rig(sources: sources) }

    @Test func activationMarksTheOverlayOfANoteItsOwnerTrashedWithoutTheWorkspace() async throws {
        let r = try rig()
        let store = try r.harness.openStore()
        try store.insertDocument(.overlay("m1"))
        r.owner.trashed = [key: deletedAt]
        r.plugin.trashSweepPassFinished = { r.passes.increment() }

        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)

        #expect(try store.markedOverlayKeys() == [key])
        #expect(r.plugin.builtWorkspace == nil)  // the section was never built
        await r.plugin.deactivate()
    }

    @Test func aDetachedOrSwitchedOffSourceDecidesNothing() async throws {
        let r = try rig(sources: false)
        let store = try r.harness.openStore()
        try store.insertDocument(.overlay("m1"))
        r.owner.trashed = [key: deletedAt]
        r.plugin.trashSweepPassFinished = { r.passes.increment() }

        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)

        #expect(try store.markedOverlayKeys().isEmpty)
        #expect(r.owner.trashedKeysCalls.isEmpty)
        await r.plugin.deactivate()
    }

    @Test func aFreshProfileCreatesNoFileNoKeychainItemAndNoSetting() async throws {
        let harness = try NotesHarness()
        let keychain = CountingKeychain()
        let settings = MemorySettings()
        let clock = ManualClock()
        let storage = harness.directory  // never created
        let plugin = NotesPlugin(
            context: makeContext(storage: storage, settings: settings, keychain: keychain, clock: clock))
        let passes = CountLatch()
        plugin.trashSweepPassFinished = { passes.increment() }

        try await plugin.activate()
        await passes.wait(atLeast: 1)
        await clock.waitForSleeps(1)  // the loop is asleep: a pass ran and found no library
        clock.advance(by: SourceReconciler.sweepInterval)
        await passes.wait(atLeast: 2)

        #expect(keychain.calls == 0)
        #expect(!FileManager.default.fileExists(atPath: storage.path))
        #expect(plugin.library.store == nil)
        #expect(settings.isEmpty)
        await plugin.deactivate()
        #expect(keychain.calls == 0)
    }

    @Test func theFirstPassNeverPurgesAndThePurgeComesTenMinutesLater() async throws {
        let r = try rig(sources: false)
        let store = try r.harness.openStore()
        try store.insertDocument(.manual("a"))
        try store.trashManualNotes([NoteKey(pluginID: "notes", id: "a")], at: Date().addingTimeInterval(-40 * 86_400))
        let toldLatch = CountLatch()
        let broadcast = r.plugin.trashChanges.makeStream()
        let watcher = Task {
            for await _ in broadcast { toldLatch.increment() }
        }
        r.plugin.trashSweepPassFinished = { r.passes.increment() }

        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)
        #expect(try store.manualNoteCounts() == (live: 0, trashed: 1))  // marked by the first pass, not purged
        #expect(toldLatch.count == 0)

        r.clock.advance(by: .seconds(599))
        #expect(try store.manualNoteCounts() == (live: 0, trashed: 1))
        r.clock.advance(by: .seconds(1))
        await r.passes.wait(atLeast: 2)
        await toldLatch.wait(atLeast: 1)
        #expect(try store.manualNoteCounts() == (live: 0, trashed: 0))

        watcher.cancel()
        await r.plugin.deactivate()
    }

    @Test func aLibraryCreatedAfterActivationIsSweptFromTheNextPass() async throws {
        let r = try rig()
        r.owner.trashed = [key: deletedAt]
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)
        #expect(!FileManager.default.fileExists(atPath: r.harness.directory.path))

        // A first write (the user's first note) creates the library.
        let store = try r.harness.openStore()
        try store.insertDocument(.overlay("m1"))
        r.clock.advance(by: SourceReconciler.sweepInterval)
        await r.passes.wait(atLeast: 2)

        #expect(try store.markedOverlayKeys() == [key])
        await r.plugin.deactivate()
    }

    @Test func deactivationEndsTheTaskAndNoLaterTimeStartsAPass() async throws {
        let r = try rig(sources: false)
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)
        #expect(r.clock.sleeperCount == 1)

        await r.plugin.deactivate()
        #expect(r.clock.sleeperCount == 0)
        r.clock.advance(by: .seconds(3600))
        #expect(r.passes.count == 1)
    }

    @Test func activatingAgainReplacesTheTaskInsteadOfAddingOne() async throws {
        let r = try rig(sources: false)
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 2)
        await r.clock.waitForSleeps(2)
        await r.clock.waitForCancelledSleeps(1)
        #expect(r.clock.sleeperCount == 1)  // one loop, not two
        await r.plugin.deactivate()
    }

    @Test func theSectionAddsNoSecondLoop() async throws {
        let r = try rig(sources: false)
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)

        // The section's lifetime task only asks for one trash pass; it starts no sweep loop of its own.
        let view = Task { await r.plugin.workspace.run() }
        await waitUntil { r.plugin.workspace.screen != .loading }
        #expect(r.clock.sleeperCount == 1)
        view.cancel()
        await view.value
        await r.plugin.deactivate()
        #expect(r.clock.sleeperCount == 0)
    }

    @Test func aSourceThatBecameActiveAfterTheFirstPassIsSweptFromTheNextPassWithoutASignal() async throws {
        // Notes activates before Meetings and Dictation, so the set the library cached on the first pass is empty.
        let r = try rig(sources: false)
        let store = try r.harness.openStore()
        try store.insertDocument(.overlay("m1"))
        r.owner.trashed = [key: deletedAt]
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(1)
        #expect(try store.markedOverlayKeys().isEmpty)

        r.activateOwner()  // no `noteSourcesChanged` event
        r.clock.advance(by: SourceReconciler.sweepInterval)
        await r.passes.wait(atLeast: 2)

        #expect(try store.markedOverlayKeys() == [key])
        await r.plugin.deactivate()
    }

    @Test func deactivationWaitsForTheSourceChangeListenerEvenMidSweep() async throws {
        let r = try rig()
        let store = try r.harness.openStore()
        try store.insertDocument(.overlay("m1"))
        let order = Mutex<[String]>([])
        r.plugin.trashSweepPassFinished = { r.passes.increment() }
        r.plugin.trashSweepListenerEnded = { order.withLock { $0.append("listener ended") } }
        try await r.plugin.activate()
        await r.passes.wait(atLeast: 1)
        await r.clock.waitForSleeps(2)  // the first pass's source deadline, then the loop's own sleep
        await r.owner.inner.waitForChangeStream(1)

        // A change event puts the listener in the middle of a trash sweep that never answers.
        r.owner.trashedKeysBehavior = .hangs
        r.owner.inner.signalChange()
        await r.clock.waitForSleeps(3)  // the hanging call's deadline

        await r.plugin.deactivate()
        order.withLock { $0.append("deactivate returned") }

        #expect(order.withLock { $0 } == ["listener ended", "deactivate returned"])
        #expect(r.plugin.library.store == nil)  // closed after the task, not under it
    }
}
