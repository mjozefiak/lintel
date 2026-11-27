import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

/// A fixed calendar and locale so row text does not depend on the machine.
private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()
private let english = Locale(identifier: "en_US")

@MainActor
private struct Rig {
    let meetings: ScriptedNoteSource
    let dictation: ScriptedNoteSource
    let model: NotesWorkspaceModel
    let sourceSet: AsyncStream<Void>.Continuation
    let settingsOpened = Counter()
    let pasteboard = RecordingPasteboard()
    let saver = ScriptedSaver()

    final class Counter { var count = 0 }

    static let meetingKey = Fixtures.key("meetings", "orchard")
    static let otherKey = Fixtures.key("meetings", "call")
    static let dictationKey = Fixtures.key("dictation", "store/7")

    init(writing: Bool = false) {
        let now = Fixtures.epoch
        meetings = ScriptedNoteSource(
            "meetings",
            items: [
                NoteSummary(
                    id: Self.meetingKey, kind: .meeting, title: "Orchard weekly sync",
                    startedAt: now.addingTimeInterval(-3600), durationMs: 2_520_000, sourceApp: "Zoom"),
                NoteSummary(
                    id: Self.otherKey, kind: .meeting, title: "Customer call",
                    startedAt: now.addingTimeInterval(-86_400 - 3600),
                    state: writing ? .writing(done: 2, of: 5) : .interrupted),
            ])
        dictation = ScriptedNoteSource(
            "dictation",
            items: [
                NoteSummary(
                    id: Self.dictationKey, kind: .dictation, title: "Hi Kasia",
                    startedAt: now.addingTimeInterval(-7200),
                    durationMs: 18_000)
            ])
        meetings.contents[Self.meetingKey] = NoteContent(
            summary: meetings.items[0],
            layers: [
                NoteLayer(id: "notes", author: .agent, markdown: "## Summary\n\nShip it.", version: "1"),
                NoteLayer(id: "transcript", author: .stt, markdown: "Agreed.", version: "1"),
            ], speakers: [NoteSpeaker(id: "1", name: "Kasia")], details: [])
        let box = SourceBox([meetings, dictation])
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        sourceSet = continuation
        let library = NoteLibrary(box: box)
        let counter = settingsOpened
        model = NotesWorkspaceModel(
            environment: NotesWorkspaceModel.Environment(
                library: library, pasteboard: pasteboard, saver: saver, sourceSetChanges: { stream },
                openSettings: { counter.count += 1 },
                now: { now }, calendar: utc, locale: english))
        // The tests below read the Meetings list (the old Notes list without manual notes).
        model.prepareCollection(.meetings)
    }
}

@MainActor
@Suite("Notes workspace: listing, the full window and routes")
struct NotesWorkspaceModelTests {
    @Test("the first read lists the notes newest first, grouped by time; dictations are their own list")
    func listing() async {
        let rig = Rig()
        #expect(rig.model.loadState == .loading)
        await rig.model.refresh()
        #expect(rig.model.loadState == .loaded)
        #expect(rig.model.rows.map(\.id.key.rawValue) == ["meetings:orchard", "meetings:call"])
        #expect(rig.model.groups.map { rig.model.title(of: $0) } == ["Today", "Yesterday"])
        #expect(rig.model.total == 2)
        await rig.model.setCollection(.dictations)
        #expect(rig.model.rows.map(\.id.key.rawValue) == ["dictation:store/7"])
        #expect(rig.model.total == 1)
    }

    @Test("grouping by source follows the plugins")
    func bySource() async {
        let rig = Rig()
        await rig.model.refresh()
        rig.model.grouping = .source
        #expect(rig.model.groups.map { rig.model.title(of: $0) } == ["Meetings"])
        await rig.model.setCollection(.dictations)
        #expect(rig.model.groups.map { rig.model.title(of: $0) } == ["Dictation"])
    }

