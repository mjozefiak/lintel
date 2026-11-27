import Foundation
import LintelProviders
import LintelSpeech
import os

/// Why a chunk that went to an external provider came back raw, as far as the HUD tells the user. A closed set: the
/// provider's own words (stdout, stderr, an API error) are classified by `LintelProviders` and dropped, so no text is
/// ever carried here.
enum ProviderProblem: String, Equatable, Sendable {
    case notSignedIn
    case rateLimited
    case network
    /// Not installed, an unsupported version, a model the plan does not include, a failed start: "unavailable".
    case unavailable
}

/// Tidies a chunk through an external AI provider's CLI (spec `2026-11-25-dictation-cleanup-levels`, "Source:
/// external AI provider"): the same `CleanupPrompt`, `FormatterGuard` and per-chunk fallbacks as `BuiltInFormatter`,
/// with `ProviderRunner` instead of a local model. Never throws except on cancellation: a chunk the provider cannot
/// tidy in time comes back raw, with a closed reason.
///
/// What leaves the Mac in a request: the recognised text of the chunk and up to 300 characters of the previous chunk of
/// the SAME dictation (`<context>`, as for the local sources), flattened by the `cli1` rule the Phase 4 measurement
/// used. Never audio, never the focus context (app, field, window title), never vocabulary terms (they are applied after
/// formatting, on this Mac), clipboard or selection: this type has no access to any of them.
///
/// Every request goes through `ProviderRunner.run`, which asks `currentSelection` directly before the process starts: it
/// allows the start only while the user still has this provider chosen as the dictation source, so switching back to
/// This Mac (or removing the choice) stops the next chunk's process. The request waits on the `interactive` lane of
/// `ProviderGate`, so a long meeting-notes run never delays it.
struct ProviderFormatter: TextFormatter {
    let selection: DictationSettings.ProviderSelection
    private let runner: ProviderRunner
    private let level: DictationSettings.CleanupLevel
    private let currentSelection: @Sendable () -> DictationSettings.ProviderSelection?
    private let timeout: @Sendable (Int) -> Duration
    private let logger: Logger

    /// - Parameters:
    ///   - currentSelection: the user's choice right now, read at every authorization question, not once per session.
    ///   - timeout: how long one chunk of this many words may take at the provider (the local sources' 5 s + 0.2 s a word).
    init(
        runner: ProviderRunner, selection: DictationSettings.ProviderSelection,
        level: DictationSettings.CleanupLevel = .standard,
        currentSelection: @escaping @Sendable () -> DictationSettings.ProviderSelection?,
        timeout: @escaping @Sendable (Int) -> Duration = ProviderFormatter.timeout(forWords:),
        logger: Logger = Logger(subsystem: "com.lintelapp", category: "dictation")
    ) {
        self.runner = runner
        self.selection = selection
        self.level = level
        self.currentSelection = currentSelection
        self.timeout = timeout
        self.logger = logger
    }

    static func timeout(forWords words: Int) -> Duration {
        .seconds(LocalLLMFormatter.timeout(forWords: words))
    }

    func format(chunk: String, previousContext: String?) async throws -> FormatResult {
        let raw = FormatResult.raw(chunk)
        let words = FormatterGuard.words(in: chunk)
        let request = ProviderRequest(
            provider: selection.provider, feature: .dictationCleanup, model: selection.model,
            messages: Self.messages(chunk: chunk, context: previousContext, level: level), timeout: timeout(words),
            lane: .interactive)
        let provider = selection.provider
        let model = selection.model
        let current = currentSelection
        let authorization: ProviderAuthorization = {
            guard let chosen = current() else { return .denied(.noConsent) }
            guard chosen.provider == provider else { return .denied(.otherProvider) }
            return chosen.model == model ? .allowed : .denied(.otherModel)
        }
        let result: GenerationResult
        do {
            result = try await runner.run(request, authorization: authorization)
        } catch let error as ProviderError {
            if error == .cancelled { throw CancellationError() }
            let reason = Self.reason(for: error)
            // Only the closed reason, never the provider's words.
            logger.error("The provider did not tidy a chunk: \(String(describing: reason), privacy: .public)")
            return raw.falling(reason)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            logger.error("The provider failed: \(String(describing: type(of: error)), privacy: .public)")
            return raw.falling(.provider(.unavailable))
        }
        try Task.checkCancellation()
        guard !result.stoppedByTokenLimit else { return raw.falling(.badResponse) }
        switch FormatterGuard.check(input: chunk, output: result.text, level: level) {
        case .accepted(let text):
            return FormatResult(text: text, outcome: .formatted)
        case .rejected(let reason):
            logger.info("A tidied chunk was rejected: \(String(describing: reason), privacy: .public)")
            return raw.falling(.rejected(reason))
        }
    }

    /// What the user is told. A refusal (the choice was withdrawn while the dictation ran) says nothing: the user did
    /// that themselves. A timeout of the process is "too slow", like the deadline after the key release.
    static func reason(for error: ProviderError) -> FallbackReason {
        switch error {
        case .notAuthorized: .notConfigured
        case .timedOut: .tooSlow
        case .outputTooLarge: .badResponse
        case .failed(let failure):
            switch failure {
            case .notSignedIn: .provider(.notSignedIn)
            case .rateLimited: .provider(.rateLimited)
            case .network: .provider(.network)
            case .incompatibleVersion, .modelNotAvailable, .other: .provider(.unavailable)
            }
        case .cancelled, .notInstalled, .isolationNotVerified, .isolationProblem, .unsupportedProvider, .invalidModel,
            .invalidRequest, .launchFailed:
            .provider(.unavailable)
        }
    }

    // MARK: What is sent

    /// The request's messages for a command-line provider: the level's system prompt goes to argv (our static text), the
    /// examples and this transcript to stdin, flattened with the `cli1` rule of Meetings' `ProviderPromptSerializer`
    /// (the one the Phase 4 measurement used): a `<user>` or `<assistant>` block per turn, with a block marker in the
    /// content removed, so the content cannot close a block. The content is exactly `CleanupPrompt.messages(…level:)`.
    static func messages(
        chunk: String, context: String?, level: DictationSettings.CleanupLevel
    ) -> [ChatMessage] {
        let chat = CleanupPrompt.messages(transcript: chunk, context: context, level: level)
        let system = chat.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
        let input = chat.filter { $0.role != "system" }.map { message -> String in
            let role = message.role == "assistant" ? "assistant" : "user"
            return "<\(role)>\n\(strippingBlockMarkers(message.content))\n</\(role)>"
        }.joined(separator: "\n")
        return [ChatMessage(role: "system", content: system), ChatMessage(role: "user", content: input)]
    }

    private static func strippingBlockMarkers(_ text: String) -> String {
        var result = text
        while true {
            let next = result.replacing(/(?i)<\s*\/?\s*(?:user|assistant)\b[^<>]*>/, with: "")
            if next == result { return result }
            result = next
        }
    }
}

extension FormatResult {
    fileprivate func falling(_ reason: FallbackReason) -> FormatResult {
        FormatResult(text: text, outcome: .fellBack(reason))
    }
}
