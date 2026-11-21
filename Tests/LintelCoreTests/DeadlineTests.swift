import Synchronization
import Testing

@testable import LintelCore

@Suite struct DeadlineTests {
    @Test func answersWithTheWorksValueWhenItIsInTime() async {
        let value = await withDeadline(.seconds(5), clock: ContinuousClock()) { 7 }
        #expect(value == 7)
    }

    /// The work cannot finish until the test releases it, so "without waiting for it" is checked by the work's
    /// state, not by a wall-clock bound (a loaded CI runner took 1.2 s for the old 1 s bound).
    @Test func givesUpOnWorkThatOutlastsTheBudgetWithoutWaitingForIt() async {
        let (release, releaser) = AsyncStream<Void>.makeStream()
        let finished = Mutex(false)
        // If `withDeadline` ever waited for the work, this ends the wait so the test fails instead of hanging.
        let safety = Task {
            try? await Task.sleep(for: .seconds(30))
            releaser.finish()
        }
        let value = await withDeadline(.milliseconds(20), clock: ContinuousClock()) {
            for await _ in release {}
            finished.withLock { $0 = true }
            return 1
        }
        #expect(value == nil)
        #expect(!finished.withLock { $0 }, "withDeadline waited for the work to finish")
        releaser.finish()
        safety.cancel()
    }
}
