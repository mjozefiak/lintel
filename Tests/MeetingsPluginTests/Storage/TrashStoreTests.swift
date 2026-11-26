import Foundation
import GRDB
import LintelCore
import LintelPersistence
import LintelTestSupport
import Testing

@testable import MeetingsPlugin

private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func openStore(directory: TemporaryDirectory? = nil) throws -> (MeetingsStore, TemporaryDirectory) {
    let directory = try directory ?? TemporaryDirectory()
    return (try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: testKeys()), directory)
}

/// One synthetic meeting: a segment and (optionally) notes, both holding "roadmap" so a search finds it.
@discardableResult
private func add(
    _ store: MeetingsStore, _ uuid: String, status: MeetingStatus = .ready, startedAt: Date = base,
    notes: String? = "Roadmap notes", audio: AudioState = .deleted
) throws -> Int64 {
    let id = try store.insertMeeting(uuid: uuid, startedAt: startedAt, speechModelID: "m", status: status)
    try store.insertSegment(meetingID: id, channel: .mic, startMs: 0, endMs: 1000, text: "Roadmap talk \(uuid)")
    if let notes { try store.setNotes(id, markdown: notes, status: .ok) }
    try store.setAudioState(id, state: audio)
    return id
}

@discardableResult
private func trash(_ store: MeetingsStore, _ uuid: String, at date: Date = base) throws -> Date {
    guard case .trashed(let stamp) = try store.trash(uuid: uuid, at: date) else {
        Issue.record("the meeting was not trashed")
        return date
    }
    return stamp
}

/// Every read the user sees leaves a meeting in Recently deleted out, and the reads that must keep seeing it do
/// (notes explorer spec, Data Model: "a trashed meeting is never listed, searched, counted, resumed, retried or sent
/// to a provider"; its spool and FTS rows stay until the purge).
@Suite struct TrashedMeetingVisibilityTests {
    @Test func aTrashedMeetingIsInEveryListCountAndSearchOnlyUntilItIsTrashed() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let live = try add(store, "live")
        try add(store, "gone")
        #expect(try store.libraryEntries(matching: "roadmap", filter: .all, limit: 10).count == 2)
        try trash(store, "gone")

