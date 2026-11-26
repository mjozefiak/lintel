import Foundation
import Testing

@testable import DictationPlugin
@testable import LintelSpeech

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 2: the Full level's prompt and the guard limits at Full. Every
/// sentence is invented.
@Suite struct FullPromptTests {
    @Test func theFullPromptMatchesTheSnapshot() throws {
        let rendered =
            CleanupPrompt.messages(transcript: "TRANSCRIPT", context: "CONTEXT", level: .full)
            .map { "[\($0.role)]\n\($0.content)" }.joined(separator: "\n\n") + "\n"
        if ProcessInfo.processInfo.environment["LINTEL_RECORD_SNAPSHOT"] != nil {
            let source = URL(filePath: #filePath).deletingLastPathComponent()
                .appending(path: "Fixtures/cleanup/prompt-full-v3.txt")
            try rendered.write(to: source, atomically: true, encoding: .utf8)
        }
        let url = try #require(Bundle.module.url(forResource: "Fixtures/cleanup/prompt-full-v3", withExtension: "txt"))
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(
            rendered == expected,
            "The Full prompt changed. Bump CleanupPrompt.fullVersion, update the snapshot and note it in the release notes."
        )
        #expect(CleanupPrompt.version(for: .full) == 3)
    }

    @Test func standardIsUntouchedAndStillTheDefault() {
        #expect(CleanupPrompt.version(for: .standard) == 2)
        #expect(CleanupPrompt.system(for: .standard) == CleanupPrompt.system)
        #expect(CleanupPrompt.examples(for: .standard).count == CleanupPrompt.examples.count)
        let plain = CleanupPrompt.messages(transcript: "tak", context: "przed")
        #expect(
            plain.map(\.content)
                == CleanupPrompt.messages(transcript: "tak", context: "przed", level: .standard).map(\.content))
        // Light has no prompt; asked for one it reads as Standard rather than failing.
        #expect(CleanupPrompt.system(for: .light) == CleanupPrompt.system)
    }

