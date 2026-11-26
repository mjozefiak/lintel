import Foundation
import LintelKit
import LintelSpeech
import Testing

@testable import DictationPlugin

/// Spec `2026-11-23-automatic-language-detection`, step 2.3: Dictation reads the shared setting and sends its
/// options with every request. Whisper is pinned to the single language or the first listed one; Parakeet gets no
/// hint (automatic dictation is Phase 3).
@Suite struct DictationLanguageTests {
    private let second = AudioFormat.sampleRate

    @Test func automaticPinsWhisperToTheFirstListedLanguageAndSendsNoHint() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: ["uk", "pl"], isDerived: false)
        #expect(
            DictationPlugin.requestOptions(for: selection)
                == SpeechRequestOptions(scriptHint: nil, whisperLanguage: .pinned("uk")))
    }

    @Test func singleModePinsWhisperToThatLanguageAndStillSendsNoHint() {
        let selection = SpeechLanguageSelection(mode: .single("el"), languages: ["pl", "en"], isDerived: false)
        #expect(
            DictationPlugin.requestOptions(for: selection)
                == SpeechRequestOptions(scriptHint: nil, whisperLanguage: .pinned("el")))
    }

    @Test func anEmptyListFallsBackToEnglish() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: [], isDerived: true)
        #expect(DictationPlugin.requestOptions(for: selection).whisperLanguage == .pinned("en"))
    }

    /// The options reach the engine with every segment of the dictation, through the lease.
    @Test func everySegmentIsSentWithTheDictationsOptions() async throws {
        let engine = FakeEngine()
        let options = SpeechRequestOptions(whisperLanguage: .pinned("uk"))
        let ranges = [second..<(2 * second), (3 * second)..<(4 * second)]
        let session = DictationSession(
            audio: ScriptedAudioInput(seconds: 5), vad: RangeVAD(ranges), engine: engine,
            modelFolder: URL(filePath: "/tmp/none"), lease: SpeechEngineLease(), options: options)
        try await session.start()
        _ = try await session.finish()
        #expect(engine.state.withLock { $0.options } == [options, options])
    }
}
