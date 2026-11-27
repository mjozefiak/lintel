import Testing

@testable import DictationPlugin

/// The guard's term check (spec `2026-11-25-dictation-cleanup-levels`, Phase 3). Every input is invented.
@Suite struct TermCheckTests {
    private func check(
        _ input: String, _ output: String, level: DictationSettings.CleanupLevel = .standard,
        vocabulary: [String] = [], checksTerms: Bool = true
    ) -> FormatterGuard.Verdict {
        FormatterGuard.check(
            input: input, output: output, level: level, vocabulary: vocabulary, checksTerms: checksTerms)
    }

    private let sentence = "wyślij to jutro do Anny w sprawie nowej umowy z klientem"

    // MARK: Names

    @Test func aMidSentenceNameThatSurvivesIsAccepted() {
        for level in [DictationSettings.CleanupLevel.standard, .full] {
            #expect(
                check(sentence, "Wyślij to jutro do Anny w sprawie nowej umowy z klientem.", level: level)
                    != .rejected(.lostTerm))
        }
    }

    @Test func aLostNameIsRejectedAtStandardAndFull() {
        let output = "Wyślij to jutro do niej w sprawie nowej umowy z klientem."
        for level in [DictationSettings.CleanupLevel.standard, .full] {
            #expect(check(sentence, output, level: level) == .rejected(.lostTerm))
        }
    }

    @Test func aPolishInflectionKeepsTheName() {
        let input = "napisz do Anna że spotkanie jest jutro o dziesiątej rano"
        #expect(
            check(input, "Napisz do Anny, że spotkanie jest jutro o dziesiątej rano.")
                == .accepted("Napisz do Anny, że spotkanie jest jutro o dziesiątej rano."))
        #expect(check(input, "Napisz do niej, że spotkanie jest jutro o dziesiątej rano.") == .rejected(.lostTerm))
        // Another name that only shares the first letters is not the same name.
        #expect(check(input, "Napisz do Ewy, że spotkanie jest jutro o dziesiątej rano.") == .rejected(.lostTerm))
    }

    @Test func aShortNameMustComeBackAsItWas() {
        let input = "powiedz Ola że paczka już dotarła do nas dzisiaj"
        #expect(check(input, "Powiedz Ola, że paczka już dotarła do nas dzisiaj.") != .rejected(.lostTerm))
        #expect(check(input, "Powiedz Oli, że paczka już dotarła do nas dzisiaj.") == .rejected(.lostTerm))
        // Under four letters there is no stem: "Ola" is not kept by "Olaf".
        #expect(check(input, "Powiedz Olaf, że paczka już dotarła do nas dzisiaj.") == .rejected(.lostTerm))
    }

    @Test func caseAndDiacriticsDoNotMatter() {
        let input = "poproś o to Łukasz bo on zna ten kod najlepiej z nas"
        #expect(check(input, "Poproś o to lukasz, bo on zna ten kod najlepiej z nas.") != .rejected(.lostTerm))
    }

    @Test func theFirstWordOfASentenceIsNotAName() {
        let input = "Dzisiaj spotkanie jest o piątej. Potem idziemy na obiad do domu razem"
        let output = "Dziś spotkanie jest o piątej. Potem idziemy na obiad do domu razem."
        #expect(check(input, output) != .rejected(.lostTerm))
        #expect(TermCheck.names(in: input).isEmpty)
        #expect(TermCheck.names(in: "pierwsza linia tutaj\nDruga linia też") == [])
    }

    @Test func aCapitalisedWordAfterAFullStopCountsOnlyAtTheStartOfTheSentence() {
        #expect(TermCheck.names(in: "to jest test. Anna wie. Poproś Marka o to") == ["marka"])
        #expect(TermCheck.names(in: "czy to Anna? Tak, Marek wie") == ["anna", "marek"])
        #expect(TermCheck.names(in: "powiedział \"Anna\" i wyszedł") == ["anna"])
    }

    @Test func anAcronymAndAHyphenatedNameAreNames() {
        #expect(
            TermCheck.names(in: "zapisz to w pliku CSV dla Jean-Pierre Dubois") == ["csv", "jean", "pierre", "dubois"])
    }

    @Test func aSingleLetterIsNotAName() {
        #expect(TermCheck.names(in: "jeśli I think that works") == [])
    }

    @Test func aLineBreakIsNotAWord() {
        let input = "sprawdź to w Argo CD przed końcem dnia i daj znać wszystkim"
        let output = "Sprawdź to w Argo\nCD przed końcem dnia i daj znać wszystkim."
        #expect(check(input, output) != .rejected(.lostTerm))
    }

    @Test func aChunkWithASelfCorrectionIsExempt() {
        let input = "wyślij to do Anny nie czekaj wyślij to do całego zespołu jutro rano"
        let output = "Wyślij to do całego zespołu jutro rano."
        #expect(check(input, output) != .rejected(.lostTerm))
        #expect(check(input, output, vocabulary: ["Anny"]) != .rejected(.lostTerm))
    }

    @Test func theCheckIsOffWhenTheSwitchIsOff() {
        let output = "Wyślij to jutro do niej w sprawie nowej umowy z klientem."
        #expect(check(sentence, output, checksTerms: false) != .rejected(.lostTerm))
    }

    /// The measured result of Phase 3 (spec): the check adds one chunk of fallback on the owner's corpus (2.4 points
    /// of 42 chunks, over the 2-point limit) and keeps no term that the baseline did not, so it ships switched off.
    @Test func theShippedSwitchIsOffAndTheDefaultCallsFollowIt() {
        #expect(!FormatterGuard.checksTerms)
        let lost = "Wyślij to jutro do niej w sprawie nowej umowy z klientem."
        #expect(FormatterGuard.check(input: sentence, output: lost) != .rejected(.lostTerm))
        #expect(
            FormatterGuard.check(input: sentence, output: lost, level: .standard, vocabulary: ["Anny"])
                != .rejected(.lostTerm))
    }

    // MARK: Vocabulary

    @Test func aVocabularyTermTheTranscriptHoldsMustSurvive() {
        let input = "wdróż to na kubernetes jeszcze dzisiaj wieczorem po pracy"
        #expect(
            check(input, "Wdróż to na klaster jeszcze dzisiaj wieczorem po pracy.", vocabulary: ["Kubernetes"])
                == .rejected(.lostTerm))
        #expect(
            check(input, "Wdróż to na Kubernetes jeszcze dzisiaj wieczorem po pracy.", vocabulary: ["Kubernetes"])
                != .rejected(.lostTerm))
    }

    @Test func aVocabularyTermTheTranscriptLacksIsNotRequired() {
        let input = "wdróż to na klaster jeszcze dzisiaj wieczorem po pracy"
        #expect(
            check(input, "Wdróż to na klaster jeszcze dzisiaj wieczorem po pracy.", vocabulary: ["Kubernetes"])
                != .rejected(.lostTerm))
    }

    @Test func aSpokenVariantMustStayAsSpoken() {
        // The replacer works on the exact variant, so a model that "fixes" it breaks the replacement.
        let input = "otwórz dżira i zobacz zgłoszenie które dostałem wczoraj"
        #expect(
            check(input, "Otwórz Jirę i zobacz zgłoszenie, które dostałem wczoraj.", vocabulary: ["Jira", "dżira"])
                == .rejected(.lostTerm))
        #expect(
            check(input, "Otwórz dżira i zobacz zgłoszenie, które dostałem wczoraj.", vocabulary: ["Jira", "dżira"])
                != .rejected(.lostTerm))
    }

    @Test func aMultiWordTermIsKeptAsARun() {
        let input = "ustaw to w github actions przed końcem tygodnia dla całego zespołu"
        #expect(
            check(
                input, "Ustaw to w GitHub Actions przed końcem tygodnia dla całego zespołu.",
                vocabulary: ["GitHub Actions"]) != .rejected(.lostTerm))
        #expect(
            check(
                input, "Ustaw to w actions github przed końcem tygodnia dla całego zespołu.",
                vocabulary: ["GitHub Actions"]) == .rejected(.lostTerm))
        #expect(
            check(input, "Ustaw to w GitHub przed końcem tygodnia dla całego zespołu.", vocabulary: ["GitHub Actions"])
                == .rejected(.lostTerm))
    }

    @Test func aVocabularyTermIsNotMatchedInsideAnotherWord() {
        let input = "to jest nasz nowy plan na cały następny kwartał roboczy"
        #expect(
            check(input, "To jest nasz nowy plan na cały następny kwartał roboczy.", vocabulary: ["lan"])
                != .rejected(.lostTerm))
    }

    @Test func aTermWithoutLettersIsIgnored() {
        let input = "to jest nasz nowy plan na cały następny kwartał roboczy"
        #expect(
            check(input, "To jest nasz nowy plan na cały następny kwartał roboczy.", vocabulary: ["", "..."])
                != .rejected(.lostTerm))
    }

    // MARK: The reasons that come first

    @Test func aLostTermDoesNotHideAnEarlierReason() {
        let input = "wyślij to jutro do Anny w sprawie nowej umowy z klientem"
        #expect(check(input, "Oczywiście, wyślij to jutro w sprawie nowej umowy z klientem.") == .rejected(.answered))
    }
}