    @Test("a route selects the note and opens it in the full window; one note at a time")
    func routeOpensTheFullWindow() async {
        let rig = Rig()
        await rig.model.refresh()
        let route = NoteRoute.route(for: Rig.meetingKey)
        #expect(rig.model.handle(route))
        #expect(rig.model.currentID == .live(Rig.meetingKey))
        #expect(rig.model.explorer.selection == .live(Rig.meetingKey))
        #expect(rig.model.isFullWindow)
        // The same route, and Open in the explorer, show the same note.
        #expect(rig.model.handle(route))
        rig.model.open(.live(Rig.meetingKey))
        #expect(rig.model.currentID == .live(Rig.meetingKey))
        // Another note replaces it: the first one's document goes, the new one is selected.
        #expect(rig.model.handle(NoteRoute.route(for: Rig.dictationKey)))
        #expect(rig.model.currentID == .live(Rig.dictationKey))
        #expect(rig.model.explorer.selection == .live(Rig.dictationKey))
        #expect(rig.model.documents[.live(Rig.meetingKey)] == nil)
    }

    @Test("Open shows the layer of the preview's tab, and going back shows the tab of the layer on screen")
    func openKeepsThePreviewTab() async throws {
        let rig = Rig()
        await rig.model.refresh()
        let id = NoteItemID.live(Rig.meetingKey)
        rig.model.select(row: id)
        await rig.model.loadPreview(id)
        rig.model.selectPreviewTab(.transcript)
        let document = try #require(rig.model.previewDocument)
        rig.model.open(id)
        #expect(rig.model.currentDocument === document)
        #expect(document.layerID == "transcript")
        // In the full window the layer is the user's: a reload does not switch it back.
        document.selectLayer("notes")
        await rig.model.loadContent(id)
        #expect(document.layerID == "notes")
        rig.model.closeFullWindow()
        #expect(rig.model.previewTab == .notes)
        #expect(rig.model.explorer.selection == id)
        #expect(rig.model.previewDocument === document)
        // My notes in the preview is My notes in the full window, and back.
        rig.model.selectPreviewTab(.mine)
        rig.model.open(id)
        #expect(document.showsMine)
        rig.model.closeFullWindow()
        #expect(rig.model.previewTab == .mine)
    }

    @Test("a route of another kind, or without a note key, is not handled")
    func unhandledRoutes() async {
        let rig = Rig()
        await rig.model.refresh()
        #expect(!rig.model.handle(WorkspaceRoute(kind: "openModels", id: "meetings:orchard")))
        #expect(!rig.model.handle(WorkspaceRoute(kind: "openNote", id: "orchard")))
        #expect(!rig.model.handle(WorkspaceRoute(kind: "openNote", id: ":orchard")))
        #expect(!rig.model.handle(WorkspaceRoute(kind: "openNote", id: "meetings:")))
        #expect(!rig.model.handle(WorkspaceRoute(kind: "openNote", id: "")))
        #expect(!rig.model.isFullWindow)
        #expect(rig.model.currentID == nil)
    }

    @Test("the route id is the key's raw value, also for a dictation key with a slash and a colon")
    func routeRoundTrip() {
        let key = Fixtures.key("dictation", "a:b/9")
        #expect(NoteRoute.itemID(for: NoteRoute.route(for: key)) == .live(key))
        #expect(NoteRoute.route(for: key).kind == "openNote")
    }

    @Test("⌘W and ‹ All notes leave the full window; in the list ⌘W leaves the window to close")
    func closing() async {
        let rig = Rig()
        await rig.model.refresh()
        let id = NoteItemID.live(Rig.meetingKey)
        #expect(!rig.model.handleClose())
        rig.model.open(id)
        let requests = rig.model.listFocusRequests
        #expect(rig.model.handleClose())
        #expect(!rig.model.isFullWindow)
        #expect(rig.model.explorer.selection == id)
        // The list takes the keyboard back, so ↑ / ↓ and Return work at once.
        #expect(rig.model.listFocusRequests == requests + 1)
        // The preview keeps the same document (nothing is read again).
        #expect(rig.model.documents[id] != nil)
        #expect(!rig.model.handleClose())
        rig.model.open(id)
        rig.model.closeFullWindow()
        #expect(rig.model.currentID == nil)
    }

    @Test("content: an answer is shown, no such note is gone, a failure or a missing source is only unavailable")
    func content() async throws {
        let rig = Rig()
        await rig.model.refresh()
        let id = NoteItemID.live(Rig.meetingKey)
        rig.model.open(id)
        let document = try #require(rig.model.documents[id])
        #expect(document.phase == .loading)
        await rig.model.loadContent(id)
        #expect(document.phase == .loaded)
        #expect(document.layers.map(\.id) == ["notes", "transcript"])
        #expect(document.layerID == "notes")
        // The source stops answering: what was shown stays.
        rig.meetings.contentBehavior = .throwsError
        await rig.model.loadContent(id)
        #expect(document.phase == .loaded)
        // A note the source does not know any more is gone.
        rig.meetings.contentBehavior = .answers
        rig.meetings.contents = [:]
        await rig.model.loadContent(id)
        #expect(document.phase == .gone)
        // A note whose plugin has no source is unavailable, not gone.
        let orphan = NoteItemID.live(Fixtures.key("clipboard", "x"))
        rig.model.open(orphan)
        await rig.model.loadContent(orphan)
        #expect(rig.model.documents[orphan]?.phase == .unavailable)
    }

