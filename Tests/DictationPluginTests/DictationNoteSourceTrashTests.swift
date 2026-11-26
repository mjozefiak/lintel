import Foundation
import LintelCore
import LintelKit
import Testing
import os

@testable import DictationPlugin

private let day: TimeInterval = 86_400
private let started = Date(timeIntervalSince1970: 1_800_000_000)

private func query(_ text: String) -> NormalizedQuery {
    NormalizedQuery(raw: text, normalized: text.lowercased())
}

private func entry(
    _ raw: String, formatted: String? = nil, at date: Date, status: FormatStatus? = nil
) -> DictationEntry {
    DictationEntry(
        createdAt: date, durationMs: 4_000, rawText: raw, formattedText: formatted,
        formatMode: formatted == nil ? .raw : .clean, formatStatus: status ?? (formatted == nil ? .none : .ok),
        detectedLanguages: "pl", speechModelID: "parakeet-ultra", formatterModel: nil, targetBundleID: nil,
        pasteResult: .pasted)
}

/// Five entries of the history read through a Notes source that has a clock, a retention setting and a change
/// counter of its own. The history's `changed` feeds both the counter and the hub, like the plugin wires it.
@MainActor
private struct TrashRig {
    let directory: TemporaryDirectory
    let history: DictationHistory
    let hub = NoteChangeHub()
    let now = Shared(started.addingTimeInterval(day))
    let retentionDays = Shared(0)
    let changes = Shared(0)
    let source: DictationNoteSource
    let ids: [String: Int64]

