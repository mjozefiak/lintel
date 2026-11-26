import Foundation
import Testing

@testable import LintelSpeech

/// A synthetic segment table modelled on the length buckets of #132 (no real meeting text): the wrong segments
/// are short, the long ones are right.
@Suite struct SuspectSegmentPolicyTests {
    private let policy = SuspectSegmentPolicy(identifier: FakeIdentifier())
    /// Polish meeting with some English: 50 s of Polish, 10 s of English (16.7%).
    private let polishWithEnglish = confidentProfile(["pl": 50, "en": 10])

    private func segment(_ text: String, _ seconds: TimeInterval) -> ProfileSegment {
        ProfileSegment(text: text, duration: seconds)
    }

    @Test func aLongSegmentIsNeverSuspectEvenInAnotherScript() {
        #expect(!policy.isSuspect(segment(words(12, "дякую"), 5), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment("Thank you. Thank you. Thank you.", 2.5), profile: polishWithEnglish))
        // Three words but 3 s: the shortness is "at most 3 words OR at most 2 s", so this one is short.
        #expect(policy.isSuspect(segment("Дякую вам усім", 3), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment(words(4, "дякую"), 2.1), profile: polishWithEnglish))
    }

    @Test func aShortSegmentInAScriptOutsideTheProfileIsSuspect() {
        #expect(policy.isSuspect(segment("Дякую.", 1.2), profile: polishWithEnglish))
        #expect(policy.isSuspect(segment("ありがとう", 1), profile: polishWithEnglish))
    }

    @Test func aMixedScriptMeetingKeepsItsShortCyrillicSegments() {
        let mixed = confidentProfile(["pl": 30, "uk": 30])
        #expect(!policy.isSuspect(segment("Дякую.", 1.2), profile: mixed))
        #expect(!policy.isSuspect(segment("Dziękuję.", 1.2), profile: mixed))
    }

    @Test func englishFillerIsSuspectOnlyWhileTheMeetingIsNotEnglish() {
        #expect(policy.isSuspect(segment("Thank you.", 1), profile: polishWithEnglish))
        #expect(policy.isSuspect(segment("Yeah.", 0.8), profile: polishWithEnglish))
        #expect(policy.isSuspect(segment("Yeah, yeah", 1.4), profile: polishWithEnglish))
        let english = confidentProfile(["en": 50, "pl": 10])
        #expect(!policy.isSuspect(segment("Thank you.", 1), profile: english))
        // Polish filler in a Polish meeting is what people say.
        #expect(!policy.isSuspect(segment("Dziękuję.", 1), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment("Tak.", 0.7), profile: polishWithEnglish))
    }

    @Test func realEnglishInAPolishMeetingStaysBecauseItIsLong() {
        let english = segment("Let me share my screen for a second", 3.4)
        #expect(!policy.isSuspect(english, profile: polishWithEnglish))
    }

    @Test func aConfidentLanguageOutsideTheProfileMakesAShortSegmentSuspect() {
        let identifier = FakeIdentifier(answers: [
            "Guten Tag": LanguageGuess(code: "de", confidence: 0.92),
            "Czesc": LanguageGuess(code: "cs", confidence: 0.5),
            "Hola": LanguageGuess(code: "pl", confidence: 0.99),
        ])
        let policy = SuspectSegmentPolicy(identifier: identifier)
        #expect(policy.isSuspect(segment("Guten Tag", 1.5), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment("Czesc", 1.5), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment("Hola", 1.5), profile: polishWithEnglish))
    }

    @Test func fillerThatIsAlsoFillerInTheMeetingsLanguageIsLeftAlone() {
        // "OK" and "Mhm" are Polish filler too: a correct short segment must not be decoded again and overwritten.
        #expect(!policy.isSuspect(segment("OK.", 0.6), profile: polishWithEnglish))
        #expect(!policy.isSuspect(segment("Mhm", 0.5), profile: polishWithEnglish))
        #expect(policy.isSuspect(segment("Thank you.", 0.9), profile: polishWithEnglish))
    }

