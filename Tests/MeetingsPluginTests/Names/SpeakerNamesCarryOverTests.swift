import Foundation
import GRDB
import LintelPersistence
import LintelSpeech
import LintelTestSupport
import Synchronization
import Testing

@testable import MeetingsPlugin

/// A second finalization (`applySpeakerPlan` again, after a crash or "Dokończ") keeps what the user decided about
/// names (spec `2026-11-25-meeting-speaker-names`, Edge Cases, "Ponowna finalizacja"), on the real encrypted store.
/// All names are fictional.
@Suite struct SpeakerNamesCarryOverTests {
    private struct Fixture {
        let store: MeetingsStore
        let directory: TemporaryDirectory
        let meeting: Int64
        let segments: [Int64]
    }

    /// Six segments: 0–1 the owner, 2–3 the first caller, 4–5 the second.
    private func fixture() throws -> Fixture {
        let directory = try TemporaryDirectory()
        let store = try MeetingsStore.open(in: directory.url, keys: testKeys())
        let meeting = try store.insertMeeting(
            uuid: "m", startedAt: Date(timeIntervalSince1970: 1_000), speechModelID: "m", status: .ready)
        var segments: [Int64] = []
        for index in 0..<6 {
            segments.append(
                try store.insertSegment(
                    meetingID: meeting, channel: index < 2 ? .mic : .system, startMs: index * 1000,
                    endMs: index * 1000 + 900, text: "Synthetic \(index)"))
        }
        return Fixture(store: store, directory: directory, meeting: meeting, segments: segments)
    }

    private func plan(_ f: Fixture, swapped: Bool = false) -> SpeakerPlan {
        let first = swapped ? 2 : 1
        let second = swapped ? 1 : 2
        return SpeakerPlan(
            mode: .diarized,
            speakers: [
                .init(label: "Ja", isSelf: true, channel: .mic),
                .init(label: "Mówca 1", isSelf: false, channel: .system),
                .init(label: "Mówca 2", isSelf: false, channel: .system),
            ],
            assignments: [
                f.segments[0]: 0, f.segments[1]: 0, f.segments[2]: first, f.segments[3]: first,
                f.segments[4]: second, f.segments[5]: second,
            ])
    }

