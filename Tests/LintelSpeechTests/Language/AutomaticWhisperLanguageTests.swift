import Foundation
import Testing

@testable import LintelSpeech

/// Spec `2026-11-23-automatic-language-detection`, step 2.5: Whisper's language per segment in Automatic mode.
@Suite struct AutomaticWhisperLanguageTests {
    private func profile(_ spoken: KeyValuePairs<String, TimeInterval>) -> LanguageProfile {
        var profile = LanguageProfile()
        for (code, seconds) in spoken { profile.add(LanguageGuess(code: code, confidence: 0.95), duration: seconds) }
        return profile
    }

    private let long = AutomaticWhisperLanguage.minimumDetectionDuration
    private let short = AutomaticWhisperLanguage.minimumDetectionDuration - 0.1

    @Test func theConstantsAreTheSpecsAndTheEngines() {
        #expect(AutomaticWhisperLanguage.minimumDetectionDuration == 3)
        #expect(AutomaticWhisperLanguage.minimumDetectionDuration == LanguageProfile.minimumDuration)
        #expect(AutomaticWhisperLanguage.recheckInterval == 10)
    }

    @Test func beforeTheProfileSettlesALongSegmentIsDetectedAmongTheList() {
        var whisper = AutomaticWhisperLanguage()
        // No profile yet: the fallback is the first listed language.
        #expect(
            whisper.choice(duration: long, languages: ["pl", "en"], profile: LanguageProfile())
                == .detect(candidates: ["pl", "en"], fallback: "pl"))
        // An unsettled profile: its dominant language is the fallback.
        let unsettled = profile(["en": 12])
        #expect(!unsettled.isSettled)
        #expect(
            whisper.choice(duration: 20, languages: ["pl", "en"], profile: unsettled)
                == .detect(candidates: ["pl", "en"], fallback: "en"))
        // The counter runs only after settling.
        #expect(whisper.longSegmentsSinceSettled == 0)
    }

    @Test func aShortSegmentIsNeverDetected() {
        var whisper = AutomaticWhisperLanguage()
        #expect(whisper.choice(duration: short, languages: ["pl", "en"], profile: LanguageProfile()) == .pinned("pl"))
        #expect(whisper.choice(duration: 0.4, languages: ["pl", "en"], profile: profile(["en": 12])) == .pinned("en"))
        #expect(whisper.choice(duration: 1, languages: [], profile: LanguageProfile()) == .pinned("en"))
        let settled = profile(["uk": 40])
        for _ in 0..<25 {
            #expect(whisper.choice(duration: short, languages: ["pl", "uk"], profile: settled) == .pinned("uk"))
        }
        // Short segments do not count towards the re-check.
        #expect(whisper.longSegmentsSinceSettled == 0)
    }

    @Test func afterSettlingLongSegmentsArePinnedAndEveryTenthIsCheckedAgain() {
        var whisper = AutomaticWhisperLanguage()
        let settled = profile(["pl": 40, "en": 5])
        #expect(settled.isSettled)
        let choices = (1...30).map { _ in whisper.choice(duration: 8, languages: ["pl", "en"], profile: settled) }
        let detect = WhisperLanguageChoice.detect(candidates: ["pl", "en"], fallback: "pl")
        for (index, choice) in choices.enumerated() {
            let number = index + 1
            #expect(choice == (number.isMultiple(of: 10) ? detect : .pinned("pl")), "long segment \(number)")
        }
        #expect(whisper.longSegmentsSinceSettled == 30)
    }

    /// The profile is identified against the whole catalog, so a settled Ukrainian meeting with a Polish and English
    /// list is checked again with Ukrainian among the candidates; it is not re-detected as Polish every time.
    @Test func theDominantLanguageJoinsTheCandidatesWhenTheListLacksIt() {
        let ukrainian = profile(["uk": 15])
        #expect(
            AutomaticWhisperLanguage.candidates(languages: ["pl", "en"], profile: ukrainian) == ["pl", "en", "uk"])
        #expect(AutomaticWhisperLanguage.candidates(languages: ["uk", "pl"], profile: ukrainian) == ["uk", "pl"])
        var whisper = AutomaticWhisperLanguage()
        #expect(
            whisper.choice(duration: long, languages: ["pl", "en"], profile: ukrainian)
                == .detect(candidates: ["pl", "en", "uk"], fallback: "uk"))
    }

    @Test func oneCandidateIsPinnedWithoutADetection() {
        var whisper = AutomaticWhisperLanguage()
        #expect(whisper.choice(duration: 20, languages: ["pl"], profile: LanguageProfile()) == .pinned("pl"))
        #expect(whisper.choice(duration: 20, languages: ["pl"], profile: profile(["pl": 12])) == .pinned("pl"))
        // Codes Whisper does not know are no candidates.
        #expect(whisper.choice(duration: 20, languages: ["pl", "xx"], profile: LanguageProfile()) == .pinned("pl"))
    }
}
