#if DEBUG
import Foundation
import LintelKit
import LintelUI
import SwiftUI

/// DEBUG only: the design gallery scenes of `NotesPlugin` (spec `2026-11-23-swiftui-design-gallery`; notes explorer
/// phase 3a). Every scene draws the REAL list, preview and sidebar block over a `NotesWorkspaceModel` that reads
/// `NotesQAFixtureSource` (invented text, a fixed "now") and the empty or locked variants of it. Nothing opens a store,
/// the Keychain, a model, the network or a file; a fresh model is made for every state, so states cannot affect each
/// other.
extension NotesPlugin: GalleryProviding {
    public static var galleryScenes: [GalleryScene] {
        [NotesExplorerGallery.explorer, NotesExplorerGallery.preview, NotesExplorerGallery.sidebar]
    }
}

/// What one state needs: the sources behind the model, the collection and search the list shows, the note selected
/// for the preview and which of its tabs is on top.
@MainActor struct NotesExplorerGalleryCase {
    enum Sources {
        /// The fixture meetings and dictations.
        case fixtures
        /// Meetings and Dictation are on and have no notes.
        case empty
        /// Neither recording plugin is on.
        case none
        /// The key to the notes cannot be read.
        case locked
        /// The fixtures, every meeting without its notes: a finished meeting whose notes are off.
        case notesOff
        /// The fixtures, but the text of a note never arrives: the preview's skeleton.
        case slowText
        /// The fixtures and one note you wrote (`GalleryManualNote`).
        case withManualNote
    }

    var sources: Sources = .fixtures
    var collection: NoteCollection = .all
    var query: String?
    var selected: NoteKey?
    /// The preview's tab; `nil` keeps Notes, as for every new selection.
    var tab: PreviewTab?
    /// `false` leaves the list before its first read: the list's skeleton.
    var readsList = true
    var dictationShortcut: KeyShortcut? = KeyShortcut(key: " ", modifiers: [.option])
    /// A recorder that can write the notes again (the "Try Again" button of a failed meeting).
    var canRetry = false
    /// My notes as the user sees them while typing (phase 3b): `nil` leaves the pad the section makes.
    var myNotes: GalleryMyNotes?
}

/// The My notes pad of a gallery state: what is typed and whether it is being written or failed to be.
enum GalleryMyNotes {
    case empty, saving, failed

    static let text = """
        Ask Ola for the budget numbers before Friday.
        - Send Marek the export deck
        - Check the pricing page copy
        """
}

/// A fixed moment (3 Nov 2024, noon UTC) and calendar, so no picture carries the date of the day it was made.
private let galleryNow = Date(timeIntervalSince1970: 1_730_635_200)
private let galleryCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
    return calendar
}()

private final class GalleryRecorder: LiveRecorder, @unchecked Sendable {
    var pluginID: PluginID { "meetings" }
    func status() -> AsyncStream<LiveRecordingStatus> { AsyncStream { $0.finish() } }
    func start() async throws {}
    func stop(writeNotes: Bool) async {}
    func retryNotes(_ key: NoteKey) async throws {}
}

