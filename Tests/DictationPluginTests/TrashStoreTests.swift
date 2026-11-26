import Foundation
import GRDB
import LintelCore
import LintelKit
import LintelPersistence
import LintelTestSupport
import Synchronization
import Testing
import os

@testable import DictationPlugin

private let day: TimeInterval = 86_400
private let base = Date(timeIntervalSince1970: 1_800_000_000)

private func keys() throws -> MasterKeys {
    try #require(MasterKeys(master: Data(repeating: 9, count: 32)))
}

private func entry(_ raw: String, formatted: String? = nil, at date: Date = base) -> DictationEntry {
    DictationEntry(
        createdAt: date, durationMs: 4_000, rawText: raw, formattedText: formatted,
        formatMode: formatted == nil ? .raw : .clean, formatStatus: formatted == nil ? .none : .ok,
        detectedLanguages: "pl", speechModelID: "parakeet-ultra", formatterModel: nil, targetBundleID: nil,
        pasteResult: .pasted)
}

/// Migration `v2-trash` (notes explorer spec, Data Model): `dictation_entry.deleted_at` and a partial index. All
/// data is synthetic. A previous-schema database with a row in every table is migrated and read back.
@Suite struct DictationTrashMigrationTests {
    @Test func aFreshDatabaseHasTheNullableDeletedAtColumnAndThePartialIndex() throws {
        let queue = try DatabaseQueue()
        try DictationStore.migrator.migrate(queue)
        let columns = try queue.read { try Row.fetchAll($0, sql: "PRAGMA table_info(dictation_entry)") }
        let column = try #require(columns.first { ($0["name"] as String) == "deleted_at" })
        #expect((column["type"] as String) == "REAL")
        #expect((column["notnull"] as Int) == 0)
        #expect((column["dflt_value"] as String?) == nil)
        let index = try #require(
            try queue.read {
                try Row.fetchOne(
                    $0, sql: "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = 'dictation_entry_deleted'")
            })
        let definition = (index["sql"] as String).lowercased()
        #expect(definition.contains("on dictation_entry(deleted_at)"))
        #expect(definition.contains("where deleted_at is not null"))
        try queue.write {
            try $0.execute(sql: "INSERT INTO dictation_entry (created_at, raw_text) VALUES (1, 'n')")
        }
        #expect(
            try queue.read { try Double?.fetchOne($0, sql: "SELECT deleted_at FROM dictation_entry") } == .some(nil))
    }

    @Test func aDatabaseFromBeforeTheMigrationKeepsEveryTableAndReadsEveryEntryAsLive() throws {
        let queue = try DatabaseQueue()
        let migrator = DictationStore.migrator
        try migrator.migrate(queue, upTo: "v1-history")
        try queue.write { db in
            try db.execute(
                sql: """
                    INSERT INTO dictation_entry (id, created_at, duration_ms, raw_text, formatted_text, format_mode,
                        format_status, detected_languages, speech_model_id, formatter_model, target_bundle_id,
                        paste_result)
                    VALUES (1, 1000, 3000, 'syntetyczny zażółć tekst', 'Syntetyczny zażółć tekst.', 'clean', 'ok',
                        'pl', 'parakeet-ultra', 'model-x', 'com.example.app', 'pasted'),
                        (2, 2000, 1500, 'drugi wpis', NULL, 'raw', 'none', 'pl,en', 'parakeet-ultra', NULL, NULL,
                        'copied')
                    """)
        }
        try migrator.migrate(queue)
        #expect(try queue.read { try migrator.appliedIdentifiers($0) } == ["v1-history", "v2-trash"])

        let store = DictationStore(database: queue)
        let rows = try queue.read {
            try Row.fetchAll(
                $0, sql: "SELECT id, raw_text, formatter_model, deleted_at FROM dictation_entry ORDER BY id")
        }
        #expect(rows.map { $0["id"] as Int64 } == [1, 2])
        #expect((rows[0]["raw_text"] as String) == "syntetyczny zażółć tekst")
        #expect((rows[0]["formatter_model"] as String) == "model-x")
        #expect(rows.allSatisfy { ($0["deleted_at"] as Double?) == nil })
        #expect(try store.count() == 2)
        #expect(try store.liveCount() == 2)
        #expect(try store.trashedCount() == 0)
        // The full-text index built before the migration still finds the rows, through the filtered reads.
        #expect(try store.search("syntetyczny", limit: 5).map(\.id) == [1])
        #expect(try store.recent(limit: 10).map(\.id) == [2, 1])
        #expect(try store.noteEntries(matching: "drugi", after: nil, limit: 5).map(\.id) == [2])
        #expect(try store.entry(1)?.deletedAt == nil)
    }

    @Test func theMigrationIsRegisteredAfterEveryEarlierOne() {
        let names = DictationStore.migrator.migrations
        #expect(names == ["v1-history", "v2-trash"])
    }

    /// The rollback note: an older build, whose migrator has never heard of `v2-trash`, opens the migrated database
    /// without an error and without touching it (GRDB ignores an applied migration it does not know).
    @Test func anOlderBuildThatDoesNotKnowTheMigrationStillOpensTheDatabase() throws {
        let queue = try DatabaseQueue()
        try DictationStore.migrator.migrate(queue)
        try queue.write {
            try $0.execute(
                sql: "INSERT INTO dictation_entry (created_at, raw_text, deleted_at) VALUES (1, 'trashed', 5.5)")
        }
        var older = DatabaseMigrator()
        older.registerMigration("v1-history") { _ in Issue.record("an applied migration ran again") }
        try older.migrate(queue)
        #expect(try queue.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM dictation_entry") } == 1)
        // The column is untouched: the older build never names it, so it reads the row as a live one.
        #expect(try queue.read { try Double.fetchOne($0, sql: "SELECT deleted_at FROM dictation_entry") } == 5.5)
    }
}

