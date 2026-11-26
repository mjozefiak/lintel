import Dispatch
import Foundation
import LintelTestSupport
import Synchronization
import Testing

@testable import MeetingsPlugin

/// The resolution of speaker names reads the meeting, resolves and writes in one transaction (spec
/// `2026-11-25-meeting-speaker-names`, F1 review M1). A name the user gives while the notes job runs therefore lands
/// either entirely before the resolution sees the meeting or entirely after it was written; it can never land
/// between the read and the write and be overwritten by a stale resolution.
@Suite struct SpeakerNamesTransactionTests {
    @Test func aUserWriteWaitsForTheResolveTransaction() async throws {
        let rig = try await SpeakerNamesRig.make()
        let bartek = rig.bartek
        let store = rig.store
        let entered = CountLatch()
        let release = Mutex(false)
        let seen = Mutex<[MeetingsStore.SpeakerNameState]>([])

        // The plan runs inside the store's transaction and holds it until the test lets go.
        let resolution = Task.detached {
            try store.resolveSpeakerNames(meetingID: rig.meetingID) { document, states, _ in
                seen.withLock { $0 = states }
                entered.increment()
                while !release.withLock({ $0 }) { Thread.sleep(forTimeInterval: 0.002) }
                return MeetingSpeakerNames.Plan(
                    speakers: document.speakers.count,
                    updates: [
                        .init(
                            speakerID: bartek, label: "Mówca 1", source: .transcript, status: .suggested,
                            suggestedName: "Marek")
                    ],
                    evidence: [], applied: [:], suggested: ["transcript": 1])
            }
        }
        // The plan holds the transaction now: everything below happens while it is open.
        #expect(await entered.wait(atLeast: 1, "the plan to run inside the transaction"))
        let rename = CountLatch()
        let renaming = CountLatch()
        let writer = Task.detached {
            renaming.increment()
            try store.renameSpeaker(bartek, label: "Marek")
            rename.increment()
        }
        #expect(await renaming.wait(atLeast: 1, "the rename to be issued"))
        // The rename is a write of the same store: it cannot land while the resolution's transaction is open.
        for _ in 0..<20 where rename.count == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(rename.count == 0)

        // Let the resolution finish. It saw the speaker before the rename, and its write committed first.
        release.withLock { $0 = true }
        _ = try await resolution.value
        try await writer.value
        #expect(seen.withLock { $0.first { $0.speakerID == bartek }?.label } == "Bartek Nowak")
        // The user's write landed after it and is the one that stands.
        #expect(try rig.state(bartek)?.label == "Marek")
        #expect(try rig.state(bartek)?.source == .user)
    }
}
