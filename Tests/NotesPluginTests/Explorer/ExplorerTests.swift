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
        let both = ExplorerEmptyContent.library(collection: .all, meetingsOn: true, dictationOn: true, shortcut: "⌥Space")
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