    /// The state of the speaker that now holds this segment.
    private func state(_ f: Fixture, segment: Int) throws -> MeetingsStore.SpeakerNameState {
        let speaker = try #require(
            try f.store.loadDocument(id: f.meeting)?.segments.first { $0.id == f.segments[segment] }?.speakerID)
        return try #require(try f.store.speakerNameStates(meetingID: f.meeting).first { $0.speakerID == speaker })
    }

    @Test func aUserNameAConfirmedNameAndRejectionsSurviveANewPlan() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.applySpeakerPlan(plan(f), meetingID: f.meeting, diarizationModelID: nil)
        let first = try state(f, segment: 2)
        let second = try state(f, segment: 4)
        try f.store.renameSpeaker(first.speakerID, label: "Zofia Wysocka")
        try f.store.saveSpeakerNames(
            [
                .init(
                    speakerID: second.speakerID, label: "Mówca 2", source: .transcript, status: .suggested,
                    suggestedName: "Bogdan")
            ], evidence: [], meetingID: f.meeting)
        #expect(try f.store.rejectSuggestedName(speakerID: second.speakerID, name: "Bogdan"))
        try f.store.saveSpeakerNames(
            [
                .init(
                    speakerID: second.speakerID, label: "Mówca 2", source: .transcript, status: .suggested,
                    suggestedName: "Celina")
            ], evidence: [], meetingID: f.meeting)

        // The diarizer numbers the two callers the other way round this time: the segments decide, not the order.
        try f.store.applySpeakerPlan(plan(f, swapped: true), meetingID: f.meeting, diarizationModelID: nil)

        let user = try state(f, segment: 2)
        #expect(user.label == "Zofia Wysocka")
        #expect(user.source == .user)
        #expect(user.status == .confirmed)
        let rejected = try state(f, segment: 4)
        #expect(rejected.rejectedNames == ["Bogdan"])
        // An automatic suggestion is not the user's: it is computed again, never carried.
        #expect(rejected.suggestedName == nil)
        #expect(rejected.label == "Mówca 1")
        #expect(rejected.source == .default)
        // The plan still decides who the owner is.
        let owner = try state(f, segment: 0)
        #expect(owner.isSelf && owner.source == .me)
    }

    @Test func aConfirmedAutomaticNameSurvivesAndAnAppliedOneDoesNot() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.applySpeakerPlan(plan(f), meetingID: f.meeting, diarizationModelID: nil)
        let first = try state(f, segment: 2)
        let second = try state(f, segment: 4)
        try f.store.saveSpeakerNames(
            [
                .init(
                    speakerID: first.speakerID, label: "Zofia", source: .transcript, status: .applied,
                    suggestedName: nil)
            ], evidence: [], meetingID: f.meeting)
        // A confirmed automatic name, as a newer flow could write it.
        try f.store.write { db in
            try db.execute(
                sql: """
                    UPDATE meeting_speaker SET label = 'Bogdan', name_source = 'transcript', name_status = 'confirmed'
                    WHERE id = ?
                    """, arguments: [second.speakerID])
        }

        try f.store.applySpeakerPlan(plan(f), meetingID: f.meeting, diarizationModelID: nil)

        let applied = try state(f, segment: 2)
        #expect(applied.label == "Mówca 1")
        #expect(applied.source == .default)
        let confirmed = try state(f, segment: 4)
        #expect(confirmed.label == "Bogdan")
        #expect(confirmed.source == .transcript)
        #expect(confirmed.status == .confirmed)
    }

    @Test func oneUserNameGoesToOneNewSpeakerOnly() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        // First plan: the first caller holds segments 2, 3 and 4, the second only 5.
        var first = plan(f)
        first.assignments[f.segments[4]] = 1
        try f.store.applySpeakerPlan(first, meetingID: f.meeting, diarizationModelID: nil)
        try f.store.renameSpeaker(try state(f, segment: 2).speakerID, label: "Zofia Wysocka")
        // The new plan splits those segments: 3 and 4 go to one speaker, 2 to the other (with 5). The speaker with
        // more of them takes the name, and only that one.
        var split = plan(f)
        split.assignments[f.segments[2]] = 2
        split.assignments[f.segments[3]] = 1
        split.assignments[f.segments[4]] = 1
        split.assignments[f.segments[5]] = 2
        try f.store.applySpeakerPlan(split, meetingID: f.meeting, diarizationModelID: nil)
        #expect(try state(f, segment: 3).label == "Zofia Wysocka")
        #expect(try state(f, segment: 3).source == .user)
        #expect(try state(f, segment: 2).label == "Mówca 2")
        #expect(try state(f, segment: 2).source == .default)
    }
}

/// The glue between the store rows and the resolver (`MeetingSpeakerNames`), pure parts.
@Suite struct MeetingSpeakerNamesTests {
    private func speaker(_ id: Int64, _ label: String, isSelf: Bool = false) -> MeetingDocument.Speaker {
        MeetingDocument.Speaker(id: id, label: label, isSelf: isSelf, channel: isSelf ? .mic : .system)
    }

    private func state(
        _ id: Int64, _ label: String, isSelf: Bool = false, source: NameSource?, status: SpeakerNameStatus?
    ) -> MeetingsStore.SpeakerNameState {
        MeetingsStore.SpeakerNameState(
            speakerID: id, label: label, isSelf: isSelf, source: source, status: status, suggestedName: nil,
            rejectedNames: [])
    }

    @Test func theStoresNoNameStateIsNotAConfirmedName() {
        let cluster = MeetingSpeakerNames.cluster(
            for: speaker(1, "Mówca 1"), state: state(1, "Mówca 1", source: .default, status: .confirmed))
        #expect(cluster.source == .default)
        #expect(cluster.status == .suggested)
    }