        #expect(try store.libraryEntries(matching: nil, filter: .all, limit: 10).map(\.uuid) == ["live"])
        #expect(try store.libraryEntries(matching: "roadmap", filter: .all, limit: 10).map(\.uuid) == ["live"])
        #expect(try store.libraryEntries(matching: nil, filter: .withNotes, limit: 10).map(\.uuid) == ["live"])
        #expect(try store.libraryCount(matching: nil, filter: .all) == 1)
        #expect(try store.libraryCount(matching: "roadmap", filter: .all) == 1)
        #expect(try store.searchSegments("roadmap", limit: 10) == [live])
        #expect(try store.searchNotes("roadmap", limit: 10) == [live])
        #expect(try store.meetingCount() == 1)
        #expect(try store.meetingIDs() == [live])
        #expect(try store.loadDocument(uuid: "gone") == nil)
        #expect(try store.loadDocument(uuid: "live") != nil)
    }

    @Test func aTrashedMeetingNeedingAttentionIsNotInThatFilter() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "broken", status: .incomplete)
        try add(store, "also-broken", status: .failed)
        try trash(store, "also-broken")
        #expect(try store.libraryEntries(matching: nil, filter: .needsAttention, limit: 10).map(\.uuid) == ["broken"])
    }

    @Test func aTrashedMeetingIsNeverResumedRecoveredRetriedOrSentToANotesProvider() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let incomplete = try add(store, "incomplete", status: .incomplete, audio: .spool)
        // `readyMeetingsWithSpool` reads only meetings whose uuid is a UUID (they own a spool folder).
        let readyUUID = UUID().uuidString.lowercased()
        let ready = try add(store, readyUUID, audio: .spool)
        try store.markNotesAwaitingModel(ready)
        let liveOne = try add(store, "other", audio: .spool)
        try store.markNotesAwaitingModel(liveOne)
        #expect(try store.readyMeetingsWithSpool().count == 1)
        #expect(try store.meetingsAwaitingNotesModel() == [ready, liveOne])
        try trash(store, "incomplete")
        try trash(store, readyUUID)

        #expect(try store.recoverableMeetings(statuses: [.incomplete]).isEmpty)
        #expect(try store.recoverableMeeting(id: incomplete) == nil)
        #expect(try store.claimForFinishing(incomplete) == false)
        #expect(try store.status(of: incomplete) == .incomplete)
        #expect(try store.readyMeetingsWithSpool().isEmpty)
        #expect(try store.beginNotes(ready) == nil)
        #expect(try store.notesStatus(of: ready) == .ok)
        #expect(try store.meetingsAwaitingNotesModel() == [liveOne])
        // Restored, the same meeting is a candidate again.
        try store.restore(uuids: [readyUUID])
        #expect(try store.readyMeetingsWithSpool().count == 1)
        #expect(try store.beginNotes(ready) == .ok)
    }

    @Test func theReadsThatMustSeeATrashedMeetingStillDo() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let id = try add(store, "gone", status: .incomplete, notes: nil, audio: .spool)
        let kept = try add(store, "kept", startedAt: base.addingTimeInterval(-60 * day), audio: .kept)
        let stamp = try trash(store, "gone")
        try trash(store, "kept")

        // `exists` and `content` read through these: a note in Recently deleted still exists and has its content.
        let entry = try #require(try store.libraryEntry(uuid: "gone"))
        #expect(entry.deletedAt == stamp)
        #expect(try store.libraryEntries(uuids: ["gone", "kept"]).count == 2)
        let document = try #require(try store.loadDocument(uuid: "gone", includingTrashed: true))
        #expect(document.deletedAt == stamp)
        #expect(document.segments.count == 1)
        #expect(try store.loadDocument(id: id, includingTrashed: true) != nil)
        // The spool bookkeeping sees it, so a trashed meeting's audio is neither an orphan nor immortal.
        #expect(try store.allMeetingUUIDs() == ["gone", "kept"])
        #expect(try store.incompleteSpoolUUIDs() == ["gone"])
        #expect(try store.keptSpoolUUIDs() == ["kept"])
        #expect(try store.expiredKeptSpoolUUIDs(cutoff: base.addingTimeInterval(-30 * day)) == ["kept"])
        #expect(try store.audioState(of: kept) == .kept)
    }

    @Test func theOrphanSweepNeverTreatsATrashedMeetingsSpoolAsAnOrphan() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "gone", status: .incomplete, audio: .spool)
        try trash(store, "gone")
        let spool = RecordingSpool(existing: ["gone", "stray"])
        let report = try OrphanSpoolSweep.run(
            store: store, spool: spool, now: base.addingTimeInterval(10 * day), grace: 3_600)
        #expect(report.removed == ["stray"])
        #expect(spool.state.withLock { $0.existing } == ["gone"])
    }
}

/// The stamp rules every store of Recently deleted follows (copy the names into the Dictation and Notes suites).
@Suite struct TrashStampTests {
    @Test func aSingleTrashReturnsItsStampAndTrashingAgainIsANoOpWithTheSameStamp() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "a")
        let first = try trash(store, "a", at: base)
        #expect(first == TrashStamp.date(micros: TrashStamp.micros(base)))
        #expect(try store.trash(uuid: "a", at: base.addingTimeInterval(day)) == .alreadyTrashed(first))
        #expect(try store.trashedStamps(uuids: ["a"]) == ["a": first])
        #expect(try store.trash(uuid: "missing", at: base) == .missing)
    }

    @Test func aStampReadBackAfterReopeningTheDatabaseEqualsTheOneWritten() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "single")
        try add(store, "batch-a")
        try add(store, "batch-b")
        // Sub-microsecond noise on purpose: the stamp is rounded to a whole microsecond on write and on compare.
        let single = try trash(store, "single", at: Date(timeIntervalSince1970: 1_800_000_000.123_456_789))
        let at = Date(timeIntervalSince1970: 1_800_000_100.987_654_321)
        #expect(try store.trashAll(at: at) == .init(moved: 2, stayed: 0))
        try store.close()

        let (reopened, _) = try openStore(directory: directory)
        let stamps = try reopened.trashedStamps(uuids: ["single", "batch-a", "batch-b"])
        #expect(stamps["single"] == single)
        #expect(stamps["batch-a"] == stamps["batch-b"])
        // The caller passes back the date it gave (or the one read back): both find the batch.
        let readBack = try #require(stamps["batch-a"])
        #expect(try reopened.restoreBatch(deletedAt: readBack) == 2)
        #expect(try reopened.trashedCount() == 1)
        #expect(try reopened.trashAll(at: at).moved == 2)
        #expect(try reopened.restoreBatch(deletedAt: at) == 2)
        #expect(try reopened.trashedStamps(uuids: ["single"]) == ["single": single])
    }

    @Test func aSingleTrashNeverReusesABatchStamp() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "batch")
        try add(store, "later")
        #expect(try store.trashAll(at: base).moved == 2)
        try add(store, "newcomer")
        // The same instant as the batch: the store moves the stamp on by 1 µs.
        let stamp = try trash(store, "newcomer", at: base)
        #expect(TrashStamp.micros(stamp) == TrashStamp.micros(base) + 1)
        #expect(try store.restoreBatch(deletedAt: base) == 2)
        #expect(try store.trashedStamps(uuids: ["newcomer"]) == ["newcomer": stamp])
    }

    @Test func restoreBatchPutsBackExactlyThatBatchNeverARowDeletedEarlierOrLater() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        for name in ["earlier", "b1", "b2", "later"] { try add(store, name) }
        try trash(store, "earlier", at: base.addingTimeInterval(-day))
        // The batch moves every live row at that moment: put the other two back first, as a real second batch would.
        #expect(try store.trashAll(at: base).moved == 3)
        try store.restore(uuids: ["later"])
        try trash(store, "later", at: base.addingTimeInterval(day))
        #expect(try store.restoreBatch(deletedAt: base) == 2)
        #expect(
            try store.trashedStamps(uuids: ["earlier", "b1", "b2", "later"]).keys.sorted() == ["earlier", "later"])
        // Nothing left of that batch: a second call restores nothing.
        #expect(try store.restoreBatch(deletedAt: base) == 0)
    }
}

