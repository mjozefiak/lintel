import Foundation
import LintelCore

/// The "Speakers" list of the meeting window (spec `2026-11-25-meeting-speaker-names`, UI/UX): the names, the
/// edit in place (Return saves, Esc cancels, no confirmation), a suggestion "Marek?" with Yes / No and the time it
/// was heard, and the question "Marek is already in this meeting. Merge?" when a name another speaker has is
/// typed or confirmed. All decisions live here; `MeetingSpeakersList` draws `speakerList` and calls back.
extension MeetingWindowModel {
    /// The name being typed for one speaker.
    struct SpeakerEdit: Equatable {
        var speakerID: Int64
        var draft: String
    }

    /// "Marek is already in this meeting. Merge?"
    struct MergeOffer: Equatable {
        enum Origin: Equatable {
            /// The user typed the name.
            case rename
            /// The user pressed Yes on a suggestion of the name.
            case confirm
        }

        /// The speaker the user named; it goes away on "Merge".
        var speakerID: Int64
        /// The speaker that already has the name; it stays on "Merge".
        var targetID: Int64
        var name: String
        var origin: Origin
    }

    struct ScrollRequest: Equatable {
        var segmentID: Int64
        var serial: Int
    }

    // MARK: Reading

    /// The list as drawn: one row per speaker, the edit in progress and the merge question.
    var speakerList: MeetingSpeakersList.State {
        MeetingSpeakersList.State(
            rows: speakers.map(row(for:)), edit: speakerEdit, mergeOffer: mergeOffer)
    }

    private func row(for speaker: MeetingDocument.Speaker) -> MeetingSpeakersList.Row {
        let name = Self.visible(speaker.label)
        var suggestion: MeetingSpeakersList.Suggestion?
        if let suggested = speaker.pendingSuggestion {
            let found = evidence(of: speaker.id, named: suggested)
            suggestion = MeetingSpeakersList.Suggestion(
                name: suggested, heardAt: found.map { Self.shortClock(milliseconds: $0.timeMs) },
                segmentID: found?.segmentID)
        }
        var origin: String?
        if speaker.isAppliedName, let found = evidence(of: speaker.id, named: name) {
            origin = Self.originText(kind: found.kind, time: Self.shortClock(milliseconds: found.timeMs))
        }
        return MeetingSpeakersList.Row(
            id: speaker.id, name: name, badge: Self.badge(for: name), isSelf: speaker.isSelf,
            canMarkSelf: canMarkSelf(speaker), origin: origin, suggestion: suggestion)
    }

    /// The strongest piece of evidence for `name` at this speaker that points at a time, earliest first among
    /// equals.
    private func evidence(of speakerID: Int64, named name: String)
        -> (timeMs: Int, segmentID: Int64?, kind: NameEvidenceKind?)?
    {
        let candidates = nameEvidence.compactMap { item -> (Double, Int, Int64?, NameEvidenceKind?)? in
            guard item.speakerID == speakerID, Self.sameName(item.name, name) else { return nil }
            let segmentStart = item.segmentID.flatMap { id in document?.segments.first { $0.id == id }?.startMs }
            guard let time = item.startMs ?? segmentStart else { return nil }
            return (item.strength, time, item.segmentID, item.kind)
        }
        let best = candidates.min { lhs, rhs in lhs.0 != rhs.0 ? lhs.0 > rhs.0 : lhs.1 < rhs.1 }
        return best.map { ($0.1, $0.2, $0.3) }
    }

    /// Where an automatic name came from, for the tooltip: "Introduced themselves at 03:12".
    static func originText(kind: NameEvidenceKind?, time: String) -> String? {
        switch kind {
        case .introduction:
            String(
                localized: "Introduced themselves at \(time)",
                comment: "Meeting window: tooltip of a name the person said themselves; the time in the recording")
        case .announced:
            String(
                localized: "Announced at \(time)",
                comment: "Meeting window: tooltip of a name someone announced; the time in the recording")
        case .addressed:
            String(
                localized: "Called by name at \(time)",
                comment: "Meeting window: tooltip of a name someone called the person by; the time in the recording")
        case .referred, nil:
            nil
        }
    }

    /// "03:12", or "1:03:12" from the first hour on: the time in the recording, as the mockup shows it.
    static func shortClock(milliseconds: Int) -> String {
        let seconds = max(0, milliseconds) / 1000
        let hours = seconds / 3600
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, seconds % 3600 / 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    /// The circle before a name: the initials of a name ("AK"), the number of a default label ("2").
    static func badge(for name: String) -> String {
        if NotesGuard.isGenericLabel(name), let number = name.split(separator: " ").last, Int(number) != nil {
            return String(number)
        }
        let initials = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first)
        return initials.isEmpty ? "?" : String(initials).uppercased()
    }

