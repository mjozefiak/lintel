import FluidAudio
import Foundation
import Testing

@testable import LintelSpeech

@Suite struct SpeechLanguageCatalogTests {
    private static let parakeet25 = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu", "it", "lt", "lv", "mt", "nl", "pl",
        "pt", "ro", "ru", "sk", "sl", "sv", "uk",
    ]

    @Test func codesAreUniqueAndEveryLanguageHasAScript() {
        let codes = SpeechLanguageCatalog.all.map(\.code)
        #expect(Set(codes).count == codes.count)
        #expect(codes.count >= 99)
        #expect(SpeechLanguageCatalog.all.allSatisfy { $0.whisperSupported })
    }

    @Test func parakeetSupportsExactlyItsTwentyFiveLanguages() {
        let supported = SpeechLanguageCatalog.all.filter(\.parakeetSupported).map(\.code)
        #expect(Set(supported) == Set(Self.parakeet25))
        #expect(supported.count == 25)
    }

    @Test func everyParakeetLanguageIsWrittenInAScriptThatCanGetAHint() {
        for code in Self.parakeet25 {
            let script = SpeechLanguageCatalog.language(for: code)?.script
            #expect(script == .latin || script == .cyrillic || script == .greek, "\(code)")
            #expect(ScriptHint.hint(forLanguages: [code]) != nil, "\(code)")
        }
    }

    @Test func scriptsOfTheLanguagesTheSpecNames() {
        #expect(SpeechLanguageCatalog.language(for: "pl")?.script == .latin)
        #expect(SpeechLanguageCatalog.language(for: "uk")?.script == .cyrillic)
        #expect(SpeechLanguageCatalog.language(for: "ru")?.script == .cyrillic)
        #expect(SpeechLanguageCatalog.language(for: "el")?.script == .greek)
        #expect(SpeechLanguageCatalog.language(for: "ja")?.script == LanguageScript.other)
        #expect(SpeechLanguageCatalog.language(for: "ja")?.parakeetSupported == false)
        // Written in both scripts, so no hint is right for it.
        #expect(SpeechLanguageCatalog.language(for: "sr")?.script == LanguageScript.other)
    }

    @Test func identifiersAreReducedToACatalogCode() {
        #expect(SpeechLanguageCatalog.normalize("pl-PL") == "pl")
        #expect(SpeechLanguageCatalog.normalize("zh-Hans-CN") == "zh")
        #expect(SpeechLanguageCatalog.normalize("zh-Hant") == "zh")
        #expect(SpeechLanguageCatalog.normalize("en_US") == "en")
        #expect(SpeechLanguageCatalog.normalize("nb") == "no")
        #expect(SpeechLanguageCatalog.normalize("nn-NO") == "no")
        // Every language the catalog lists comes back as itself, so none is unreachable behind an alias.
        for language in SpeechLanguageCatalog.all {
            #expect(SpeechLanguageCatalog.normalize(language.code) == language.code, "\(language.code)")
        }
        #expect(SpeechLanguageCatalog.normalize("yue") == "yue")
        #expect(SpeechLanguageCatalog.normalize("haw") == "haw")
        #expect(SpeechLanguageCatalog.normalize("xx") == nil)
        #expect(SpeechLanguageCatalog.normalize("") == nil)
    }

    @Test func aCodeOutsideTheCatalogCountsAsAnUnknownScript() {
        #expect(SpeechLanguageCatalog.scripts(of: ["pl", "xx"]) == [.latin, .other])
    }
}

@Suite struct ScriptHintTests {
    @Test func oneHintableScriptGivesItsHint() {
        #expect(ScriptHint.hint(for: [.latin]) == .latin)
        #expect(ScriptHint.hint(for: [.cyrillic]) == .cyrillic)
        #expect(ScriptHint.hint(for: [.greek]) == .greek)
    }

    @Test func aMixOtherOrNothingGivesNoHint() {
        #expect(ScriptHint.hint(for: []) == nil)
        #expect(ScriptHint.hint(for: [.latin, .cyrillic]) == nil)
        #expect(ScriptHint.hint(for: [.other]) == nil)
        #expect(ScriptHint.hint(for: [.latin, .other]) == nil)
    }

    @Test func hintsForLanguageCodes() {
        #expect(ScriptHint.hint(forLanguages: ["pl"]) == .latin)
        #expect(ScriptHint.hint(forLanguages: ["pl", "en"]) == .latin)
        #expect(ScriptHint.hint(forLanguages: ["uk"]) == .cyrillic)
        #expect(ScriptHint.hint(forLanguages: ["uk", "ru", "bg"]) == .cyrillic)
        #expect(ScriptHint.hint(forLanguages: ["el"]) == .greek)
        #expect(ScriptHint.hint(forLanguages: ["pl", "uk"]) == nil)
        #expect(ScriptHint.hint(forLanguages: ["pl", "ja"]) == nil)
        #expect(ScriptHint.hint(forLanguages: ["xx"]) == nil)
        #expect(ScriptHint.hint(forLanguages: []) == nil)
    }

    @Test func hintsMapToTheFluidAudioScriptFilters() {
        #expect(ScriptHint.latin.fluidAudioLanguage.script == .latin)
        #expect(ScriptHint.cyrillic.fluidAudioLanguage.script == .cyrillic)
        #expect(ScriptHint.greek.fluidAudioLanguage.script == .greek)
    }

    /// The rule of #203 is kept: for the languages `ParakeetLanguage` knows (`pl`, `en`) the new type agrees with it,
    /// and wherever it widens (Cyrillic, Greek) the old type sent nothing.
    @Test func agreesWithTodaysParakeetLanguageWhereItHadAnAnswer() {
        for codes in [["pl"], ["en"], ["en", "pl"], ["pl", "uk"], ["uk"], ["el"], [], ["xx"]] {
            let old = ParakeetLanguage.hint(for: codes)
            let new = ScriptHint.hint(forLanguages: codes)
            if old != nil { #expect(new == .latin, "\(codes)") }
            if new == .latin { #expect(old != nil || codes.contains { !["pl", "en"].contains($0) }, "\(codes)") }
        }
    }
}

@Suite struct TextScriptTests {
    @Test func theDominantScriptOfAText() {
        #expect(TextScript.dominant(in: "Dzień dobry, to jest test") == .latin)
        #expect(TextScript.dominant(in: "Доброго дня, це тест") == .cyrillic)
        #expect(TextScript.dominant(in: "Καλημέρα, αυτό είναι ένα τεστ") == .greek)
        #expect(TextScript.dominant(in: "こんにちは") == .other)
        #expect(TextScript.dominant(in: "Zażółć gęślą jaźń") == .latin)
    }

    @Test func aMixedTextFollowsTheMajorityOfItsLetters() {
        #expect(TextScript.dominant(in: "Okay, дякую вам дуже") == .cyrillic)
        #expect(TextScript.dominant(in: "Дякую ok") == .cyrillic)
    }

    @Test func aTextWithoutLettersHasNoScript() {
        #expect(TextScript.dominant(in: "...") == nil)
        #expect(TextScript.dominant(in: "42 — 7%") == nil)
        #expect(TextScript.dominant(in: "") == nil)
    }

    @Test func wordsAreCountedByTheSystemsWordBoundaries() {
        #expect(TextScript.wordCount("To jest krótkie zdanie.") == 4)
        #expect(TextScript.wordCount("") == 0)
        #expect(TextScript.wordCount("...") == 0)
        // No spaces in Japanese: the system still finds the words.
        #expect(TextScript.wordCount("昨日の夜、来週の新しいお客様向けのプレゼンテーションについて話しました") >= 5)
    }
}
