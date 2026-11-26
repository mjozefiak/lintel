import Foundation
import GRDB
import LintelKit
import LintelSpeech
import LintelTestSupport
import Synchronization
import Testing

@testable import LintelProviders
@testable import MeetingsPlugin

/// Speaker names wired into the notes job (spec `2026-11-25-meeting-speaker-names`, step 1.4b), over the notes rig:
/// a real encrypted library, a scripted model and, for the provider, a fake CLI process. Every name is fictional,
/// and none of the prompt's own example (Marek, Anna, Ewa) is used, so a name found in a request or a trace can only
/// come from the meeting.
enum NamesWiring {
    static let owner = "Ala Testowa"

    /// The owner on the microphone and two people on the call, numbered as `SpeakerAssigner` does.
    static let speakers: [SpeakerPlan.Speaker] = [
        .init(label: SpeakerLabels.me, isSelf: true, channel: .mic),
        .init(label: SpeakerLabels.numbered(1), isSelf: false, channel: .system),
        .init(label: SpeakerLabels.numbered(2), isSelf: false, channel: .system),
    ]

    /// Zofia introduces herself, calls Bogdan by name and he answers; the owner takes a task; a last line far from
    /// any name is outside every excerpt.
    static let lines: [(speaker: Int, text: String)] = [
        (1, "Dzień dobry, nazywam się Zofia."),
        (1, "Bogdan, czy budżet jest gotowy?"),
        (2, "Tak, budżet jest gotowy, zatwierdzamy go bez zmian."),
        (0, "Dziękuję, wyślę ofertę do klienta do piątku."),
        (2, "Omawiamy jeszcze harmonogram projektu w tym kwartale."),
    ]

    /// The model's answer for `lines`: a sure introduction and a vocative.
    static let answer = """
        [
          {"speaker": "Mówca 1", "name": "Zofia", "kind": "introduction", "quote": "nazywam się Zofia", "confidence": "high"},
          {"speaker": "Mówca 2", "name": "Bogdan", "kind": "addressed", "quote": "Bogdan, czy budżet jest gotowy", "confidence": "high"}
        ]
        """

    static func isNames(_ messages: [ChatMessage]) -> Bool { messages.first?.content == SpeakerNamePrompt.system }

    /// `NotesFake.standard` for the notes; `names` answers the names request.
    static func handler(names: @escaping @Sendable () async throws -> GenerationResult) -> ScriptedLLM.Handler {
        { call, messages, maxTokens in
            if isNames(messages) { return try await names() }
            return try await NotesFake.standard(call, messages, maxTokens)
        }
    }

    static func answering(_ text: String = answer) -> ScriptedLLM.Handler {
        handler { .done(text) }
    }

    static func settings(_ extra: [String: SettingValue] = [:]) -> [String: SettingValue] {
        var settings: [String: SettingValue] = [
            "plugins.meetings.notesEnabled": .bool(true), "plugins.meetings.selfName": .string(owner),
        ]
        settings.merge(extra) { _, new in new }
        return settings
    }

    /// A `ready` meeting with `lines`, given speakers by a speaker plan (as the finalizer does).
    @MainActor
    static func addMeeting(
        _ rig: NotesServiceRig, mode: SpeakerMode = .diarized, lines: [(speaker: Int, text: String)] = lines,
        plan: [SpeakerPlan.Speaker] = NamesWiring.speakers
    ) async throws -> Int64 {
        let lines = lines.map { ($0.speaker, $0.text) }
        return try await rig.perform { store in
            let id = try store.insertMeeting(
                uuid: UUID().uuidString, startedAt: Date(timeIntervalSince1970: 1_700_000_000), speechModelID: "m",
                status: .ready)
            var assignments: [Int64: Int] = [:]
            for (index, line) in lines.enumerated() {
                let segment = try store.insertSegment(
                    meetingID: id, channel: plan[line.0].channel, startMs: index * 10_000 + 5_000,
                    endMs: index * 10_000 + 9_000, text: line.1)
                assignments[segment] = line.0
            }
            try store.applySpeakerPlan(
                SpeakerPlan(mode: mode, speakers: plan, assignments: assignments), meetingID: id,
                diarizationModelID: nil)
            return id
        }
    }