@MainActor private func galleryModel(_ scenario: NotesExplorerGalleryCase) -> NotesWorkspaceModel {
    let sources: [any NoteSource]
    let overlays: any OverlayIndex & OverlayDetacher
    switch scenario.sources {
    case .fixtures:
        sources = NotesQAFixtureSource.all(now: galleryNow)
        overlays = NoOverlays()
    case .empty:
        sources = NotesQAFixtureSource.all(now: galleryNow, empty: true)
        overlays = NoOverlays()
    case .none:
        sources = []
        overlays = NoOverlays()
    case .locked:
        sources = NotesQAFixtureSource.all(now: galleryNow, empty: true)
        overlays = NotesQALockedOverlays()
    case .notesOff:
        sources = NotesQAFixtureSource.all(now: galleryNow, contentStyle: .notesOff)
        overlays = NoOverlays()
    case .slowText:
        sources = NotesQAFixtureSource.all(now: galleryNow, contentStyle: .neverAnswers)
        overlays = NoOverlays()
    case .withManualNote:
        sources = NotesQAFixtureSource.all(now: galleryNow)
        overlays = GalleryManualNote.Overlays()
    }
    var environment = NotesWorkspaceModel.Environment(
        library: NoteLibrary(sources: { sources }, overlays: overlays, detacher: overlays),
        pasteboard: GalleryPasteboard(), now: { galleryNow }, calendar: galleryCalendar, locale: .current)
    environment.canCreateNotes = true
    environment.dictationShortcut = { scenario.dictationShortcut }
    if scenario.canRetry { environment.liveRecorder = { GalleryRecorder() } }
    if scenario.sources == .slowText {
        // The read never ends while the picture is taken: with the usual budget it would turn into "couldn't read
        // this note" part-way through a recording, so the golden and the contact sheet could differ.
        environment.contentBudget = .seconds(3600)
    }
    if scenario.sources == .withManualNote {
        environment.overlayHeads = { id in id.key == GalleryManualNote.key ? [GalleryManualNote.head] : [] }
    }
    let model = NotesWorkspaceModel(environment: environment)
    model.animationsDisabled = true
    return model
}

/// A note you wrote, read as the head of its own document (a manual note has no source).
private enum GalleryManualNote {
    static let key = NoteKey(pluginID: NotesStore.manualPluginID, id: "gallery-manual")
    static let head = OverlayLayerHead(
        layerID: "body",
        markdown: """
            - Short video of the export flow
            - Ask Ola for two customer quotes
            - Check the Polish texts before Friday
            """,
        provenance: [], seedSpeakers: [], attribution: nil)

    /// The overlay index of the gallery: this one note, nothing else.
    struct Overlays: OverlayIndex, OverlayDetacher {
        func overlays(for keys: [NoteKey]) async throws -> [OverlayRecord] { [] }
        func manualNotes() async throws -> [OverlayRecord] {
            [
                OverlayRecord(
                    docID: 1, key: key, layer: "body", kind: .manual, sourcePluginID: NotesStore.manualPluginID,
                    title: "Ideas for the Harbor launch", createdAt: galleryNow.addingTimeInterval(-3600),
                    updatedAt: galleryNow.addingTimeInterval(-3600), isKept: true)
            ]
        }
        func detachedOverlays() async throws -> [OverlayRecord] { [] }
        func keptOverlays(excludingPlugins excluding: Set<PluginID>) async throws -> [OverlayRecord] { [] }
        func liveOverlayKeys() async throws -> [NoteKey] { [] }
        func detach(_ key: NoteKey, reason: OverlayDetachReason) async throws {}
    }
}

private struct GalleryPasteboard: PasteboardClient {
    @MainActor var changeCount: Int { 0 }
    @MainActor func string() -> String? { nil }
    @MainActor @discardableResult func setString(_ string: String) -> Int { 0 }
    @MainActor func types() -> [String] { [] }
}

/// One of the two views over one model: the list column or the preview. They are drawn apart (the pictures stay
/// inside the golden budget); the live window shows them side by side.
private struct NotesExplorerGalleryHost: View {
    enum Part { case list, preview }

    let model: NotesWorkspaceModel
    let scenario: NotesExplorerGalleryCase
    let part: Part

    var body: some View {
        Group {
            switch part {
            case .list: NoteListView(model: model, width: 320)
            case .preview: NotePreviewView(model: model)
            }
        }
        .background(LintelBrand.windowBackground)
        .task {
            guard scenario.readsList else { return }
            model.prepareCollection(scenario.collection)
            if let query = scenario.query {
                model.searchText = query
                await model.runSearch()
            } else {
                await model.refresh()
            }
            guard let key = scenario.selected else { return }
            let id = NoteItemID.live(key)
            model.select(row: id)
            if let tab = scenario.tab { model.selectPreviewTab(tab) }
            // The text that never arrives stays a skeleton; otherwise wait for the one read the preview also waits
            // for, so the picture is never taken half way.
            guard scenario.sources != .slowText else { return }
            await model.loadPreview(id)
            // The pad without a store: editable, with the saving line or the failed strip as the state asks.
            if let mine = scenario.myNotes, let document = model.previewDocument {
                let pad = MyNotesPad(text: mine == .empty ? "" : GalleryMyNotes.text, session: nil)
                pad.showForGallery(saving: mine == .saving, failed: mine == .failed)
                document.myNotes = pad
            }
        }
    }
}