    @Test func fullKeepsStandardsRulesThatProtectTheWords() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full != CleanupPrompt.system)
        #expect(full.contains("never a request"))
        #expect(full.contains("Never change a number, unit, date, time, amount, name or any other detail."))
        #expect(full.contains("Change as little as possible."))
        #expect(full.contains("Never write a greeting"))
        // Standard's "do not fix style" must not survive in the Full text, where it would contradict the style rule.
        #expect(!full.contains("Do not fix grammar"))
        #expect(
            CleanupPrompt.examples(for: .full).count
                == CleanupPrompt.fullBaseExamples.count + CleanupPrompt.fullExamples.count
                + CleanupPrompt.fullClosingExamples.count)
    }

    @Test func theSelfCorrectionExamplesComeLastAndStandardsInTheMiddle() {
        let all = CleanupPrompt.examples(for: .full)
        #expect(
            all.suffix(CleanupPrompt.fullClosingExamples.count).map(\.input)
                == CleanupPrompt.fullClosingExamples.map(\.input))
        let middle = all.dropFirst(CleanupPrompt.fullExamples.count).prefix(CleanupPrompt.fullBaseExamples.count)
        #expect(middle.map(\.input) == CleanupPrompt.fullBaseExamples.map(\.input))
        // Standard's pairs, unchanged in what they are about: only the way a number is written differs.
        #expect(CleanupPrompt.fullBaseExamples.map(\.input) == CleanupPrompt.examples.map(\.input))
        // Each closing example takes something back, and the output keeps only the correction.
        for example in CleanupPrompt.fullClosingExamples {
            #expect(
                ["czekaj", "albo jednak", "a właściwie"].contains { example.input.contains($0) },
                "\(example.input.prefix(30))"
            )
        }
    }

    /// Owner decision 2026-11-26 (question 8 of the review of #337): the layout follows what was said, not how long the
    /// message is, so a short greeting and sign-off are laid out and a message with neither stays one line.
    @Test func theLayoutRuleDoesNotDependOnTheLengthOfTheBody() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full.contains("whatever the length of the message"))
        #expect(!full.contains("at least two sentences"))
        #expect(!full.contains("(about 25 words or more) between them"))
        // Paragraphs still start only from a longer text.
        #expect(full.contains("about 40 words or more"))
        #expect(full.contains("Never split a text of fewer than about 25 words into paragraphs"))
    }

    @Test func aSentenceIsSplitOnlyFromAboutThirtyWordsAndAnOddWordIsKept() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full.contains("split a sentence of more than about 30 words"))
        #expect(full.contains("A shorter sentence stays as it is."))
        #expect(full.contains("write it exactly as it stands"))
    }

    /// Owner decision 2026-11-26 (Full v3): a number keeps the form the transcript has, so "like three days" stays a
    /// word and a number already in digits stays in digits; a clock time said as hours and minutes is the one exception.
    @Test func aNumberKeepsTheFormTheTranscriptHasInTheRuleAndInEveryExample() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full.contains("keep the form the transcript has"))
        #expect(full.contains("Never turn one into the other."))
        #expect(!full.contains("\"three days\" is \"3 days\""))
        let clock = "widzimy się o piętnastej czterdzieści pięć w sali dwa"
        for example in CleanupPrompt.examples(for: .full) where example.input != clock {
            let wanted = Set(digitRuns(example.input))
            for digits in digitRuns(example.output) {
                #expect(wanted.contains(digits), "\(example.input.prefix(40)): \(digits)")
            }
        }
        // The words stay words in the pairs that were digits in v2, and the clock time is written as digits.
        let all = CleanupPrompt.examples(for: .full)
        #expect(all.contains { $0.output.contains("like three days") })
        #expect(all.contains { $0.output == "Zamów taksówkę na siódmą, bo prom odpływa wcześniej." })
        #expect(all.contains { $0.input == clock && $0.output == "Widzimy się o 15:45 w sali dwa." })
        #expect(all.contains { $0.input.contains("3 pm") && $0.output.contains("3 pm") })
    }

    /// A word the model does not know is kept, never swapped for a guess (Full v3: the two garbled corpus items).
    @Test func anUnknownWordIsKeptAndNeverGuessedInTheRuleAndTheExamples() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full.contains("Never replace a word you do not recognise"))
        #expect(full.contains("never a verb's form"))
        let all = CleanupPrompt.examples(for: .full)
        #expect(all.contains { $0.input.contains("Rkvq") && $0.output.contains("Rkvq") })
        #expect(all.contains { $0.input.contains("aber ich muss") && $0.output.contains("aber ich muss") })
    }

    /// The digit runs of a text, without the "1." that numbers a list item.
    private func digitRuns(_ text: String) -> [String] {
        var runs: [String] = []
        for line in text.split(separator: "\n") {
            var rest = Substring(line)
            let number = rest.prefix { $0.isNumber }
            if !number.isEmpty, rest.dropFirst(number.count).hasPrefix(". ") {
                rest = rest.dropFirst(number.count + 2)
            }
            runs += rest.split { !$0.isNumber }.map(String.init)
        }
        return runs
    }

    @Test func theFullExamplesCoverMailParagraphsAndAShortLine() {
        let outputs = CleanupPrompt.fullExamples.map(\.output)
        #expect(
            outputs.contains { $0.hasPrefix("Dzień dobry pani Moniko,\n\n") && $0.hasSuffix("Pozdrawiam,\nKrzysztof") })
        #expect(outputs.contains { $0.hasPrefix("Hi Mark,\n\n") && $0.hasSuffix("Thanks,\nJulia") })
        // A longer statement without a greeting is split into paragraphs.
        #expect(
            outputs.contains {
                !$0.hasPrefix("W zeszłym tygodniu") ? false : $0.components(separatedBy: "\n\n").count == 3
            })
        // A short message WITH a greeting or a sign-off is laid out, whatever its length.
        for (input, prefix, suffix) in [
            ("dzień dobry chciałbym zapytać o status zamówienia numer siedem", "Dzień dobry,\n\n", "numer siedem."),
            ("hi Dan the printer is jammed again can you look at it thanks Eva", "Hi Dan,\n\n", "Thanks,\nEva"),
        ] {
            let example = CleanupPrompt.fullExamples.first { $0.input == input }
            #expect(example?.output.hasPrefix(prefix) == true && example?.output.hasSuffix(suffix) == true)
        }
        // A short message with neither stays one line.
        for input in ["będę za dziesięć minut weź mi proszę kawę", "are you free at three I need five minutes"] {
            let example = CleanupPrompt.fullExamples.first { $0.input == input }
            #expect(example != nil && example?.output.contains("\n") == false)
        }
    }

    @Test func everyFullExampleIsAcceptedByTheFullGuard() {
        for example in CleanupPrompt.fullExamples + CleanupPrompt.fullClosingExamples {
            let verdict = FormatterGuard.check(input: example.input, output: example.output, level: .full)
            #expect(verdict == .accepted(example.output), "\(example.input.prefix(30)): \(verdict)")
        }
    }

    @Test func noExampleCarriesTheMarkersTheWrapperUses() {
        for example in CleanupPrompt.examples(for: .full) {
            for text in [example.input, example.output] {
                #expect(!text.contains("<transcript>") && !text.contains("<context>"))
            }
        }
    }
}