    @Test func aProfileWithLessThanTenSecondsIsNotUsedToRewriteAnything() {
        #expect(!policy.isSuspect(segment("Дякую.", 1), profile: confidentProfile(["pl": 9.9])))
        #expect(policy.isSuspect(segment("Дякую.", 1), profile: confidentProfile(["pl": 10])))
        #expect(!policy.isSuspect(segment("Thank you.", 1), profile: confidentProfile(["pl": 9.9])))
        #expect(policy.isSuspect(segment("Thank you.", 1), profile: confidentProfile(["pl": 10])))
    }

    @Test func theIdentifierIsAskedWithoutHintsBecauseAHintMakesEveryShortTextLookLikeTheProfile() {
        let identifier = FakeIdentifier()
        let policy = SuspectSegmentPolicy(identifier: identifier)
        _ = policy.isSuspect(segment("Guten Tag", 1.5), profile: polishWithEnglish)
        _ = policy.acceptsReplacement("Guten Tag", profile: polishWithEnglish)
        let seen = identifier.hintsSeen.withLock { $0 }
        #expect(seen.count == 2)
        #expect(seen.allSatisfy { $0.isEmpty })
    }

    @Test func nothingIsSuspectWithoutAProfile() {
        #expect(!policy.isSuspect(segment("Thank you.", 1), profile: LanguageProfile()))
        #expect(!policy.isSuspect(segment("Дякую.", 1), profile: LanguageProfile()))
    }

    @Test func aSegmentWithoutLettersHasNoScriptAndIsLeftAlone() {
        #expect(!policy.isSuspect(segment("...", 1), profile: polishWithEnglish))
    }

    // MARK: Accepting a new decoding

    @Test func aReplacementInTheProfilesScriptIsAccepted() {
        #expect(policy.acceptsReplacement("Dobrze, zróbmy to jutro", profile: polishWithEnglish))
        #expect(policy.acceptsReplacement("Follow-up", profile: polishWithEnglish))
    }

    @Test func aReplacementInAnotherScriptOrWithoutLettersIsRefused() {
        #expect(!policy.acceptsReplacement("Дякую за увагу", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("...", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Dobrze", profile: LanguageProfile()))
    }

    @Test func aReplacementOnAnyBackChannelOrHallucinationListIsRefusedTheDominantLanguageIncluded() {
        // Whisper pinned to Polish answers noise with Polish filler: it would "agree" with the profile.
        #expect(!policy.acceptsReplacement("Dziękuję.", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Dzięki", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Thank you.", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Danke", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Napisy stworzone przez społeczność Amara.org", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Thanks for watching!", profile: polishWithEnglish))
        #expect(!policy.acceptsReplacement("Tak tak tak", profile: polishWithEnglish))
    }

    @Test func theIdentifierMayVetoAReplacementButNeverApproveIt() {
        let identifier = FakeIdentifier(answers: [
            "Guten Abend zusammen": LanguageGuess(code: "de", confidence: 0.95),
            "Wieczór dobry": LanguageGuess(code: "pl", confidence: 0.99),
            "Krótko": LanguageGuess(code: "de", confidence: 0.4),
        ])
        let policy = SuspectSegmentPolicy(identifier: identifier)
        #expect(!policy.acceptsReplacement("Guten Abend zusammen", profile: polishWithEnglish))
        #expect(policy.acceptsReplacement("Wieczór dobry", profile: polishWithEnglish))
        // Unsure about a short text: it passes.
        #expect(policy.acceptsReplacement("Krótko", profile: polishWithEnglish))
        // Nothing known about the text: it passes too (the other three conditions already held).
        #expect(policy.acceptsReplacement("Nieznane zdanie", profile: polishWithEnglish))
    }