    @Test func theOwnerCalledJaIsLeftToTheResolverAndANamedOwnerIsKept() {
        let ja = MeetingSpeakerNames.cluster(
            for: speaker(1, "Ja", isSelf: true), state: state(1, "Ja", isSelf: true, source: .me, status: .confirmed))
        #expect(ja.source == .me && ja.status == .suggested)
        let named = MeetingSpeakerNames.cluster(
            for: speaker(1, "Zofia", isSelf: true),
            state: state(1, "Zofia", isSelf: true, source: .me, status: .confirmed))
        #expect(named.source == .user && named.status == .confirmed)
    }

    @Test func aValueOfANewerBuildIsUntouchable() {
        let newer = MeetingSpeakerNames.cluster(
            for: speaker(1, "Zofia"), state: state(1, "Zofia", source: nil, status: .applied))
        #expect(newer.source == .user && newer.status == .confirmed)
        #expect(!MeetingSpeakerNames.isWritable(state(1, "Zofia", source: nil, status: .applied)))
    }

    @Test func theWritableTestIsTheStoresGuard() {
        let cases: [(NameSource?, SpeakerNameStatus?, Bool, Bool)] = [
            (.default, .confirmed, false, true), (.default, .suggested, false, true),
            (.transcript, .applied, false, true), (.transcript, .suggested, false, true),
            (.platform, .applied, false, true), (.calendar, .suggested, false, true),
            (.transcript, .confirmed, false, false), (.user, .confirmed, false, false),
            (.me, .confirmed, false, false), (.default, .confirmed, true, false), (nil, .confirmed, false, false),
        ]
        for (source, status, isSelf, writable) in cases {
            #expect(
                MeetingSpeakerNames.isWritable(state(1, "x", isSelf: isSelf, source: source, status: status))
                    == writable, "\(String(describing: source)) \(String(describing: status)) self=\(isSelf)")
        }
    }

    private func document(_ speakers: [MeetingDocument.Speaker], firsts: [Int64: Int]) -> MeetingDocument {
        MeetingDocument(
            id: 1, uuid: "u", startedAt: Date(timeIntervalSince1970: 0), durationMs: 0, title: nil, status: .ready,
            speakerMode: .diarized, audioState: .deleted, notesMarkdown: nil, notesStatus: .none,
            notesDroppedCount: 0, speakers: speakers,
            segments: firsts.sorted { $0.value < $1.value }.enumerated().map { index, entry in
                MeetingDocument.Segment(
                    id: Int64(index + 1), channel: .system, startMs: entry.value, endMs: entry.value + 500,
                    speakerID: entry.key, text: "Synthetic")
            })
    }

    @Test func aWithdrawnNameGetsTheNumberOfItsFirstAppearance() {
        let doc = document(
            [speaker(1, "Ja", isSelf: true), speaker(2, "Zofia"), speaker(3, "Mówca 1"), speaker(4, "Bogdan")],
            firsts: [1: 0, 3: 1_000, 2: 2_000, 4: 3_000])
        let labels = MeetingSpeakerNames.defaultLabels(for: doc, reverting: [2, 3, 4])
        #expect(labels[3] == "Mówca 1")
        #expect(labels[2] == "Mówca 2")
        #expect(labels[4] == "Mówca 3")
    }

    @Test func aTakenNumberGivesTheLowestFreeOne() {
        // Speaker 3 shows "Mówca 1" (after "To ja" moved the owner), so Zofia's first-appearance number is taken.
        let doc = document(
            [speaker(1, "Ja", isSelf: true), speaker(2, "Zofia"), speaker(3, "Mówca 1")],
            firsts: [1: 0, 2: 1_000, 3: 2_000])
        let labels = MeetingSpeakerNames.defaultLabels(for: doc, reverting: [2])
        #expect(labels[2] == "Mówca 2")
    }
}