    /// The labels of the transcript lines a names request carried (the excerpts), in order.
    static func excerptLabels(_ call: ScriptedLLM.Call) -> [String] {
        (call.messages.last?.content ?? "").split(separator: "\n").compactMap { line in
            line.firstMatch(of: #/^\[\d+:\d\d\] ([^:]+): /#).map { String($0.1) }
        }
    }

    /// Every request of the name pass, in order.
    static func namesCalls(_ llm: ScriptedLLM) -> [ScriptedLLM.Call] {
        llm.calls.filter { isNames($0.messages) }
    }

    /// The labels of the speakers in a document, by speaker id (the test's own ids, never shown anywhere).
    static func labels(of document: MeetingDocument) -> [Int64: String] {
        Dictionary(document.speakers.map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    /// The speaker labels the notes' MAP requests carried (`[mm:ss] Label: text`).
    static func notesLabels(_ llm: ScriptedLLM) -> Set<String> {
        Set(
            llm.calls.filter { NotesFake.isMap($0.messages) }.flatMap { call in
                NotesFake.lastUser(call.messages).split(separator: "\n").compactMap { line in
                    line.firstMatch(of: #/^\[\d+:\d\d\] ([^:]+): /#).map { String($0.1) }
                }
            })
    }

    static func namesRequests(_ llm: ScriptedLLM) -> Int { llm.calls.filter { isNames($0.messages) }.count }

    /// The stored name state of the speaker with this plan index (the speakers are written in plan order).
    @MainActor
    static func state(_ rig: NotesServiceRig, _ id: Int64, speaker index: Int) throws
        -> MeetingsStore.SpeakerNameState
    {
        let states = try rig.store.speakerNameStates(meetingID: id)
        return try #require(states.indices.contains(index) ? states[index] : nil)
    }
}

/// Collects the trace events the service sends.
final class TraceLog: Sendable {
    private let events = Mutex<[NotesTraceEvent]>([])
    var all: [NotesTraceEvent] { events.withLock { $0 } }
    var sink: NotesTraceSink { { [self] event in events.withLock { $0.append(event) } } }

    var speakerNames: [NotesTraceSpeakerNames] {
        all.compactMap { event in
            if case .speakerNames(let names) = event { return names }
            return nil
        }
    }
}

@MainActor
@Suite struct SpeakerNamesWiringTests {
    typealias W = NamesWiring

    // MARK: Names reach the transcript and the notes

    @Test func aSureIntroductionBecomesTheLabelOfTheTranscriptAndTheNotes() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 1)
        // The names request comes before the notes' first request.
        #expect(rig.llm.calls.first.map { W.isNames($0.messages) } == true)

        let zofia = try W.state(rig, id, speaker: 1)
        #expect(zofia.label == "Zofia")
        #expect(zofia.source == .transcript)
        #expect(zofia.status == .applied)
        // The stored transcript shows it: the document's speaker label is the name.
        #expect(try rig.document(id).speakers.map(\.label) == [SpeakerLabels.me, "Zofia", "Mówca 2"])

        // A vocative is only a suggestion: the label stays the default one.
        let bogdan = try W.state(rig, id, speaker: 2)
        #expect(bogdan.label == "Mówca 2")
        #expect(bogdan.status == .suggested)
        #expect(bogdan.suggestedName == "Bogdan")

        // The notes read the applied name and never the suggestion; the owner's "Ja" is `selfName`, as before.
        let labels = W.notesLabels(rig.llm)
        #expect(labels.contains("Zofia"))
        #expect(labels.contains("Mówca 2"))
        #expect(labels.contains(W.owner))
        #expect(!labels.contains("Bogdan"))
        #expect(!labels.contains("Mówca 1"))
        #expect(try rig.record(id).status == .ok)

        // The owner's speaker is never written by a resolution.
        let owner = try W.state(rig, id, speaker: 0)
        #expect(owner.label == SpeakerLabels.me)
        #expect(owner.source == .me)

        // Only the evidence the result rests on, pointing at its segments.
        let evidence = try rig.store.nameEvidence(meetingID: id)
        #expect(evidence.count == 2)
        #expect(evidence.allSatisfy { $0.segmentID != nil && $0.source == .transcript })
    }

    @Test func theOwnersNameIsNeverGivenToAnotherSpeaker() async throws {
        let answer = """
            [{"speaker": "Mówca 1", "name": "Ala Testowa", "kind": "introduction", "quote": "nazywam się Ala Testowa", "confidence": "high"}]
            """
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering(answer))
        await rig.start()
        let id = try await W.addMeeting(
            rig, lines: [(1, "Dzień dobry, nazywam się Ala Testowa."), (0, "Zatwierdzamy budżet bez zmian.")])
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 1)
        let other = try W.state(rig, id, speaker: 1)
        #expect(other.label == "Mówca 1")
        #expect(other.suggestedName == nil)
    }

