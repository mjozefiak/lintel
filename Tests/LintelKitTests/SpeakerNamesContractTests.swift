import Foundation
import Synchronization
import Testing

@testable import LintelKit

/// A source written before speaker names: only the first three edits. It must compile unchanged, and the new edits
/// reach the defaults through the existential.
struct OldEditingSource: NoteSourceEditing {
    let pluginID: PluginID = "old"
    func list(matching: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage { NotePage() }
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { Set(keys) }
    func content(for key: NoteKey) async throws -> NoteContent? { nil }
    func delete(_ key: NoteKey) async throws {}
    func actions(for key: NoteKey) -> [NoteSourceAction] { [] }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func renameTitle(_ key: NoteKey, to: String) async throws {}
    func renameSpeaker(_ key: NoteKey, speakerID: String, to: String) async throws {}
    func markSelf(_ key: NoteKey, speakerID: String) async throws {}
}

/// A source that offers the speaker-name edits: its own versions must be the ones called through the existential.
final class NamingSource: NoteSourceEditing {
    let pluginID: PluginID = "naming"
    let calls = Mutex<[String]>([])
    func list(matching: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage { NotePage() }
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { Set(keys) }
    func content(for key: NoteKey) async throws -> NoteContent? { nil }
    func delete(_ key: NoteKey) async throws {}
    func actions(for key: NoteKey) -> [NoteSourceAction] { [] }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    func renameTitle(_ key: NoteKey, to: String) async throws {}
    func renameSpeaker(_ key: NoteKey, speakerID: String, to: String) async throws {}
    func markSelf(_ key: NoteKey, speakerID: String) async throws {}
    func confirmSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        calls.withLock { $0.append("confirm \(speakerID) \(name)") }
    }
    func rejectSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        calls.withLock { $0.append("reject \(speakerID) \(name)") }
    }
    func mergeSpeakers(_ key: NoteKey, speakerID: String, into targetSpeakerID: String) async throws {
        calls.withLock { $0.append("merge \(speakerID) \(targetSpeakerID)") }
    }
}

@Suite struct SpeakerNamesContractTests {
    private let key = NoteKey(pluginID: "old", id: "1")

    @Test func aSpeakerMadeTheOldWayIsConfirmedWithoutASuggestion() {
        let speaker = NoteSpeaker(id: "s1", name: "Ann", isSelf: true)
        #expect(speaker.nameStatus == .confirmed)
        #expect(speaker.suggestion == nil)
        #expect(NoteSpeaker(id: "s2", name: "Speaker 2") == NoteSpeaker(id: "s2", name: "Speaker 2", isSelf: false))
    }

    @Test func aSuggestedSpeakerCarriesItsSuggestion() {
        let speaker = NoteSpeaker(id: "s2", name: "Speaker 2", nameStatus: .suggested, suggestion: "Marek")
        #expect(speaker.nameStatus == .suggested)
        #expect(speaker.suggestion == "Marek")
        #expect(speaker != NoteSpeaker(id: "s2", name: "Speaker 2"))
    }

    @Test func theStatusesAreAClosedSetWithStableRawValues() {
        #expect(NoteSpeakerNameStatus.allCases.map(\.rawValue) == ["confirmed", "applied", "suggested"])
    }

    @Test func anOldSourceAnswersTheNewEditsWithUnsupported() async {
        let source: any NoteSourceEditing = OldEditingSource()
        await #expect(throws: NoteEditingError.unsupported) {
            try await source.confirmSpeakerName(key, speakerID: "1", name: "Marek")
        }
        await #expect(throws: NoteEditingError.unsupported) {
            try await source.rejectSpeakerName(key, speakerID: "1", name: "Marek")
        }
        await #expect(throws: NoteEditingError.unsupported) {
            try await source.mergeSpeakers(key, speakerID: "1", into: "2")
        }
    }

    @Test func anOldSourceIsStillFoundAsEditing() {
        let source: any NoteSource = OldEditingSource()
        #expect(source is any NoteSourceEditing)
    }

    @Test func aSourceThatOffersTheEditsIsCalledThroughTheExistential() async throws {
        let naming = NamingSource()
        let source: any NoteSource = naming
        let editing = try #require(source as? any NoteSourceEditing)
        try await editing.confirmSpeakerName(key, speakerID: "2", name: "Marek")
        try await editing.rejectSpeakerName(key, speakerID: "3", name: "Anna")
        try await editing.mergeSpeakers(key, speakerID: "3", into: "2")
        #expect(naming.calls.withLock { $0 } == ["confirm 2 Marek", "reject 3 Anna", "merge 3 2"])
    }
}
