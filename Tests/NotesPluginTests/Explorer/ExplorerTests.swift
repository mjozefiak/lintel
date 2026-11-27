import Foundation
import LintelKit
import Testing

@testable import NotesPlugin

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()

private func item(_ id: String) -> NoteItemID { .live(Fixtures.key("meetings", id)) }

@MainActor
@Suite("Explorer: collection, selection and counts")
struct ExplorerModelTests {
    @Test("the stored collection is read; an unknown value reads as All notes")
    func storedCollection() {
        let store = MemorySettings()
        let settings = PluginSettings(pluginID: "notes", store: store)
        #expect(ExplorerModel(settings: settings).collection == .all)
        settings.set("dictations", for: NotesSettingsKey.explorerCollection)
        #expect(ExplorerModel(settings: settings).collection == .dictations)
        settings.set("folder:abc", for: NotesSettingsKey.explorerCollection)
        #expect(ExplorerModel(settings: settings).collection == .all)
    }

    @Test("only a user's choice is stored; a route that widens the list to All notes is not")
    func persistence() {
        let store = MemorySettings()
        let settings = PluginSettings(pluginID: "notes", store: store)
        let model = ExplorerModel(settings: settings)
        #expect(model.setCollection(.meetings, persist: true))
        #expect(settings.string(NotesSettingsKey.explorerCollection) == "meetings")
        #expect(model.setCollection(.all, persist: false))
        #expect(settings.string(NotesSettingsKey.explorerCollection) == "meetings")
        #expect(!model.setCollection(.all, persist: true))
    }

    @Test("the selection stays while its row is listed, else goes to the first row, and is empty for an empty list")
    func reconcile() {
        let model = ExplorerModel()
        let order = [item("a"), item("b"), item("c")]
        #expect(model.reconcile(order: order) == item("a"))
        model.select(item("b"))
        #expect(model.reconcile(order: order) == item("b"))
        #expect(model.reconcile(order: [item("c"), item("a")]) == item("c"))
        #expect(model.reconcile(order: []) == nil)
        #expect(model.selection == nil)
    }

    @Test("arrow keys stop at both ends and start at the ends from no selection")
    func neighbour() {
        let model = ExplorerModel()
        let order = [item("a"), item("b")]
        #expect(model.neighbour(of: nil, in: order, step: 1) == item("a"))
        #expect(model.neighbour(of: nil, in: order, step: -1) == item("b"))
        #expect(model.neighbour(of: item("a"), in: order, step: -1) == item("a"))
        #expect(model.neighbour(of: item("b"), in: order, step: 1) == item("b"))
        #expect(model.neighbour(of: item("a"), in: order, step: 1) == item("b"))
    }

    @Test("a count that could not be read keeps the last number")
    func countsKeepLast() {
        let model = ExplorerModel()
        model.setCounts(NoteCollectionCounts(all: 6, meetings: 2, dictations: 3))
        model.setCounts(NoteCollectionCounts(all: 7, meetings: nil, dictations: nil))
        #expect(model.counts == NoteCollectionCounts(all: 7, meetings: 2, dictations: 3))
    }
}

@Suite("Explorer: empty states")
struct ExplorerEmptyContentTests {
    @Test("All notes: four variants by what is on, the shortcut read as given")
    func allNotes() {
        let both = ExplorerEmptyContent.library(
            collection: .all, meetingsOn: true, dictationOn: true, shortcut: "⌥Space")
        #expect(both.message.contains("⌥Space"))
        #expect(both.action == nil)
        let noShortcut = ExplorerEmptyContent.library(
            collection: .all, meetingsOn: true, dictationOn: true, shortcut: nil)
        #expect(!noShortcut.message.contains("%@"))
        let meetingsOnly = ExplorerEmptyContent.library(
            collection: .all, meetingsOn: true, dictationOn: false, shortcut: "⌥Space")
        #expect(meetingsOnly.action == .openSettings)
        #expect(!meetingsOnly.message.contains("⌥Space"))
        let off = ExplorerEmptyContent.library(collection: .all, meetingsOn: false, dictationOn: false, shortcut: nil)
        #expect(off.action == .openSettings)
        #expect(off.hint != nil)
    }

