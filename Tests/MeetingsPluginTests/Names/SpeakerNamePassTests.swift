import Foundation
import LintelSpeech
import LintelTestSupport
import Synchronization
import Testing

@testable import MeetingsPlugin

/// The name pass over a fake notes generator (spec `2026-11-25-meeting-speaker-names`, step 1.3): one request,
/// the guard after it, no evidence on any failure, and no request at all when a condition of the spec forbids it.
/// Every name and quote here is fictional.
@Suite struct SpeakerNamePassTests {
    /// A transcript a proposal can be checked against: an introduction, a vocative and an announcement.
    private func transcript() -> [NameSegment] {
        let lines: [(String, String)] = [
            ("Mówca 1", "Dzień dobry, nazywam się Marek."),
            ("Mówca 2", "Cześć, ja jestem Anna."),
            ("Mówca 1", "Anna, czy testy już przeszły?"),
            ("Mówca 2", "Tak, wszystko zielone."),
            ("Mówca 1", "Głos ma pani prezes, czyli Ewa."),
            ("Mówca 3", "Dziękuję, zaczynamy od budżetu."),
        ]
        return lines.enumerated().map { index, line in
            NameSegment(
                speaker: line.0, startMs: index * 10_000, endMs: index * 10_000 + 9_000, text: line.1)
        }
    }

    /// The answer that matches `transcript()`: one entry per name, every quote word for word.
    private static let answer = """
        [
          {"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "nazywam się Marek", "confidence": "high"},
          {"speaker": "Mówca 2", "name": "Anna", "kind": "introduction", "quote": "ja jestem Anna", "confidence": "high"},
          {"speaker": "Mówca 2", "name": "Anna", "kind": "addressed", "quote": "Anna, czy testy już przeszły", "confidence": "low"},
          {"speaker": "Mówca 3", "name": "Ewa", "kind": "announced", "quote": "Głos ma pani prezes, czyli Ewa", "confidence": "high"}
        ]
        """

    private func pass(_ generator: ScriptedGenerator, knownNames: [String] = []) -> SpeakerNamePass {
        SpeakerNamePass(generator: generator, knownNames: knownNames)
    }

    // MARK: The answer

    @Test func aCorrectAnswerGivesEvidenceAfterTheGuard() async {
        let generator = ScriptedGenerator.answering(Self.answer)
        let outcome = await pass(generator).run(segments: transcript(), conditions: .init())

        #expect(generator.opened == 1)
        #expect(generator.released == 1)
        #expect(generator.calls.count == 1)
        #expect(outcome.answers == 4)
        // The phrases make one excerpt; "czyli Ewa" is a bare word, so its own (second tier).
        #expect(outcome.excerpts == 2)
        #expect(outcome.droppedExcerpts == 0)
        #expect(outcome.accepted.count == 4)
        #expect(outcome.rejections.isEmpty)

        let marek = outcome.accepted.first { $0.kind == .introduction && $0.name == "Marek" }
        #expect(marek?.source == .transcript)
        #expect(marek?.speaker == "Mówca 1")
        #expect(marek?.segment == 0)
        #expect(marek?.startMs == 0)
        #expect(marek?.strength == NameEvidenceGuard.highStrength)
        #expect(marek?.confidence == .high)

        let ann = outcome.accepted.first { $0.kind == .addressed && $0.name == "Anna" }
        #expect(ann?.speaker == "Mówca 2")
        #expect(ann?.strength == NameEvidenceGuard.lowStrength)
        #expect(outcome.accepted.contains { $0.kind == .announced && $0.name == "Ewa" && $0.speaker == "Mówca 3" })
    }