    var store: DictationStore {
        get throws { try #require(history.storeBox.value) }
    }

    init() throws {
        directory = try TemporaryDirectory()
        let hub = hub
        let changes = changes
        let settings = DictationSettings(PluginSettings(pluginID: "dictation", store: MemorySettingsStore()))
        history = DictationHistory(
            directory: directory.url, keychain: MemoryKeychain(), settings: settings, clock: ContinuousClock(),
            runsRetentionJob: false, logger: Logger(subsystem: "com.lintelapp.tests", category: "dictation"),
            changed: {
                changes.update { $0 += 1 }
                hub.notify()
            })
        let now = now
        let retentionDays = retentionDays
        source = DictationNoteSource(
            history: history, hub: hub, appName: { _ in nil }, retentionDays: { retentionDays.value },
            now: { now.value })
        history.open()
        let store = try #require(history.storeBox.value)
        ids = [
            "plain": try store.insert(entry("zwykły wpis o roadmapie", at: started)),
            "cleaned": try store.insert(
                entry("sprawdź to jutro", formatted: "Sprawdź to jutro.", at: started.addingTimeInterval(10))),
            "stale": try store.insert(entry("niepełny wpis", at: started.addingTimeInterval(20), status: .partial)),
            "failed": try store.insert(entry("nieudany wpis", at: started.addingTimeInterval(30), status: .failed)),
            "last": try store.insert(entry("ostatni wpis", at: started.addingTimeInterval(40))),
        ]
    }

    func key(_ name: String) throws -> NoteKey {
        DictationNoteSource.key(storeID: try #require(history.storeID), row: try #require(ids[name]))
    }

    func name(of key: NoteKey) -> String? {
        ids.first { (try? self.key($0.key)) == key }?.key
    }

    /// An entry with a real id that is not one of the five.
    @discardableResult
    func insert(_ raw: String, at date: Date = started) throws -> NoteKey {
        let id = try store.insert(entry(raw, at: date))
        return DictationNoteSource.key(storeID: try #require(history.storeID), row: id)
    }
}

/// The rules of `NoteSourceTrash` every conforming source follows (the Meetings and Notes suites use the same
/// scenarios under the same names; Dictation is never recording or processing, so it has no busy case).
@MainActor
@Suite("DictationNoteSource: NoteSourceTrash contract")
struct DictationNoteSourceTrashContractTests {
    @Test func theSourceOffersRecentlyDeletedThroughTheOptionalCapability() throws {
        let rig = try TrashRig()
        #expect((rig.source as any NoteSource) is any NoteSourceTrash)
    }

    @Test func aTrashedNoteLeavesTheListSearchAndCountsButStillExists() async throws {
        let rig = try TrashRig()
        let plain = try rig.key("plain")
        let stamp = try await rig.source.trash(plain)

        let page = try await rig.source.list(matching: nil, after: nil, limit: 100)
        #expect(page.total == 4)
        #expect(!page.items.contains { $0.id == plain })
        let found = try await rig.source.list(matching: query("roadmapie"), after: nil, limit: 100)
        #expect(found.items.isEmpty)
        #expect(found.total == 0)
        #expect(try await rig.source.liveCount() == 4)
        #expect(try await rig.source.trashedCount() == 1)
        #expect(try await rig.source.exists([plain]) == [plain])
        #expect(try await rig.source.trashedKeys([plain, try rig.key("cleaned")]) == [plain: stamp])
    }

    @Test func aTrashedNoteIsNotInTheHistoryListModeOrItsFilters() async throws {
        let rig = try TrashRig()
        let id = try #require(rig.ids["cleaned"])
        let box = rig.history.storeBox
        let source = DictationHistorySource(
            store: { box.value }, paste: { _ in }, delete: { _ in }, now: { started })
        #expect(try await source.search(query("jutro"), filter: nil, limit: 20).count == 1)
        try await rig.source.trash(try rig.key("cleaned"))
        #expect(try await source.search(query(""), filter: nil, limit: 20).count == 4)
        #expect(try await source.search(query("jutro"), filter: nil, limit: 20).isEmpty)
        for filter in HistoryFilter.allCases {
            let found = try await source.search(query(""), filter: filter.rawValue, limit: 20)
            #expect(!found.contains { DictationPresentation.entryID($0.itemKey) == id })
        }
        // The panel's actions read the entry by row id: a trashed one is not there to paste.
        #expect(try rig.store.entry(id) == nil)
        #expect(try rig.store.entry(id, includingTrashed: true) != nil)
    }

    @Test func aTrashedNoteStillHasItsContentWithDeletedAtAndPurgeAtAndNoActions() async throws {
        let rig = try TrashRig()
        let key = try rig.key("cleaned")
        let live = try #require(try await rig.source.content(for: key))
        #expect(live.summary.deletedAt == nil)
        #expect(live.summary.purgeAt == nil)

        let stamp = try await rig.source.trash(key)
        let content = try #require(try await rig.source.content(for: key))
        #expect(content.summary.deletedAt == stamp)
        #expect(content.summary.purgeAt == stamp.addingTimeInterval(30 * day))
        #expect(content.summary.title == live.summary.title)
        #expect(content.layers == live.layers)
        #expect(!content.layers.isEmpty)
        #expect(rig.source.actions(for: key).isEmpty)
    }

    @Test func trashOfAMissingNoteThrowsNotFoundAndOfATrashedOneIsANoOpWithTheSameStamp() async throws {
        let rig = try TrashRig()
        let storeID = try #require(rig.history.storeID)
        // A well formed key of this store with no row, and one of an earlier store: both are simply not there.
        await #expect(throws: NoteSourceError.notFound) {
            try await rig.source.trash(DictationNoteSource.key(storeID: storeID, row: 9_999))
        }
        await #expect(throws: NoteSourceError.notFound) {
            try await rig.source.trash(DictationNoteSource.key(storeID: "0000000000000000", row: 1))
        }
        // A key that is not this source's shape is an invalid argument, and changes nothing.
        await #expect(throws: DictationNoteSourceError.invalidArgument) {
            try await rig.source.trash(NoteKey(pluginID: "meetings", id: "x"))
        }
        await #expect(throws: DictationNoteSourceError.invalidArgument) {
            try await rig.source.trash(NoteKey(pluginID: "dictation", id: "no-slash"))
        }
        let key = try rig.key("stale")
        let stamp = try await rig.source.trash(key)
        let changes = rig.changes.value
        rig.now.update { $0 = $0.addingTimeInterval(day) }
        #expect(try await rig.source.trash(key) == stamp)
        #expect(rig.changes.value == changes)
        #expect(try await rig.source.trashedCount() == 1)
    }

    @Test func dictationIsNeverBusyEvenForTheNewestEntry() async throws {
        let rig = try TrashRig()
        // There is no recording or processing state: every live entry can be trashed.
        let moved = try await rig.source.trashAll(at: started.addingTimeInterval(day))
        #expect(moved.stayed == 0)
        #expect(moved.moved == 5)
    }

    @Test func restoreOfALiveNoteIsANoOpAndAPartialBatchReturnsTheKeysThatAreGone() async throws {
        let rig = try TrashRig()
        let trashed = try rig.key("plain")
        let purged = try rig.key("failed")
        let live = try rig.key("cleaned")
        try await rig.source.trash(trashed)
        try await rig.source.trash(purged)
        try await rig.source.delete(purged)
        let foreign = NoteKey(pluginID: "meetings", id: "x")
        let unknown = DictationNoteSource.key(storeID: try #require(rig.history.storeID), row: 9_999)
        let malformed = NoteKey(pluginID: "dictation", id: "not-a-key")
        let earlierStore = DictationNoteSource.key(storeID: "0000000000000000", row: 1)

        let missing = try await rig.source.restore([trashed, live, purged, foreign, unknown, malformed, earlierStore])
        #expect(missing == [purged, foreign, unknown, malformed, earlierStore])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.liveCount() == 4)
        #expect(try await rig.source.restore([live]).isEmpty)
    }

    @Test func trashedPagesNewestDeletedFirstWithDeletedAtAndPurgeAtOnEveryRow() async throws {
        let rig = try TrashRig()
        var stamps: [String: Date] = [:]
        for name in ["plain", "stale", "failed"] {
            stamps[name] = try await rig.source.trash(try rig.key(name))
            rig.now.update { $0 = $0.addingTimeInterval(60) }
        }
        let first = try await rig.source.trashed(after: nil, limit: 2)
        #expect(first.total == 3)
        #expect(first.items.compactMap { rig.name(of: $0.id) } == ["failed", "stale"])
        let next = try #require(first.next)
        let second = try await rig.source.trashed(after: next, limit: 2)
        #expect(second.items.compactMap { rig.name(of: $0.id) } == ["plain"])
        #expect(second.next == nil)
        for item in first.items + second.items {
            let name = try #require(rig.name(of: item.id))
            #expect(item.deletedAt == stamps[name])
            #expect(item.purgeAt == item.deletedAt?.addingTimeInterval(30 * day))
        }
        await #expect(throws: DictationNoteSourceError.invalidArgument) {
            try await rig.source.trashed(after: NoteCursor(token: "nonsense"), limit: 2)
        }
    }

    @Test func purgeAtIsTheEarlierOfThirtyDaysAfterTheDeleteAndTheRetentionLimit() async throws {
        let rig = try TrashRig()
        let key = try rig.key("cleaned")
        let stamp = try await rig.source.trash(key)
        // Unlimited (0) or a long limit: thirty days after the delete.
        for days in [0, 90] {
            rig.retentionDays.update { $0 = days }
            let summary = try #require(try await rig.source.content(for: key)).summary
            #expect(summary.purgeAt == stamp.addingTimeInterval(30 * day))
        }
        // A 7-day limit counted from the time of the dictation ends sooner.
        rig.retentionDays.update { $0 = 7 }
        let page = try await rig.source.trashed(after: nil, limit: 10)
        #expect(page.items.first?.purgeAt == started.addingTimeInterval(10 + 7 * day))
    }

    @Test func trashAllMovesEveryLiveNoteWithOneStampAndRestoreBatchPutsBackOnlyThatBatch() async throws {
        let rig = try TrashRig()
        let earlier = try rig.key("failed")
        let earlierStamp = try await rig.source.trash(earlier)
        let at = started.addingTimeInterval(2 * day)

        let batch = try await rig.source.trashAll(at: at)
        #expect(batch.moved == 4)
        #expect(batch.stayed == 0)
        #expect(batch.deletedAt == at)
        #expect(try await rig.source.liveCount() == 0)
        let stamps = try await rig.source.trashedKeys([earlier, try rig.key("cleaned"), try rig.key("plain")])
        #expect(stamps[earlier] == earlierStamp)
        #expect(stamps[try rig.key("cleaned")] == batch.deletedAt)
        #expect(stamps[try rig.key("plain")] == batch.deletedAt)

        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 4)
        #expect(try await rig.source.liveCount() == 4)
        #expect(try await rig.source.trashedCount() == 1)
        // The stamp is the batch: nothing is left of it.
        #expect(try await rig.source.restoreBatch(deletedAt: batch.deletedAt) == 0)
    }

    @Test func aSingleTrashNeverReusesABatchStamp() async throws {
        let rig = try TrashRig()
        let at = started.addingTimeInterval(3 * day)
        #expect(try await rig.source.trashAll(at: at).moved == 5)
        let newcomer = try rig.insert("nowy wpis")
        rig.now.update { $0 = at }
        let stamp = try await rig.source.trash(newcomer)
        #expect(stamp != at)
        #expect(try await rig.source.restoreBatch(deletedAt: at) == 5)
        #expect(try await rig.source.trashedKeys([newcomer]) == [newcomer: stamp])
    }

    @Test func trashedKeysAndRestoreProcessMoreThanFiveHundredKeysInChunks() async throws {
        let rig = try TrashRig()
        let store = try rig.store
        let keys = try (0..<1_100).map { index in
            DictationNoteSource.key(
                storeID: try #require(rig.history.storeID),
                row: try store.insert(entry("masowy \(index)", at: started.addingTimeInterval(Double(index)))))
        }
        let edges = [0, 499, 500, 501, 999, 1_000, 1_099].map { keys[$0] }
        for key in edges { try await rig.source.trash(key) }

        let unknown = DictationNoteSource.key(storeID: try #require(rig.history.storeID), row: 99_999)
        let stamps = try await rig.source.trashedKeys(keys + [unknown])
        #expect(Set(stamps.keys) == Set(edges))
        #expect(try await rig.source.restore(keys + [unknown]) == [unknown])
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.trashedKeys(keys).isEmpty)
    }

    @Test func deleteIsPermanentAndWorksOnATrashedNote() async throws {
        let rig = try TrashRig()
        let key = try rig.key("stale")
        try await rig.source.trash(key)
        try await rig.source.delete(key)
        #expect(try await rig.source.content(for: key) == nil)
        #expect(try await rig.source.exists([key]).isEmpty)
        #expect(try await rig.source.trashedCount() == 0)
        #expect(try await rig.source.restore([key]) == [key])
    }

    @Test func theChangeStreamIsToldAfterTrashRestoreTrashAllAndRestoreBatch() async throws {
        let rig = try TrashRig()
        let key = try rig.key("plain")
        var seen = rig.changes.value
        func announced() -> Bool {
            defer { seen = rig.changes.value }
            return rig.changes.value > seen
        }
        try await rig.source.trash(key)
        #expect(announced())
        try await rig.source.restore([key])
        #expect(announced())
        let at = started.addingTimeInterval(day)
        try await rig.source.trashAll(at: at)
        #expect(announced())
        try await rig.source.restoreBatch(deletedAt: at)
        #expect(announced())
        // A read changes nothing.
        _ = try await rig.source.trashed(after: nil, limit: 10)
        #expect(!announced())

        // The stream itself carries it (the hub is what the plugin hands to Notes).
        var iterator = rig.source.makeChanges().makeAsyncIterator()
        try await rig.source.trash(key)
        #expect(await iterator.next() != nil)
    }

    @Test func aRestoreThatPutsNothingBackAnnouncesNothing() async throws {
        let rig = try TrashRig()
        let live = try rig.key("plain")
        var seen = rig.changes.value
        func announced() -> Bool {
            defer { seen = rig.changes.value }
            return rig.changes.value > seen
        }
        // A live entry, a key of another plugin, a key that never existed and an empty list: nothing came back.
        try await rig.source.restore([live])
        #expect(!announced())
        let foreign = NoteKey(pluginID: "meetings", id: "1")
        let unknown = NoteKey(pluginID: rig.source.pluginID, id: "9999")
        _ = try await rig.source.restore([foreign, unknown])
        #expect(!announced())
        try await rig.source.restore([])
        #expect(!announced())
        // A second restore of an entry that is already back is not a change either; the first one is.
        try await rig.source.trash(live)
        #expect(announced())
        try await rig.source.restore([live])
        #expect(announced())
        try await rig.source.restore([live])
        #expect(!announced())
    }

    @Test func aHistoryThatIsNotOpenThrowsAndNeverReadsAnEmptyAnswer() async throws {
        let rig = try TrashRig()
        let key = try rig.key("plain")
        rig.history.close()
        await #expect(throws: DictationNoteSourceError.storeUnavailable) { try await rig.source.trash(key) }
        await #expect(throws: DictationNoteSourceError.storeUnavailable) { try await rig.source.restore([key]) }
        await #expect(throws: DictationNoteSourceError.storeUnavailable) {
            try await rig.source.trashed(after: nil, limit: 5)
        }
        await #expect(throws: DictationNoteSourceError.storeUnavailable) { try await rig.source.trashedKeys([key]) }
        await #expect(throws: DictationNoteSourceError.storeUnavailable) { try await rig.source.liveCount() }
    }
}

/// `wordCount` is filled for the explorer's row ("118 words").
@MainActor
@Suite("DictationNoteSource: explorer fields")
struct DictationNoteSourceExplorerFieldTests {
    @Test func wordCountIsTheWordsOfTheTextReturnPastes() async throws {
        let rig = try TrashRig()
        let page = try await rig.source.list(matching: nil, after: nil, limit: 100)
        let counts = Dictionary(
            uniqueKeysWithValues: page.items.compactMap { item in rig.name(of: item.id).map { ($0, item.wordCount) } })
        #expect(counts["plain"] == 4)  // the raw text
        #expect(counts["cleaned"] == 3)  // the cleaned text: "Sprawdź to jutro."
        let content = try #require(try await rig.source.content(for: try rig.key("plain")))
        #expect(content.summary.wordCount == 4)
        // Nothing to count: no count.
        let blank = try rig.insert("   \n ")
        let blankContent = try #require(try await rig.source.content(for: blank))
        #expect(blankContent.summary.wordCount == nil)
    }
}