/// The reads the user sees leave a trashed entry out; `exists` and `content` still see it.
@Suite struct DictationTrashStoreTests {
    private func open(directory: TemporaryDirectory? = nil) throws -> (DictationStore, TemporaryDirectory) {
        let directory = try directory ?? TemporaryDirectory()
        return (try DictationStore.open(in: directory.url, keys: keys()), directory)
    }

    @discardableResult
    private func add(_ store: DictationStore, _ raw: String, formatted: String? = nil, at date: Date = base) throws
        -> Int64
    {
        try store.insert(entry(raw, formatted: formatted, at: date))
    }

    @Test func aTrashedEntryLeavesEveryListSearchAndCountButStillExists() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let keep = try add(store, "zostaje roadmapa", at: base)
        let gone = try add(store, "znika roadmapa", formatted: "Znika roadmapa.", at: base.addingTimeInterval(10))
        #expect(try store.search("roadmapa", limit: 10).count == 2)
        let stamp = try #require(try store.trash(id: gone, at: base.addingTimeInterval(day)).stamp)

        #expect(try store.recent(limit: 10).map(\.id) == [keep])
        #expect(try store.recent(limit: 10, filter: .formatted).isEmpty)
        #expect(try store.search("roadmapa", limit: 10).map(\.id) == [keep])
        #expect(try store.search("roadmapa", limit: 10, filter: .formatted).isEmpty)
        #expect(try store.noteEntries(matching: nil, after: nil, limit: 10).map(\.id) == [keep])
        #expect(try store.noteEntries(matching: "roadmapa", after: nil, limit: 10).map(\.id) == [keep])
        #expect(try store.noteCount(matching: nil) == 1)
        #expect(try store.noteCount(matching: "roadmapa") == 1)
        #expect(try store.liveCount() == 1)
        #expect(try store.trashedCount() == 1)
        // The total of every row still counts it (Clear History removes it with the rest).
        #expect(try store.count() == 2)
        // `exists` and `content` still see it, and a live read does not.
        #expect(try store.entries(ids: [gone]).map(\.id) == [gone])
        #expect(try store.entry(gone) == nil)
        #expect(try store.entry(gone, includingTrashed: true)?.deletedAt == stamp)
        #expect(try store.entry(keep)?.deletedAt == nil)
    }

    @Test func aTrashedEntryDoesNotCountTowardTheMaximumAndAgeRetentionDeletesItAtOnce() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let oldest = try add(store, "najstarszy", at: base)
        let trashedNewest = try add(store, "wyrzucony", at: base.addingTimeInterval(40))
        let middle = try add(store, "środkowy", at: base.addingTimeInterval(20))
        let newest = try add(store, "najnowszy", at: base.addingTimeInterval(30))
        try store.trash(id: trashedNewest, at: base)
        let cutoff = base.addingTimeInterval(-day)

        // Two live entries are allowed: the trashed one (the newest by date) does not push another out.
        #expect(try store.applyRetention(cutoff: cutoff, maximumCount: 2) == 1)
        #expect(
            Set(try store.entries(ids: [oldest, trashedNewest, middle, newest]).map(\.id)) == [
                trashedNewest, middle, newest,
            ])
        #expect(try store.recent(limit: 10).map(\.id) == [newest, middle])

        // By age a trashed entry goes at once, like a live one.
        #expect(try store.applyRetention(cutoff: base.addingTimeInterval(100), maximumCount: 10) == 3)
        #expect(try store.count() == 0)
    }

    @Test func purgeTrashedDeletesOnlyEntriesDeletedBeforeTheCutoff() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let old = try add(store, "stary")
        let recent = try add(store, "niedawny")
        let live = try add(store, "żywy")
        try store.trash(id: old, at: base)
        try store.trash(id: recent, at: base.addingTimeInterval(29 * day))
        let cutoff = base.addingTimeInterval(30 * day).addingTimeInterval(-TrashStamp.retention)
        #expect(try store.purgeTrashed(olderThan: cutoff.addingTimeInterval(1)) == 1)
        #expect(Set(try store.entries(ids: [old, recent, live]).map(\.id)) == [recent, live])
        #expect(try store.purgeTrashed(olderThan: cutoff.addingTimeInterval(1)) == 0)
        // The full-text row of a purged entry goes with it.
        #expect(try store.search("stary", limit: 5).isEmpty)
        #expect(
            try store.read {
                try Int.fetchOne($0, sql: "SELECT count(*) FROM dictation_fts WHERE dictation_fts MATCH 'stary'")
            } == 0)
    }

    @Test func trashedPagesAreNewestDeletedFirstWithTiesBrokenByIdDescending() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let ids = try (0..<5).map { try add(store, "wpis \($0)") }
        try store.trash(id: ids[0], at: base)
        try store.trash(id: ids[1], at: base.addingTimeInterval(10))
        try store.trash(id: ids[2], at: base.addingTimeInterval(10).addingTimeInterval(0.000_001))
        let first = try store.trashedEntries(limit: 2)
        #expect(first.map(\.id) == [ids[2], ids[1]])
        let last = try #require(first.last)
        let second = try store.trashedEntries(
            after: .init(micros: TrashStamp.micros(try #require(last.deletedAt)), id: last.id), limit: 2)
        #expect(second.map(\.id) == [ids[0]])
        #expect(first.allSatisfy { $0.deletedAt != nil })
    }

    @Test func aStampReadBackAfterReopeningTheDatabaseEqualsTheOneWritten() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let single = try add(store, "pojedynczy")
        let a = try add(store, "partia a")
        let b = try add(store, "partia b")
        // Sub-microsecond noise on purpose: the stamp is rounded to a whole microsecond on write and on compare.
        let singleStamp = try #require(
            try store.trash(id: single, at: Date(timeIntervalSince1970: 1_800_000_000.123_456_789)).stamp)
        let at = Date(timeIntervalSince1970: 1_800_000_100.987_654_321)
        #expect(try store.trashAll(at: at) == 2)
        try store.close()

        let (reopened, _) = try open(directory: directory)
        let stamps = try reopened.trashedStamps(ids: [single, a, b])
        #expect(stamps[single] == singleStamp)
        #expect(stamps[a] == stamps[b])
        // The caller passes back the date it gave (or the one read back): both find the batch.
        let readBack = try #require(stamps[a])
        #expect(try reopened.restoreBatch(deletedAt: readBack) == 2)
        #expect(try reopened.trashedCount() == 1)
        #expect(try reopened.trashAll(at: at) == 2)
        #expect(try reopened.restoreBatch(deletedAt: at) == 2)
        #expect(try reopened.trashedStamps(ids: [single]) == [single: singleStamp])
    }

    @Test func aSingleTrashReturnsItsStampAndTrashingAgainIsANoOpWithTheSameStamp() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let id = try add(store, "a")
        let first = try #require(try store.trash(id: id, at: base).stamp)
        #expect(first == TrashStamp.date(micros: TrashStamp.micros(base)))
        #expect(try store.trash(id: id, at: base.addingTimeInterval(day)) == .alreadyTrashed(first))
        #expect(try store.trashedStamps(ids: [id]) == [id: first])
        #expect(try store.trash(id: 9_999, at: base) == .missing)
    }

    @Test func aSingleTrashNeverReusesABatchStamp() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        try add(store, "partia")
        try add(store, "później")
        #expect(try store.trashAll(at: base) == 2)
        let newcomer = try add(store, "nowy")
        // The same instant as the batch: the store moves the stamp on by 1 µs.
        let stamp = try #require(try store.trash(id: newcomer, at: base).stamp)
        #expect(TrashStamp.micros(stamp) == TrashStamp.micros(base) + 1)
        #expect(try store.restoreBatch(deletedAt: base) == 2)
        #expect(try store.trashedStamps(ids: [newcomer]) == [newcomer: stamp])
    }

    @Test func restoreBatchPutsBackExactlyThatBatchNeverARowDeletedEarlierOrLater() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let earlier = try add(store, "wcześniej")
        let b1 = try add(store, "partia 1")
        let b2 = try add(store, "partia 2")
        let later = try add(store, "później")
        try store.trash(id: earlier, at: base.addingTimeInterval(-day))
        // The batch moves every live row at that moment: put the later one back first, then trash it afterwards.
        #expect(try store.trashAll(at: base) == 3)
        try store.restore(ids: [later])
        try store.trash(id: later, at: base.addingTimeInterval(day))
        #expect(try store.restoreBatch(deletedAt: base) == 2)
        #expect(Set(try store.trashedStamps(ids: [earlier, b1, b2, later]).keys) == [earlier, later])
        #expect(try store.restoreBatch(deletedAt: base) == 0)
    }

    @Test func restoreOfALiveEntryIsANoOpAndAMissingIdIsReturned() throws {
        let (store, directory) = try open()
        defer { withExtendedLifetime(directory) {} }
        let live = try add(store, "żywy")
        let trashed = try add(store, "kosz")
        try store.trash(id: trashed, at: base)
        #expect(try store.restore(ids: [live, trashed, 9_999]) == [9_999])
        #expect(try store.trashedCount() == 0)
        #expect(try store.liveCount() == 2)
    }

    @Test func purgeAtIsTheEarlierOfThirtyDaysAfterTheDeleteAndTheRetentionLimit() {
        let deleted = base
        let created = base.addingTimeInterval(-10 * day)
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, createdAt: created, retentionDays: 0)
                == deleted.addingTimeInterval(30 * day))
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, createdAt: created, retentionDays: 90)
                == deleted.addingTimeInterval(30 * day))
        #expect(
            TrashStamp.purgeAt(deletedAt: deleted, createdAt: created, retentionDays: 7)
                == created.addingTimeInterval(7 * day))
    }
}

