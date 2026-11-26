import Foundation
import Testing

@testable import MeetingsPlugin

/// The first filter before the notes model sees anything (spec `2026-11-25-meeting-speaker-names`, step 1.2):
/// which places in a transcript can hold a name, and the excerpts around them. Every name here is fictional.
@Suite struct NameMentionExtractorTests {
    private func segments(_ texts: [String]) -> [NameSegment] {
        texts.enumerated().map { index, text in
            NameSegment(
                speaker: index.isMultiple(of: 2) ? "Mówca 1" : "Mówca 2", startMs: index * 10_000,
                endMs: index * 10_000 + 9_000, text: text)
        }
    }

    private func candidates(_ text: String, known: [String] = []) -> [NameMentionExtractor.Candidate] {
        NameMentionExtractor(knownNames: known).candidates(in: segments([text])[0], at: 0)
    }

    // MARK: Self introduction

    @Test func aSelfIntroductionInPolishIsACandidate() {
        let found = candidates("Dzień dobry, nazywam się Marek Nowak.")
        let marek = found.first { $0.name == "Marek" }
        #expect(marek?.kind == .introduction)
        #expect(marek?.segment == 0)
    }

    @Test func aShortIntroductionInPolishIsACandidate() {
        let found = candidates("To ja, tu Marek z działu sprzedaży.")
        #expect(found.contains { $0.name == "Marek" && $0.kind == .introduction })
    }

    @Test func aSelfIntroductionInEnglishIsACandidate() {
        let found = candidates("Hi, I'm Anna and I run the programme.")
        #expect(found.contains { $0.name == "Anna" && $0.kind == .introduction })
    }

    @Test func aPhraseNeedsACapitalAfterIt() {
        // "this is the budget" is no name: the word after the phrase has no capital.
        #expect(candidates("So this is the plan for the quarter.").isEmpty)
    }

    // MARK: Announcement

    @Test func anAnnouncementNamesTheSpeaker() {
        let found = candidates("Głos ma pan poseł Kowalski.")
        #expect(found.contains { $0.name == "Kowalski" && $0.kind == .announced })
    }

    @Test func aPhraseOutranksABareCapital() {
        let found = candidates("Nazywam się Ewa Kowalska.")
        #expect(found.contains { $0.name == "Ewa" && $0.kind == .introduction })
    }

    // MARK: Vocative

    @Test func aVocativeIsACandidate() {
        let found = candidates("Marku, zrobisz to do piątku?")
        #expect(found.contains { $0.name == "Marku" && $0.kind == .addressed })
    }

    @Test func aCommaAfterASentenceOpeningIsNoVocative() {
        // Every sentence that opens with a capital and a comma would otherwise look like one.
        #expect(candidates("Widzę, że oferta jest gotowa.").isEmpty)
    }

    // MARK: A third person

    @Test func aThirdPersonsNameIsStillACandidate() {
        // The guard refuses `referred`; the extractor does not know who is speaking, so the excerpt goes out.
        let found = candidates("Wczoraj Marek mówił, że oferta jest gotowa.")
        #expect(found.contains { $0.name == "Marek" && $0.kind == nil })
    }

    // MARK: What is not a name

    @Test func aCapitalAtASentenceStartIsNoEvidence() {
        #expect(candidates("Dziś zajmiemy się harmonogramem.").isEmpty)
    }

    @Test func productNamesAreNotCandidates() {
        #expect(candidates("Otwórz Jirę, potem sprawdź Slacka i Teamsy.").isEmpty)
        #expect(candidates("Jedziemy do Warszawy we wtorek.").isEmpty)
        #expect(candidates("Spotkanie na Zoomie o dziesiątej.").isEmpty)
    }

    @Test func aPlaceholderIsNoCandidate() {
        #expect(candidates("Widzę, że Speaker mówi dalej.").isEmpty)
    }

    // MARK: Known names

    @Test func aKnownNameIsFoundInAnyForm() {
        let found = candidates("Zgadzam się, Markiem się zajmiemy.", known: ["Marek"])
        #expect(found.contains { $0.name == "Marek" && $0.kind == nil })
    }

    @Test func aKnownNameIsFoundWithoutACapital() {
        let found = candidates("Poproszę marka o pomoc w tym zadaniu.", known: ["Marek"])
        #expect(found.contains { $0.name == "Marek" })
    }

    // MARK: Excerpts

    @Test func anExcerptHoldsTheNeighboursOfTheCandidate() {
        let result = NameMentionExtractor().excerpts(
            from: segments([
                "Zaczynamy punkt drugi.", "Wczoraj Marek mówił o ofercie.", "Tak, pamiętam.", "Punkt trzeci.",
            ]))
        #expect(result.excerpts.count == 1)
        #expect(result.excerpts.first?.range == 0...2)
        #expect(result.excerpts.first?.segments.count == 3)
        #expect(result.droppedExcerpts == 0)
    }

    @Test func overlappingExcerptsAreMerged() {
        let result = NameMentionExtractor().excerpts(
            from: segments([
                "Zaczynamy.", "Wczoraj Marek mówił o ofercie.", "Anno, a ty co myślisz?", "Dobrze.", "Koniec.",
            ]))
        #expect(result.excerpts.count == 1)
        #expect(result.excerpts.first?.range == 0...3)
        #expect(result.candidates.map(\.name).sorted() == ["Anno", "Marek"])
    }

    @Test func everyExcerptStartsAtTheCandidate() {
        let result = NameMentionExtractor().excerpts(
            from: segments(["A.", "B.", "C.", "Wczoraj Marek mówił o ofercie.", "D.", "E.", "F."]))
        #expect(result.excerpts.first?.range == 2...4)
    }

    @Test func theLimitCapsTheExcerptsAndCountsTheRest() {
        // A candidate every third segment: their windows do not overlap, so each one is its own excerpt.
        var texts: [String] = []
        for index in 0..<135 {
            texts.append(index.isMultiple(of: 3) ? "Zgadzam się, Marku, na to." : "Omawiamy punkt kolejny.")
        }
        let result = NameMentionExtractor().excerpts(from: segments(texts))
        #expect(result.excerpts.count == NameMentionExtractor.maximumExcerpts)
        #expect(result.candidates.count == NameMentionExtractor.maximumExcerpts)
        #expect(result.droppedExcerpts == 5)
    }

    @Test func aPhraseExcerptWinsTheBudget() {
        // 41 excerpts of bare capitals and one self introduction at the end: the introduction is kept.
        var texts: [String] = []
        for _ in 0..<41 {
            texts.append(contentsOf: ["Wczoraj Marek mówił o ofercie.", "Omawiamy punkt kolejny.", "Tak."])
        }
        texts.append("Nazywam się Ewa Kowalska.")
        let result = NameMentionExtractor().excerpts(from: segments(texts))
        #expect(result.excerpts.count == NameMentionExtractor.maximumExcerpts)
        #expect(result.candidates.contains { $0.name == "Ewa" && $0.kind == .introduction })
        #expect(result.droppedExcerpts == 2)
    }
}
