import Foundation
import GRDB
import LintelPersistence
import Testing

@testable import MeetingsPlugin

/// Reading and writing speaker names and their evidence (`MeetingsStore+SpeakerNames.swift`) on the real encrypted
/// store, so the foreign keys and their cascades are the ones the app gets. All names are fictional.
@Suite struct SpeakerNamesStoreTests {
    private typealias Update = MeetingsStore.SpeakerNameUpdate
    private typealias Evidence = MeetingsStore.StoredNameEvidence

    private struct Fixture {
        let store: MeetingsStore
        let directory: TemporaryDirectory
        let meeting: Int64
        /// "Mówca 1", "Mówca 2", "Ja" (self).
        let speakers: [Int64]
        let segment: Int64
    }

    private func fixture(uuid: String = "m", notes: String? = nil, in existing: Fixture? = nil) throws -> Fixture {
        let directory = try existing?.directory ?? TemporaryDirectory()
        let store = try existing?.store ?? MeetingsStore.open(in: directory.url, keys: testKeys())
        let meeting = try store.insertMeeting(
            uuid: uuid, startedAt: Date(timeIntervalSince1970: 1_000), speechModelID: "m", status: .ready)
        let speakers = [
            try store.insertSpeaker(meetingID: meeting, label: "Mówca 1", isSelf: false, channel: .system),
            try store.insertSpeaker(meetingID: meeting, label: "Mówca 2", isSelf: false, channel: .system),
            try store.insertSpeaker(meetingID: meeting, label: "Ja", isSelf: true, channel: .mic),
        ]
        let segment = try store.insertSegment(
            meetingID: meeting, channel: .system, startMs: 0, endMs: 1000, text: "Synthetic", speakerID: speakers[0])
        if let notes { try store.setNotes(meeting, markdown: notes, status: .ok) }
        return Fixture(store: store, directory: directory, meeting: meeting, speakers: speakers, segment: segment)
    }

    private func state(_ f: Fixture, _ speaker: Int64) throws -> MeetingsStore.SpeakerNameState {
        try #require(try f.store.speakerNameStates(meetingID: f.meeting).first { $0.speakerID == speaker })
    }

    private func evidence(_ f: Fixture, speaker: Int64? = nil, name: String = "Marek") -> Evidence {
        Evidence(
            speakerID: speaker ?? f.speakers[0], source: .transcript, name: name, kind: .introduction,
            segmentID: f.segment, startMs: 0, endMs: 1000, strength: 1.0)
    }

    private func evidenceCount(_ f: Fixture) throws -> Int {
        try f.store.read { try Int.fetchOne($0, sql: "SELECT count(*) FROM meeting_name_evidence") ?? -1 }
    }

    // MARK: New rows

    @Test func aNewSpeakerIsDefaultAndTheOwnSpeakerIsSelfThroughBothWriters() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        let states = try f.store.speakerNameStates(meetingID: f.meeting)
        #expect(states.map(\.source) == [.default, .default, .me])
        #expect(states.allSatisfy { $0.status == .confirmed && $0.suggestedName == nil && $0.rejectedNames.isEmpty })

