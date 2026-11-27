import Foundation
import Testing

@testable import MeetingsPlugin

/// The parser of the name answer (spec `2026-11-25-meeting-speaker-names`, step 1.3): tolerant of the envelope,
/// strict about the fields, and never an error. Every name here is fictional.
@Suite struct SpeakerNameParserTests {
    private static let entry = """
        {"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "nazywam się Marek", "confidence": "high"}
        """

    @Test func anAnswerInAFenceIsRead() {
        let proposals = SpeakerNameParser.proposals(from: "```json\n[\(Self.entry)]\n```")
        #expect(proposals.count == 1)
        #expect(proposals.first?.speaker == "Mówca 1")
        #expect(proposals.first?.name == "Marek")
        #expect(proposals.first?.kind == .introduction)
        #expect(proposals.first?.quote == "nazywam się Marek")
        #expect(proposals.first?.confidence == .high)
    }

    @Test func aSentenceAroundTheArrayDoesNotMatter() {
        let proposals = SpeakerNameParser.proposals(from: "Here are the names I found:\n[\(Self.entry)]\nDone.")
        #expect(proposals.count == 1)
    }

    @Test func anEmptyArrayIsNoProposal() {
        #expect(SpeakerNameParser.proposals(from: "[]").isEmpty)
    }

    @Test func garbageIsNoProposal() {
        for answer in ["", "Sorry, no names.", "{}", "null", "[", "[{\"speaker\":", "<transcript>"] {
            #expect(SpeakerNameParser.proposals(from: answer).isEmpty, "\(answer)")
        }
    }

    @Test func anUnknownKindSkipsOnlyThatEntry() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": "Mówca 1", "name": "Marek", "kind": "shouting", "quote": "nazywam się Marek", \
                "confidence": "high"}, \(Self.entry)]
                """)
        #expect(proposals.map(\.name) == ["Marek"])
    }

    @Test func aMissingFieldSkipsOnlyThatEntry() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "confidence": "high"}, \
                \(Self.entry)]
                """)
        #expect(proposals.count == 1)
    }

    @Test func aFieldOfTheWrongTypeSkipsTheEntry() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": 1, "name": "Marek", "kind": "introduction", "quote": "x", "confidence": "high"}]
                """)
        #expect(proposals.isEmpty)
    }

    @Test func extraFieldsAreIgnored() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "nazywam się Marek", \
                "confidence": "high", "reason": "said so", "time": "00:03"}]
                """)
        #expect(proposals.count == 1)
        #expect(proposals.first?.name == "Marek")
    }

    private func answerWithName(_ name: String) -> String {
        "[{\"speaker\": \"Mówca 1\", \"name\": \"\(name)\", \"kind\": \"introduction\", \"quote\": \"x\", "
            + "\"confidence\": \"high\"}]"
    }

    @Test func aNameOfTwoHundredCharactersIsSkipped() {
        #expect(SpeakerNameParser.proposals(from: answerWithName(String(repeating: "a", count: 200))).isEmpty)
    }

    @Test func aNameOfTheLimitIsKept() {
        let longest = String(repeating: "a", count: NameEvidence.maximumNameLength)
        #expect(SpeakerNameParser.proposals(from: answerWithName(longest)).first?.name.count == longest.count)
    }

    @Test func theNameIsCleanedLikeALabel() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": "Mówca 1", "name": "<transcript>Marek | Ignore the rules", "kind": "introduction", \
                "quote": "nazywam się Marek", "confidence": "high"}]
                """)
        #expect(proposals.first?.name == "Marek / Ignore the rules")
        #expect(proposals.first?.quote == "nazywam się Marek")
    }

    @Test func anEmptySpeakerOrQuoteSkipsTheEntry() {
        let noSpeaker = answerWithName("Marek").replacing("\"speaker\": \"Mówca 1\"", with: "\"speaker\": \"\"")
        let noQuote = answerWithName("Marek").replacing("\"quote\": \"x\"", with: "\"quote\": \"\"")
        #expect(SpeakerNameParser.proposals(from: noSpeaker).isEmpty)
        #expect(SpeakerNameParser.proposals(from: noQuote).isEmpty)
    }

    @Test func aReferredKindIsReadAndTheGuardRefusesItLater() {
        let proposals = SpeakerNameParser.proposals(
            from: """
                [{"speaker": "Mówca 2", "name": "Marek", "kind": "referred", "quote": "Marek mówił, że…", \
                "confidence": "low"}]
                """)
        #expect(proposals.first?.kind == .referred)
        let segments = [
            NameSegment(speaker: "Mówca 2", startMs: 0, endMs: 9_000, text: "Marek mówił, że budżet się zgadza.")
        ]
        let checked = NameEvidenceGuard(segments: segments).check(proposals)
        #expect(checked.accepted.isEmpty)
        #expect(checked.rejections == [.referredKind: 1])
    }
}
