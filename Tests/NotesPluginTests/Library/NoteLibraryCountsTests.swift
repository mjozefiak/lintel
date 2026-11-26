import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

/// `NoteLibrary.counts()`: the sidebar's numbers (spec `2026-11-24-notes-explorer-main-window`, step 3.3; review M2
/// of #348).
@Suite("Notes library: the sidebar's counts")
struct NoteLibraryCountsTests {
    /// Two meetings (a source with Recently deleted, so `liveCount` answers), two dictations (a plain source, so the
    /// total of a page answers), a note you wrote, the kept copy of a removed meeting and of a removed dictation.
    private func rig() -> (NoteLibrary, TrashingNoteSource, ScriptedNoteSource) {
        let meetings = TrashingNoteSource(
            ScriptedNoteSource(
                "meetings",
                items: [
                    Fixtures.summary("meetings", "a", secondsAgo: 100),
                    Fixtures.summary("meetings", "b", secondsAgo: 300),
                ]))
        meetings.liveCountAnswer = 2
        let dictation = ScriptedNoteSource(
            "dictation",
            items: [
                Fixtures.summary("dictation", "s/1", secondsAgo: 200, kind: .dictation),
                Fixtures.summary("dictation", "s/2", secondsAgo: 400, kind: .dictation),
            ])
        var keptDictation = Fixtures.overlay(
            3, Fixtures.key("dictation", "s/9"), layer: "cleaned", startedAt: Fixtures.epoch.addingTimeInterval(-500))
        keptDictation.kind = .dictation
        let keptMeeting = Fixtures.overlay(
            2, Fixtures.key("meetings", "gone"), layer: "notes", startedAt: Fixtures.epoch.addingTimeInterval(-600))
        let store = FakeOverlayStore(
            present: [Fixtures.manual(1, "m", secondsAgo: 250, title: "Plan")], detached: [keptMeeting, keptDictation])
        return (NoteLibrary(box: SourceBox([meetings, dictation]), store: store), meetings, dictation)
    }

    @Test("each collection sums its sources and Notes' own rows: a note you wrote only in All, kept copies by kind")
    func sums() async {
        let (library, _, _) = rig()
        let counts = await library.counts()
        #expect(counts == NoteCollectionCounts(all: 7, meetings: 3, dictations: 3))
    }

    @Test("the counts agree with the total of each collection's browse list")
    func agreeWithTheList() async {
        let (library, _, _) = rig()
        let counts = await library.counts()
        for collection in NoteCollection.allCases {
            let listing = await library.list(matching: nil, after: nil, limit: 50, collection: collection)
            #expect(counts.count(of: collection) == listing.total, "\(collection)")
        }
    }

    @Test("a source with Recently deleted is counted by liveCount, so its trashed notes are not counted")
    func trashIsNotCounted() async {
        let (library, meetings, _) = rig()
        // Three rows in the source's store, one of them trashed: its live count is 2, a page's total would be 3.
        meetings.inner.items += [Fixtures.summary("meetings", "t", secondsAgo: 50)]
        meetings.trashed = [Fixtures.key("meetings", "t"): Fixtures.epoch]
        meetings.liveCountAnswer = 2
        let counts = await library.counts()
        #expect(counts.meetings == 3)  // 2 live + the kept copy
        #expect(counts.all == 7)
    }

    @Test("a liveCount that throws falls back to the total of a page")
    func liveCountFallback() async {
        let (library, meetings, _) = rig()
        meetings.liveCountBehavior = .throwsError
        let counts = await library.counts()
        #expect(counts == NoteCollectionCounts(all: 7, meetings: 3, dictations: 3))
    }

    @Test("a source that does not answer leaves its collections and All unknown; the explorer keeps the last number")
    func downSource() async {
        let (library, _, dictation) = rig()
        dictation.behavior = .throwsError
        let counts = await library.counts()
        #expect(counts.dictations == nil)
        #expect(counts.all == nil)
        #expect(counts.meetings == 3)

        let explorer = await ExplorerModel()
        await explorer.setCounts(NoteCollectionCounts(all: 7, meetings: 3, dictations: 3))
        await explorer.setCounts(counts)
        #expect(await explorer.counts == NoteCollectionCounts(all: 7, meetings: 3, dictations: 3))
    }

    @Test("a source that overruns its budget counts as not answering")
    func hangingSource() async {
        let meetings = ScriptedNoteSource("meetings", items: [Fixtures.summary("meetings", "a", secondsAgo: 1)])
        let dictation = ScriptedNoteSource(
            "dictation", items: [Fixtures.summary("dictation", "s/1", secondsAgo: 2, kind: .dictation)])
        dictation.behavior = .hangs
        let clock = ManualClock()
        let library = NoteLibrary(box: SourceBox([meetings, dictation]), clock: clock)
        let task = Task { await library.counts() }
        await clock.waitForSleeps(2)
        await clock.waitForCancelledSleeps(1)
        clock.advance(by: .milliseconds(150))
        let counts = await task.value
        #expect(counts == NoteCollectionCounts(all: nil, meetings: 1, dictations: nil))
    }
}