    // MARK: When the model is not asked

    @Test func withNotesOffNoModelIsAskedAndTheOwnerKeepsSelf() async throws {
        let rig = try NotesServiceRig(
            settings: W.settings(["plugins.meetings.notesEnabled": .bool(false)]), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        #expect(rig.llm.calls.isEmpty)
        let owner = try W.state(rig, id, speaker: 0)
        #expect(owner.source == .me && owner.label == SpeakerLabels.me)
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
    }

    @Test func aRegenerateWithTheNotesSwitchOffStillAsksForNames() async throws {
        // "Regenerate" writes notes whatever the switch says, so its job loads the model anyway: the names come
        // with it (orchestrator decision 2026-11-26).
        let rig = try NotesServiceRig(
            settings: W.settings(["plugins.meetings.notesEnabled": .bool(false)]), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.regenerate(id)
        #expect(await rig.settle())
        #expect(W.namesRequests(rig.llm) == 1)
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia")
        #expect(W.notesLabels(rig.llm).contains("Zofia"))
        #expect(W.notesLabels(rig.llm).contains(W.owner))
        #expect(try W.state(rig, id, speaker: 0).source == .me)
    }

    @Test func aResolveWithoutThePassKeepsTheNamesFromTheConversation() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let evidence = try rig.store.nameEvidence(meetingID: id)
        #expect(evidence.count == 2)

        // The user turns names from the conversation off, then asks for the notes again: nothing new is known
        // about the conversation, so what it gave stays.
        rig.settings.setNamesFromConversation(false)
        let before = rig.llm.calls.count
        rig.service.regenerate(id)
        #expect(await rig.settle())
        #expect(W.namesRequests(rig.llm) == 1)
        let zofia = try W.state(rig, id, speaker: 1)
        #expect(zofia.label == "Zofia")
        #expect(zofia.source == .transcript && zofia.status == .applied)
        let bogdan = try W.state(rig, id, speaker: 2)
        #expect(bogdan.suggestedName == "Bogdan")
        #expect(bogdan.label == "Mówca 2")
        #expect(try rig.store.nameEvidence(meetingID: id).count == evidence.count)
        // The new notes read the kept name.
        let again = rig.llm.calls.dropFirst(before).filter { NotesFake.isMap($0.messages) }
        #expect(!again.isEmpty)
        #expect(again.contains { NotesFake.lastUser($0.messages).contains("Zofia: ") })
    }

    @Test func namesFromTheConversationOffMeansNoRequest() async throws {
        let rig = try NotesServiceRig(
            settings: W.settings(["plugins.meetings.namesFromConversation": .bool(false)]), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 0)
        #expect(try rig.record(id).status == .ok)
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
    }

    @Test func aChannelsMeetingIsNeverNamed() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig, mode: .channels)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 0)
        #expect(try rig.record(id).status == .ok)
        #expect(try rig.store.speakerNameStates(meetingID: id).allSatisfy { $0.source != .transcript })
    }

    // MARK: A pass that fails never stops the notes

    @Test func aFailingPassLeavesTheNotesWithoutNames() async throws {
        let rig = try NotesServiceRig(
            settings: W.settings(), handler: W.handler { throw NotesFake.Failure() })
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 1)
        #expect(try rig.record(id).status == .ok)
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
        #expect(W.notesLabels(rig.llm).contains("Mówca 1"))
    }

    @Test func aPassOverItsLimitLeavesTheNotesWithoutNames() async throws {
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                try await Task.sleep(for: .seconds(3600))
                return .done(NamesWiring.answer)
            },
            configureNames: { $0.timeout = .milliseconds(50) })
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 1)
        #expect(try rig.record(id).status == .ok)
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
    }

    @Test func aShutDownDuringThePassWritesNothing() async throws {
        let started = LintelTestSupport.Latch()
        let log = TraceLog()
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                started.open()
                try await Task.sleep(for: .seconds(3600))
                return .done(NamesWiring.answer)
            }, shutdownLimit: .seconds(5), trace: log.sink)
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await started.wait("the names request to start"))
        await rig.service.shutDown()

        #expect(rig.llm.calls.allSatisfy { W.isNames($0.messages) })
        #expect(try rig.record(id).status == .none)
        #expect(try rig.record(id).hasMarkdown == false)
        // The job ends at the pass: no result is reported for a pass that was cut off.
        #expect(!log.all.contains { if case .speakerNames = $0 { true } else { false } })
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
        #expect(try rig.store.nameEvidence(meetingID: id).isEmpty)
    }

    // MARK: A regeneration keeps the user's decisions

    @Test func aRegenerationKeepsWhatTheUserDecidedAndRecomputesTheRest() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let bogdan = try W.state(rig, id, speaker: 2)
        #expect(bogdan.suggestedName == "Bogdan")

        // "To nie Bogdan" on the suggestion, then a name the user types for Zofia's speaker.
        let zofia = try W.state(rig, id, speaker: 1)
        _ = try await rig.perform { try $0.rejectSuggestedName(speakerID: bogdan.speakerID, name: "Bogdan") }
        try await rig.perform { try $0.renameSpeaker(zofia.speakerID, label: "Zofia Wysocka") }

        rig.service.regenerate(id)
        #expect(await rig.settle())
        #expect(W.namesRequests(rig.llm) == 2)

        let renamed = try W.state(rig, id, speaker: 1)
        #expect(renamed.label == "Zofia Wysocka")
        #expect(renamed.source == .user)
        // Where the name the user kept came from stays with it (the 1.6 tooltip reads it).
        #expect(try rig.store.nameEvidence(meetingID: id).contains { $0.speakerID == renamed.speakerID })
        let rejected = try W.state(rig, id, speaker: 2)
        #expect(rejected.suggestedName == nil)
        #expect(rejected.label == "Mówca 2")
        #expect(rejected.rejectedNames == ["Bogdan"])
        #expect(W.notesLabels(rig.llm).contains("Zofia Wysocka"))
    }

    @Test func aConfirmedSuggestionSurvivesARegeneration() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering("[]"))
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        // The first run found nothing; a suggestion the user then confirms stands for every later run.
        let speaker = try W.state(rig, id, speaker: 2)
        try await rig.perform { store in
            try store.saveSpeakerNames(
                [
                    .init(
                        speakerID: speaker.speakerID, label: "Mówca 2", source: .transcript, status: .suggested,
                        suggestedName: "Bogdan")
                ], evidence: [], meetingID: id)
        }
        #expect(try await rig.perform { try $0.confirmSuggestedName(speakerID: speaker.speakerID, name: "Bogdan") })

        rig.service.regenerate(id)
        #expect(await rig.settle())
        let confirmed = try W.state(rig, id, speaker: 2)
        #expect(confirmed.label == "Bogdan")
        #expect(confirmed.status == .confirmed)
    }

    @Test func aNameWithoutEvidenceGetsItsDefaultLabelBack() async throws {
        let answers = Mutex([NamesWiring.answer, "[]"])
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                .done(answers.withLock { $0.count > 1 ? $0.removeFirst() : $0[0] })
            })
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia")

        rig.service.regenerate(id)
        #expect(await rig.settle())
        let reverted = try W.state(rig, id, speaker: 1)
        #expect(reverted.label == "Mówca 1")
        #expect(reverted.source == .default)
        #expect(try W.state(rig, id, speaker: 2).suggestedName == nil)
        #expect(try rig.store.nameEvidence(meetingID: id).isEmpty)
    }

    @Test func aFailedPassOnARegenerationKeepsTheEarlierNames() async throws {
        let fail = Flag()
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                if fail.isSet { throw NotesFake.Failure() }
                return .done(NamesWiring.answer)
            })
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        fail.set()
        rig.service.regenerate(id)
        #expect(await rig.settle())

        #expect(W.namesRequests(rig.llm) == 2)
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia")
        #expect(try W.state(rig, id, speaker: 2).suggestedName == "Bogdan")
        #expect(try rig.store.nameEvidence(meetingID: id).count == 2)
    }

    // MARK: Privacy

    @Test func theTraceHoldsCountsAndNoName() async throws {
        let log = TraceLog()
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering(), trace: log.sink)
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        let names = try #require(log.speakerNames.first)
        #expect(log.speakerNames.count == 1)
        #expect(names.passStatus == .answered)
        #expect(names.excerpts == 1)
        #expect(names.answers == 2)
        #expect(names.acceptedEvidence == 2)
        #expect(names.speakers == 3)
        #expect(names.written)
        #expect(names.applied == ["transcript": 1])
        #expect(names.suggested == ["transcript": 1])

        let encoded = String(decoding: try JSONEncoder().encode(log.all), as: UTF8.self)
        for text in ["Zofia", "Bogdan", "Ala", "Testowa", "nazywam", "budżet", "Mówca"] {
            #expect(!encoded.contains(text), "the trace holds \(text)")
        }
    }

    @Test func theProviderGetsOnlyExcerptsForNames() async throws {
        let process = CountingProviderProcess { _, spec in
            let request = String(decoding: spec.stdin, as: UTF8.self) + spec.arguments.joined(separator: " ")
            if request.contains("You find the names of the people") {
                return ProviderFixtures.output(answer: NamesWiring.answer)
            }
            return ProviderFixtures.output(answer: ProviderFixtures.draft)
        }
        var settings = ProviderFixtures.chosen
        settings["plugins.meetings.selfName"] = .string(W.owner)
        let rig = try NotesServiceRig(settings: settings, providerRunner: ProviderFixtures.runner(process))
        await rig.start()
        // The owner opens, right before Zofia's introduction: the owner's line is inside the excerpt.
        let id = try await W.addMeeting(rig, lines: [(0, "Dzień dobry wszystkim, zaczynamy spotkanie.")] + W.lines)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())

        #expect(rig.llm.calls.isEmpty)
        let specs = process.specs
        #expect(specs.count >= 2)
        let names = String(decoding: try #require(specs.first).stdin, as: UTF8.self)
        // The excerpt around the names, nothing else of the meeting, and nothing the conversation did not say.
        #expect(names.contains("nazywam się Zofia"))
        #expect(names.contains("Bogdan, czy budżet jest gotowy?"))
        #expect(!names.contains("harmonogram"))
        #expect(!names.contains("wyślę ofertę"))
        // The owner's line goes with its stored label, never with `selfName`.
        #expect(names.contains("Ja: Dzień dobry wszystkim"))
        #expect(!names.contains(W.owner))

        // The notes go to the same provider afterwards, with the applied name as the speaker label.
        let notes = String(decoding: specs[1].stdin, as: UTF8.self)
        #expect(notes.contains("Zofia:"))
        #expect(notes.contains("harmonogram"))
        #expect(!notes.contains("Bogdan:"))
        #expect(notes.contains(W.owner))
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia")
    }

    @Test func writeOnThisMacNeverSendsExcerptsToTheProvider() async throws {
        let process = CountingProviderProcess()
        var settings = ProviderFixtures.chosen
        settings["plugins.meetings.selfName"] = .string(W.owner)
        let rig = try NotesServiceRig(
            settings: settings, handler: W.answering(), providerRunner: ProviderFixtures.runner(process))
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.writeOnThisMac(id)
        #expect(await rig.settle())

        #expect(process.contentRuns == 0)
        #expect(W.namesRequests(rig.llm) == 1)
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia")
    }

    // MARK: A decision made while the model reads

    @Test func aRejectionDuringThePassKeepsTheNameAway() async throws {
        let storeBox = Shared<MeetingsStore?>(nil)
        let passes = Mutex(0)
        let rejected = Mutex<Int64?>(nil)
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                let pass = passes.withLock { count -> Int in
                    count += 1
                    return count
                }
                if pass == 2, let store = storeBox.get(), let speaker = rejected.withLock({ $0 }) {
                    _ = try store.rejectSuggestedName(speakerID: speaker, name: "Bogdan")
                }
                return .done(NamesWiring.answer)
            })
        await rig.start()
        storeBox.update { $0 = rig.store }
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let bogdan = try W.state(rig, id, speaker: 2)
        #expect(bogdan.suggestedName == "Bogdan")
        rejected.withLock { $0 = bogdan.speakerID }

        // "To nie Bogdan" lands while the second pass is reading: the resolution must see it and never offer the
        // name again.
        rig.service.regenerate(id)
        #expect(await rig.settle())
        #expect(W.namesRequests(rig.llm) == 2)
        let after = try W.state(rig, id, speaker: 2)
        #expect(after.suggestedName == nil)
        #expect(after.rejectedNames == ["Bogdan"])
        #expect(after.label == "Mówca 2")
    }

    @Test func aRenameDuringThePassReservesTheNameForItsSpeaker() async throws {
        let storeBox = Shared<MeetingsStore?>(nil)
        let passes = Mutex(0)
        let renamed = Mutex<Int64?>(nil)
        let answer = """
            [{"speaker": "Mówca 1", "name": "Marek", "kind": "introduction", "quote": "nazywam się Marek", \
            "confidence": "high"}]
            """
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                let pass = passes.withLock { count -> Int in
                    count += 1
                    return count
                }
                if pass == 1, let store = storeBox.get(), let speaker = renamed.withLock({ $0 }) {
                    try store.renameSpeaker(speaker, label: "Marek")
                }
                return .done(answer)
            })
        await rig.start()
        storeBox.update { $0 = rig.store }
        let id = try await W.addMeeting(
            rig, lines: [(1, "Dzień dobry, nazywam się Marek."), (2, "Cześć, zaczynamy spotkanie.")])
        let second = try W.state(rig, id, speaker: 2)
        renamed.withLock { $0 = second.speakerID }

        // The user names the second speaker "Marek" while the pass is reading; the name found in the first
        // speaker's words must not be applied to it.
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        #expect(try W.state(rig, id, speaker: 1).label == "Mówca 1")
        #expect(try W.state(rig, id, speaker: 1).suggestedName == nil)
        #expect(try W.state(rig, id, speaker: 2).label == "Marek")
        #expect(try W.state(rig, id, speaker: 2).source == .user)
    }

    @Test func aMergeDuringThePassNumbersTheSpeakersOfTheNewSet() async throws {
        let plan: [SpeakerPlan.Speaker] = [
            .init(label: SpeakerLabels.me, isSelf: true, channel: .mic),
            .init(label: SpeakerLabels.numbered(1), isSelf: false, channel: .system),
            .init(label: SpeakerLabels.numbered(2), isSelf: false, channel: .system),
            .init(label: SpeakerLabels.numbered(3), isSelf: false, channel: .system),
        ]
        let storeBox = Shared<MeetingsStore?>(nil)
        let merge = Shared<(source: Int64, target: Int64, meeting: Int64)?>(nil)
        let passes = Mutex(0)
        let first = """
            [
              {"speaker": "Mówca 1", "name": "Zofia", "kind": "introduction", "quote": "nazywam się Zofia", \
            "confidence": "high"},
              {"speaker": "Mówca 2", "name": "Anna", "kind": "introduction", "quote": "jestem Anna", \
            "confidence": "high"}
            ]
            """
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                let pass = passes.withLock { count -> Int in
                    count += 1
                    return count
                }
                if pass == 1 { return .done(first) }
                if let store = storeBox.get(), let plan = merge.get() {
                    try store.mergeSpeaker(plan.source, into: plan.target, meetingID: plan.meeting)
                }
                return .done("[]")
            })
        await rig.start()
        storeBox.update { $0 = rig.store }
        let id = try await W.addMeeting(
            rig,
            lines: [
                (1, "Dzień dobry, nazywam się Zofia."), (2, "Cześć, jestem Anna."),
                (3, "Zaczynamy od budżetu."),
            ], plan: plan)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let states = try rig.store.speakerNameStates(meetingID: id)
        #expect(states.count == 4)
        #expect(states[1].label == "Zofia")
        #expect(states[2].label == "Anna")
        merge.update { $0 = (states[1].speakerID, states[2].speakerID, id) }

        // The first and the second speaker are one person now, and the answer names nobody: the reverted name takes
        // the number of the new set (the order of first appearance), never the one from before the pass.
        rig.service.regenerate(id)
        #expect(await rig.settle())
        let labels = W.labels(of: try rig.document(id))
        #expect(!labels.values.contains("Zofia"))
        #expect(!labels.values.contains("Anna"))
        #expect(labels[states[2].speakerID] == "Mówca 1")
        #expect(labels[states[3].speakerID] == "Mówca 3")
        #expect(labels[states[0].speakerID] == SpeakerLabels.me)
    }

    @Test func aMergeDuringThePassFollowsTheSegments() async throws {
        let storeBox = Shared<MeetingsStore?>(nil)
        let merge = Shared<(source: Int64, target: Int64, meeting: Int64)?>(nil)
        let passes = Mutex(0)
        let answer = """
            [{"speaker": "Mówca 1", "name": "Zofia", "kind": "introduction", "quote": "nazywam się Zofia", \
            "confidence": "high"}]
            """
        let rig = try NotesServiceRig(
            settings: W.settings(),
            handler: W.handler {
                let pass = passes.withLock { count -> Int in
                    count += 1
                    return count
                }
                if pass == 1, let store = storeBox.get(), let plan = merge.get() {
                    try store.mergeSpeaker(plan.source, into: plan.target, meetingID: plan.meeting)
                }
                return .done(answer)
            })
        await rig.start()
        storeBox.update { $0 = rig.store }
        let id = try await W.addMeeting(
            rig, lines: [(1, "Dzień dobry, nazywam się Zofia."), (2, "Cześć, zaczynamy spotkanie.")])
        let states = try rig.store.speakerNameStates(meetingID: id)
        merge.update { $0 = (states[1].speakerID, states[2].speakerID, id) }

        // The speaker who introduced themselves is merged into the other one while the model reads: the name found
        // in that segment belongs to the speaker who owns it now.
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let labels = W.labels(of: try rig.document(id))
        #expect(labels[states[2].speakerID] == "Zofia")
        #expect(!labels.values.contains("Mówca 1"))
        let evidence = try rig.store.nameEvidence(meetingID: id)
        #expect(!evidence.isEmpty)
        #expect(evidence.allSatisfy { $0.speakerID != nil })
        #expect(evidence.allSatisfy { $0.speakerID == states[2].speakerID })
        #expect(W.notesLabels(rig.llm).contains("Zofia"))
    }

    // MARK: The pass never reads a name as a label

    @Test func aRegenerationSendsNumberedLabelsNeverTheStoredNames() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        rig.service.meetingBecameReady(id)
        #expect(await rig.settle())
        let zofia = try W.state(rig, id, speaker: 1)
        try await rig.perform { try $0.renameSpeaker(zofia.speakerID, label: "Zofia Wysocka") }

        rig.service.regenerate(id)
        #expect(await rig.settle())
        let calls = W.namesCalls(rig.llm)
        #expect(calls.count == 2)
        let labels = W.excerptLabels(calls[1])
        #expect(!labels.isEmpty)
        #expect(!labels.contains("Zofia Wysocka"))
        #expect(labels.allSatisfy { $0 == SpeakerLabels.me || $0.hasPrefix(SpeakerLabels.numberedPrefix) })
        // The answer still lands: the suggestion of the second speaker comes back.
        #expect(try W.state(rig, id, speaker: 2).suggestedName == "Bogdan")
        // The user's own name is untouched by the resolution.
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia Wysocka")
        #expect(try W.state(rig, id, speaker: 1).source == .user)
    }

    // MARK: A read that fails writes nothing

    @Test func anEvidenceReadErrorAbortsTheNameWrite() async throws {
        let rig = try NotesServiceRig(settings: W.settings(), handler: W.answering())
        await rig.start()
        let id = try await W.addMeeting(rig)
        let states = try rig.store.speakerNameStates(meetingID: id)
        let named = states[1]
        // The user names the first speaker and its evidence points where the name came from; that row is one the
        // next refresh does not write and must keep.
        try await rig.perform { store in
            try store.renameSpeaker(named.speakerID, label: "Zofia Wysocka")
            try store.saveSpeakerNames(
                [],
                evidence: [
                    .init(
                        speakerID: named.speakerID, source: .transcript, name: "Zofia", kind: .introduction,
                        segmentID: nil, startMs: nil, endMs: nil, strength: 1)
                ], meetingID: id)
        }

        let report = try #require(
            await MeetingSpeakerNames.refresh(
                store: FailingEvidenceReads(base: rig.store), document: try rig.document(id),
                selfName: NamesWiring.owner, pass: nil, conditions: .init()))

        #expect(report.writeFailure == .evidenceRead)
        #expect(!report.written)
        let kept = try await rig.perform { store in
            try store.read { db in
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM meeting_name_evidence WHERE meeting_id = ?", arguments: [id]) ?? 0
            }
        }
        #expect(kept == 1)
        #expect(try W.state(rig, id, speaker: 1).label == "Zofia Wysocka")
    }
}

/// A store whose evidence read fails: everything else goes to the real one. The refresh must abort the write when
/// it cannot see the rows the save would delete.
private final class FailingEvidenceReads: SpeakerNameStore, @unchecked Sendable {
    let base: MeetingsStore

    init(base: MeetingsStore) { self.base = base }

    func loadDocument(id: Int64, includingTrashed: Bool) throws -> MeetingDocument? {
        try base.loadDocument(id: id, includingTrashed: includingTrashed)
    }

    func speakerNameStates(meetingID: Int64) throws -> [MeetingsStore.SpeakerNameState] {
        try base.speakerNameStates(meetingID: meetingID)
    }

    func nameEvidence(meetingID: Int64) throws -> [MeetingsStore.StoredNameEvidence] {
        throw MeetingsStoreError.closed
    }

    @discardableResult
    func saveSpeakerNames(
        _ updates: [MeetingsStore.SpeakerNameUpdate], evidence: [MeetingsStore.StoredNameEvidence], meetingID: Int64
    ) throws -> Set<Int64> {
        try base.saveSpeakerNames(updates, evidence: evidence, meetingID: meetingID)
    }
}
