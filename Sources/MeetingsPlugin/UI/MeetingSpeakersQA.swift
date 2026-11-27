#if DEBUG
import AppKit
import LintelKit

/// DEBUG only, `--qa-setting plugins.meetings.qaSpeakerNames=<state>` (speaker names, step 1.8): writes one meeting
/// with fictional speaker names into the QA run's own library (an isolated data root and an in-memory Keychain) and
/// opens its meeting window in that state. The window gets the identifier `--qa-snapshot` looks for, so the
/// snapshot is this window. Nothing is recorded, nothing is played. Not a contract.
@MainActor
final class MeetingSpeakersQA {
    static let settingName = "qaSpeakerNames"
    /// The identifier `--qa-snapshot` draws (`QAHUDRequest.identifier` in the shell).
    static let windowIdentifier = "lintel.qa.hud"

    enum State: String, CaseIterable {
        /// Names, an automatic name and one suggestion "Marek?" (the mockup).
        case mixed
        /// Every speaker named.
        case named
        /// Two speakers suggest the same name.
        case conflict
        /// "Mówca 3" is being renamed.
        case editing
        /// "Mówca 3" was given Bartek's name: the merge question.
        case merge
    }

    private var controller: MeetingWindowController?
    private var model: MeetingWindowModel?

    /// Seeds the meeting and opens its window; false for an unknown state or a library that is not open.
    func show(named name: String, library: MeetingsLibrary, pasteboard: any PasteboardClient) async -> Bool {
        guard let state = State(rawValue: name), let store = library.store else { return false }
        let now = Date()
        guard
            let seeded = try? await Task.detached(operation: { try Self.seedOnce(store, state: state, now: now) }).value
        else {
            return false
        }
        let model = MeetingWindowModel(
            meetingID: seeded.meetingID, store: store, spool: NoSpoolMaintenance(), pasteboard: pasteboard)
        // The state is set before the window opens: the window's own load starts a newer generation, and a load
        // that loses to it returns without a document.
        await model.load()
        switch state {
        case .editing:
            await model.beginEditing(seeded.third)
            model.updateDraft("Ola")
        case .merge:
            await model.beginEditing(seeded.third)
            model.updateDraft("Bartek Nowak")
            await model.commitEdit(of: seeded.third)
        case .mixed, .named, .conflict:
            break
        }
        let controller = MeetingWindowController { _ in model }
        controller.show(meetingID: seeded.meetingID)
        // The shell's `--qa-snapshot` draws the window with this identifier instead of the main window.
        controller.window(for: seeded.meetingID)?.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        self.controller = controller
        self.model = model
        return true
    }

    func close() {
        controller?.closeAll()
        controller = nil
        model = nil
    }

    struct Seeded {
        var meetingID: Int64
        var third: Int64
    }

    /// The fixture meeting of each state has its own fixed id, so a run with `--qa-persistent-settings` finds it again.
    nonisolated static func uuid(of state: State) -> String {
        let index = State.allCases.firstIndex(of: state).map { $0 + 1 } ?? 0
        return String(format: "00000000-0000-4000-8000-0000000051%02d", index)
    }

    /// The fixture meeting of `state`: the one already in the library (a relaunch with the same data root), else a
    /// new one. Never a second copy, so the meeting a tester edited stays as they left it.
    nonisolated static func seedOnce(_ store: MeetingsStore, state: State, now: Date) throws -> Seeded {
        if let id = try store.meetingID(uuid: uuid(of: state)) {
            let speakers = try store.speakers(meetingID: id)
            guard let third = speakers.dropFirst(3).first?.id ?? speakers.last?.id else {
                return Seeded(meetingID: id, third: 0)
            }
            return Seeded(meetingID: id, third: third)
        }
        return try seed(store, state: state, now: now)
    }

    /// One `ready`, diarized meeting: Anna (the user's own), a second speaker, "Mówca 2" and "Mówca 3". It started a
    /// day before `now`, so the library's retention (90 days by default) never removes it before the QA run.
    nonisolated static func seed(_ store: MeetingsStore, state: State, now: Date) throws -> Seeded {
        let start = now.addingTimeInterval(-24 * 60 * 60)
        let id = try store.insertMeeting(
            uuid: uuid(of: state), startedAt: start, speechModelID: "parakeet-ultra", status: .ready)
        try store.setTitle(id, title: "Przegląd wdrożenia")
        try store.write { db in
            try db.execute(
                sql: "UPDATE meeting SET speaker_mode = 'diarized', duration_ms = 240000 WHERE id = ?", arguments: [id])
        }
        let anna = try store.insertSpeaker(meetingID: id, label: "Anna Kowalska", isSelf: true, channel: .mic)
        let first = try store.insertSpeaker(meetingID: id, label: "Mówca 1", isSelf: false, channel: .system)
        let second = try store.insertSpeaker(meetingID: id, label: "Mówca 2", isSelf: false, channel: .system)
        let third = try store.insertSpeaker(meetingID: id, label: "Mówca 3", isSelf: false, channel: .system)
        try store.insertSegment(
            meetingID: id, channel: .mic, startMs: 5_000, endMs: 9_000,
            text: "Dzień dobry, zaczynamy przegląd wdrożenia.", speakerID: anna)
        let introduction = try store.insertSegment(
            meetingID: id, channel: .system, startMs: 170_000, endMs: 175_000,
            text: "Tu Bartek Nowak, to przejdźmy do wdrożenia.", speakerID: first)
        let marek = try store.insertSegment(
            meetingID: id, channel: .system, startMs: 192_000, endMs: 196_000,
            text: "Tu Marek, mam aktualizację z testów.", speakerID: second)
        try store.insertSegment(
            meetingID: id, channel: .system, startMs: 220_000, endMs: 224_000,
            text: "Dzięki, to wszystko ode mnie.", speakerID: third)
        let bartekEvidence = MeetingsStore.StoredNameEvidence(
            speakerID: first, source: .transcript, name: "Bartek Nowak", kind: .introduction,
            segmentID: introduction, startMs: 170_000, endMs: 175_000, strength: 1)
        let marekEvidence = MeetingsStore.StoredNameEvidence(
            speakerID: second, source: .transcript, name: "Marek", kind: .introduction, segmentID: marek,
            startMs: 192_000, endMs: 196_000, strength: 0.6)
        switch state {
        case .mixed, .editing, .merge:
            try store.saveSpeakerNames(
                [
                    .init(speakerID: first, label: "Bartek Nowak", source: .transcript, status: .applied),
                    .init(
                        speakerID: second, label: "Mówca 2", source: .transcript, status: .suggested,
                        suggestedName: "Marek"),
                ],
                evidence: [bartekEvidence, marekEvidence], meetingID: id)
        case .named:
            try store.saveSpeakerNames(
                [.init(speakerID: first, label: "Bartek Nowak", source: .transcript, status: .applied)],
                evidence: [bartekEvidence], meetingID: id)
            try store.renameSpeaker(second, label: "Marek Wiśniewski")
            try store.renameSpeaker(third, label: "Ola Zielińska")
        case .conflict:
            var early = marekEvidence
            early.speakerID = first
            early.segmentID = introduction
            early.startMs = 170_000
            try store.saveSpeakerNames(
                [
                    .init(
                        speakerID: first, label: "Mówca 1", source: .transcript, status: .suggested,
                        suggestedName: "Marek"),
                    .init(
                        speakerID: second, label: "Mówca 2", source: .transcript, status: .suggested,
                        suggestedName: "Marek"),
                ],
                evidence: [early, marekEvidence], meetingID: id)
        }
        return Seeded(meetingID: id, third: third)
    }
}
#endif