    @Test("Meetings and Dictations say they are off, with Open Settings, when their plugin is off")
    func offVariants() {
        let meetings = ExplorerEmptyContent.library(
            collection: .meetings, meetingsOn: false, dictationOn: true, shortcut: nil)
        #expect(meetings.action == .openSettings)
        let dictations = ExplorerEmptyContent.library(
            collection: .dictations, meetingsOn: true, dictationOn: false, shortcut: "⌥Space")
        #expect(dictations.action == .openSettings)
        let on = ExplorerEmptyContent.library(
            collection: .dictations, meetingsOn: true, dictationOn: true, shortcut: "⌥Space")
        #expect(on.action == nil)
        #expect(on.message.contains("⌥Space"))
    }

    @Test("a search in one collection offers Search All Notes; in All notes it does not")
    func noResults() {
        #expect(ExplorerEmptyContent.noResults(query: "x", collection: .all).action == nil)
        #expect(ExplorerEmptyContent.noResults(query: "x", collection: .meetings).action == .searchAllNotes)
        #expect(ExplorerEmptyContent.noResults(query: "x", collection: .dictations).action == .searchAllNotes)
        #expect(ExplorerEmptyContent.noResults(query: "zzz", collection: .all).message.contains("zzz"))
    }

    @Test("every sentence is at most 15 words and no help line is long (C6)")
    func copyIsShort() {
        var all: [ExplorerEmptyContent] = []
        for collection in NoteCollection.allCases {
            for meetings in [true, false] {
                for dictation in [true, false] {
                    for shortcut in ["⌥Space", nil] {
                        all.append(
                            .library(
                                collection: collection, meetingsOn: meetings, dictationOn: dictation,
                                shortcut: shortcut))
                    }
                }
            }
            all.append(.noResults(query: "q", collection: collection))
        }
        all.append(.locked)
        for content in all {
            for text in [content.message, content.hint ?? ""] {
                let sentences = text.split(whereSeparator: { ".!?".contains($0) })
                for sentence in sentences {
                    #expect(sentence.split(separator: " ").count <= 15, "\(sentence)")
                }
            }
        }
    }
}

@MainActor
@Suite("Explorer: rows")
struct ExplorerRowTextTests {
    private let text = ExplorerRowText(
        presentation: NoteRowPresentation(calendar: utc, locale: Locale(identifier: "en_US")))

    @Test("a meeting says kind, duration and tasks; a dictation says kind and words")
    func meta() {
        var meeting = Fixtures.summary("meetings", "a", secondsAgo: 10)
        meeting.durationMs = 42 * 60_000
        meeting.taskCount = 3
        #expect(text.meta(meeting).hasPrefix("Meeting · "))
        #expect(text.meta(meeting).hasSuffix("3 tasks"))
        var dictation = Fixtures.summary("dictation", "s/1", secondsAgo: 10, kind: .dictation)
        dictation.wordCount = 118
        #expect(text.meta(dictation) == "Dictation · 118 words")
        dictation.wordCount = nil
        #expect(text.meta(dictation) == "Dictation")
    }

    @Test("the ring and the words always go together; a finished note has neither")
    func states() {
        #expect(text.state(nil).text == nil)
        #expect(text.state(.recording).ring == .listening)
        #expect(text.state(.recording).text != nil)
        #expect(text.state(.failed).ring == .error)
        #expect(text.state(.failed).text != nil)
        if case .processing(let progress) = text.state(.writing(done: 1, of: 4)).ring {
            #expect(progress == 0.25)
        } else {
            Issue.record("a note being written shows the working ring with its progress")
        }
        #expect(text.state(.needsModel).ring == .idle)
        #expect(text.state(.needsModel).text != nil)
    }

