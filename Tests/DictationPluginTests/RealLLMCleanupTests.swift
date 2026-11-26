import Foundation
import Testing

@testable import DictationPlugin
@testable import LintelSpeech

@Suite struct RealLLMCleanupTests {
    /// Loads the GGUF in `LINTEL_LLAMA_MODEL` and cleans a Polish dictation with the real prompt. Off by default,
    /// like the other real-model tests (ADR 0005).
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINTEL_LLAMA_MODEL"] != nil))
    func realModel() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINTEL_LLAMA_MODEL"])
        let runtime = LlamaRuntime()
        let loadStarted = ContinuousClock.now
        try await runtime.load(modelAt: URL(fileURLWithPath: path))
        print("[llama] load \(ContinuousClock.now - loadStarted)")
        #expect(await runtime.isLoaded)

        let transcript = "yyy no więc jutro mamy spotkanie o dziesiątej nie to znaczy o jedenastej w biurze"
        let messages = CleanupPrompt.messages(transcript: transcript, context: nil)
        for run in ["first", "second"] {
            let started = ContinuousClock.now
            let text = try await runtime.generate(messages: messages, maxTokens: 96)
            print("[llama] \(run) request \(ContinuousClock.now - started): \(text)")
            #expect(!text.isEmpty)
            #expect(text.localizedCaseInsensitiveContains("jedenastej") || text.contains("11"))
            #expect(FormatterGuard.check(input: transcript, output: text) != .rejected(.empty))
        }

        // Cancelling stops the decode and leaves the runtime usable.
        let task = Task { try await runtime.generate(messages: messages, maxTokens: 512) }
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        #expect(try await runtime.generate(messages: messages, maxTokens: 96).isEmpty == false)

        await runtime.unload()
        #expect(await runtime.isLoaded == false)
    }

    /// The context keeps the start of the prompt between requests: the answer after another transcript must be
    /// the one a fresh context gives, and a repeated request must not change it either.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LINTEL_LLAMA_MODEL"] != nil))
    func aReusedPromptStartGivesTheSameAnswer() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["LINTEL_LLAMA_MODEL"])
        let runtime = LlamaRuntime()
        try await runtime.load(modelAt: URL(fileURLWithPath: path))
        let first = CleanupPrompt.messages(
            transcript: "yyy no więc jutro mamy spotkanie o dziesiątej nie to znaczy o jedenastej w biurze",
            context: nil)
        let second = CleanupPrompt.messages(
            transcript: "um we should we should ship on friday no wait thursday", context: "Plan na tydzień.")
        _ = try await runtime.generate(messages: first, maxTokens: 96)
        let reused = try await runtime.generate(messages: second, maxTokens: 96)
        let again = try await runtime.generate(messages: second, maxTokens: 96)
        try await runtime.load(modelAt: URL(fileURLWithPath: path))
        let fresh = try await runtime.generate(messages: second, maxTokens: 96)
        #expect(reused == fresh)
        #expect(again == fresh)
        await runtime.unload()
    }
}
