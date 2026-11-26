import Foundation
import LintelCore

/// The edits a person makes to a meeting that must stay in the owner: the title, a speaker's name and "this is
/// me", as the Notes workspace asks for them (`MeetingNoteSource`, `NoteSourceEditing` semantics: an unknown
/// speaker is `notFound`, "this is me" on a recording is `refused`). The meeting window keeps its own earlier
/// behaviour (it guards in the model and calls the store directly); only `visible` is shared.
enum MeetingEdits {
    enum Failure: Error, Equatable {
        /// There is no such meeting or speaker.
        case notFound
        /// The edit is not allowed now (a recording in progress, tracks instead of speakers).
        case refused
    }

    /// The text without invisible characters, trimmed.
    static func visible(_ text: String) -> String {
        MarkdownText.cleaned(text, keepNewlines: false).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sets the title; a blank one clears it. The notes stay current (the title is not part of them).
    static func renameTitle(_ id: Int64, to title: String, in store: MeetingsStore) throws {
        try store.renameMeeting(id, title: visible(title))
    }

    /// Renames a speaker of the meeting; the notes become `stale`. A blank name or the same name changes nothing.
    static func renameSpeaker(_ speakerID: Int64, of meetingID: Int64, to name: String, in store: MeetingsStore)
        throws
    {
        guard let speaker = try store.speakers(meetingID: meetingID).first(where: { $0.id == speakerID }) else {
            throw Failure.notFound
        }
        let trimmed = visible(name)
        guard !trimmed.isEmpty, trimmed != speaker.label else { return }
        try store.renameSpeaker(speakerID, label: trimmed)
    }

    /// Marks the speaker as the user and sets the notes `stale`. Refused for a meeting that is being recorded
    /// or has tracks instead of speakers; a speaker that is already the user changes nothing.
    static func markSelf(_ speakerID: Int64, of meetingID: Int64, in store: MeetingsStore) throws {
        guard let speaker = try store.speakers(meetingID: meetingID).first(where: { $0.id == speakerID }) else {
            throw Failure.notFound
        }
        guard !speaker.isSelf else { return }
        guard try store.speakerMode(of: meetingID) != .channels,
            try store.recoverableMeeting(id: meetingID)?.status != .recording
        else { throw Failure.refused }
        guard try store.markSelf(speakerID: speakerID) else { throw Failure.refused }
    }

    /// "Tak" on a suggestion: `name` becomes the speaker's name (the user's own) and the notes become `stale`.
    /// `notFound` when the speaker is not in the meeting or no longer suggests `name` (the screen was older than
    /// the row); `refused` while the meeting is recorded or processed.
    static func confirmName(_ name: String, speaker speakerID: Int64, of meetingID: Int64, in store: MeetingsStore)
        throws
    {
        try requireEditable(speakerID, of: meetingID, in: store)
        guard try store.confirmSuggestedName(speakerID: speakerID, name: name) else { throw Failure.notFound }
    }

    /// "Nie" on a suggestion: the speaker never gets `name` again and keeps its label; the notes stay current.
    /// The same refusals as `confirmName`.
    static func rejectName(_ name: String, speaker speakerID: Int64, of meetingID: Int64, in store: MeetingsStore)
        throws
    {
        try requireEditable(speakerID, of: meetingID, in: store)
        guard try store.rejectSuggestedName(speakerID: speakerID, name: name) else { throw Failure.notFound }
    }

    /// "Połącz": `speakerID` and `targetID` are one person (`MeetingsStore.mergeSpeaker`). `notFound` for a
    /// speaker that is not in the meeting, `refused` while it is recorded or processed or in `channels` mode.
    static func mergeSpeaker(_ speakerID: Int64, into targetID: Int64, of meetingID: Int64, in store: MeetingsStore)
        throws
    {
        do {
            try store.mergeSpeaker(speakerID, into: targetID, meetingID: meetingID)
        } catch MeetingsStore.MergeRefusal.notFound {
            throw Failure.notFound
        } catch MeetingsStore.MergeRefusal.refused {
            throw Failure.refused
        }
    }

    /// The speaker belongs to the meeting, and the meeting is not being recorded or processed (the finalization
    /// writes the speakers then).
    private static func requireEditable(_ speakerID: Int64, of meetingID: Int64, in store: MeetingsStore) throws {
        guard try store.speakers(meetingID: meetingID).contains(where: { $0.id == speakerID }) else {
            throw Failure.notFound
        }
        guard let status = try store.status(of: meetingID) else { throw Failure.notFound }
        guard status != .recording, status != .processing else { throw Failure.refused }
    }
}