    /// Two names are the same person's when they read the same, whatever the case or invisible characters.
    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        let left = visible(lhs)
        let right = visible(rhs)
        return !left.isEmpty && left.compare(right, options: [.caseInsensitive], locale: nil) == .orderedSame
    }

    /// The other speaker that already has `name`, when merging is possible: never for a generic label, a meeting
    /// with tracks instead of speakers or one that is recorded or processed.
    func speakerHolding(_ name: String, besides speakerID: Int64) -> MeetingDocument.Speaker? {
        guard let document, document.speakerMode != .channels, !document.status.isActive,
            !NotesGuard.isGenericLabel(Self.visible(name))
        else { return nil }
        return document.speakers.first { $0.id != speakerID && Self.sameName($0.label, name) }
    }

    // MARK: Editing in place

    /// A click on a name: the name becomes a field with the current name. Ignored while the merge question waits.
    func beginEditing(_ speakerID: Int64) {
        guard mergeOffer == nil, let speaker = document?.speaker(id: speakerID) else { return }
        speakerEdit = SpeakerEdit(speakerID: speakerID, draft: Self.visible(speaker.label))
    }

    func updateDraft(_ text: String) {
        guard speakerEdit != nil else { return }
        speakerEdit?.draft = text
    }

    /// Esc: nothing is saved.
    func cancelEdit() {
        speakerEdit = nil
    }

    /// Return (and the field losing focus): saves the typed name. A blank one or the same one changes nothing; a
    /// name another speaker has asks whether to merge instead of saving. Does nothing when no edit is open (Esc
    /// came first).
    func commitEdit() async {
        guard let edit = speakerEdit else { return }
        speakerEdit = nil
        let name = Self.visible(edit.draft)
        guard let speaker = document?.speaker(id: edit.speakerID), !name.isEmpty, name != speaker.label else {
            return
        }
        if let holder = speakerHolding(name, besides: speaker.id) {
            setMergeOffer(MergeOffer(speakerID: speaker.id, targetID: holder.id, name: name, origin: .rename))
            return
        }
        await renameSpeaker(speaker.id, to: name)
    }

    // MARK: Suggestions

    /// "Yes" (or Return on the suggestion): the suggested name becomes the speaker's. A name another speaker has
    /// asks whether to merge first.
    func confirmSuggestion(_ speakerID: Int64) async {
        guard mergeOffer == nil, let speaker = document?.speaker(id: speakerID),
            let name = speaker.pendingSuggestion
        else { return }
        if let holder = speakerHolding(name, besides: speakerID) {
            setMergeOffer(MergeOffer(speakerID: speakerID, targetID: holder.id, name: name, origin: .confirm))
            return
        }
        let id = meetingID
        let stored = speaker.suggestedName ?? name
        await mutate { try MeetingEdits.confirmName(stored, speaker: speakerID, of: id, in: $0) }
    }

    /// "No": the speaker is never suggested this name again and keeps its label.
    func rejectSuggestion(_ speakerID: Int64) async {
        guard let speaker = document?.speaker(id: speakerID), speaker.pendingSuggestion != nil,
            let stored = speaker.suggestedName
        else { return }
        let id = meetingID
        await mutate { try MeetingEdits.rejectName(stored, speaker: speakerID, of: id, in: $0) }
    }

    /// The time next to a suggestion: scrolls the transcript to the segment it was heard in.
    func showEvidence(of speakerID: Int64) {
        guard let segmentID = speakerList.rows.first(where: { $0.id == speakerID })?.suggestion?.segmentID else {
            return
        }
        requestScroll(to: segmentID)
    }

    // MARK: The merge question

    /// "Merge": everything the named speaker said moves to the one that has the name.
    func mergeSpeakers() async {
        guard let offer = mergeOffer else { return }
        setMergeOffer(nil)
        let id = meetingID
        await mutate { try MeetingEdits.mergeSpeaker(offer.speakerID, into: offer.targetID, of: id, in: $0) }
    }

    /// "Keep Separate": two people with the same name; the name is saved at both.
    func keepSeparate() async {
        guard let offer = mergeOffer else { return }
        setMergeOffer(nil)
        switch offer.origin {
        case .rename:
            await mutate { try $0.renameSpeaker(offer.speakerID, label: offer.name) }
        case .confirm:
            guard let stored = document?.speaker(id: offer.speakerID)?.suggestedName else { return }
            let id = meetingID
            await mutate { try MeetingEdits.confirmName(stored, speaker: offer.speakerID, of: id, in: $0) }
        }
    }

    /// "Cancel": nothing is saved; the name stays as it was.
    func cancelMerge() {
        setMergeOffer(nil)
    }

    /// After a reload: an edit or a question about a speaker that is gone (merged elsewhere) is dropped.
    func dropStaleSpeakerState() {
        guard let document else { return }
        if let edit = speakerEdit, document.speaker(id: edit.speakerID) == nil { speakerEdit = nil }
        if let offer = mergeOffer,
            document.speaker(id: offer.speakerID) == nil || document.speaker(id: offer.targetID) == nil
        {
            setMergeOffer(nil)
        }
    }
}
