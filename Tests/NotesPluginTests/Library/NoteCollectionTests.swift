import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

private func ids(_ rows: [NoteRow]) -> [String] { rows.map { $0.id.key.rawValue } }

@Suite("Notes and Dictations lists")
struct NoteCollectionTests {
    private func rig() -> (NoteLibrary, ScriptedNoteSource, ScriptedNoteSource) {
        let meetings = ScriptedNoteSource(
            "meetings",
            items: [
                Fixtures.summary("meetings", "a", secondsAgo: 100), Fixtures.summary("meetings", "c", secondsAgo: 300),
            ])
        let dictation = ScriptedNoteSource(
            "dictation",
            items: [
                Fixtures.summary("dictation", "s/1", secondsAgo: 200, kind: .dictation),
                Fixtures.summary("dictation", "s/2", secondsAgo: 400, kind: .dictation),
            ])
        // A manual note, and the kept copy of a dictation whose recording is gone.
        let gone = Fixtures.overlay(2, Fixtures.key("dictation", "s/9"), layer: "cleaned", startedAt: Fixtures.epoch)
        var kept = gone
        kept.kind = .dictation
        let store = FakeOverlayStore(
            present: [Fixtures.manual(1, "m", secondsAgo: 250, title: "Plan")], detached: [kept])
        return (NoteLibrary(box: SourceBox([meetings, dictation]), store: store), meetings, dictation)
    }

    @Test("classification reads the plugin id and the kind only")
    func classification() {
        let meeting = Fixtures.key("meetings", "a")
        let manual = Fixtures.key("notes", "x")
        let dictation = Fixtures.key("dictation", "s/1")
        #expect(NoteCollection.meetings.contains(key: meeting))
        #expect(!NoteCollection.meetings.contains(key: manual, kind: .manual))
        #expect(!NoteCollection.meetings.contains(key: dictation))
        #expect(NoteCollection.dictations.contains(key: dictation))
        #expect(NoteCollection.dictations.contains(key: Fixtures.key("anything", "1"), kind: .dictation))
        #expect(NoteCollection.dictations.contains(.detached(dictation, startedAtMs: 1)))
        for key in [meeting, manual, dictation] { #expect(NoteCollection.all.contains(key: key)) }
    }

    @Test("an unknown or missing stored collection reads as All notes")
    func storedValue() {
        #expect(NoteCollection(stored: nil) == .all)
        #expect(NoteCollection(stored: "") == .all)
        #expect(NoteCollection(stored: "folder:abc") == .all)
        #expect(NoteCollection(stored: "meetings") == .meetings)
        #expect(NoteCollection(stored: "dictations") == .dictations)
    }

    @Test("All lists everything, Meetings only meetings, Dictations only dictations (live and kept copies)")
    func split() async {
        let (library, meetings, dictation) = rig()
        let all = await library.list(matching: nil, after: nil, limit: 10)
        #expect(all.rows.count == 6)
        let shown = await library.list(matching: nil, after: nil, limit: 10, collection: .meetings)
        #expect(ids(shown.rows) == ["meetings:a", "meetings:c"])
        #expect(shown.total == 2)
        let dictations = await library.list(matching: nil, after: nil, limit: 10, collection: .dictations)
        #expect(Set(ids(dictations.rows)) == ["dictation:s/1", "dictation:s/2", "dictation:s/9"])
        #expect(!ids(dictations.rows).contains("notes:m"))
        // The list that is not shown does not ask its sources at all.
        #expect(meetings.listCalls == 2)
        #expect(dictation.listCalls == 2)
    }

    @Test("a dictation source that is down does not touch the Meetings list")
    func downSourceStaysInItsList() async {
        let (library, _, dictation) = rig()
        dictation.behavior = .throwsError
        let shown = await library.list(matching: nil, after: nil, limit: 10, collection: .meetings)
        #expect(shown.unavailable.isEmpty)
        let dictations = await library.list(matching: nil, after: nil, limit: 10, collection: .dictations)
        #expect(dictations.unavailable.map(\.pluginID) == ["dictation"])
    }

    @Test("day grouping: today, yesterday, then one group per day")
    func dayGroups() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Fixtures.epoch
        let today = NoteGroupingRules.dayKey(now, now: now, calendar: calendar)
        let yesterday = NoteGroupingRules.dayKey(
            now.addingTimeInterval(-86_400), now: now, calendar: calendar)
        let older = NoteGroupingRules.dayKey(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)
        #expect(today == .today)
        #expect(yesterday == .yesterday)
        if case .day = older {} else { Issue.record("a day three days ago has its own group") }
    }
}
