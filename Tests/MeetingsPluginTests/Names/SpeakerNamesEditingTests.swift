import Foundation
import GRDB
import LintelKit
import Testing

@testable import MeetingsPlugin

/// A diarized meeting with four speakers in every name state (spec `2026-11-25-meeting-speaker-names`, step 1.6):
/// Anna (the user's own, `self`), Bartek (`applied` from an introduction), "Mówca 2" with the suggestion Marek and
/// "Mówca 3" with no name. Fictional names only.
struct SpeakerNamesRig: Sendable {
    let directory: TemporaryDirectory
    let store: MeetingsStore
    let meetingID: Int64
    let uuid: String
    let anna: Int64
    let bartek: Int64
    let second: Int64
    let third: Int64
    let marekSegment: Int64

    nonisolated static func make(
        status: MeetingStatus = .ready, mode: SpeakerMode = .diarized, notes: String? = "## Notes\n\n- Done"
    ) async throws -> SpeakerNamesRig {
        try SpeakerNamesRig(status: status, mode: mode, notes: notes)
    }

    init(status: MeetingStatus, mode: SpeakerMode, notes: String?) throws {
        directory = try TemporaryDirectory()
        store = try MeetingsStore.open(in: directory.url.appending(path: "meetings"), keys: testKeys())
        uuid = UUID().uuidString.lowercased()
        let id = try store.insertMeeting(
            uuid: uuid, startedAt: ExportFixtures.started, speechModelID: "m", status: status)
        meetingID = id
        try store.write { db in
            try db.execute(
                sql: "UPDATE meeting SET speaker_mode = ?, duration_ms = 300000 WHERE id = ?",
                arguments: [mode.rawValue, id])
        }
        anna = try store.insertSpeaker(meetingID: id, label: "Anna Kowalska", isSelf: true, channel: .mic)
        bartek = try store.insertSpeaker(meetingID: id, label: "Mówca 1", isSelf: false, channel: .system)
        second = try store.insertSpeaker(meetingID: id, label: "Mówca 2", isSelf: false, channel: .system)
        third = try store.insertSpeaker(meetingID: id, label: "Mówca 3", isSelf: false, channel: .system)
        let bartekSegment = try store.insertSegment(
            meetingID: id, channel: .system, startMs: 170_000, endMs: 178_000, text: "Tu Bartek, zaczynamy.",
            speakerID: bartek)
        marekSegment = try store.insertSegment(
            meetingID: id, channel: .system, startMs: 192_000, endMs: 196_000,
            text: "Tu Marek, mam aktualizację z testów.", speakerID: second)
        try store.insertSegment(
            meetingID: id, channel: .system, startMs: 200_000, endMs: 204_000, text: "Dzięki.", speakerID: third)
        if let notes { try store.setNotes(id, markdown: notes, status: .ok) }
        try store.saveSpeakerNames(
            [
                .init(speakerID: bartek, label: "Bartek Nowak", source: .transcript, status: .applied),
                .init(
                    speakerID: second, label: "Mówca 2", source: .transcript, status: .suggested, suggestedName: "Marek"
                ),
            ],
            evidence: [
                .init(
                    speakerID: bartek, source: .transcript, name: "Bartek Nowak", kind: .introduction,
                    segmentID: bartekSegment, startMs: 170_000, endMs: 178_000, strength: 1),
                .init(
                    speakerID: second, source: .transcript, name: "Marek", kind: .addressed,
                    segmentID: marekSegment, startMs: 192_000, endMs: 196_000, strength: 0.6),
            ],
            meetingID: id)
        // The names were written before the notes existed in a real run; the notes stay current here.
        if notes != nil { try store.setNotes(id, markdown: notes, status: .ok) }
    }

    func state(_ speaker: Int64) throws -> MeetingsStore.SpeakerNameState? {
        try store.speakerNameStates(meetingID: meetingID).first { $0.speakerID == speaker }
    }

    func segmentSpeakers() throws -> [Int64?] {
        try store.loadDocument(id: meetingID)?.segments.map(\.speakerID) ?? []
    }
}

// MARK: - Store

@Suite struct SpeakerMergeStoreTests {
    @Test func mergingMovesTheSegmentsAndTheEvidenceAndDeletesTheSpeaker() async throws {
        let rig = try await SpeakerNamesRig.make()
        try rig.store.mergeSpeaker(rig.second, into: rig.bartek, meetingID: rig.meetingID)
        #expect(try rig.state(rig.second) == nil)
        #expect(try rig.segmentSpeakers() == [rig.bartek, rig.bartek, rig.third])
        let evidence = try rig.store.nameEvidence(meetingID: rig.meetingID)
        #expect(evidence.map(\.speakerID) == [rig.bartek, rig.bartek])
        #expect(try rig.state(rig.bartek)?.label == "Bartek Nowak")
        #expect(try rig.store.notesStatus(of: rig.meetingID) == .stale)
    }