    @Test("day group titles: Today, Yesterday, a weekday within the week, else the date")
    func titles() {
        let now = Fixtures.epoch
        #expect(text.title(of: .today, now: now) == "Today")
        #expect(text.title(of: .yesterday, now: now) == "Yesterday")
        let recent = utc.startOfDay(for: now.addingTimeInterval(-3 * 86_400))
        #expect(!text.title(of: .day(recent), now: now).isEmpty)
        let old = utc.startOfDay(for: now.addingTimeInterval(-40 * 86_400))
        #expect(text.title(of: .day(old), now: now).contains(" "))
    }
}

@MainActor
@Suite("Explorer: sidebar block")
struct NotesSidebarBlockTests {
    @Test("the block lists All notes, Meetings and Dictations in that order, and no Folders row")
    func order() {
        #expect(NotesSidebarBlock.rows.map(\.collection) == [.all, .meetings, .dictations])
        #expect(NotesSidebarBlock.rows.count == 3)
    }
}

@MainActor
@Suite("Explorer: selection after a reload (review m1 of #348)")
struct ExplorerReconcileNeighbourTests {
    @Test("a selected row that leaves from the middle hands the selection to the row that took its place")
    func middle() {
        let model = ExplorerModel()
        _ = model.reconcile(order: [item("a"), item("b"), item("c")])
        model.select(item("b"))
        #expect(model.reconcile(order: [item("a"), item("c")]) == item("c"))
    }

    @Test("the last row leaving hands the selection to the one before it")
    func end() {
        let model = ExplorerModel()
        _ = model.reconcile(order: [item("a"), item("b"), item("c")])
        model.select(item("c"))
        #expect(model.reconcile(order: [item("a"), item("b")]) == item("b"))
    }

    @Test("when every neighbour left too, the first row is selected; an empty list selects nothing")
    func allNeighboursGone() {
        let model = ExplorerModel()
        _ = model.reconcile(order: [item("a"), item("b"), item("c")])
        model.select(item("b"))
        #expect(model.reconcile(order: [item("x"), item("y")]) == item("x"))
        #expect(model.reconcile(order: []) == nil)
    }

    @Test("several rows leaving at once: the next one still listed takes the place")
    func severalLeave() {
        let model = ExplorerModel()
        _ = model.reconcile(order: [item("a"), item("b"), item("c"), item("d")])
        model.select(item("b"))
        #expect(model.reconcile(order: [item("a"), item("d")]) == item("d"))
    }
}

@Suite("Explorer: day groups (review m7 of #348)")
struct ExplorerDayGroupTests {
    private static let warsaw: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Warsaw") ?? .gmt
        return calendar
    }()

    private func row(_ id: String, _ date: Date) -> NoteRow {
        let summary = NoteSummary(id: Fixtures.key("meetings", id), kind: .meeting, startedAt: date)
        return NoteRow(id: .live(summary.id), summary: summary, badge: nil, overlays: [], isReadOnly: false)
    }

    @Test("Today, Yesterday, then one group per older day, newest first; rows keep their order inside a group")
    func groups() {
        let now = Date(timeIntervalSince1970: 1_793_966_400)  // 2026-11-06 12:00 UTC
        let hour = 3600.0
        let rows = [
            row("three-days", now.addingTimeInterval(-74 * hour)),
            row("today-late", now.addingTimeInterval(-60)),
            row("yesterday", now.addingTimeInterval(-24 * hour)),
            row("two-days-b", now.addingTimeInterval(-50 * hour)),
            row("today-early", now.addingTimeInterval(-11 * hour)),
            row("two-days-a", now.addingTimeInterval(-49 * hour)),
        ]
        let groups = NoteGroupingRules.group(rows, by: .day, now: now, calendar: utc)
        let twoDays = utc.startOfDay(for: now.addingTimeInterval(-49 * hour))
        let threeDays = utc.startOfDay(for: now.addingTimeInterval(-74 * hour))
        #expect(groups.map(\.key) == [.today, .yesterday, .day(twoDays), .day(threeDays)])
        #expect(
            groups.map { $0.rows.map(\.id.key.id) } == [
                ["today-late", "today-early"], ["yesterday"], ["two-days-a", "two-days-b"], ["three-days"],
            ])
    }

    @Test("the day ends at midnight in the calendar's zone, not in UTC")
    func zoneBoundary() {
        // 2026-11-06 00:30 in Warsaw (UTC+1) is 2026-11-05 23:30 UTC.
        let now = Date(timeIntervalSince1970: 1_793_921_400)
        let beforeMidnight = now.addingTimeInterval(-40 * 60)  // 23:50 Warsaw, 22:50 UTC
        #expect(NoteGroupingRules.dayKey(beforeMidnight, now: now, calendar: Self.warsaw) == .yesterday)
        #expect(NoteGroupingRules.dayKey(beforeMidnight, now: now, calendar: utc) == .today)
        let groups = NoteGroupingRules.group(
            [row("late", beforeMidnight), row("now", now)], by: .day, now: now, calendar: Self.warsaw)
        #expect(groups.map(\.key) == [.today, .yesterday])
    }
}

