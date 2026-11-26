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
        let seeded = try await Task.detached { try MeetingSpeakersQA.seed(store, state: state) }.value
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
}
#endif