    @Test func mergingKeepsTheRefusedNamesOfBoth() async throws {
        let rig = try await SpeakerNamesRig.make()
        #expect(try rig.store.rejectSuggestedName(speakerID: rig.second, name: "Marek"))
        try rig.store.write { db in
            try db.execute(
                sql: "UPDATE meeting_speaker SET rejected_names = ? WHERE id = ?",
                arguments: [MeetingsStore.encodeNames(["Marek", "Ewa"]), rig.second])
        }
        try rig.store.write { db in
            try db.execute(
                sql: "UPDATE meeting_speaker SET rejected_names = ? WHERE id = ?",
                arguments: [MeetingsStore.encodeNames(["marek", "Ola"]), rig.third])
        }
        try rig.store.mergeSpeaker(rig.second, into: rig.third, meetingID: rig.meetingID)
        #expect(try rig.state(rig.third)?.rejectedNames == ["marek", "Ola", "Ewa"])
    }

    @Test func theUsersOwnSpeakerSurvivesAMergeOnEitherSide() async throws {
        let rig = try await SpeakerNamesRig.make()
        try rig.store.mergeSpeaker(rig.anna, into: rig.third, meetingID: rig.meetingID)
        let target = try #require(try rig.state(rig.third))
        #expect(target.isSelf)
        #expect(target.source == .me)
        #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID).filter(\.isSelf).count == 1)

        let other = try await SpeakerNamesRig.make()
        try other.store.mergeSpeaker(other.second, into: other.anna, meetingID: other.meetingID)
        #expect(try other.state(other.anna)?.isSelf == true)
        #expect(try other.state(other.anna)?.label == "Anna Kowalska")
    }

    @Test func aMergeIsRefusedWhileRecordingOrProcessingAndInChannelsMode() async throws {
        for status in [MeetingStatus.recording, .processing] {
            let rig = try await SpeakerNamesRig.make(status: status)
            #expect(throws: MeetingsStore.MergeRefusal.refused) {
                try rig.store.mergeSpeaker(rig.second, into: rig.bartek, meetingID: rig.meetingID)
            }
            #expect(try rig.state(rig.second) != nil)
            #expect(try rig.segmentSpeakers() == [rig.bartek, rig.second, rig.third])
        }
        let channels = try await SpeakerNamesRig.make(mode: .channels)
        #expect(throws: MeetingsStore.MergeRefusal.refused) {
            try channels.store.mergeSpeaker(channels.second, into: channels.bartek, meetingID: channels.meetingID)
        }
    }

    @Test func aSpeakerOfAnotherMeetingOrTheSameSpeakerIsNotFound() async throws {
        let rig = try await SpeakerNamesRig.make()
        let other = try rig.store.insertMeeting(
            uuid: "other", startedAt: ExportFixtures.started, speechModelID: "m", status: .ready)
        let stranger = try rig.store.insertSpeaker(meetingID: other, label: "Ola", isSelf: false, channel: .system)
        #expect(throws: MeetingsStore.MergeRefusal.notFound) {
            try rig.store.mergeSpeaker(stranger, into: rig.bartek, meetingID: rig.meetingID)
        }
        #expect(throws: MeetingsStore.MergeRefusal.notFound) {
            try rig.store.mergeSpeaker(rig.bartek, into: rig.bartek, meetingID: rig.meetingID)
        }
        #expect(try rig.store.speakerCount(meetingID: other) == 1)
    }
}

// MARK: - The Notes source

/// `MeetingNoteSource` over a library whose store is the rig's.
@MainActor
struct SpeakerNamesSourceRig {
    let harness: MeetingsHarness
    let library: MeetingsLibrary
    let source: MeetingNoteSource
    let changes = Shared(0)
    let key: NoteKey
    let ids: (anna: Int64, bartek: Int64, second: Int64, third: Int64, segment: Int64)
    let meetingID: Int64

    var store: MeetingsStore {
        get throws { try #require(library.store) }
    }

    init(status: MeetingStatus = .ready, mode: SpeakerMode = .diarized) async throws {
        harness = try MeetingsHarness()
        library = harness.library()
        library.open()
        let store = try #require(library.store)
        let changes = changes
        source = MeetingNoteSource(
            library: library, board: NotesBoard(), hub: NoteChangeHub(), regenerate: { _ in },
            openNotesModel: {}, changed: { changes.update { $0 += 1 } })
        let seeded = try await Task.detached { try SpeakerNamesSeed.seed(store, status: status, mode: mode) }.value
        meetingID = seeded.meetingID
        ids = (seeded.anna, seeded.bartek, seeded.second, seeded.third, seeded.segment)
        key = NoteKey(pluginID: "meetings", id: seeded.uuid)
    }

    func speakers() async throws -> [NoteSpeaker] {
        try #require(try await source.content(for: key)).speakers
    }
}

/// The same four speakers as `SpeakerNamesRig`, written into an existing store.
enum SpeakerNamesSeed {
    struct Seeded: Sendable {
        var meetingID: Int64
        var uuid: String
        var anna: Int64
        var bartek: Int64
        var second: Int64
        var third: Int64
        var segment: Int64
    }

