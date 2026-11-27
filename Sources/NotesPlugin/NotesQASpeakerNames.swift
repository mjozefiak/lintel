import Foundation
import LintelKit
import Synchronization

#if DEBUG

/// `plugins.notes.qaSpeakerSuggestion=on` (with `--qa-notes`): the fixture meetings' speakers with a name
/// suggestion and a long applied name, answered in memory, so a QA run can press Yes and No in the transcript
/// (speaker names, step 1.6b). Invented names only. Not a contract.
final class NotesQASpeakerNames: Sendable {
    /// Kasia's long name shows the speaker column at its width (#362); speaker 2 waits for "Marek?".
    static let initialSpeakers = [
        NoteSpeaker(id: "1", name: "Katarzyna Nowakowska", nameStatus: .applied),
        NoteSpeaker(id: "2", name: "Speaker 2", nameStatus: .suggested, suggestion: "Marek"),
        NoteSpeaker(id: "3", name: "You", isSelf: true),
    ]

    struct Stale: Error {}

    private let state = Mutex(NotesQASpeakerNames.initialSpeakers)

    var speakers: [NoteSpeaker] { state.withLock { $0 } }

    /// Yes: the suggestion becomes the name. Throws when the speaker no longer suggests `name`, like the owner.
    func confirm(speakerID: String, name: String) throws {
        try state.withLock { speakers in
            guard let index = speakers.firstIndex(where: { $0.id == speakerID && $0.suggestion == name }) else {
                throw Stale()
            }
            speakers[index].name = name
            speakers[index].nameStatus = .confirmed
            speakers[index].suggestion = nil
        }
    }

    /// No: the suggestion goes, the shown name stays.
    func reject(speakerID: String, name: String) throws {
        try state.withLock { speakers in
            guard let index = speakers.firstIndex(where: { $0.id == speakerID && $0.suggestion == name }) else {
                throw Stale()
            }
            speakers[index].nameStatus = .confirmed
            speakers[index].suggestion = nil
        }
    }

    /// The fixture sources with the meetings' one made editable over a shared set of speakers.
    static func editable(_ sources: [any NoteSource]) -> [any NoteSource] {
        let names = NotesQASpeakerNames()
        return sources.map { source in
            guard let fixture = source as? NotesQAFixtureSource, fixture.pluginID == "meetings" else { return source }
            return NotesQAEditableMeetings(base: fixture, names: names)
        }
    }
}

/// The meetings fixture source with the speakers of `NotesQASpeakerNames` and the speaker answers. Renames do
/// nothing here.
struct NotesQAEditableMeetings: NoteSourceEditing {
    let base: NotesQAFixtureSource
    let names: NotesQASpeakerNames

    var pluginID: PluginID { base.pluginID }

    func list(matching query: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage {
        try await base.list(matching: query, after: after, limit: limit)
    }

    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { try await base.exists(keys) }

    func content(for key: NoteKey) async throws -> NoteContent? {
        guard var content = try await base.content(for: key) else { return nil }
        if !content.speakers.isEmpty { content.speakers = names.speakers }
        return content
    }

    func delete(_ key: NoteKey) async throws { try await base.delete(key) }
    func actions(for key: NoteKey) -> [NoteSourceAction] { base.actions(for: key) }
    func makeChanges() -> AsyncStream<Void> { base.makeChanges() }

    func renameTitle(_ key: NoteKey, to: String) async throws {}
    func renameSpeaker(_ key: NoteKey, speakerID: String, to: String) async throws {}
    func markSelf(_ key: NoteKey, speakerID: String) async throws {}

    func confirmSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        try names.confirm(speakerID: speakerID, name: name)
    }

    func rejectSpeakerName(_ key: NoteKey, speakerID: String, name: String) async throws {
        try names.reject(speakerID: speakerID, name: name)
    }
}
#endif