@Suite struct FullGuardTests {
    private let mailInput =
        "cześć Anno wysyłam ci raport za marzec i proszę o uwagi do piątku potem go przekażę dalej dzięki Tomek"
    private let mailOutput =
        "Cześć Anno,\n\nwysyłam ci raport za marzec i proszę o uwagi do piątku.\n\nPotem go przekażę dalej.\n\nDzięki,\nTomek"

    private func full(_ input: String, _ output: String) -> FormatterGuard.Verdict {
        FormatterGuard.check(input: input, output: output, level: .full)
    }

    @Test func aLaidOutMailIsAcceptedAndLineBreaksAreNotWords() {
        #expect(full(mailInput, mailOutput) == .accepted(mailOutput))
        let words = FormatterGuard.words(in: mailOutput)
        #expect(words == FormatterGuard.words(in: mailOutput.replacingOccurrences(of: "\n\n", with: " ")))
    }

    @Test func standardCheckIsTheSameAsBeforeWithoutALevel() {
        let input = "yyy no więc jutro mamy spotkanie o dziesiątej w biurze i to jest ważne"
        let output = "Jutro mamy spotkanie o dziesiątej w biurze i to jest ważne."
        #expect(
            FormatterGuard.check(input: input, output: output)
                == FormatterGuard.check(input: input, output: output, level: .standard))
        #expect(full(input, output) == .accepted(output))
    }

    // MARK: Every reason of rejection at Full

    @Test func anEmptyAnswerIsRejected() {
        #expect(full(mailInput, "  \n ") == .rejected(.empty))
    }

    @Test func anAnswerInsteadOfACleaningIsRejected() {
        let question = "um what is the capital of france I mean of poland please tell me"
        #expect(full(question, "Sure, the capital of Poland is Warsaw, of course.") == .rejected(.answered))
    }

    @Test func aChangedLanguageIsRejected() {
        let output = "We have a meeting at the office tomorrow and it is important"
        #expect(full("jutro mamy spotkanie w biurze z klientem i to jest ważne", output) == .rejected(.languageChanged))
    }

    @Test func aForeignScriptIsRejected() {
        let input = "jutro mamy spotkanie w biurze o dziesiątej i to jest ważne"
        #expect(full(input, "Jutro mamy spotkanie в biurze o dziesiątej i to jest ważne.") == .rejected(.foreignScript))
    }

    @Test func aNewNumberIsRejectedAtFull() {
        let input = "w raporcie jest 6 cali deszczu i dużo wiatru dzisiaj"
        #expect(full(input, "W raporcie jest 60 mm deszczu i dużo wiatru dzisiaj.") == .rejected(.newNumber))
    }

    @Test func aLostNumberIsRejectedAtFullButNotAtStandard() {
        let input = "spotkanie jest o 16 w biurze a potem mamy telefon z klientem o 18 i raport"
        let output = "Spotkanie jest o 16 w biurze, a potem mamy telefon z klientem i raport."
        #expect(full(input, output) == .rejected(.lostNumber))
        // Standard has no such check (its chunks pass the length and the new-number checks as before).
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func aWholeSpokenNumberCountsOnceWhenItIsWrittenAsDigits() {
        let input = "paczka waży dwadzieścia pięć kilogramów i kosztuje sto złotych razem z wysyłką do domu"
        let output = "Paczka waży 25 kilogramów i kosztuje 100 złotych razem z wysyłką do domu."
        #expect(full(input, output) == .accepted(output))
    }

    @Test func aSpokenNumberAboveTenThatIsGoneIsALostNumber() {
        let input = "spotkanie przesuwamy na czternastą trzydzieści a potem jedziemy razem do biura na Mokotowie"
        let output = "Spotkanie przesuwamy, a potem jedziemy razem do biura na Mokotowie."
        #expect(full(input, output) == .rejected(.lostNumber))
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func aSpokenTimeWrittenAsDigitsIsKept() {
        let input = "spotkanie przesuwamy na czternastą trzydzieści a potem jedziemy razem do biura"
        let output = "Spotkanie przesuwamy na 14:30, a potem jedziemy razem do biura."
        #expect(full(input, output) == .accepted(output))
    }

    @Test func spokenNumbersUpToTenAreNotCheckedForLoss() {
        // "po pierwsze", "po drugie" become list markers: a run of number words whose largest reading is 10 or less
        // is exempt, because a list or a rewrite turns such words into markers or other words.
        let input = "na zakupy po pierwsze mleko i masło po drugie chleb razowy z piekarni"
        let output = "Na zakupy:\n- mleko i masło\n- chleb razowy z piekarni"
        #expect(SpokenNumbers.lostNumbers(in: output, comparedTo: input).isEmpty)
        #expect(full(input, output) == .accepted(output))
    }

    @Test func aNumberSaidInGroupsIsKeptWhenItsGroupsAre() {
        let input = "zadzwoń do Marka na numer 501 234 567 jutro rano przed spotkaniem w biurze"
        let output = "Zadzwoń do Marka na numer 501-234-567 jutro rano przed spotkaniem w biurze."
        #expect(SpokenNumbers.lostNumbers(in: output, comparedTo: input).isEmpty)
        #expect(full(input, output) == .accepted(output))
    }

    @Test func aSelfCorrectionMayWithdrawANumber() {
        let input = "zamówcie pizzę na 16 sorry na 17 i weźcie jedną dużą dla wszystkich"
        let output = "Zamówcie pizzę na 17 i weźcie jedną dużą dla wszystkich."
        #expect(full(input, output) == .accepted(output))
    }

    @Test func aDroppedPartIsTooShort() {
        let input = "wczoraj byliśmy u klienta i omówiliśmy cały harmonogram prac na kolejny kwartał razem z budżetem"
        #expect(full(input, "Wczoraj byliśmy u klienta.") == .rejected(.tooShort))
    }

    @Test func anAddedPartIsTooLong() {
        let input = "wczoraj byliśmy u klienta i omówiliśmy harmonogram prac na kolejny kwartał"
        let output =
            input + " oraz ustaliliśmy wszystkie szczegóły dotyczące budżetu, ryzyka, terminów i odpowiedzialności"
        #expect(full(input, output) == .rejected(.tooLong))
    }

    @Test func aWrittenGreetingIsRejected() {
        let input = "wysyłam raport za marzec i proszę o uwagi do piątku potem przekażę go dalej do działu finansów"
        let output =
            "Dzień dobry,\n\nwysyłam raport za marzec i proszę o uwagi do piątku. Potem przekażę go dalej do działu finansów."
        #expect(full(input, output) == .rejected(.inventedLayout))
        // The same text without a level is Standard's, which does not look for it.
        #expect(FormatterGuard.check(input: input, output: output) != .rejected(.inventedLayout))
    }

    @Test func aWrittenSignOffIsRejected() {
        let input = "the report for March is attached please send me your comments by Friday and I will pass it on"
        let output =
            "The report for March is attached. Please send me your comments by Friday and I will pass it on.\n\nBest regards,\nTom"
        #expect(full(input, output) == .rejected(.inventedLayout))
    }

    @Test func aSpokenGreetingAndSignOffAreNotInvented() {
        let input = "hello Anna the report is attached please send me your comments by Friday thanks Tom"
        let output = "Hello Anna,\n\nThe report is attached. Please send me your comments by Friday.\n\nThanks,\nTom"
        #expect(full(input, output) == .accepted(output))
        // Diacritics and case do not matter: "Dzięki" matches a spoken "dzięki".
        #expect(!InventedLayout.adds(to: "dzięki za wszystko", in: "Dzięki za wszystko."))
    }

    // MARK: The length range

    @Test func fullNeverRejectsForALengthStandardAccepts() {
        // Standard's plain range is 0.85...1.15; Full's contains it, and the corrections' and minors' are shared.
        #expect(FormatterGuard.fullPlainLengthRange.lowerBound <= FormatterGuard.plainLengthRange.lowerBound)
        #expect(FormatterGuard.fullPlainLengthRange.upperBound >= FormatterGuard.plainLengthRange.upperBound)
        let input = "dzisiaj rano byłem w biurze i rozmawiałem z kierownikiem o nowym projekcie dla klienta z Krakowa"
        for keep in 11...14 {
            let words = input.split(separator: " ")
            let output = words.prefix(keep).joined(separator: " ") + "."
            let standard = FormatterGuard.check(input: input, output: output)
            if case .accepted = standard { #expect(full(input, output) == standard, "\(keep) words") }
        }
    }

    @Test func fullAcceptsAShorterPlainChunkThanStandardDoes() {
        // 14 words in, 10 out (ratio 0.71): a style edit at Full, too short for Standard's plain range.
        let input = "dzisiaj rano byłem w biurze i rozmawiałem z kierownikiem o nowym projekcie dla klienta"
        let output = "Dzisiaj rano byłem w biurze, rozmawiałem z kierownikiem o nowym projekcie."
        #expect(FormatterGuard.check(input: input, output: output) == .rejected(.tooShort))
        #expect(full(input, output) == .accepted(output))
    }

    @Test func fullsPlainRangeStartsAtSevenTenths() {
        // The spec's first 0.6 was tightened to 0.7 from the eval: 9 words of 14 (0.64) is a dropped detail.
        #expect(FormatterGuard.fullPlainLengthRange == 0.7...1.15)
        let input = "dzisiaj rano byłem w biurze i rozmawiałem z kierownikiem o nowym projekcie dla klienta"
        #expect(full(input, "Rano byłem w biurze, rozmawiałem z kierownikiem o projekcie.") == .rejected(.tooShort))
    }

    @Test func tooShortStillStopsAtFullBelowTheWideRange() {
        let input = "dzisiaj rano byłem w biurze i rozmawiałem z kierownikiem o nowym projekcie dla klienta"
        #expect(full(input, "Byłem w biurze i rozmawiałem z kierownikiem.") == .rejected(.tooShort))
    }
}