    @Test("the status bar counts the notes being written")
    func writingCount() async {
        let rig = Rig(writing: true)
        await rig.model.refresh()
        #expect(rig.model.writingCount == 1)
        #expect(rig.model.statusSummary.hasSuffix("1 writing"))
        rig.meetings.items = [
            NoteSummary(
                id: Rig.otherKey, kind: .meeting, title: "Renamed call",
                startedAt: Fixtures.epoch.addingTimeInterval(-90_000))
        ]
        await rig.model.refresh()
        #expect(rig.model.writingCount == 0)
    }

    @Test("a change signalled by the set of sources reads the list again")
    func followsTheSourceSet() async {
        let rig = Rig()
        let running = Task { await rig.model.run() }
        await waitUntil { rig.model.loadState == .loaded }
        #expect(rig.model.rows.count == 2)
        rig.meetings.items = [rig.meetings.items[0]]
        rig.sourceSet.yield()
        await waitUntil { rig.model.rows.count == 1 }
        running.cancel()
        #expect(rig.model.rows.count == 1)
    }

    @Test("the Settings link asks the shell")
    func settingsLink() {
        let rig = Rig()
        rig.model.openSettings()
        #expect(rig.settingsOpened.count == 1)
    }

    // MARK: Copy and save

    private func openMeeting(_ rig: Rig) async {
        await rig.model.refresh()
        let id = NoteItemID.live(Rig.meetingKey)
        rig.model.open(id)
        await rig.model.loadContent(id)
    }

    @Test("Copy Markdown writes the layer on screen and says so")
    func copy() async throws {
        let rig = Rig()
        await openMeeting(rig)
        rig.model.copyMarkdown()
        let write = try #require(rig.pasteboard.writes.first)
        #expect(write.options == [.currentHostOnly])
        let text = write.items.first.flatMap { $0.data(for: PasteboardRepresentation.plainTextType) }
        #expect(text.map { String(decoding: $0, as: UTF8.self) } == "# Orchard weekly sync\n\n## Summary\n\nShip it.\n")
        #expect(rig.model.feedback == .copied)
        let serial = rig.model.feedbackSerial
        rig.model.dismissFeedback()
        #expect(rig.model.feedback == nil)
        #expect(rig.model.feedbackSerial == serial + 1)
        // Nothing is open: nothing is copied.
        rig.model.closeFullWindow()
        rig.model.copyMarkdown()
        #expect(rig.pasteboard.writes.count == 1)
    }

    @Test("Save .md writes the text under a file name; cancelling says nothing; a failure says so")
    func save() async {
        let rig = Rig()
        await openMeeting(rig)
        await rig.model.saveMarkdown()
        #expect(rig.saver.saved.map(\.name) == ["Orchard weekly sync.md"])
        #expect(rig.saver.saved.first?.text.hasPrefix("# Orchard weekly sync") == true)
        #expect(rig.model.feedback == .saved)
        rig.saver.answer = .cancelled
        await rig.model.saveMarkdown()
        #expect(rig.model.feedback == nil)
        rig.saver.answer = .fails
        await rig.model.saveMarkdown()
        #expect(rig.model.feedback == .saveFailed)
        // Trying again after the disk is fine clears the error.
        rig.saver.answer = .saved
        await rig.model.saveMarkdown()
        #expect(rig.model.feedback == .saved)
    }

    @Test("the transcript is what is copied once it is shown")
    func copyTranscript() async throws {
        let rig = Rig()
        await openMeeting(rig)
        try #require(rig.model.currentDocument).selectLayer("transcript")
        rig.model.copyMarkdown()
        let data = rig.pasteboard.writes.first?.items.first?.data(for: PasteboardRepresentation.plainTextType)
        #expect(String(decoding: data ?? Data(), as: UTF8.self).contains("Agreed."))
    }
}