private struct NotesSidebarGalleryHost: View {
    let model: NotesWorkspaceModel
    let collection: NoteCollection

    var body: some View {
        NotesSidebarBlock(
            model: model, context: WorkspaceSidebarContext(isSelected: true, activate: {})
        )
        .padding(8)
        .frame(width: 220)
        .background(LintelBrand.sidebarBackground)
        .task {
            model.prepareCollection(collection)
            await model.refresh()
        }
    }
}

@MainActor enum NotesExplorerGallery {
    private static let listWindow = GalleryPresentation.window(width: 320, height: 620)
    private static let previewWindow = GalleryPresentation.window(width: 560, height: 500)

    private static func state(
        _ id: String, _ summary: String, _ scenario: NotesExplorerGalleryCase,
        part: NotesExplorerGalleryHost.Part = .list, variants: [GalleryVariant] = GalleryVariant.ciSubset
    ) -> GalleryState {
        GalleryState(
            id: id, summary: summary, presentation: part == .list ? listWindow : previewWindow, variants: variants
        ) {
            AnyView(NotesExplorerGalleryHost(model: galleryModel(scenario), scenario: scenario, part: part))
        }
    }

    static var explorer: GalleryScene {
        GalleryScene(
            id: "notes.explorer", title: "Notes → Explorer: list, search and empty states",
            states: [
                state(
                    "all-notes",
                    "All notes: day groups, a ring and one meta line per row, the first row selected and its notes in the preview.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID)),
                state(
                    "meetings",
                    "Meetings: only meetings; rows still writing, interrupted, waiting for a download or failed carry their state in words beside the ring.",
                    NotesExplorerGalleryCase(collection: .meetings, selected: NotesQAFixtures.meetingID)),
                state(
                    "dictations",
                    "Dictations: only dictations; the meta line says the length in words and the preview has no tabs.",
                    NotesExplorerGalleryCase(collection: .dictations, selected: NotesQAFixtures.dictationID)),
                state(
                    "search",
                    "A search in All notes: the matching word is marked in the snippet of the one note that holds it.",
                    NotesExplorerGalleryCase(query: "postpone", selected: NotesQAFixtures.meetingID)),
                state(
                    "search-no-results-meetings",
                    "A search in Meetings that finds nothing: one sentence and Search All Notes.",
                    NotesExplorerGalleryCase(collection: .meetings, query: "zzzz")),
                state(
                    "empty-all",
                    "All notes with nothing yet: meetings and dictation are on, the dictation shortcut is read as it is now.",
                    NotesExplorerGalleryCase(sources: .empty)),
                state(
                    "empty-all-off",
                    "All notes with nothing yet and both recording features off: Open Settings.",
                    NotesExplorerGalleryCase(sources: .none)),
                state(
                    "empty-meetings",
                    "Meetings with nothing yet.",
                    NotesExplorerGalleryCase(sources: .empty, collection: .meetings)),
                state(
                    "empty-dictations",
                    "Dictations with nothing yet, with the dictation shortcut.",
                    NotesExplorerGalleryCase(sources: .empty, collection: .dictations)),
                state(
                    "empty-dictations-no-shortcut",
                    "Dictations with nothing yet when the dictation shortcut is not set: the sentence says “your dictation shortcut”.",
                    NotesExplorerGalleryCase(sources: .empty, collection: .dictations, dictationShortcut: nil)),
                state(
                    "locked",
                    "The key to the notes cannot be read: one sentence, nothing was deleted, Try Again.",
                    NotesExplorerGalleryCase(sources: .locked)),
                state(
                    "loading",
                    "The first page is being read: grey bars where the rows will be, no spinner.",
                    NotesExplorerGalleryCase(readsList: false)),
            ])
    }

    static var preview: GalleryScene {
        GalleryScene(
            id: "notes.preview", title: "Notes → Explorer: the preview",
            states: [
                state(
                    "meeting-notes",
                    "A meeting's notes with the tabs Notes, My notes and Transcript and the footer that says who wrote them.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.summaryID), part: .preview),
                state(
                    "meeting-transcript",
                    "The Transcript tab: speakers and times, the text read-only.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID, tab: .transcript), part: .preview),
                state(
                    "my-notes",
                    "The My notes tab, empty: “Only you write here…” above the pad and what the pad is for.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID, tab: .mine, myNotes: .empty),
                    part: .preview,
                    variants: [
                        GalleryVariant(appearance: .light, textSize: .medium, language: "en"),
                        GalleryVariant(appearance: .light, textSize: .extraLarge, language: "pl"),
                    ]),
                // The 25 MiB budget: the three My notes states share the CI subset (dark is the saving pad's, pl + XL
                // the failed one's) instead of three goldens each; the contact sheet shows every variant.
                state(
                    "my-notes-saving",
                    "My notes while what was typed is being written: “Saving…” on the right of the line.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID, tab: .mine, myNotes: .saving),
                    part: .preview, variants: [GalleryVariant(appearance: .dark, textSize: .medium, language: "en")]),
                state(
                    "my-notes-failed",
                    "My notes could not be written: the strip “Your notes weren’t saved. Lintel keeps trying.” with Try Now; the text stays.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID, tab: .mine, myNotes: .failed),
                    part: .preview,
                    variants: [GalleryVariant(appearance: .light, textSize: .extraLarge, language: "pl")]),
                state(
                    "dictation",
                    "A dictation: its cleaned text, no tabs.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.dictationID), part: .preview),
                state(
                    "own-note",
                    "A note you wrote: its text, no tabs and no footer.",
                    NotesExplorerGalleryCase(sources: .withManualNote, selected: GalleryManualNote.key),
                    part: .preview),
                state(
                    "writing",
                    "The notes are being written (the meeting has its transcript): the Notes tab shows the working ring and one sentence.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.writingID), part: .preview),
                state(
                    "needs-model",
                    "The notes wait for a model (the meeting has its transcript): the Notes tab says so, with Download.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.needsModelID), part: .preview),
                state(
                    "failed-with-retry",
                    "The notes failed and a recorder can write them again: the Notes tab says the transcript is safe, Try Again.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.failedID, canRetry: true), part: .preview),
                state(
                    "failed-no-retry",
                    "The notes failed and Meetings is off: no button, the sentence says the transcript can be read.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.failedID), part: .preview),
                state(
                    "notes-off",
                    "A finished meeting without notes, Meetings off: “Notes are off for this meeting.” and no button.",
                    NotesExplorerGalleryCase(sources: .notesOff, selected: NotesQAFixtures.meetingID), part: .preview),
                state(
                    "loading",
                    "The note's text is being read: a skeleton of grey lines.",
                    NotesExplorerGalleryCase(sources: .slowText, selected: NotesQAFixtures.meetingID), part: .preview),
                state(
                    "unreadable",
                    "The note's plugin did not answer: “Lintel couldn’t read this note. Nothing was deleted.” and Try Again.",
                    NotesExplorerGalleryCase(sources: .none, selected: NotesQAFixtures.meetingID), part: .preview),
            ])
    }

    static var sidebar: GalleryScene {
        GalleryScene(
            id: "notes.sidebar", title: "Main window → Sidebar: the Notes block",
            states: ["all", "meetings", "dictations"].map { name in
                let collection = NoteCollection(stored: name)
                return GalleryState(
                    id: "selected-\(name)",
                    summary: "The Notes block with \(collection.rawValue) selected; the counts come from the sources.",
                    presentation: .window(width: 240)
                ) {
                    AnyView(
                        NotesSidebarGalleryHost(
                            model: galleryModel(NotesExplorerGalleryCase()), collection: collection))
                }
            })
    }
}
#endif