        let plan = SpeakerPlan(
            mode: .channels,
            speakers: [
                .init(label: "Ja", isSelf: true, channel: .mic), .init(label: "Inni", isSelf: false, channel: .system),
            ])
        try f.store.applySpeakerPlan(plan, meetingID: f.meeting, diarizationModelID: nil)
        let planned = try f.store.speakerNameStates(meetingID: f.meeting)
        #expect(planned.map(\.label) == ["Ja", "Inni"])
        #expect(planned.map(\.source) == [.me, .default])
    }

    // MARK: Saving a resolution

    @Test func aResolutionWritesAppliedAndSuggestedNamesAndItsEvidence() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        let written = try f.store.saveSpeakerNames(
            [
                Update(speakerID: f.speakers[0], label: "Marek", source: .transcript, status: .applied),
                Update(
                    speakerID: f.speakers[1], label: "Mówca 2", source: .transcript, status: .suggested,
                    suggestedName: "Anna"),
            ],
            evidence: [evidence(f), evidence(f, speaker: f.speakers[1], name: "Anna")], meetingID: f.meeting)
        #expect(written == [f.speakers[0], f.speakers[1]])
        let first = try state(f, f.speakers[0])
        #expect(first.label == "Marek" && first.source == .transcript && first.status == .applied)
        let second = try state(f, f.speakers[1])
        #expect(second.label == "Mówca 2" && second.status == .suggested && second.suggestedName == "Anna")
        #expect(
            try f.store.nameEvidence(meetingID: f.meeting) == [
                evidence(f), evidence(f, speaker: f.speakers[1], name: "Anna"),
            ])
    }

    @Test func aResolutionNeverOverwritesAUserSelfOrConfirmedNameAndKeepsRejections() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        // Speaker 1: the user's name. Speaker 2: a refused suggestion (default again, with a rejection).
        try f.store.renameSpeaker(f.speakers[0], label: "Ewa")
        try f.store.saveSpeakerNames(
            [
                Update(
                    speakerID: f.speakers[1], label: "Mówca 2", source: .transcript, status: .suggested,
                    suggestedName: "Ala")
            ],
            evidence: [], meetingID: f.meeting)
        #expect(try f.store.rejectSuggestedName(speakerID: f.speakers[1], name: "Ala"))

        let written = try f.store.saveSpeakerNames(
            [
                Update(speakerID: f.speakers[0], label: "Marek", source: .platform, status: .applied),
                Update(speakerID: f.speakers[1], label: "Anna", source: .transcript, status: .applied),
                Update(speakerID: f.speakers[2], label: "Piotr", source: .platform, status: .applied),
            ],
            evidence: [], meetingID: f.meeting)
        #expect(written == [f.speakers[1]])
        let user = try state(f, f.speakers[0])
        #expect(user.label == "Ewa" && user.source == .user && user.status == .confirmed)
        let resolved = try state(f, f.speakers[1])
        #expect(resolved.label == "Anna" && resolved.rejectedNames == ["Ala"])
        let me = try state(f, f.speakers[2])
        #expect(me.label == "Ja" && me.source == .me)
    }

    /// The guard is the SQL `WHERE`: a confirmed automatic name, a value from a newer build and the user's own
    /// speaker (even one an older build left `default`) are left alone even when written straight into the table.
    @Test func theGuardInTheSQLKeepsAConfirmedUnknownOrOwnRow() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.write { db in
            try db.execute(
                sql:
                    "UPDATE meeting_speaker SET label = 'Ola', name_source = 'transcript', name_status = 'confirmed' WHERE id = ?",
                arguments: [f.speakers[0]])
            try db.execute(
                sql:
                    "UPDATE meeting_speaker SET label = 'Iga', name_source = 'future', name_status = 'applied' WHERE id = ?",
                arguments: [f.speakers[1]])
            try db.execute(
                sql: "UPDATE meeting_speaker SET name_source = 'default' WHERE id = ?", arguments: [f.speakers[2]])
        }
        let written = try f.store.saveSpeakerNames(
            [
                Update(speakerID: f.speakers[0], label: "Marek", source: .transcript, status: .applied),
                Update(speakerID: f.speakers[1], label: "Anna", source: .transcript, status: .applied),
                Update(speakerID: f.speakers[2], label: "Piotr", source: .transcript, status: .applied),
            ],
            evidence: [], meetingID: f.meeting)
        #expect(written.isEmpty)
        #expect(try state(f, f.speakers[0]).label == "Ola")
        #expect(try state(f, f.speakers[2]).label == "Ja")
        let unknown = try state(f, f.speakers[1])
        #expect(unknown.label == "Iga" && unknown.source == nil)
    }

    @Test func anAutomaticNameCanBeReplacedOrResetByTheNextResolution() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames(
            [Update(speakerID: f.speakers[0], label: "Marek", source: .transcript, status: .applied)],
            evidence: [], meetingID: f.meeting)
        try f.store.saveSpeakerNames(
            [Update(speakerID: f.speakers[0], label: "Mówca 1", source: .default, status: .confirmed)],
            evidence: [], meetingID: f.meeting)
        let reset = try state(f, f.speakers[0])
        #expect(reset.label == "Mówca 1" && reset.source == .default && reset.status == .confirmed)
    }

    @Test func aResolutionRefusesUserSelfAndConfirmedAutomaticNamesBeforeWritingAnything() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames([], evidence: [evidence(f)], meetingID: f.meeting)
        for bad in [
            Update(speakerID: f.speakers[0], label: "Marek", source: .user, status: .confirmed),
            Update(speakerID: f.speakers[0], label: "Marek", source: .me, status: .applied),
            Update(speakerID: f.speakers[0], label: "Marek", source: .transcript, status: .confirmed),
        ] {
            #expect(throws: MeetingsStore.SpeakerNamesError.notAnAutomaticName) {
                try f.store.saveSpeakerNames(
                    [Update(speakerID: f.speakers[1], label: "Anna", source: .transcript, status: .applied), bad],
                    evidence: [], meetingID: f.meeting)
            }
        }
        #expect(try state(f, f.speakers[1]).label == "Mówca 2")
        #expect(try evidenceCount(f) == 1)
    }

    @Test func theEvidenceIsReplacedAndOtherMeetingsKeepTheirs() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        let other = try fixture(uuid: "other", in: f)
        try f.store.saveSpeakerNames([], evidence: [evidence(other)], meetingID: other.meeting)
        try f.store.saveSpeakerNames([], evidence: [evidence(f), evidence(f, name: "Ala")], meetingID: f.meeting)
        try f.store.saveSpeakerNames([], evidence: [evidence(f, name: "Ewa")], meetingID: f.meeting)
        #expect(try f.store.nameEvidence(meetingID: f.meeting).map(\.name) == ["Ewa"])
        #expect(try f.store.nameEvidence(meetingID: other.meeting).map(\.name) == ["Marek"])
    }

    @Test func evidenceThatNamesAnotherMeetingsSpeakerOrSegmentStoresNull() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        let other = try fixture(uuid: "other", in: f)
        try f.store.saveSpeakerNames([], evidence: [evidence(other)], meetingID: f.meeting)
        let stored = try #require(try f.store.nameEvidence(meetingID: f.meeting).first)
        #expect(stored.speakerID == nil && stored.segmentID == nil)
    }

    @Test func aChangedLabelMakesTheNotesStaleAndASuggestionDoesNot() throws {
        let f = try fixture(notes: "Synthetic notes")
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames(
            [
                Update(
                    speakerID: f.speakers[0], label: "Mówca 1", source: .transcript, status: .suggested,
                    suggestedName: "Ala")
            ],
            evidence: [], meetingID: f.meeting)
        #expect(try f.store.notesStatus(of: f.meeting) == .ok)
        try f.store.saveSpeakerNames(
            [Update(speakerID: f.speakers[1], label: "Marek", source: .transcript, status: .applied)],
            evidence: [], meetingID: f.meeting)
        #expect(try f.store.notesStatus(of: f.meeting) == .stale)
    }

    // MARK: Confirming and rejecting a suggestion

    @Test func confirmingTheSuggestionMakesItTheUsersNameAndTheNotesStale() throws {
        let f = try fixture(notes: "Synthetic notes")
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames(
            [
                Update(
                    speakerID: f.speakers[0], label: "Mówca 1", source: .transcript, status: .suggested,
                    suggestedName: "Marek")
            ],
            evidence: [], meetingID: f.meeting)
        #expect(try !f.store.confirmSuggestedName(speakerID: f.speakers[0], name: "Anna"))
        #expect(try f.store.notesStatus(of: f.meeting) == .ok)
        #expect(try f.store.confirmSuggestedName(speakerID: f.speakers[0], name: "Marek"))
        let confirmed = try state(f, f.speakers[0])
        #expect(confirmed.label == "Marek" && confirmed.source == .user && confirmed.status == .confirmed)
        #expect(confirmed.suggestedName == nil)
        #expect(try f.store.notesStatus(of: f.meeting) == .stale)
        // Nothing waits any more.
        #expect(try !f.store.confirmSuggestedName(speakerID: f.speakers[0], name: "Marek"))
    }

    @Test func rejectingTheSuggestionRemembersTheNameOnceAndKeepsTheNotes() throws {
        let f = try fixture(notes: "Synthetic notes")
        defer { withExtendedLifetime(f.directory) {} }
        func suggest(_ name: String) throws {
            try f.store.saveSpeakerNames(
                [
                    Update(
                        speakerID: f.speakers[0], label: "Mówca 1", source: .transcript, status: .suggested,
                        suggestedName: name)
                ],
                evidence: [], meetingID: f.meeting)
        }
        try suggest("Marek")
        #expect(try !f.store.rejectSuggestedName(speakerID: f.speakers[0], name: "Anna"))
        #expect(try f.store.rejectSuggestedName(speakerID: f.speakers[0], name: "Marek"))
        try suggest("marek")
        #expect(try f.store.rejectSuggestedName(speakerID: f.speakers[0], name: "marek"))
        try suggest("Ala")
        #expect(try f.store.rejectSuggestedName(speakerID: f.speakers[0], name: "Ala"))
        let rejected = try state(f, f.speakers[0])
        #expect(rejected.rejectedNames == ["Marek", "Ala"])
        #expect(rejected.label == "Mówca 1" && rejected.source == .default && rejected.status == .confirmed)
        #expect(rejected.suggestedName == nil)
        #expect(try f.store.notesStatus(of: f.meeting) == .ok)
    }

    @Test func unreadableRejectedNamesReadAsNone() {
        #expect(MeetingsStore.decodeNames(nil).isEmpty)
        #expect(MeetingsStore.decodeNames("not json").isEmpty)
        #expect(MeetingsStore.decodeNames(#"{"a":1}"#).isEmpty)
        #expect(MeetingsStore.decodeNames(MeetingsStore.encodeNames(["Ala", "Zoë"])) == ["Ala", "Zoë"])
    }

    // MARK: The user's own edits

    @Test func renamingASpeakerMakesItTheUsersConfirmedNameAndClearsTheSuggestion() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames(
            [
                Update(
                    speakerID: f.speakers[0], label: "Mówca 1", source: .transcript, status: .suggested,
                    suggestedName: "Ala")
            ],
            evidence: [], meetingID: f.meeting)
        try MeetingEdits.renameSpeaker(f.speakers[0], of: f.meeting, to: "Ewa", in: f.store)
        let renamed = try state(f, f.speakers[0])
        #expect(renamed.label == "Ewa" && renamed.source == .user && renamed.status == .confirmed)
        #expect(renamed.suggestedName == nil)
    }

    @Test func markingSelfWritesSelfAndTheFormerSelfBecomesDefaultOrUser() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.write { db in
            try db.execute(sql: "UPDATE meeting SET speaker_mode = 'diarized' WHERE id = ?", arguments: [f.meeting])
        }
        // The former "Ja" goes back to a default label.
        #expect(try f.store.markSelf(speakerID: f.speakers[0]))
        let me = try state(f, f.speakers[0])
        #expect(me.isSelf && me.label == "Ja" && me.source == .me && me.status == .confirmed)
        let former = try state(f, f.speakers[2])
        #expect(!former.isSelf && former.label.hasPrefix(SpeakerLabels.numberedPrefix) && former.source == .default)
        // A self speaker with a typed name keeps it as the user's when the flag moves on.
        try f.store.renameSpeaker(f.speakers[0], label: "Ala Testowa")
        try MeetingEdits.markSelf(f.speakers[1], of: f.meeting, in: f.store)
        #expect(try state(f, f.speakers[1]).source == .me)
        let typed = try state(f, f.speakers[0])
        #expect(!typed.isSelf && typed.label == "Ala Testowa" && typed.source == .user)
    }

    // MARK: Deletion

    @Test func deletingASpeakerOrASegmentKeepsTheEvidenceWithoutTheLink() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames([], evidence: [evidence(f)], meetingID: f.meeting)
        try f.store.write { db in
            try db.execute(sql: "DELETE FROM meeting_segment WHERE id = ?", arguments: [f.segment])
        }
        #expect(try f.store.nameEvidence(meetingID: f.meeting).first?.segmentID == nil)
        #expect(try f.store.nameEvidence(meetingID: f.meeting).first?.speakerID == f.speakers[0])
        try f.store.write { db in
            try db.execute(sql: "DELETE FROM meeting_speaker WHERE id = ?", arguments: [f.speakers[0]])
        }
        let left = try #require(try f.store.nameEvidence(meetingID: f.meeting).first)
        #expect(left.speakerID == nil && left.name == "Marek")
    }

    @Test func everyWayAMeetingIsDeletedTakesItsEvidenceAndTheTrashKeepsIt() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames([], evidence: [evidence(f)], meetingID: f.meeting)
        let deleted = try fixture(uuid: "deleted", in: f)
        try f.store.saveSpeakerNames([], evidence: [evidence(deleted)], meetingID: deleted.meeting)
        let retained = try fixture(uuid: "old", in: f)
        try f.store.saveSpeakerNames([], evidence: [evidence(retained)], meetingID: retained.meeting)

        // Single delete.
        try f.store.deleteMeetings([deleted.meeting])
        #expect(try f.store.nameEvidence(meetingID: deleted.meeting).isEmpty)
        // Retention by age.
        try f.store.write { db in
            try db.execute(sql: "UPDATE meeting SET started_at = 1 WHERE id = ?", arguments: [retained.meeting])
        }
        #expect(try f.store.applyRetention(cutoff: Date(timeIntervalSince1970: 500)) == ["old"])
        #expect(try f.store.nameEvidence(meetingID: retained.meeting).isEmpty)
        // Recently deleted keeps the evidence until the purge.
        let trashedAt = Date(timeIntervalSince1970: 10_000)
        guard case .trashed = try f.store.trash(uuid: "m", at: trashedAt) else {
            Issue.record("the meeting was not trashed")
            return
        }
        #expect(try evidenceCount(f) == 1)
        #expect(try f.store.purgeTrashed(olderThan: trashedAt.addingTimeInterval(1)) == ["m"])
        #expect(try evidenceCount(f) == 0)
    }

    @Test func clearingTheLibraryTakesAllEvidence() throws {
        let f = try fixture()
        defer { withExtendedLifetime(f.directory) {} }
        try f.store.saveSpeakerNames([], evidence: [evidence(f)], meetingID: f.meeting)
        try f.store.deleteAll()
        #expect(try evidenceCount(f) == 0)
    }
}