@MainActor
@Suite("Explorer: exact row and heading text in en_GB (review m7 and m8 of #348)")
struct ExplorerExactTextTests {
    private let text = ExplorerRowText(
        presentation: NoteRowPresentation(calendar: utc, locale: Locale(identifier: "en_GB")))
    /// 2027-01-15 08:00 UTC, a Friday.
    private let now = Fixtures.epoch

    @Test("group headings: Today, Yesterday, the weekday within the week, the date before, the year in another year")
    func headings() {
        let day = 86_400.0
        #expect(text.title(of: .today, now: now) == "Today")
        #expect(text.title(of: .yesterday, now: now) == "Yesterday")
        #expect(text.title(of: .day(utc.startOfDay(for: now.addingTimeInterval(-3 * day))), now: now) == "Tuesday")
        #expect(text.title(of: .day(utc.startOfDay(for: now.addingTimeInterval(-10 * day))), now: now) == "5 January")
        #expect(
            text.title(of: .day(utc.startOfDay(for: now.addingTimeInterval(-40 * day))), now: now)
                == "6 December 2026")
    }

    @Test("the meta line and the time of a row")
    func rowText() {
        var meeting = Fixtures.summary("meetings", "a", secondsAgo: 30 * 60)
        meeting.durationMs = 42 * 60_000
        meeting.taskCount = 3
        #expect(text.meta(meeting) == "Meeting · 42 min · 3 tasks")
        #expect(text.time(meeting) == "7:30")
    }

    @Test("VoiceOver reads the kind, the title, the day with the time, the facts and the state")
    func spokenLabel() {
        var meeting = Fixtures.summary("meetings", "a", secondsAgo: 30 * 60, state: .writing(done: 1, of: 4))
        meeting.durationMs = 42 * 60_000
        meeting.taskCount = 3
        let row = NoteRow(
            id: .live(meeting.id), summary: meeting, badge: NoteBadge(state: meeting.state), overlays: [],
            isReadOnly: false)
        #expect(
            text.accessibilityLabel(row, snippet: nil, title: "Client call", now: now)
                == "Meeting, Client call, today 7:30, 42 min, 3 tasks, Writing notes…")
        var older = meeting
        older.startedAt = now.addingTimeInterval(-26 * 3600)
        older.state = .ready
        let yesterday = NoteRow(id: .live(older.id), summary: older, badge: nil, overlays: [], isReadOnly: false)
        #expect(
            text.accessibilityLabel(yesterday, snippet: nil, title: "Client call", now: now)
                == "Meeting, Client call, yesterday 6:00, 42 min, 3 tasks")
        older.startedAt = now.addingTimeInterval(-3 * 86_400)
        let tuesday = NoteRow(id: .live(older.id), summary: older, badge: nil, overlays: [], isReadOnly: false)
        #expect(
            text.accessibilityLabel(tuesday, snippet: nil, title: "Client call", now: now)
                == "Meeting, Client call, Tuesday 8:00, 42 min, 3 tasks")
    }
}

