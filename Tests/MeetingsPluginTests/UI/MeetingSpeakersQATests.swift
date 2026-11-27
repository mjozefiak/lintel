#if DEBUG
import Foundation
import Testing

@testable import MeetingsPlugin

/// `plugins.meetings.qaSpeakerNames` (DEBUG only): every state writes its fixture meeting and draws what it names.
@MainActor
@Suite struct MeetingSpeakersQATests {
    @Test(arguments: MeetingSpeakersQA.State.allCases)
    func everyStateSeedsItsMeeting(_ state: MeetingSpeakersQA.State) async throws {
        let directory = try TemporaryDirectory()
        let store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: testKeys())
        let seeded = try await Task.detached { try MeetingSpeakersQA.seed(store, state: state, now: Date()) }.value
        let model = MeetingWindowModel(
            meetingID: seeded.meetingID, store: store, spool: NoSpoolMaintenance(), pasteboard: RecordingPasteboard())
        await model.load()
        let rows = model.speakerList.rows
        #expect(rows.count == 4)
        switch state {
        case .named:
            #expect(rows.map(\.name) == ["Anna Kowalska", "Bartek Nowak", "Marek Wiśniewski", "Ola Zielińska"])
        case .conflict:
            #expect(rows.compactMap(\.suggestion?.name) == ["Marek", "Marek"])
        case .mixed, .editing, .merge:
            #expect(rows.compactMap(\.suggestion?.name) == ["Marek"])
            #expect(rows[1].origin != nil)
        }
    }

    /// QA m7: the fixture used to start on 2024-11-03, so the 90-day retention removed it on a relaunch with
    /// `--qa-persistent-settings`, and every launch wrote one more copy.
    @Test func theFixtureStartsADayBeforeNowAndIsWrittenOnce() async throws {
        let directory = try TemporaryDirectory()
        let store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: testKeys())
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try await Task.detached { try MeetingSpeakersQA.seedOnce(store, state: .editing, now: now) }.value
        let again = try await Task.detached {
            try MeetingSpeakersQA.seedOnce(store, state: .editing, now: now.addingTimeInterval(3600))
        }.value
        #expect(again.meetingID == first.meetingID)
        #expect(again.third == first.third)
        let count = try store.read { db in try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM meeting") }
        #expect(count == 1)
        let entry = try #require(try store.libraryEntry(uuid: MeetingSpeakersQA.uuid(of: .editing)))
        #expect(entry.startedAt == now.addingTimeInterval(-24 * 60 * 60))
        // Each state has its own meeting.
        let other = try await Task.detached { try MeetingSpeakersQA.seedOnce(store, state: .merge, now: now) }.value
        #expect(other.meetingID != first.meetingID)
        #expect(Set(MeetingSpeakersQA.State.allCases.map(MeetingSpeakersQA.uuid(of:))).count == 5)
        #expect(MeetingSpeakersQA.State.allCases.allSatisfy { UUID(uuidString: MeetingSpeakersQA.uuid(of: $0)) != nil })
    }
}
#endif
