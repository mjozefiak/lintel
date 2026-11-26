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

    @Test func anEmptyListThatTheUserWroteFallsBackToEnglish() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: [], isDerived: false)
        #expect(DictationPlugin.requestOptions(for: selection).whisperLanguage == .pinned("en"))
    }

    // MARK: Regression: Polish stays the Whisper dictation default until Phase 3 (owner, 2026-11-26)

    /// A user who never chose a language, on a Mac that speaks only English: the list is derived (`["en"]`), and
    /// Whisper dictation must keep getting `pl`, as it did before the shared setting.
    @Test func anUntouchedListOnAnEnglishOnlyMacKeepsWhisperDictationOnPolish() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: ["en"], isDerived: true)
        #expect(DictationPlugin.requestOptions(for: selection).whisperLanguage == .pinned("pl"))
    }

    @Test func anUntouchedListOnAnyOtherMacAlsoKeepsPolish() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: ["de", "fr"], isDerived: true)
        #expect(DictationPlugin.requestOptions(for: selection).whisperLanguage == .pinned("pl"))
    }

    /// Writing the list is a choice: a one-language English list pins English.
    @Test func aListTheUserWroteWinsOverThePolishDefault() {
        let selection = SpeechLanguageSelection(mode: .automatic, languages: ["en"], isDerived: false)
        #expect(DictationPlugin.requestOptions(for: selection).whisperLanguage == .pinned("en"))
    }

    /// The default is not a pin the user cannot undo: "Always one language" still wins.
    @Test func singleModeWinsEvenWhileTheListIsDerived() {
        let selection = SpeechLanguageSelection(mode: .single("en"), languages: ["en"], isDerived: true)
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