/// `trash`, `trashAll`, `restore`, paging and the purge (the store's half of the contract rules).
@Suite struct TrashStoreOperationTests {
    @Test func aMeetingBeingRecordedOrProcessedOrHeldIsBusyAndChangesNothing() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "recording", status: .recording)
        try add(store, "processing", status: .processing)
        let held = try add(store, "held")
        #expect(try store.trash(uuid: "recording", at: base) == .busy)
        #expect(try store.trash(uuid: "processing", at: base) == .busy)
        #expect(try store.trash(uuid: "held", at: base, protected: [held]) == .busy)
        #expect(try store.trashedCount() == 0)
        #expect(try store.meetingCount() == 3)
    }

    @Test func trashAllMovesEveryLiveMeetingExceptTheBusyOnesAndCountsWhatStayed() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "a")
        try add(store, "b", status: .incomplete)
        try add(store, "recording", status: .recording)
        try add(store, "processing", status: .processing)
        let held = try add(store, "held")
        #expect(try store.trashAll(at: base, protected: [held]) == .init(moved: 2, stayed: 3))
        #expect(
            try store.libraryEntries(matching: nil, filter: .all, limit: 10).map(\.uuid).sorted()
                == ["held", "processing", "recording"])
        // A row that is trashed already is not moved again (its stamp stays).
        #expect(try store.trashAll(at: base.addingTimeInterval(day), protected: [held]).moved == 0)
        #expect(try store.restoreBatch(deletedAt: base) == 2)
    }

    @Test func restoreBringsTheMeetingBackWithItsAudioAndReportsWhatIsGone() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let id = try add(store, "incomplete", status: .incomplete, audio: .spool)
        try add(store, "live")
        try trash(store, "incomplete")
        #expect(try store.recoverableMeeting(id: id) == nil)

        let missing = try store.restore(uuids: ["incomplete", "live", "purged", "never-existed"])
        #expect(missing == ["purged", "never-existed"])
        #expect(try store.audioState(of: id) == .spool)
        #expect(try store.recoverableMeeting(id: id)?.audioState == .spool)
        #expect(try store.trashedCount() == 0)
        // Restoring a live meeting again is a no-op.
        #expect(try store.restore(uuids: ["incomplete"]).isEmpty)
    }

    @Test func trashedEntriesPageNewestDeletedFirstWithTiesBrokenByIdAndNeverIncludeALiveRow() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        for name in ["a", "b", "c", "d"] { try add(store, name) }
        try add(store, "live")
        try trash(store, "a", at: base)
        try trash(store, "b", at: base.addingTimeInterval(10))
        // c, d and live share a batch stamp; then live comes back.
        #expect(try store.trashAll(at: base.addingTimeInterval(20)).moved == 3)
        try store.restore(uuids: ["live"])

        var seen: [String] = []
        var position: MeetingsStore.TrashPosition?
        while true {
            let page = try store.trashedEntries(after: position, limit: 2)
            seen += page.map(\.uuid)
            guard page.count == 2, let last = page.last, let stamp = last.deletedAt else { break }
            position = .init(micros: TrashStamp.micros(stamp), id: last.id)
        }
        #expect(seen == ["d", "c", "b", "a"])
        #expect(try store.trashedCount() == 4)
        #expect(try store.trashedEntries(limit: 10).allSatisfy { $0.deletedAt != nil })
    }

    @Test func trashedStampsAnswerForAnyNumberOfKeysWithoutLoadingRows() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try store.write { db in
            for index in 0..<1_200 {
                try db.execute(
                    sql: "INSERT INTO meeting (uuid, started_at, status) VALUES (?, ?, 'ready')",
                    arguments: ["m\(index)", 1_000 + index])
            }
        }
        for name in ["m3", "m600", "m1199"] { try trash(store, name) }
        let asked = (0..<1_200).map { "m\($0)" } + ["unknown"]
        #expect(try store.trashedStamps(uuids: asked).keys.sorted() == ["m1199", "m3", "m600"])
        #expect(try store.trashedStamps(uuids: []).isEmpty)
    }

    @Test func purgeTrashedDeletesOnlyThoseDeletedBeforeTheCutoffAndTheirTextGoesWithThem() throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "old")
        try add(store, "new")
        try add(store, "live")
        try trash(store, "old", at: base)
        try trash(store, "new", at: base.addingTimeInterval(5 * day))
        let purged = try store.purgeTrashed(olderThan: base.addingTimeInterval(day))
        #expect(purged == ["old"])
        #expect(try store.trashedCount() == 1)
        #expect(try store.segmentCount() == 2)
        #expect(try store.allMeetingUUIDs() == ["new", "live"])
        // The full-text rows of the purged meeting are gone with it.
        #expect(
            try store.read {
                try Int.fetchOne($0, sql: "SELECT count(*) FROM meeting_fts WHERE meeting_fts MATCH 'old'")
            } == 0)
    }
}

