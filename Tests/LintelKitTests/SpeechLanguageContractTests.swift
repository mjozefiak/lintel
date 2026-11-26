import Foundation
import LintelKit
import Testing

/// Spec `2026-11-23-automatic-language-detection`, step 2.1: the shared language port is additive, and a context
/// built without a host gets Automatic with English.
@Suite struct SpeechLanguageContractTests {
    @Test func aContextWithoutAHostGetsAutomaticWithEnglish() {
        let context = TestContext.make()
        let selection = context.speechLanguages.current()
        #expect(selection == SpeechLanguageSelection(mode: .automatic, languages: ["en"], isDerived: true))
    }

    @Test func fixedSettingsIgnoreUpdates() {
        let fixed = FixedSpeechLanguageSettings(.single("pl"), ["pl", "en"])
        fixed.update(SpeechLanguageSelection(mode: .automatic, languages: ["uk"], isDerived: false))
        #expect(
            fixed.current() == SpeechLanguageSelection(mode: .single("pl"), languages: ["pl", "en"], isDerived: true))
    }

    @Test func fixedSettingsChangesFinishAtOnceAndEveryReadIsANewStream() async {
        let fixed = FixedSpeechLanguageSettings()
        var first = fixed.changes.makeAsyncIterator()
        var second = fixed.changes.makeAsyncIterator()
        #expect(await first.next() == nil)
        #expect(await second.next() == nil)
    }
}