/// How the pass reports its end, and the time limit around the open of the writer.
@Suite struct SpeakerNamePassStatusTests {
    private static let lines = [
        NameSegment(speaker: "Mówca 1", startMs: 0, endMs: 900, text: "Dzień dobry, nazywam się Zofia."),
        NameSegment(speaker: "Mówca 2", startMs: 1000, endMs: 1900, text: "Witam wszystkich."),
    ]

    @Test func theStatusSaysWhatHappened() async {
        let answered = await SpeakerNamePass(generator: ScriptedGenerator.answering("[]"))
            .run(segments: Self.lines, conditions: .init())
        #expect(answered.status == .answered)

        let failing = ScriptedGenerator { _, _ in throw NotesFake.Failure() }
        #expect(
            await SpeakerNamePass(generator: failing).run(segments: Self.lines, conditions: .init()).status == .failed)

        let cut = ScriptedGenerator { _, _ in GenerationResult(text: "[", stoppedByTokenLimit: true) }
        #expect(await SpeakerNamePass(generator: cut).run(segments: Self.lines, conditions: .init()).status == .failed)

        let off = await SpeakerNamePass(generator: ScriptedGenerator.answering("[]"))
            .run(segments: Self.lines, conditions: .init(namesFromConversation: false))
        #expect(off.status == .notAsked)

        let plain = [NameSegment(speaker: "Mówca 1", startMs: 0, endMs: 900, text: "witam wszystkich")]
        let nothing = await SpeakerNamePass(generator: ScriptedGenerator.answering("[]"))
            .run(segments: plain, conditions: .init())
        #expect(nothing.status == .noExcerpts)
    }

    @Test func theRequestTimeIsMeasuredOnTheInjectedClock() async {
        let base = ContinuousClock.now
        let ticks = Mutex(0)
        let now: @Sendable () -> ContinuousClock.Instant = {
            base
                + .milliseconds(
                    1500
                        * ticks.withLock { tick in
                            defer { tick += 1 }
                            return tick
                        })
        }
        let outcome = await SpeakerNamePass(generator: ScriptedGenerator.answering("[]"), now: now)
            .run(segments: Self.lines, conditions: .init())
        #expect(outcome.elapsedMs == 1500)
    }

    @Test func aStuckOpenIsBoundedByTheLimit() async {
        let clock = LintelTestSupport.TestClock()
        let generator = StuckOpenGenerator()
        let pass = SpeakerNamePass(generator: generator, sleep: clock.sleeper)
        let task = Task { await pass.run(segments: Self.lines, conditions: .init()) }
        await clock.waitForSleepers(1, dueWithin: .seconds(60))
        clock.advance(by: .seconds(60))
        let outcome = await task.value
        #expect(outcome.status == .failed)
        #expect(outcome.accepted.isEmpty)
        #expect(generator.requests == 0)
        // The open comes back later (a load that ignores cancellation) and is released, never kept.
        generator.letGo()
        #expect(await pollUntil("the stuck writer to be released") { generator.released == 1 })
        clock.finish()
    }
}

/// A writer whose open waits until the test lets it go, ignoring cancellation like a model load.
final class StuckOpenGenerator: NotesGenerating, @unchecked Sendable {
    let profile = NotesGeneratorProfile(strategy: .quotedChunks, inputBudgetTokens: 8192, promptFormat: "test")
    private let state = Mutex((open: false, released: 0, requests: 0))

    var released: Int { state.withLock { $0.released } }
    var requests: Int { state.withLock { $0.requests } }
    func letGo() { state.withLock { $0.open = true } }

    func open() async throws {
        while !state.withLock({ $0.open }) { try? await Task.sleep(for: .milliseconds(2)) }
    }

    func release() async { state.withLock { $0.released += 1 } }

    func generateResult(
        messages: [ChatMessage], maxTokens: Int, onPhase: (@Sendable (GenerationPhase) -> Void)?
    ) async throws -> GenerationResult {
        state.withLock { $0.requests += 1 }
        return GenerationResult(text: "[]", stoppedByTokenLimit: false)
    }
}