    @Test func anAnswerCutByTheTokenLimitKeepsItsCompleteEntries() async {
        // A loop until the limit (step 1.5): the complete entries count, the open one at the end does not, and a
        // repeated entry is read once.
        let entry =
            #"{"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "nazywam się Marek", "confidence": "high"}"#
        let looping = "[\n  " + Array(repeating: entry, count: 3).joined(separator: ",\n  ") + #",\n  {"speaker": "Mów"#
        let generator = ScriptedGenerator { _, _ in GenerationResult(text: looping, stoppedByTokenLimit: true) }
        let outcome = await pass(generator).run(segments: transcript(), conditions: .init())
        #expect(outcome.status == .answered)
        #expect(outcome.answers == 1)
        #expect(outcome.accepted.map(\.name) == ["Marek"])
        #expect(generator.released == 1)
    }

    @Test func theExcerptsFitTheGeneratorsBudget() async throws {
        // A long meeting's excerpts do not fit the built-in model's context (step 1.5): the pass sends what fits,
        // the phrases first, and counts the rest as dropped.
        let configuration = SpeakerNamePass.Configuration()
        let noRoom = ScriptedGenerator.answering("[]", budget: configuration.answerMaxTokens)
        let none = await pass(noRoom).run(segments: transcript(), conditions: .init())
        #expect(noRoom.calls.isEmpty)
        #expect(none.status == .noExcerpts)
        #expect(none.droppedExcerpts == 2)

        let all = NameMentionExtractor().excerpts(from: transcript())
        let phrase = NameMentionExtractor.estimatedTokens(of: try #require(all.excerpts.first))
        let budget = try #require(
            (configuration.answerMaxTokens...20_000).first {
                configuration.excerptBudget(inputBudgetTokens: $0) >= phrase
            })
        let oneFits = ScriptedGenerator.answering(Self.answer, budget: budget)
        let outcome = await pass(oneFits).run(segments: transcript(), conditions: .init())
        #expect(outcome.excerpts == 1)
        #expect(outcome.droppedExcerpts == 1)
        let sent = oneFits.calls.first?.last?.content ?? ""
        #expect(sent.contains("nazywam się Marek"))
        #expect(!sent.contains("czyli Ewa"))
    }

    // MARK: Failures

    @Test func aFailingGeneratorGivesNoEvidence() async {
        let generator = ScriptedGenerator { _, _ in throw NotesFake.Failure() }
        let outcome = await pass(generator).run(segments: transcript(), conditions: .init())
        #expect(outcome.accepted.isEmpty)
        #expect(generator.calls.count == 1)
        #expect(generator.released == 1)
    }

    @Test func anAnswerThatIsNoJSONGivesNoEvidence() async {
        let generator = ScriptedGenerator.answering("I cannot help with names, sorry.")
        let outcome = await pass(generator).run(segments: transcript(), conditions: .init())
        #expect(outcome.accepted.isEmpty && outcome.answers == 0)
        #expect(generator.released == 1)
    }

    @Test func aPassOverTheLimitIsCancelledAndGivesNoEvidence() async {
        // The target has a local `TestClock` for the recording tests; the shared one moves time by hand.
        let clock = LintelTestSupport.TestClock()
        let cancelled = Flag()
        let generator = ScriptedGenerator { _, _ in
            do {
                try await clock.sleep(for: .seconds(3600))
            } catch {
                cancelled.set()
                throw error
            }
            return GenerationResult(text: Self.answer, stoppedByTokenLimit: false)
        }
        let pass = SpeakerNamePass(generator: generator, sleep: clock.sleeper)
        let task = Task { await pass.run(segments: transcript(), conditions: .init()) }

        await clock.waitForSleepers(1, dueWithin: .seconds(60))
        clock.advance(by: .seconds(60))
        // The limit is the spec's 60 s, armed on the injected clock.
        #expect(clock.wokenDeadlines == [LintelTestSupport.TestInstant(offset: .seconds(60))])
        let outcome = await task.value

        #expect(outcome.accepted.isEmpty)
        #expect(generator.calls.count == 1)
        #expect(await cancelled.wait("the generator to be cancelled by the limit"))
        #expect(outcome.status == .failed)
        // The cancelled operation releases the writer itself, after the limit has already answered.
        #expect(await pollUntil("the writer to be released") { generator.released == 1 })
        clock.finish()
    }