/// The retention job and Recently deleted: the 30-day purge, the audio that stays until then, deleting by age.
@Suite @MainActor struct TrashRetentionTests {
    private func job(
        now: @escaping @Sendable () -> Date, spool: RecordingSpool, clock: any Clock<Duration> = ContinuousClock()
    )
        -> RetentionJob
    {
        RetentionJob(clock: clock, now: now, spool: spool, logger: .init(subsystem: "t", category: "t"))
    }

    private let policy = RetentionJob.Policy(retentionDays: 0, orphanAudioDays: 7)

    @Test func aMeetingIsPurgedThirtyDaysAfterItWasDeletedWithItsAudioAndNotBefore() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "gone", status: .incomplete, audio: .kept)
        try add(store, "live")
        try trash(store, "gone", at: base)
        let spool = RecordingSpool(existing: ["gone"])
        let clock = Shared(base)
        let job = job(now: { clock.get() }, spool: spool)

        clock.update { $0 = base.addingTimeInterval(30 * day - 1) }
        #expect(
            await job.run(store: store, policy: .init(retentionDays: 0, orphanAudioDays: 365, keptAudioDays: 365)) == 0)
        #expect(try store.trashedCount() == 1)
        #expect(spool.state.withLock { $0.existing } == ["gone"])

        clock.update { $0 = base.addingTimeInterval(30 * day + 1) }
        #expect(
            await job.run(store: store, policy: .init(retentionDays: 0, orphanAudioDays: 365, keptAudioDays: 365)) == 1)
        #expect(try store.trashedCount() == 0)
        #expect(try store.allMeetingUUIDs() == ["live"])
        #expect(spool.state.withLock { $0.removedForMeetings } == ["gone"])
        #expect(spool.state.withLock { $0.existing }.isEmpty)
    }

    @Test func aRestoreBeforeThePurgeBringsTheAudioBackBecauseNothingRemovedItWhileTheMeetingWasTrashed() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let id = try add(store, "gone", audio: .kept)
        try trash(store, "gone", at: base)
        let spool = RecordingSpool(existing: ["gone"])
        // Ten days later, with the audio limit at 30 days: the retention passes leave the trashed meeting alone.
        let job = job(now: { base.addingTimeInterval(10 * day) }, spool: spool)
        _ = await job.run(store: store, policy: .init(retentionDays: 0, orphanAudioDays: 30, keptAudioDays: 30))
        #expect(spool.state.withLock { $0.existing } == ["gone"])
        #expect(try store.audioState(of: id) == .kept)

        try store.restore(uuids: ["gone"])
        #expect(try store.audioState(of: id) == .kept)
        #expect(try store.libraryEntry(uuid: "gone")?.deletedAt == nil)
        #expect(spool.state.withLock { $0.existing } == ["gone"])
    }

    @Test func theMeetingAudioLimitStillRemovesAudioByAgeWhileTheMeetingIsTrashed() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        let id = try add(store, "gone", status: .incomplete, audio: .spool)
        try trash(store, "gone", at: base)
        let spool = RecordingSpool(existing: ["gone"])
        let job = job(now: { base.addingTimeInterval(8 * day) }, spool: spool)
        _ = await job.run(store: store, policy: .init(retentionDays: 0, orphanAudioDays: 7))
        #expect(try store.audioState(of: id) == .deleted)
        try store.restore(uuids: ["gone"])
        // It returns without audio, as any meeting past that limit.
        #expect(try store.libraryEntry(uuid: "gone")?.audioSpooled == false)
    }

    @Test func retentionByAgeRemovesATrashedMeetingBeforeItsThirtyDays() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "old", startedAt: base.addingTimeInterval(-100 * day), audio: .kept)
        try add(store, "recent", startedAt: base.addingTimeInterval(-5 * day))
        try trash(store, "old", at: base.addingTimeInterval(-day))
        try trash(store, "recent", at: base.addingTimeInterval(-day))
        let spool = RecordingSpool(existing: ["old", "recent"])
        let job = job(now: { base }, spool: spool)
        #expect(
            await job.run(store: store, policy: .init(retentionDays: 30, orphanAudioDays: 365, keptAudioDays: 365)) == 1
        )
        #expect(try store.allMeetingUUIDs() == ["recent"])
        #expect(spool.state.withLock { $0.removedForMeetings } == ["old"])
    }

    @Test func aPurgeCountsAsDeletedSoTheChangeIsAnnouncedAndTheVacuumRuns() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "gone")
        try trash(store, "gone", at: base)
        let job = job(now: { base.addingTimeInterval(31 * day) }, spool: RecordingSpool())
        #expect(await job.run(store: store, policy: policy) == 1)
        #expect(job.lastVacuum == base.addingTimeInterval(31 * day))
    }

    @Test func theFirstPurgeRunsTenMinutesAfterTheStartAndNotOnTheImmediatePass() async throws {
        let (store, directory) = try openStore()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "gone")
        try add(store, "live")
        try trash(store, "gone", at: base)
        let clock = LintelTestSupport.TestClock()
        let job = job(now: { base.addingTimeInterval(31 * day) }, spool: RecordingSpool(), clock: clock)
        let changes = CountLatch()
        job.start(store: { store }, policy: { self.policy }, changed: { changes.increment() })
        defer { job.stop() }

        // The immediate pass ran and went to sleep: the 31-day-old trash is still there.
        #expect(await clock.waitForSleepers(1))
        #expect(try store.trashedCount() == 1)
        #expect(changes.count == 0)

        clock.advance(by: RetentionJob.firstTrashPurgeDelay)
        #expect(await changes.wait(atLeast: 1))
        #expect(try store.trashedCount() == 0)
        #expect(try store.allMeetingUUIDs() == ["live"])
        // From then on the job runs hourly.
        #expect(await clock.waitForSleepers(1))
        #expect(clock.wokenDeadlines.last == TestInstant(offset: RetentionJob.firstTrashPurgeDelay))
    }
}

/// Erase Data removes the whole library, the trash included.
@Suite @MainActor struct TrashEraseTests {
    @Test func eraseDataRemovesTrashedMeetingsWithTheRestOfTheFolder() async throws {
        let harness = try MeetingsHarness()
        let plugin = MeetingsPlugin(context: harness.context)
        try await plugin.activate()
        let store = try #require(plugin.library.store)
        try add(store, "gone", audio: .spool)
        try trash(store, "gone")
        let spool = harness.pluginDirectory.appending(path: "Spool/gone", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: spool, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: spool.appending(path: "mic.spool"))

        await plugin.deactivate()
        try await plugin.eraseData()

        #expect(!FileManager.default.fileExists(atPath: harness.pluginDirectory.path))
        #expect(harness.keychain.itemNames.isEmpty)
        // A fresh library has no Recently deleted.
        try await plugin.activate()
        #expect(try plugin.library.store?.trashedCount() == 0)
        #expect(try plugin.library.store?.meetingCount() == 0)
        await plugin.deactivate()
    }
}