    static func seed(_ store: MeetingsStore, status: MeetingStatus, mode: SpeakerMode) throws -> Seeded {
        let uuid = UUID().uuidString.lowercased()
        let id = try store.insertMeeting(
            uuid: uuid, startedAt: ExportFixtures.started, speechModelID: "m", status: .ready)
        try store.write { db in
            try db.execute(sql: "UPDATE meeting SET speaker_mode = ? WHERE id = ?", arguments: [mode.rawValue, id])
        }
        let anna = try store.insertSpeaker(meetingID: id, label: "Anna Kowalska", isSelf: true, channel: .mic)
        let bartek = try store.insertSpeaker(meetingID: id, label: "Mówca 1", isSelf: false, channel: .system)
        let second = try store.insertSpeaker(meetingID: id, label: "Mówca 2", isSelf: false, channel: .system)
        let third = try store.insertSpeaker(meetingID: id, label: "Mówca 3", isSelf: false, channel: .system)
        let segment = try store.insertSegment(
            meetingID: id, channel: .system, startMs: 192_000, endMs: 196_000, text: "Tu Marek.", speakerID: second)
        try store.insertSegment(
            meetingID: id, channel: .system, startMs: 200_000, endMs: 204_000, text: "Dzięki.", speakerID: third)
        try store.saveSpeakerNames(
            [
                .init(speakerID: bartek, label: "Bartek Nowak", source: .transcript, status: .applied),
                .init(
                    speakerID: second, label: "Mówca 2", source: .transcript, status: .suggested, suggestedName: "Marek"
                ),
            ],
            evidence: [], meetingID: id)
        try store.setNotes(id, markdown: "## Notes\n\n- Done", status: .ok)
        try store.setStatus(id, status: status)
        return Seeded(
            meetingID: id, uuid: uuid, anna: anna, bartek: bartek, second: second, third: third, segment: segment)
    }
}

@MainActor
@Suite struct MeetingNoteSourceSpeakerNamesTests {
    @Test func theSpeakersCarryTheirNameStatusAndSuggestion() async throws {
        let rig = try await SpeakerNamesSourceRig()
        let speakers = try await rig.speakers()
        #expect(
            speakers == [
                NoteSpeaker(id: String(rig.ids.anna), name: "Anna Kowalska", isSelf: true),
                NoteSpeaker(id: String(rig.ids.bartek), name: "Bartek Nowak", nameStatus: .applied),
                NoteSpeaker(id: String(rig.ids.second), name: "Mówca 2", nameStatus: .suggested, suggestion: "Marek"),
                NoteSpeaker(id: String(rig.ids.third), name: "Mówca 3"),
            ])
    }

    @Test func aStatusFromANewerBuildOrAnInvisibleSuggestionReadsAsConfirmed() async throws {
        let rig = try await SpeakerNamesSourceRig()
        try rig.store.write { db in
            try db.execute(
                sql: "UPDATE meeting_speaker SET name_status = 'pending', suggested_name = 'Bartosz' WHERE id = ?",
                arguments: [rig.ids.bartek])
            try db.execute(
                sql: "UPDATE meeting_speaker SET suggested_name = ? WHERE id = ?",
                arguments: ["\u{200B} ", rig.ids.second])
            // The resolver's "no name" state: suggested without a name.
            try db.execute(
                sql: "UPDATE meeting_speaker SET name_status = 'suggested', suggested_name = NULL WHERE id = ?",
                arguments: [rig.ids.third])
        }
        let speakers = try await rig.speakers()
        #expect(speakers.map(\.nameStatus) == [.confirmed, .confirmed, .confirmed, .confirmed])
        #expect(speakers.allSatisfy { $0.suggestion == nil })
    }

    @Test func confirmingASuggestionNamesTheSpeakerAndMakesTheNotesStale() async throws {
        let rig = try await SpeakerNamesSourceRig()
        try await rig.source.confirmSpeakerName(rig.key, speakerID: String(rig.ids.second), name: "Marek")
        let speaker = try #require(try await rig.speakers().first { $0.id == String(rig.ids.second) })
        #expect(speaker == NoteSpeaker(id: String(rig.ids.second), name: "Marek"))
        #expect(try await rig.source.content(for: rig.key)?.summary.state == .stale)
        #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID)[2].source == .user)
        #expect(rig.changes.get() == 1)
    }