@Suite("Explorer: what the Notes tab of a meeting says (review M1 of #348)")
struct PreviewNoticeTests {
    @Test("the Notes tab says what is missing; My notes and Transcript never carry a notice")
    func rules() {
        #expect(
            PreviewNotice.make(tab: .notes, state: .failed, hasNotes: false, canRetry: true) == .failed(canRetry: true))
        #expect(
            PreviewNotice.make(tab: .notes, state: .failed, hasNotes: false, canRetry: false)
                == .failed(canRetry: false))
        #expect(PreviewNotice.make(tab: .notes, state: .needsModel, hasNotes: false, canRetry: false) == .needsModel)
        #expect(
            PreviewNotice.make(tab: .notes, state: .writing(done: 1, of: 3), hasNotes: false, canRetry: false)
                == .writing)
        #expect(PreviewNotice.make(tab: .notes, state: .processing, hasNotes: false, canRetry: false) == .writing)
        #expect(
            PreviewNotice.make(tab: .notes, state: .ready, hasNotes: false, canRetry: true) == .notesOff(canWrite: true)
        )
        #expect(PreviewNotice.make(tab: .notes, state: .interrupted, hasNotes: false, canRetry: false) == .noText)
        #expect(PreviewNotice.make(tab: .notes, state: .ready, hasNotes: true, canRetry: false) == nil)
        #expect(PreviewNotice.make(tab: .notes, state: .stale, hasNotes: true, canRetry: false) == nil)
        for tab in [PreviewTab.mine, .transcript] {
            #expect(PreviewNotice.make(tab: tab, state: .failed, hasNotes: false, canRetry: true) == nil)
        }
    }
}

/// A recorder of the meetings plugin that can write the notes again; records the keys it was asked for.
private final class RetryingRecorder: LiveRecorder, @unchecked Sendable {
    var pluginID: PluginID { "meetings" }
    var retried: [NoteKey] = []
    func status() -> AsyncStream<LiveRecordingStatus> { AsyncStream { $0.finish() } }
    func start() async throws {}
    func stop(writeNotes: Bool) async {}
    func retryNotes(_ key: NoteKey) async throws { retried.append(key) }
}

@MainActor
@Suite("Explorer: the preview of a meeting without notes (review M1 of #348)")
struct PreviewTabTests {
    private func model(recorder: (any LiveRecorder)?) -> NotesWorkspaceModel {
        let sources = NotesQAFixtureSource.all(now: Fixtures.epoch)
        var environment = NotesWorkspaceModel.Environment(
            library: NoteLibrary(sources: { sources }, overlays: NoOverlays(), detacher: NoOverlays()),
            pasteboard: NoPasteboard(), now: { Fixtures.epoch }, calendar: utc, locale: Locale(identifier: "en_GB"))
        environment.liveRecorder = { recorder }
        return NotesWorkspaceModel(environment: environment)
    }

    private func show(_ key: NoteKey, in model: NotesWorkspaceModel) async throws -> NoteDocumentModel {
        await model.refresh()
        model.select(row: .live(key))
        await model.loadPreview(.live(key))
        return try #require(model.previewDocument)
    }

    @Test("a failed meeting with a transcript shows the problem and Try Again under Notes, not the transcript")
    func failedWithTranscript() async throws {
        let recorder = RetryingRecorder()
        let model = model(recorder: recorder)
        let document = try await show(NotesQAFixtures.failedID, in: model)
        #expect(document.layers.map(\.id) == ["transcript"])
        #expect(model.previewTab == .notes)
        #expect(model.previewNotice(document) == .failed(canRetry: true))

        // The Transcript tab shows the transcript; Notes is never a dead button.
        model.selectPreviewTab(.transcript)
        #expect(model.previewNotice(document) == nil)
        #expect(document.layerID == "transcript")
        model.selectPreviewTab(.notes)
        #expect(model.previewTab == .notes)
        #expect(model.previewNotice(document) == .failed(canRetry: true))

        await model.retryNotes(.live(NotesQAFixtures.failedID))
        #expect(recorder.retried == [NotesQAFixtures.failedID])
    }

