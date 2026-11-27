import Foundation
import LintelSpeech
import Testing

@testable import DictationPlugin
@testable import LintelProviders

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 5 (risk-high): what the provider receives is the spoken chunk and
/// the fixed instructions, nothing else. The vocabulary replaces terms AFTER the tidying, so a term the user keeps there
/// (a name, a client, a codeword) never leaves the Mac. Checked through the real `DictationSession`, not the formatter alone.
@Suite(.timeLimit(.minutes(1))) struct ProviderSessionPrivacyTests {
    private static let second = AudioFormat.sampleRate
    private static let canary = "CANARY-VOCAB"

    private final class OneWordEngine: SpeechEngine, @unchecked Sendable {
        var isLoaded: Bool { true }
        func load(modelFolder: URL) async throws {}
        func transcribe(_ samples: [Float]) async throws -> TranscriptSegment {
            TranscriptSegment(text: "umów spotkanie z kanarek jutro rano")
        }
        func unload() async {}
    }

    private static func tidy(_ spec: ProviderProcessSpec) -> String {
        let input = String(decoding: spec.stdin, as: UTF8.self)
        let transcript =
            input.components(separatedBy: "<transcript>").last?
            .components(separatedBy: "</transcript>").first ?? ""
        return transcript.prefix(1).uppercased() + transcript.dropFirst() + "."
    }

    @Test func aVocabularyTermIsAppliedAfterTheProviderAndNeverSentToIt() async throws {
        let process = FakeProviderProcess { _, spec in FakeProviderProcess.output(answer: Self.tidy(spec)) }
        let selection = DictationSettings.ProviderSelection(provider: .claudeCode, model: "sonnet")
        let formatter = ProviderFormatter(
            runner: FakeProviderProcess.runner(process), selection: selection, level: .standard,
            currentSelection: { selection })
        let second = Self.second
        let canary = Self.canary
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 4), vad: RangeVAD([second..<(2 * second)]), engine: OneWordEngine(),
            formatter: formatter,
            replaceTerms: { $0.replacingOccurrences(of: "kanarek", with: canary) },
            modelFolder: URL(filePath: "/tmp/none"))
        try await session.start()
        let output = try await session.finish()

        #expect(output.text.contains(canary))
        #expect(process.contentRuns >= 1)
        for spec in process.specs {
            #expect(!String(decoding: spec.stdin, as: UTF8.self).contains(canary))
            #expect(!spec.arguments.joined(separator: " ").contains(canary))
        }
    }
}
