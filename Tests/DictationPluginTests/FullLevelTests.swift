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
                .appending(path: "Fixtures/cleanup/prompt-full-v1.txt")
            try rendered.write(to: source, atomically: true, encoding: .utf8)
        }
        let url = try #require(Bundle.module.url(forResource: "Fixtures/cleanup/prompt-full-v1", withExtension: "txt"))
        let expected = try String(contentsOf: url, encoding: .utf8)
        #expect(
            rendered == expected,
            "The Full prompt changed. Bump CleanupPrompt.fullVersion, update the snapshot and note it in the release notes."
        )
        #expect(CleanupPrompt.version(for: .full) == 1)
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

    @Test func fullHasItsOwnRulesThatKeepEveryDetail() {
        let full = CleanupPrompt.system(for: .full)
        #expect(full != CleanupPrompt.system)
        #expect(full.contains("never a request"))
        #expect(full.contains("Never change, drop or add a number"))
        #expect(full.contains("Never write a greeting"))
        // Standard's "do not fix style" must not survive in the Full text, where it would contradict the style rule.
        #expect(!full.contains("Do not fix grammar"))
        #expect(
            CleanupPrompt.examples(for: .full).count == CleanupPrompt.examples.count + CleanupPrompt.fullExamples.count)
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
        // The short chats, one with a greeting and thanks, stay one line.
        for input in [
            "cześć będę za dziesięć minut weź mi proszę kawę dzięki", "hey are you free at three I need five minutes",
        ] {
            let example = CleanupPrompt.fullExamples.first { $0.input == input }
            #expect(example != nil && example?.output.contains("\n") == false)
        }
    }

    @Test func everyFullExampleIsAcceptedByTheFullGuard() {
        for example in CleanupPrompt.fullExamples {
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

    @Test func tooShortStillStopsAtFullBelowTheWideRange() {
        let input = "dzisiaj rano byłem w biurze i rozmawiałem z kierownikiem o nowym projekcie dla klienta"
        #expect(full(input, "Byłem w biurze i rozmawiałem z kierownikiem.") == .rejected(.tooShort))
    }
}