extension DictationStore.TrashOutcome {
    /// The stamp of a trash that moved the entry or found it moved already.
    fileprivate var stamp: Date? {
        switch self {
        case .trashed(let stamp), .alreadyTrashed(let stamp): stamp
        case .missing: nil
        }
    }
}

/// The history's periodic job purges Recently deleted 30 days after the delete, the first time ten minutes after it
/// starts, and a change of the settings never purges it.
@MainActor
@Suite struct DictationTrashRetentionTests {
    private func makeHistory(
        directory: TemporaryDirectory, keychain: MemoryKeychain, clock: any Clock<Duration>, runsJob: Bool,
        now: Date, changed: @escaping @Sendable () -> Void = {}
    ) -> (DictationHistory, DictationSettings) {
        // 90 days: nothing here is old enough to be deleted by age.
        let settings = DictationSettings(
            PluginSettings(
                pluginID: "dictation",
                store: MemorySettingsStore(["plugins.dictation.retentionDays": .integer(90)])))
        let history = DictationHistory(
            directory: directory.url, keychain: keychain, settings: settings, clock: clock, now: { now },
            runsRetentionJob: runsJob, logger: Logger(subsystem: "com.lintelapp.tests", category: "dictation"),
            changed: changed)
        return (history, settings)
    }