    /// The refusal carries the same rule as a closed code, for the repair's counts (issue #315): what
    /// `acceptsReplacement` refuses gets a reason, and what it accepts gets none.
    @Test func aRefusedReplacementSaysWhichConditionRefusedIt() {
        let identifier = FakeIdentifier(answers: ["Guten Abend zusammen": LanguageGuess(code: "de", confidence: 0.95)])
        let policy = SuspectSegmentPolicy(identifier: identifier)
        #expect(policy.replacementRefusal("Дякую за увагу", profile: polishWithEnglish) == .script)
        #expect(policy.replacementRefusal("", profile: polishWithEnglish) == .script)
        #expect(policy.replacementRefusal("Thank you.", profile: polishWithEnglish) == .phrase)
        #expect(policy.replacementRefusal("Guten Abend zusammen", profile: polishWithEnglish) == .outsideProfile)
        #expect(policy.replacementRefusal("Wieczór dobry", profile: polishWithEnglish) == nil)
        #expect(policy.replacementRefusal("Follow-up", profile: polishWithEnglish) == nil)
        // Every refusal code is reachable, so none is dead and the repair's counts cover the rule.
        let refused = ["Дякую", "Thank you.", "Guten Abend zusammen"].compactMap {
            policy.replacementRefusal($0, profile: polishWithEnglish)
        }
        #expect(Set(refused) == Set(SuspectSegmentPolicy.ReplacementRefusal.allCases))
    }
}

@Suite struct BackChannelPhrasesTests {
    @Test func normalizationIgnoresCasePunctuationAndAccents() {
        #expect(BackChannelPhrases.normalize("  Dziękuję!! ") == "dziekuje")
        #expect(BackChannelPhrases.normalize("Thank-you,  THANK you.") == "thank you thank you")
        #expect(BackChannelPhrases.normalize("Łódź") == "lodz")
    }

    @Test func aBackChannelIsAWholeUtteranceOrOneRepeated() {
        #expect(BackChannelPhrases.isBackChannel("Thank you.", language: "en"))
        #expect(BackChannelPhrases.isBackChannel("thank you thank you", language: "en"))
        #expect(BackChannelPhrases.isBackChannel("Yeah, yeah, yeah", language: "en"))
        #expect(!BackChannelPhrases.isBackChannel("Thank you for the update on the budget", language: "en"))
        #expect(!BackChannelPhrases.isBackChannel("Yeah no", language: "en"))
        #expect(!BackChannelPhrases.isBackChannel("", language: "en"))
        #expect(BackChannelPhrases.isBackChannel("Dziękuję", language: "pl"))
        #expect(!BackChannelPhrases.isBackChannel("Dziękuję", language: "en"))
        #expect(!BackChannelPhrases.isBackChannel("anything", language: "xx"))
    }

    @Test func theRealFrenchAndGermanHallucinationsAreFound() {
        #expect(BackChannelPhrases.isHallucination("Sous-titres réalisés par la communauté d'Amara.org"))
        #expect(BackChannelPhrases.isHallucination("Untertitel der Amara.org-Community"))
    }

    @Test func hallucinationsAreFoundInsideALongerText() {
        #expect(BackChannelPhrases.isHallucination("Okay. Thanks for watching!"))
        #expect(BackChannelPhrases.isHallucination("Продолжение следует..."))
        #expect(!BackChannelPhrases.isHallucination("We should watch the budget"))
        #expect(!BackChannelPhrases.isHallucination(""))
    }

    @Test func everyListedPhraseMatchesItself() {
        for (language, phrases) in BackChannelPhrases.backChannel {
            for phrase in phrases {
                #expect(BackChannelPhrases.isBackChannel(phrase, language: language), "\(language): \(phrase)")
            }
        }
        for phrases in BackChannelPhrases.hallucinations.values {
            for phrase in phrases { #expect(BackChannelPhrases.isHallucination(phrase), "\(phrase)") }
        }
    }
}
