import Testing

@testable import DictationPlugin

@Suite struct SpokenNumbersTests {
    @Test func digitsAreReadWithTheirGroups() {
        #expect(SpokenNumbers.written(in: "25 000 zł").map(\.joined) == [25000])
        #expect(SpokenNumbers.written(in: "12:00").map(\.joined) == [12, 0])
        #expect(SpokenNumbers.written(in: "2,5% i 3,8%").map(\.joined) == [2, 5, 3, 8])
        #expect(SpokenNumbers.written(in: "501 234 567").first?.groups == [501, 234, 567])
        #expect(SpokenNumbers.written(in: "w 1989, p109").map(\.joined) == [1989, 109])
        #expect(SpokenNumbers.written(in: "bez liczb").isEmpty)
    }

    @Test(
        arguments: [
            ("dwadzieścia pięć tysięcy", 25000), ("dwa tysiące dwadzieścia siedem", 2027),
            ("dwunastego marca", 12), ("o dziesiątej", 10), ("pięćset jeden", 501),
            ("dwieście trzydzieści cztery", 234), ("twenty five thousand", 25000),
            ("the twenty second", 22), ("one hundred nine", 109), ("a hundred", 100),
            ("three million two hundred thousand", 3_200_000), ("półtora", 5),
        ])
    func numberWordsHaveTheirValue(text: String, value: Int) {
        #expect(SpokenNumbers.spokenNumbers(in: text).contains(value), Comment(rawValue: text))
    }

    @Test func aSpokenNumberCountsAsOneWord() {
        #expect(SpokenNumbers.wordCount(in: "budżet to dwadzieścia pięć tysięcy złotych") == 4)
        #expect(SpokenNumbers.wordCount(in: "The twenty second of December") == 4)
        #expect(SpokenNumbers.wordCount(in: "25 000 zł") == 2)
    }

    @Test func newNumbersAreOnlyTheOnesTheInputLacks() {
        #expect(SpokenNumbers.newNumbers(in: "60 mm i 7", comparedTo: "6 cali i 7") == [60])
        #expect(SpokenNumbers.newNumbers(in: "o 10:00", comparedTo: "o dziesiątej").isEmpty)
        #expect(SpokenNumbers.newNumbers(in: "ośmiu ludzi", comparedTo: "ośmiu ludzi").isEmpty)
        #expect(SpokenNumbers.newNumbers(in: "wersja 2", comparedTo: "wersja dwa").isEmpty)
    }
}

@Suite struct SpokenNumbersReviewTests {
    @Test func aRunThatOverflowsIsNoNumberAndDoesNotTrap() {
        let numbers = SpokenNumbers.spokenNumbers(
            in: "ninety hundred hundred hundred hundred hundred hundred billion billion")
        #expect(numbers.contains(90))
        #expect(numbers.allSatisfy { $0 >= 0 })
    }

    @Test(
        arguments: [
            ("he was born in nineteen eighty nine", 1989), ("the plan for twenty twenty six", 2026),
            ("one hundred and twenty chairs", 120), ("two thousand and five hundred dollars", 2500),
            ("przyjdzie troje dzieci", 3), ("czworga dorosłych", 4), ("wpół do dziesiątej", 9),
            ("wpół do dziesiątej", 30),
        ])
    func readingsOfAWholeRun(text: String, value: Int) {
        #expect(SpokenNumbers.spokenNumbers(in: text).contains(value), Comment(rawValue: text))
    }

    @Test func wpółOnlyMovesTheHourRightAfterIt() {
        #expect(!SpokenNumbers.spokenNumbers(in: "wpół godziny i dziesiątej").contains(9))
    }

    @Test(
        "Correct digits are accepted",
        arguments: [
            (
                "he was born in nineteen eighty nine in a small town near the coast",
                "He was born in 1989 in a small town near the coast."
            ),
            (
                "we need one hundred and twenty chairs for the event next week",
                "We need 120 chairs for the event next week."
            ),
            (
                "przyjdzie troje dzieci i czworo dorosłych na urodziny jutro",
                "Przyjdzie 3 dzieci i 4 dorosłych na urodziny jutro."
            ),
            (
                "spotkajmy się wpół do dziesiątej przed biurem na parkingu",
                "Spotkajmy się o 9:30 przed biurem na parkingu."
            ),
            (
                "do zrobienia po pierwsze mleko po drugie chleb i jeszcze masło",
                "Do zrobienia:\n1. Mleko.\n2. Chleb.\n3. I jeszcze masło."
            ),
        ])
    func theGuardAcceptsCorrectDigits(input: String, output: String) {
        #expect(FormatterGuard.check(input: input, output: output) == .accepted(output))
    }

    @Test func aListMarkerDoesNotHideAChangedNumber() {
        let input = "do zrobienia po pierwsze kupić 2 kable po drugie oddać laptopa"
        #expect(
            FormatterGuard.check(input: input, output: "Do zrobienia:\n1. Kupić 3 kable.\n2. Oddać laptopa.")
                == .rejected(.newNumber))
    }
}