    private func seed(_ directory: TemporaryDirectory, _ keychain: MemoryKeychain, now: Date) throws -> (
        gone: Int64, recent: Int64, live: Int64
    ) {
        let (history, _) = makeHistory(
            directory: directory, keychain: keychain, clock: ContinuousClock(), runsJob: false, now: now)
        history.open()
        let store = try #require(history.store)
        let created = now.addingTimeInterval(-40 * day)
        let gone = try store.insert(entry("stary kosz", at: created))
        let recent = try store.insert(entry("świeży kosz", at: created))
        let live = try store.insert(entry("żywy", at: created))
        try store.trash(id: gone, at: now.addingTimeInterval(-31 * day))
        try store.trash(id: recent, at: now.addingTimeInterval(-2 * day))
        history.close()
        return (gone, recent, live)
    }

    @Test func theFirstPurgeRunsTenMinutesAfterTheStartAndNotOnTheImmediatePass() async throws {
        let directory = try TemporaryDirectory()
        let keychain = MemoryKeychain()
        let now = base.addingTimeInterval(100 * day)
        let ids = try seed(directory, keychain, now: now)
        let clock = TestClock()
        let changes = CountLatch()
        let (history, _) = makeHistory(
            directory: directory, keychain: keychain, clock: clock, runsJob: true, now: now,
            changed: { changes.increment() })
        history.open()
        defer { history.close() }
        let store = try #require(history.store)

        // The immediate pass ran and went to sleep: the 31-day-old trash is still there.
        #expect(await clock.waitForSleepers(1))
        #expect(try store.trashedCount() == 2)
        #expect(changes.count == 0)

        clock.advance(by: DictationHistory.firstTrashPurgeDelay)
        #expect(await changes.wait(atLeast: 1))
        #expect(try store.trashedCount() == 1)
        #expect(Set(try store.entries(ids: [ids.gone, ids.recent, ids.live]).map(\.id)) == [ids.recent, ids.live])
        // From then on the job runs hourly.
        #expect(await clock.waitForSleepers(1))
        #expect(clock.wokenDeadlines.last == TestInstant(offset: DictationHistory.firstTrashPurgeDelay))
    }

