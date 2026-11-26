import Foundation
import Testing

@testable import DictationPlugin

/// The Light level (spec `2026-11-25-dictation-cleanup-levels`): filler words out, nothing else. Every input is invented.
@Suite struct LightCleanerTests {
    private func clean(_ text: String, protecting terms: [String] = []) -> String {
        LightCleaner.clean(text, protecting: terms)
    }

    @Test(arguments: [
        // A filler at the start: the next word takes the capital the filler carried.
        ("Yyy, spotkanie jest we wtorek.", "Spotkanie jest we wtorek."),
        ("Eee spotkanie jest we wtorek.", "Spotkanie jest we wtorek."),
        ("Um, so the meeting is on Tuesday.", "So the meeting is on Tuesday."),
        ("Uh the meeting is on Tuesday.", "The meeting is on Tuesday."),
        ("Erm, I think so.", "I think so."),
        ("Uhm so yes.", "So yes."),
        ("Eem, no dobrze.", "No dobrze."),
        ("Yhm, tak.", "Tak."),
        // In the middle, with and without a comma of its own.
        ("Spotkanie jest yyy we wtorek.", "Spotkanie jest we wtorek."),
        ("Spotkanie jest yyy, we wtorek.", "Spotkanie jest we wtorek."),
        ("The meeting is um on Tuesday.", "The meeting is on Tuesday."),
        // A filler with a comma on both sides: the two commas are one pair, so neither stays.
        ("Spotkanie jest, yyy, we wtorek.", "Spotkanie jest we wtorek."),
        ("The meeting is, um, on Tuesday.", "The meeting is on Tuesday."),
        // At the end of a sentence: the comma before it makes way for the full stop.
        ("Spotkanie jest we wtorek, yyy.", "Spotkanie jest we wtorek."),
        ("Spotkanie jest we wtorek yyy.", "Spotkanie jest we wtorek."),
        ("Spotkanie jest, yyy.", "Spotkanie jest."),
        ("The meeting is, um.", "The meeting is."),
        ("Is it on Tuesday, um?", "Is it on Tuesday?"),
        // The next sentence starts after the removed filler.
        ("We meet on Tuesday. Um, then we go.", "We meet on Tuesday. Then we go."),
        ("Spotkanie jest we wtorek. Yyy. Potem idziemy.", "Spotkanie jest we wtorek. Potem idziemy."),
        // Several in a row, in any case.
        ("Yyy eee spotkanie.", "Spotkanie."),
        ("YYY, Eee, spotkanie jest.", "Spotkanie jest."),
        // Two in one sentence.
        ("Yyy, spotkanie jest eee we wtorek.", "Spotkanie jest we wtorek."),
    ])
    func removesTheFillerAndFixesWhatItLeavesBehind(input: String, expected: String) {
        #expect(clean(input) == expected)
    }

    @Test(arguments: [
        "",
        " ",
        "Spotkanie jest we wtorek.",
        "no więc jakby tak zrobimy",
        "Bardzo, bardzo dziękuję.",
        "we we should move it",
        "Dwa  spacje i\nnowa linia.\n\nAkapit",
        "  leading and trailing  ",
        "tak tak tak, no no no",
        "Spotkanie o 10:30, sala 4, 25 osób.",
        // Not whole tokens, or with other punctuation: left alone.
        "yyyyy eeeee ummm",
        "(yyy) “eee” um… yyy… uh—",
        "pre-eee yyy/eee",
        "Dziękuję za uwagę, uhuru.",
    ])
    func aTextWithoutFillersComesBackByteForByte(input: String) {
        #expect(clean(input) == input)
    }

    @Test func theSpacesAndLineBreaksOutsideTheRemovalStay() {
        #expect(clean("Pierwszy.\n\nYyy, drugi  akapit.") == "Pierwszy.\n\nDrugi  akapit.")
        #expect(clean("  Yyy spotkanie  jest.  ") == "  Spotkanie  jest.  ")
        #expect(clean("Lista:\n1. eee jeden\n2. dwa") == "Lista:\n1. jeden\n2. dwa")
    }

