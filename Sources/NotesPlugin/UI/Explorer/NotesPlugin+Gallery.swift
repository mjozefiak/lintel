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
    }

    var sources: Sources = .fixtures
    var collection: NoteCollection = .all
    var query: String?
    var selected: NoteKey?
    var layer: String?
    var dictationShortcut: KeyShortcut? = KeyShortcut(key: " ", modifiers: [.option])
    /// A recorder that can write the notes again (the "Try Again" button of a failed meeting).
    var canRetry = false
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
    }
    var environment = NotesWorkspaceModel.Environment(
        library: NoteLibrary(sources: { sources }, overlays: overlays, detacher: overlays),
        pasteboard: GalleryPasteboard(), now: { galleryNow }, calendar: galleryCalendar, locale: .current)
    environment.canCreateNotes = true
    environment.dictationShortcut = { scenario.dictationShortcut }
    if scenario.canRetry { environment.liveRecorder = { GalleryRecorder() } }
    let model = NotesWorkspaceModel(environment: environment)
    model.animationsDisabled = true
    return model
}

private struct GalleryPasteboard: PasteboardClient {
    @MainActor var changeCount: Int { 0 }
    @MainActor func string() -> String? { nil }
    @MainActor @discardableResult func setString(_ string: String) -> Int { 0 }
    @MainActor func types() -> [String] { [] }
}

/// The list and the preview side by side, the way the section draws them, without the status bar.
private struct NotesExplorerGalleryHost: View {
    let model: NotesWorkspaceModel
    let scenario: NotesExplorerGalleryCase

    var body: some View {
        HStack(spacing: 0) {
            NoteListView(model: model, width: 300)
            LintelDivider(axis: .vertical)
            NotePreviewView(model: model)
        }
        .frame(height: 620)
        .background(LintelBrand.windowBackground)
        .task {
            model.prepareCollection(scenario.collection)
            if let query = scenario.query {
                model.searchText = query
                await model.runSearch()
            } else {
                await model.refresh()
            }
            guard let key = scenario.selected else { return }
            model.select(row: .live(key))
            // The preview view reads the selection; wait until it has.
            for _ in 0..<100 where model.previewDocument?.phase != .loaded {
                try? await Task.sleep(for: .milliseconds(10))
            }
            if let layer = scenario.layer { model.previewDocument?.selectLayer(layer) }
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
    private static let window = GalleryPresentation.window(width: 980, height: 620)

    private static func state(
        _ id: String, _ summary: String, _ scenario: NotesExplorerGalleryCase
    ) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(NotesExplorerGalleryHost(model: galleryModel(scenario), scenario: scenario))
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
                    "A search in All notes: the matching words are marked in the snippet, one list across the day groups.",
                    NotesExplorerGalleryCase(query: "onboarding", selected: NotesQAFixtures.meetingID)),
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
            ])
    }

    static var preview: GalleryScene {
        GalleryScene(
            id: "notes.preview", title: "Notes → Explorer: the preview",
            states: [
                state(
                    "meeting-notes",
                    "A meeting's notes with the tabs Notes, My notes and Transcript and the footer that says who wrote them.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.summaryID)),
                state(
                    "meeting-transcript",
                    "The Transcript tab: speakers and times, the text read-only.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.meetingID, layer: "transcript")),
                state(
                    "dictation",
                    "A dictation: its cleaned text, no tabs.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.dictationID)),
                state(
                    "writing",
                    "The notes are being written: the working ring and one sentence.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.writingID)),
                state(
                    "needs-model",
                    "The notes wait for a model: one sentence and Download.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.needsModelID)),
                state(
                    "failed-with-retry",
                    "The notes failed and a recorder can write them again: the transcript stays, Try Again.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.failedID, canRetry: true)),
                state(
                    "failed-no-retry",
                    "The notes failed and Meetings is off: no button, the sentence says the transcript can be read.",
                    NotesExplorerGalleryCase(selected: NotesQAFixtures.failedID)),
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