    @Test func aSuggestionTheScreenNoLongerShowsIsNotFound() async throws {
        let rig = try await SpeakerNamesSourceRig()
        await #expect(throws: MeetingEdits.Failure.notFound) {
            try await rig.source.confirmSpeakerName(rig.key, speakerID: String(rig.ids.second), name: "Mariusz")
        }
        await #expect(throws: MeetingEdits.Failure.notFound) {
            try await rig.source.rejectSpeakerName(rig.key, speakerID: String(rig.ids.third), name: "Marek")
        }
        await #expect(throws: MeetingEdits.Failure.notFound) {
            try await rig.source.rejectSpeakerName(rig.key, speakerID: String(rig.ids.second), name: "Mariusz")
        }
        #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID)[2].rejectedNames.isEmpty)
        #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID)[2].suggestedName == "Marek")
        #expect(try await rig.source.content(for: rig.key)?.summary.state == .ready)
    }

    @Test func rejectingASuggestionRemembersItAndLeavesTheNotes() async throws {
        let rig = try await SpeakerNamesSourceRig()
        try await rig.source.rejectSpeakerName(rig.key, speakerID: String(rig.ids.second), name: "Marek")
        let speaker = try #require(try await rig.speakers().first { $0.id == String(rig.ids.second) })
        #expect(speaker == NoteSpeaker(id: String(rig.ids.second), name: "Mówca 2"))
        #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID)[2].rejectedNames == ["Marek"])
        #expect(try await rig.source.content(for: rig.key)?.summary.state == .ready)
    }

    @Test func mergingMovesTheSegmentsAndMakesTheNotesStale() async throws {
        let rig = try await SpeakerNamesSourceRig()
        try await rig.source.mergeSpeakers(rig.key, speakerID: String(rig.ids.second), into: String(rig.ids.bartek))
        let content = try #require(try await rig.source.content(for: rig.key))
        #expect(content.speakers.map(\.id) == [rig.ids.anna, rig.ids.bartek, rig.ids.third].map(String.init))
        #expect(content.summary.state == .stale)
        let segments = try rig.store.loadDocument(id: rig.meetingID)?.segments.map(\.speakerID)
        #expect(segments == [rig.ids.bartek, rig.ids.third])
    }

    @Test func theNameEditsAreRefusedWhileTheMeetingIsRecordedOrProcessed() async throws {
        for status in [MeetingStatus.recording, .processing] {
            let rig = try await SpeakerNamesSourceRig(status: status)
            let second = String(rig.ids.second)
            await #expect(throws: MeetingEdits.Failure.refused) {
                try await rig.source.mergeSpeakers(rig.key, speakerID: second, into: String(rig.ids.bartek))
            }
            await #expect(throws: MeetingEdits.Failure.refused) {
                try await rig.source.confirmSpeakerName(rig.key, speakerID: second, name: "Marek")
            }
            await #expect(throws: MeetingEdits.Failure.refused) {
                try await rig.source.rejectSpeakerName(rig.key, speakerID: second, name: "Marek")
            }
            #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID).count == 4)
            #expect(try rig.store.speakerNameStates(meetingID: rig.meetingID)[2].suggestedName == "Marek")
        }
    }

    @Test func aMergeOfTracksIsRefused() async throws {
        let rig = try await SpeakerNamesSourceRig(mode: .channels)
        await #expect(throws: MeetingEdits.Failure.refused) {
            try await rig.source.mergeSpeakers(rig.key, speakerID: String(rig.ids.second), into: String(rig.ids.third))
        }
    }

    @Test func aSpeakerIDThatIsNotANumberIsNotFound() async throws {
        let rig = try await SpeakerNamesSourceRig()
        await #expect(throws: MeetingNoteSourceError.notFound) {
            try await rig.source.mergeSpeakers(rig.key, speakerID: "x", into: String(rig.ids.bartek))
        }
    }
}

// MARK: - Export

@Suite struct SpeakerSuggestionExportTests {
    @Test func theMarkdownNeverContainsASuggestion() async throws {
        let rig = try await SpeakerNamesRig.make()
        let document = try #require(try rig.store.loadDocument(id: rig.meetingID))
        #expect(document.speakers[2].pendingSuggestion == "Marek")
        let markdown = MarkdownExporter.export(document, labels: .english, timeZone: ExportFixtures.utc)
        #expect(markdown.contains("Mówca 2"))
        // "Marek" is only in what the speaker said, never as a name.
        #expect(!markdown.replacingOccurrences(of: "Tu Marek, mam aktualizację z testów.", with: "").contains("Marek"))
        #expect(markdown.contains("Bartek Nowak"))
    }
}
