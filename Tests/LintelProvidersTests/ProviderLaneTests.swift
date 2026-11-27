import Foundation
import LintelSpeech
import LintelTestSupport
import Synchronization
import Testing

@testable import LintelProviders

/// The runner puts a request in the lane it names (spec `2026-11-25-dictation-cleanup-levels`, Phase 5, step 1): a
/// `background` run that holds the provider (a whole-transcript meeting-notes run) does not delay an `interactive`
/// one (a dictation chunk), the status probe can ask on either lane, and a request that names no lane behaves as it
/// did before lanes existed.
@Suite(.timeLimit(.minutes(1))) struct ProviderLaneTests {
    /// Holds the first content process until the test lets it go; every later one answers at once.
    private final class FirstRunHeld: ProviderProcessRunning, @unchecked Sendable {
        let entered = Latch()
        let release = Latch()
        private let calls = Mutex(0)
        private let order = Mutex<[String]>([])

        var finishedOrder: [String] { order.withLock { $0 } }

        func runContent(_ spec: ProviderProcessSpec) async throws -> ProviderProcessOutput {
            let call = calls.withLock { value -> Int in
                value += 1
                return value
            }
            if call == 1 {
                entered.open()
                await release.wait()
            }
            order.withLock { $0.append("run \(call)") }
            return Self.answer
        }

        func runProbe(_ spec: ProviderProcessSpec) async throws -> ProviderProcessOutput {
            order.withLock { $0.append("probe") }
            return ProviderProcessOutput(
                stdout: Data("2.1.329 (Claude Code)".utf8), stderr: Data(), exitCode: 0, ending: .exited)
        }

        static let answer = ProviderProcessOutput(
            stdout: Data(#"{"type":"result","is_error":false,"result":"ok"}"#.utf8), stderr: Data(), exitCode: 0,
            ending: .exited)
    }

    private func runner(_ process: FirstRunHeld) -> ProviderRunner {
        ProviderRunner(
            system: ProviderSystem(locator: QuietProviderLocator(), process: process),
            descriptors: [ProviderDescriptor.claudeCode.with(isolationVerified: true)],
            cachesDirectory: URL(filePath: NSTemporaryDirectory()).appending(path: "providers-lanes-\(UUID())"),
            gate: ProviderGate())
    }

    private func request(_ lane: ProviderLane?) -> ProviderRequest {
        let messages = [
            ChatMessage(role: "system", content: "Tidy up."), ChatMessage(role: "user", content: syntheticCanary),
        ]
        guard let lane else { return ProviderRequest(feature: .dictationCleanup, model: "sonnet", messages: messages) }
        return ProviderRequest(feature: .dictationCleanup, model: "sonnet", messages: messages, lane: lane)
    }

    @Test func anInteractiveRunDoesNotWaitForABackgroundRun() async throws {
        let process = FirstRunHeld()
        let runner = runner(process)
        let background = Task { try await runner.run(request(.background), authorization: allowed) }
        guard await process.entered.wait(guard: .seconds(10), "the background run to be in its process") else {
            return background.cancel()
        }
        // The background run holds the provider's background slot; this one is in the other lane and must finish.
        let interactive = try await runner.run(request(.interactive), authorization: allowed)
        #expect(interactive.text == "ok")
        #expect(process.finishedOrder == ["run 2"], "the background run is still held, the interactive one is done")
        process.release.open()
        _ = try await background.value
        #expect(process.finishedOrder == ["run 2", "run 1"])
    }

    @Test func aRequestWithoutALaneWaitsBehindABackgroundRun() async throws {
        let process = FirstRunHeld()
        let runner = runner(process)
        let background = Task { try await runner.run(request(.background), authorization: allowed) }
        guard await process.entered.wait(guard: .seconds(10), "the background run to be in its process") else {
            return background.cancel()
        }
        let defaulted = Task { try await runner.run(request(nil), authorization: allowed) }
        // A request that names no lane is a background one: it queues. A short, bounded look at the process shows it
        // has not started (no sleep orders anything: the first run is still held by the latch).
        #expect(await pollUntil("the default-lane request to queue", guard: .seconds(10)) { true })
        #expect(process.finishedOrder.isEmpty)
        process.release.open()
        _ = try await background.value
        _ = try await defaulted.value
        #expect(process.finishedOrder == ["run 1", "run 2"], "first in, first out inside one lane")
    }

    @Test func theStatusProbeCanAskOnTheInteractiveLane() async throws {
        let process = FirstRunHeld()
        let runner = runner(process)
        let background = Task { try await runner.run(request(.background), authorization: allowed) }
        guard await process.entered.wait(guard: .seconds(10), "the background run to be in its process") else {
            return background.cancel()
        }
        // The two probes of the report wait in the lane they are given: on the interactive one they do not wait for
        // the background run, so a check of the provider's state in Settings is never stuck behind a notes job.
        let report = await runner.report(of: .claudeCode, lane: .interactive)
        #expect(report.version == "2.1.329")
        #expect(process.finishedOrder.contains("probe"))
        process.release.open()
        _ = try await background.value
    }
}