    @Test func neverTouchesADigitOrAWordThatIsNotAFiller() {
        let input = "Yyy, na 16, sorry, na 17 jest 4,5 razy więcej, no więc tak, jakby."
        #expect(clean(input) == "Na 16, sorry, na 17 jest 4,5 razy więcej, no więc tak, jakby.")
        // The word after the filler stays as dictated when it is not a letter.
        #expect(clean("Eee 25 osób przyjdzie.") == "25 osób przyjdzie.")
    }

    @Test func aTextOfFillersOnlyIsEmpty() {
        #expect(clean("Yyy, eee.") == "")
    }

    @Test func aCapitalisedFillerInTheMiddleOfASentenceIsAName() {
        // The engine capitalises what starts a sentence, so a capital mid-sentence is a name or an acronym and stays.
        #expect(clean("Spotkanie z Eee jest jutro.") == "Spotkanie z Eee jest jutro.")
        #expect(clean("Rozmowa z UM o podatku.") == "Rozmowa z UM o podatku.")
        #expect(clean("The plan z ERM needs a name.") == "The plan z ERM needs a name.")
        // A lowercase filler in the same place goes.
        #expect(clean("Spotkanie z eee jest jutro.") == "Spotkanie z jest jutro.")
        // At the start of a sentence the capitalised filler is removed and the next word takes the capital.
        #expect(clean("Spotkanie jest. Um, potem idziemy.") == "Spotkanie jest. Potem idziemy.")
    }

    @Test func aVocabularyWordIsNeverRemovedOrChanged() {
        // The user's own term "Eee" (and the spoken variant "yhm") stays, case-insensitively.
        #expect(clean("Spotkanie z Eee jest jutro.", protecting: ["Eee"]) == "Spotkanie z Eee jest jutro.")
        #expect(clean("Powiedz yhm, że tak.", protecting: ["yhm system"]) == "Powiedz yhm, że tak.")
        // The word after a removed filler keeps its own spelling when it is a term ("iPhone", not "IPhone").
        #expect(clean("Yyy iphone jest nowy.", protecting: ["iPhone"]) == "iphone jest nowy.")
        // A lowercase filler is protected too: with the term it stays, without it the same text loses it.
        #expect(clean("Spotkanie z eee jest jutro.", protecting: ["eee"]) == "Spotkanie z eee jest jutro.")
        #expect(clean("Spotkanie z eee jest jutro.") == "Spotkanie z jest jutro.")
    }

    @Test func itAlwaysFormatsAndNeverFails() async throws {
        let result = try await LightCleaner().format(chunk: "Um, hello there.", previousContext: nil)
        #expect(result == FormatResult(text: "Hello there.", outcome: .formatted))
        let empty = try await LightCleaner().format(chunk: "", previousContext: nil)
        #expect(empty == FormatResult(text: "", outcome: .formatted))
    }

    @Test func theVocabularyIsReadForEveryChunk() async throws {
        let terms = TermBox()
        let cleaner = LightCleaner(protectedWords: { terms.value })
        let before = try await cleaner.format(chunk: "Zjadłem, yyy, obiad.", previousContext: nil)
        terms.value = ["yyy"]
        let after = try await cleaner.format(chunk: "Zjadłem, yyy, obiad.", previousContext: nil)
        #expect(before.text == "Zjadłem obiad.")
        #expect(after.text == "Zjadłem, yyy, obiad.")
    }

    @Test func fillerProcessingIsFast() {
        // A long dictation: far below the 5 ms budget of the spec (Light runs at raw speed).
        let paragraph = "Yyy, spotkanie jest we wtorek eee o dziesiątej, no więc um zobaczymy. "
        let text = String(repeating: paragraph, count: 40)
        let started = ContinuousClock.now
        for _ in 0..<20 { _ = clean(text) }
        let each = (ContinuousClock.now - started) / 20
        #expect(each < .milliseconds(5))
    }
}

private final class TermBox: @unchecked Sendable {
    private let lock = NSLock()
    private var terms: [String] = []
    var value: [String] {
        get { lock.withLock { terms } }
        set { lock.withLock { terms = newValue } }
    }
}