    @Test func applyingTheRetentionAfterASettingChangeNeverPurgesRecentlyDeleted() throws {
        let directory = try TemporaryDirectory()
        let keychain = MemoryKeychain()
        let now = base.addingTimeInterval(100 * day)
        _ = try seed(directory, keychain, now: now)
        let (history, _) = makeHistory(
            directory: directory, keychain: keychain, clock: ContinuousClock(), runsJob: false, now: now)
        history.open()
        defer { history.close() }
        let store = try #require(history.store)
        #expect(history.applyRetention() == 0)
        #expect(try store.trashedCount() == 2)
        // The periodic job's pass purges, and reports it.
        #expect(history.applyRetention(purgesTrash: true) == 1)
        #expect(try store.trashedCount() == 1)
        #expect(history.entryCount == 2)
    }

    @Test func aPurgeIsAnnouncedAndClearHistoryRemovesRecentlyDeletedWithTheRest() throws {
        let directory = try TemporaryDirectory()
        let keychain = MemoryKeychain()
        let now = base.addingTimeInterval(100 * day)
        _ = try seed(directory, keychain, now: now)
        let changes = Shared(0)
        let (history, _) = makeHistory(
            directory: directory, keychain: keychain, clock: ContinuousClock(), runsJob: false, now: now,
            changed: { changes.update { $0 += 1 } })
        history.open()
        defer { history.close() }
        let store = try #require(history.store)
        // A purge that deleted something tells the panel and Notes; one that deleted nothing does not.
        #expect(history.applyRetention(purgesTrash: true) == 1)
        #expect(changes.value == 1)
        #expect(history.applyRetention(purgesTrash: true) == 0)
        #expect(changes.value == 1)
        // Clear History is not restricted to live rows (Phase 5 decides whether its count and rule change).
        try history.clear()
        #expect(try store.count() == 0)
        #expect(try store.trashedCount() == 0)
    }
}