    // MARK: When the model is not asked

    @Test func notesOffMeansNoRequest() async {
        let generator = ScriptedGenerator.answering(Self.answer)
        let outcome = await pass(generator).run(
            segments: transcript(), conditions: .init(notesEnabled: false))
        #expect(generator.calls.isEmpty && generator.opened == 0)
        #expect(outcome.excerpts == 0 && outcome.accepted.isEmpty)
    }

    @Test func namesFromConversationOffMeansNoRequest() async {
        let generator = ScriptedGenerator.answering(Self.answer)
        _ = await pass(generator).run(segments: transcript(), conditions: .init(namesFromConversation: false))
        #expect(generator.calls.isEmpty && generator.opened == 0)
    }

    @Test func aChannelsMeetingMeansNoRequest() async {
        let generator = ScriptedGenerator.answering(Self.answer)
        _ = await pass(generator).run(segments: transcript(), conditions: .init(isChannelMeeting: true))
        #expect(generator.calls.isEmpty && generator.opened == 0)
    }

    @Test func aKnownNameInAnyFormIsACandidate() async {
        // A known name in the lowercase form of the transcript is a candidate only because the list knows it.
        let segments = [
            NameSegment(speaker: "Mówca 1", startMs: 0, endMs: 9_000, text: "Dobrze, że zofia jest dziś w biurze.")
        ]
        let withoutList = ScriptedGenerator.answering("[]")
        _ = await pass(withoutList).run(segments: segments, conditions: .init())
        #expect(withoutList.calls.isEmpty)

        let withList = ScriptedGenerator.answering("[]")
        _ = await pass(withList, knownNames: ["Zofia"]).run(segments: segments, conditions: .init())
        #expect(withList.calls.count == 1)
    }

    @Test func aTranscriptWithoutCandidatesMeansNoRequest() async {
        let segments = [
            NameSegment(speaker: "Mówca 1", startMs: 0, endMs: 9_000, text: "Spotkanie było krótkie."),
            NameSegment(speaker: "Mówca 2", startMs: 10_000, endMs: 19_000, text: "Widzimy się jutro."),
        ]
        let generator = ScriptedGenerator.answering(Self.answer)
        let outcome = await pass(generator).run(segments: segments, conditions: .init())
        #expect(generator.calls.isEmpty && generator.opened == 0)
        #expect(outcome.excerpts == 0 && outcome.accepted.isEmpty)
    }

    // MARK: The guard

    @Test func aQuoteOutsideTheTranscriptIsRefused() async {
        let generator = ScriptedGenerator.answering(
            """
            [{"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "to zdanie nigdy nie padło", \
            "confidence": "high"}]
            """)
        let outcome = await pass(generator).run(segments: transcript(), conditions: .init())
        #expect(outcome.accepted.isEmpty)
        #expect(outcome.answers == 1)
        #expect(outcome.rejections == [.quoteNotInTranscript: 1])
    }

    // MARK: What the model does not see

    @Test func theKnownNamesAndSelfNameStayOutOfTheRequest() async {
        let generator = ScriptedGenerator.answering("[]")
        let pass = SpeakerNamePass(generator: generator, knownNames: ["Zofia Wysocka"])
        _ = await pass.run(segments: transcript(), conditions: .init())

        let messages = generator.calls.first ?? []
        #expect(!messages.isEmpty)
        let sent = messages.map(\.content).joined(separator: "\n")
        #expect(!sent.contains("Zofia"))
        #expect(!sent.contains("Wysocka"))
        #expect(!sent.contains("Ala Testowa"))
        // The last turn is the excerpts alone: no list of participants, no title, no self name.
        let input = messages.last?.content ?? ""
        let lines = input.split(separator: "\n").filter { $0.hasPrefix("[") }
        #expect(!lines.isEmpty)
        for line in lines {
            #expect(
                transcript().contains { segment in
                    line.hasSuffix("\(segment.speaker): \(segment.text)")
                }, "\(line)")
        }
    }
}