    @Test("without a recorder a failed meeting offers no Try Again")
    func failedWithoutRecorder() async throws {
        let model = model(recorder: nil)
        let document = try await show(NotesQAFixtures.failedID, in: model)
        #expect(model.previewNotice(document) == .failed(canRetry: false))
    }

    @Test("writing and waiting meetings say so under Notes although they have a transcript")
    func writingAndWaiting() async throws {
        let model = model(recorder: nil)
        let writing = try await show(NotesQAFixtures.writingID, in: model)
        #expect(writing.transcriptLayer != nil)
        #expect(model.previewNotice(writing) == .writing)
        let waiting = try await show(NotesQAFixtures.needsModelID, in: model)
        #expect(waiting.transcriptLayer != nil)
        #expect(model.previewNotice(waiting) == .needsModel)
    }

    @Test("a meeting with notes opens on them, and a new selection starts on Notes again (review n1)")
    func tabResetsOnSelection() async throws {
        let model = model(recorder: nil)
        let meeting = try await show(NotesQAFixtures.meetingID, in: model)
        #expect(meeting.layerID == "notes")
        #expect(model.previewNotice(meeting) == nil)
        model.selectPreviewTab(.mine)
        #expect(model.previewTab == .mine)
        let other = try await show(NotesQAFixtures.summaryID, in: model)
        #expect(model.previewTab == .notes)
        #expect(other.layerID == "notes")
    }

    @Test("a dictation has no tabs and no notice")
    func dictation() async throws {
        let model = model(recorder: nil)
        let document = try await show(NotesQAFixtures.dictationID, in: model)
        #expect(!NotesWorkspaceModel.isMeeting(document))
        #expect(model.previewNotice(document) == nil)
    }
}

@MainActor
@Suite("Explorer: keys of the list (review m6 of #348)")
struct ExplorerListKeyTests {
    private func model() async -> NotesWorkspaceModel {
        let sources = NotesQAFixtureSource.all(now: Fixtures.epoch)
        let environment = NotesWorkspaceModel.Environment(
            library: NoteLibrary(sources: { sources }, overlays: NoOverlays(), detacher: NoOverlays()),
            pasteboard: NoPasteboard(), now: { Fixtures.epoch }, calendar: utc, locale: Locale(identifier: "en_GB"))
        let model = NotesWorkspaceModel(environment: environment)
        await model.refresh()
        return model
    }

    @Test("↓ and ↑ move the selection along the list and stop at its ends")
    func arrows() async {
        let model = await model()
        let order = model.visibleRows.map(\.id)
        #expect(model.explorer.selection == order.first)
        #expect(model.handleListKey(.down))
        #expect(model.explorer.selection == order[1])
        #expect(model.handleListKey(.up))
        #expect(model.handleListKey(.up))
        #expect(model.explorer.selection == order.first)
    }

    @Test("Return opens the selected note in its tab")
    func open() async {
        let model = await model()
        let selected = model.explorer.selection
        #expect(model.handleListKey(.open))
        #expect(model.currentID == selected)
    }

    @Test("Esc ends a search and is left to the window otherwise")
    func escape() async {
        let model = await model()
        #expect(!model.handleListKey(.escape))
        model.searchText = "onboarding"
        await model.runSearch()
        #expect(model.isSearching)
        #expect(model.handleListKey(.escape))
        await waitUntil { !model.isSearching }
        #expect(model.searchText.isEmpty)
    }

    @Test("⌘⌫ is not taken when the selected note cannot be deleted")
    func deleteNotTaken() async {
        let model = await model()
        // The fixture sources have no store to delete through.
        if let id = model.explorer.selection, !model.canDelete(id) {
            #expect(!model.handleListKey(.delete))
        }
    }
}
