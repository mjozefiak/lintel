import Foundation
import LintelProviders
import Synchronization

@testable import DictationPlugin
@testable import LintelProviders

/// A fake provider process for the dictation tests: counts the starts that carry content, keeps what each one was
/// given and answers with a closure. Nothing real starts (the runner gets a `ProviderSystem` over this process and a
/// locator that finds a fake binary).
final class FakeProviderProcess: ProviderProcessRunning, @unchecked Sendable {
    typealias Handler = @Sendable (_ call: Int, _ spec: ProviderProcessSpec) async throws -> ProviderProcessOutput

    private let state = Mutex((specs: [ProviderProcessSpec](), probes: 0, cancelled: 0))
    private let handler: Handler

    init(handler: @escaping Handler) { self.handler = handler }

    /// Answers every request with the same text.
    convenience init(answer: String) {
        self.init { _, _ in Self.output(answer: answer) }
    }

    var contentRuns: Int { state.withLock { $0.specs.count } }
    var probeRuns: Int { state.withLock { $0.probes } }
    var specs: [ProviderProcessSpec] { state.withLock { $0.specs } }
    /// How many started runs ended by cancellation (a limit that fired, a dictation that was cancelled).
    var cancelledRuns: Int { state.withLock { $0.cancelled } }

    func runContent(_ spec: ProviderProcessSpec) async throws -> ProviderProcessOutput {
        let call = state.withLock { state -> Int in
            state.specs.append(spec)
            return state.specs.count
        }
        do {
            return try await handler(call, spec)
        } catch {
            if error is CancellationError { state.withLock { $0.cancelled += 1 } }
            throw error
        }
    }

    func runProbe(_ spec: ProviderProcessSpec) async throws -> ProviderProcessOutput {
        state.withLock { $0.probes += 1 }
        return Self.output(answer: "ok")
    }

    static func output(answer: String, isError: Bool = false) -> ProviderProcessOutput {
        let payload: [String: Any] = ["type": "result", "is_error": isError, "result": answer]
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return ProviderProcessOutput(stdout: data, stderr: Data(), exitCode: 0, ending: .exited)
    }

    /// A runner whose descriptor passed the isolation canary, over `process`, with its own gate (so a test never waits
    /// for another test's run).
    static func runner(_ process: FakeProviderProcess, verified: Bool = true) -> ProviderRunner {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "provider-dictation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return ProviderRunner(
            system: ProviderSystem(locator: QuietProviderLocator(), process: process),
            descriptors: [ProviderDescriptor.claudeCode.with(isolationVerified: verified)],
            cachesDirectory: directory, gate: ProviderGate())
    }
}
