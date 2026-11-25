import Foundation
import Testing

@testable import LintelSpeech

@Suite struct LanguageProfileTests {
    private func segment(_ text: String, _ seconds: TimeInterval) -> ProfileSegment {
        ProfileSegment(text: text, duration: seconds)
    }

    @Test func aShortOrWordPoorSegmentNeverDecides() {
        #expect(!LanguageProfile.isEligible(segment(words(12), 2.9)))
        #expect(!LanguageProfile.isEligible(segment(words(9), 10)))
        #expect(LanguageProfile.isEligible(segment(words(10), 3)))

        var profile = LanguageProfile()
        let identifier = FakeIdentifier(answers: [
            words(9): LanguageGuess(code: "uk", confidence: 0.99),
            words(12, "kr"): LanguageGuess(code: "uk", confidence: 0.99),
        ])
        let tooFewWords = profile.add(segment(words(9), 10), identifier: identifier, hints: [])
        let tooShort = profile.add(segment(words(12, "kr"), 2), identifier: identifier, hints: [])
        #expect(!tooFewWords)
        #expect(!tooShort)
        #expect(profile.confidentSeconds == 0)
        #expect(profile.dominant == nil)
    }

    @Test func anUnsureGuessIsIgnored() {
        var profile = LanguageProfile()
        profile.add(LanguageGuess(code: "pl", confidence: 0.79), duration: 20)
        profile.add(LanguageGuess(code: "xx", confidence: 0.99), duration: 20)
        #expect(profile.confidentSeconds == 0)
        profile.add(LanguageGuess(code: "pl", confidence: 0.8), duration: 20)
        #expect(profile.confidentSeconds == 20)
    }

    @Test func languagesAreWeightedByDuration() {
        let spoken = confidentProfile(["pl": 30, "en": 10, "uk": 10])
        #expect(spoken.dominant == "pl")
        #expect(abs((spoken.shares["pl"] ?? 0) - 0.6) < 1e-9)
        #expect(abs((spoken.shares["en"] ?? 0) - 0.2) < 1e-9)
        #expect(spoken.confidentSeconds == 50)
    }

    @Test func aTieNeverFlips() {
        for _ in 0..<20 {
            #expect(confidentProfile(["pl": 10, "en": 10]).dominant == "en")
        }
    }

    @Test func settlesAfterThirtySecondsOfConfidentSpeech() {
        #expect(!confidentProfile(["pl": 29.9]).isSettled)
        #expect(confidentProfile(["pl": 15, "en": 15]).isSettled)
        #expect(!confidentProfile(["pl": 9.9]).isUsableForRepair)
        #expect(confidentProfile(["pl": 10]).isUsableForRepair)
    }

    @Test func aLanguageNeedsFifteenPercentToCount() {
        let spoken = confidentProfile(["pl": 85, "uk": 15])
        #expect(spoken.languages() == ["pl", "uk"])
        let small = confidentProfile(["pl": 86, "uk": 14])
        #expect(small.languages() == ["pl"])
        #expect(small.scripts() == [.latin])
        #expect(spoken.scripts() == [.latin, .cyrillic])
    }

    @Test func theScriptHintComesOnlyAfterSettlingAndOnlyForOneScript() {
        #expect(confidentProfile(["pl": 20]).scriptHint == nil)
        #expect(confidentProfile(["pl": 20, "en": 10]).scriptHint == .latin)
        #expect(confidentProfile(["uk": 40]).scriptHint == .cyrillic)
        #expect(confidentProfile(["el": 40]).scriptHint == .greek)
        // Polish and Ukrainian: a mix of scripts sends no hint.
        #expect(confidentProfile(["pl": 25, "uk": 25]).scriptHint == nil)
        // Japanese speech is never forced into a script.
        #expect(confidentProfile(["ja": 60]).scriptHint == nil)
        // A language that holds less than 15% does not spoil the hint.
        #expect(confidentProfile(["pl": 90, "uk": 10]).scriptHint == .latin)
    }

    @Test func aProfileRebuiltFromStoredTextsEqualsTheLiveOne() {
        let polish = words(12, "pl")
        let ukrainian = words(15, "uk")
        let identifier = FakeIdentifier(answers: [
            polish: LanguageGuess(code: "pl", confidence: 0.95),
            ukrainian: LanguageGuess(code: "uk", confidence: 0.9),
        ])
        let stored = [
            segment(polish, 8), segment("Tak.", 1), segment(ukrainian, 5), segment(polish, 20), segment(words(3), 9),
        ]
        var live = LanguageProfile()
        for item in stored { live.add(item, identifier: identifier, hints: ["pl"]) }
        let rebuilt = LanguageProfile.rebuilt(from: stored, identifier: identifier, hints: ["pl"])
        #expect(rebuilt == live)
        #expect(rebuilt.seconds == ["pl": 28, "uk": 5])
        #expect(rebuilt.isSettled)
    }

    @Test func theProfileHoldsNoTextOnlyCodesAndSeconds() {
        let mirror = Mirror(reflecting: LanguageProfile())
        #expect(mirror.children.map { $0.label } == ["seconds"])
    }
}
