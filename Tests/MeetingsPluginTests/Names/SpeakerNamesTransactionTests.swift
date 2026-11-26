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
        let meetingID = rig.meetingID
        let entered = CountLatch()
        // The plan holds the transaction open until the test lets go. A semaphore with a limit, never a spin: whatever
        // happens to the test body, the transaction ends within the limit instead of hanging the whole run.
        let release = DispatchSemaphore(value: 0)
        let seen = Mutex<[MeetingsStore.SpeakerNameState]>([])

        // The plan runs inside the store's transaction and holds it until the test lets go. A `DatabaseQueue` write
        // blocks the thread it runs on, so both calls run on their own threads: on the narrow cooperative pool a CI
        // runner has, a blocked pool thread leaves nothing to run the rest of the test, and the two wait for each
        // other for good.
        let resolution = Task {
            try await offCooperativePool {
                try store.resolveSpeakerNames(meetingID: meetingID) { document, states, _ in
                    seen.withLock { $0 = states }
                    entered.increment()
                    _ = release.wait(timeout: .now() + 60)
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
        }
        // The plan holds the transaction now: everything below happens while it is open.
        #expect(await entered.wait(atLeast: 1, "the plan to run inside the transaction"))
        let rename = CountLatch()
        let renaming = CountLatch()
        let writer = Task {
            renaming.increment()
            try await offCooperativePool { try store.renameSpeaker(bartek, label: "Marek") }
            rename.increment()
        }
        #expect(await renaming.wait(atLeast: 1, "the rename to be issued"))
        // The rename is a write of the same store: it cannot land while the resolution's transaction is open.
        for _ in 0..<20 where rename.count == 0 {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(rename.count == 0)

        // Let the resolution finish. It saw the speaker before the rename, and its write committed first.
        release.signal()
        _ = try await resolution.value
        try await writer.value
        #expect(seen.withLock { $0.first { $0.speakerID == bartek }?.label } == "Bartek Nowak")
        // The user's write landed after it and is the one that stands.
        #expect(try rig.state(bartek)?.label == "Marek")
        #expect(try rig.state(bartek)?.source == .user)
    }
}

/// Runs a blocking call on a thread of its own and hands the outcome back, so a call that waits (a `DatabaseQueue`
/// write) never takes a cooperative-pool thread: the pool only has a handful of threads on a CI runner, and blocking
/// them starves every other test that needs one. A real `Thread` and not a `DispatchQueue` work item, which may run
/// on the pool.
private func offCooperativePool(_ body: @escaping @Sendable () throws -> Void) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        Thread {
            do {
                try body()
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
        .start()
    }
}
