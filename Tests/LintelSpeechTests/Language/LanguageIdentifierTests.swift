import Foundation
import Testing

@testable import LintelSpeech

/// Invented sentences (no real meeting or dictation text) through Apple's recogniser.
@Suite struct NaturalLanguageIdentifierTests {
    private let identifier = NaturalLanguageIdentifier()
    private let hints = ["pl", "en"]

    private static let samples: [(code: String, text: String)] = [
        (
            "pl",
            "Wczoraj wieczorem rozmawialiśmy o tym, jak przygotować prezentację dla nowego klienta na przyszły tydzień."
        ),
        ("en", "Yesterday evening we talked about how to prepare the presentation for the new client next week."),
        ("uk", "Вчора ввечері ми говорили про те, як підготувати презентацію для нового клієнта на наступний тиждень."),
        ("ru", "Вчера вечером мы говорили о том, как подготовить презентацию для нового клиента на следующей неделе."),
        (
            "el",
            "Χθες το βράδυ μιλήσαμε για το πώς θα ετοιμάσουμε την παρουσίαση για τον νέο πελάτη την επόμενη εβδομάδα."
        ),
        ("ja", "昨日の夜、来週の新しいお客様向けのプレゼンテーションをどう準備するかについて話しました。"),
    ]

    @Test(arguments: samples)
    func aLongSentenceIsRecognised(sample: (code: String, text: String)) {
        let guess = identifier.identify(sample.text, hints: hints, constraints: nil)
        #expect(guess?.code == sample.code)
        #expect((guess?.confidence ?? 0) >= LanguageProfile.minimumConfidence)
    }

    @Test func aConstraintLimitsTheAnswerToTheListedLanguages() {
        // Ukrainian text, but only Polish and Russian allowed: the answer is one of those, never Ukrainian.
        let guess = identifier.identify(Self.samples[2].text, hints: [], constraints: ["pl", "ru"])
        #expect(guess == nil || ["pl", "ru"].contains(guess?.code ?? ""))
    }

    /// One word has no signal of its own. (With hints the prior makes even "Tak." look certain, which is why a
    /// short text is only ever used to veto a language, never to confirm one, and never to build the profile.)
    @Test func aSingleWordIsNotConfidentWithoutHints() {
        for text in ["Tak.", "Okay."] {
            let guess = identifier.identify(text, hints: [], constraints: nil)
            #expect((guess?.confidence ?? 0) < LanguageProfile.minimumConfidence, "\(text)")
        }
    }

    @Test func aTextInALanguageOfTheCatalogOutsideTheHintsIsStillFound() {
        let guess = identifier.identify(Self.samples[2].text, hints: hints, constraints: nil)
        #expect(guess?.code == "uk")
    }

    @Test func constraintsOfAnySizeStillAnswer() {
        let japanese = Self.samples[5].text
        for constraint in [["ja"], ["pl", "ja"], ["pl", "en", "uk", "ja", "de"]] {
            #expect(identifier.identify(japanese, hints: [], constraints: constraint)?.code == "ja")
        }
    }

    @Test func aTextWithoutLettersSaysNothing() {
        #expect(identifier.identify("...", hints: hints, constraints: nil) == nil)
        #expect(identifier.identify("  ", hints: hints, constraints: nil) == nil)
        #expect(identifier.identify("12 34", hints: hints, constraints: nil) == nil)
    }
}
