import Foundation
import SwiftUI
import Synchronization
import Testing

@testable import LintelKit

/// A plugin written before the notes explorer: it must compile unchanged and contribute no trash and no recorder.
@MainActor final class PreNotesExplorerPlugin: LintelPlugin {
    static let manifest = PluginManifest(id: "pre-explorer", displayName: "Before", symbolName: "1.circle", order: 1)
    init(context: PluginContext) {}
}

struct ScriptedTrashList: TrashSource {
    var id: String = "clipboard"
    var title: LocalizedStringResource = "Clipboard"
    var items: [TrashedItem] = []

    func liveCount() async throws -> Int { 0 }
    func trashedCount() async throws -> Int { items.count }
    func trashed(after: String?, limit: Int) async throws -> TrashPage {
        TrashPage(items: Array(items.prefix(limit)), next: nil, total: items.count)
    }
    func trash(_ ids: [String]) async throws {}
    func restore(_ ids: [String]) async throws -> Set<String> { [] }
    func deleteNow(_ ids: [String]) async throws {}
    func trashAll(at deletedAt: Date) async throws -> TrashBatch {
        TrashBatch(deletedAt: deletedAt, moved: 0, stayed: 0)
    }
    func restoreBatch(deletedAt: Date) async throws -> Int { 0 }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// The clipboard's shape: it never returns a title.
struct HidingTrashList: TrashSource {
    let id = "clipboard"
    let title: LocalizedStringResource = "Clipboard"
    var hidesContent: Bool { true }

    func liveCount() async throws -> Int { 0 }
    func trashedCount() async throws -> Int { 0 }
    func trashed(after: String?, limit: Int) async throws -> TrashPage { TrashPage() }
    func trash(_ ids: [String]) async throws {}
    func restore(_ ids: [String]) async throws -> Set<String> { [] }
    func deleteNow(_ ids: [String]) async throws {}
    func trashAll(at deletedAt: Date) async throws -> TrashBatch {
        TrashBatch(deletedAt: deletedAt, moved: 0, stayed: 0)
    }
    func restoreBatch(deletedAt: Date) async throws -> Int { 0 }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// A note source that offers Recently deleted, to check the optional refinement is found through `any NoteSource`.
struct ScriptedTrashSource: NoteSourceTrash {
    let pluginID: PluginID = "meetings"
    var trashedKeysValue: [NoteKey: Date] = [:]

    func list(matching: NormalizedQuery?, after: NoteCursor?, limit: Int) async throws -> NotePage { NotePage() }
    func exists(_ keys: [NoteKey]) async throws -> Set<NoteKey> { Set(keys) }
    func content(for key: NoteKey) async throws -> NoteContent? { nil }
    func delete(_ key: NoteKey) async throws {}
    func actions(for key: NoteKey) -> [NoteSourceAction] { [] }
    func makeChanges() -> AsyncStream<Void> { AsyncStream { $0.finish() } }

    func trash(_ key: NoteKey) async throws -> Date { Date(timeIntervalSince1970: 7) }
    func trashAll(at deletedAt: Date) async throws -> TrashBatch {
        TrashBatch(deletedAt: deletedAt, moved: 0, stayed: 0)
    }
    func restore(_ keys: [NoteKey]) async throws -> Set<NoteKey> { [] }
    func restoreBatch(deletedAt: Date) async throws -> Int { 0 }
    func liveCount() async throws -> Int { 0 }
    func trashed(after: NoteCursor?, limit: Int) async throws -> NotePage { NotePage() }
    func trashedCount() async throws -> Int { trashedKeysValue.count }
    func trashedKeys(_ keys: [NoteKey]) async throws -> [NoteKey: Date] {
        trashedKeysValue.filter { keys.contains($0.key) }
    }
}

@MainActor final class ScriptedLiveRecorder: LiveRecorder {
    let pluginID: PluginID = "meetings"
    var current: LiveRecordingStatus = .idle
    var startFailure: LiveRecordingFailure?
    private(set) var startCount = 0
    private(set) var stopRequests: [Bool] = []

    func status() -> AsyncStream<LiveRecordingStatus> {
        AsyncStream { continuation in
            continuation.yield(current)
            continuation.finish()
        }
    }

    func start() async throws {
        if let startFailure { throw startFailure }
        startCount += 1
    }

    func stop(writeNotes: Bool) async { stopRequests.append(writeNotes) }
    func retryNotes(_ key: NoteKey) async throws {}
}

@MainActor final class NotesExplorerPlugin: LintelPlugin {
    static let manifest = PluginManifest(id: "explorer", displayName: "Explorer", symbolName: "2.circle", order: 2)
    var recorder: (any LiveRecorder)?

    init(context: PluginContext) {}

    var trashSources: [any TrashSource] { [ScriptedTrashList()] }
    var liveRecorder: (any LiveRecorder)? { recorder }
}

@Suite @MainActor struct NotesExplorerContractTests {
    // MARK: Defaults

    @Test func aPluginWrittenBeforeTheExplorerCompilesAndContributesNothing() {
        let plugin: any LintelPlugin = PreNotesExplorerPlugin(context: TestContext.make())
        #expect(plugin.trashSources.isEmpty)
        #expect(plugin.liveRecorder == nil)
    }

    @Test func contextDefaultsReportNoTrashAndNoRecorder() {
        let context = TestContext.make()
        #expect(context.trashSources().isEmpty)
        #expect(context.liveRecorder() == nil)
    }

    @Test func overridesAreReachedThroughTheExistential() {
        let recorder = ScriptedLiveRecorder()
        let concrete = NotesExplorerPlugin(context: TestContext.make())
        concrete.recorder = recorder
        let plugin: any LintelPlugin = concrete
        #expect(plugin.trashSources.map(\.id) == ["clipboard"])
        #expect(plugin.liveRecorder === recorder)

        let context = TestContext.make(
            trashSources: { [ScriptedTrashList(id: "notes")] }, liveRecorder: { recorder })
        #expect(context.trashSources().map(\.id) == ["notes"])
        #expect(context.liveRecorder() === recorder)
    }

    // MARK: Rows

    @Test func theNewRowFieldsDefaultToNothingShown() {
        let summary = NoteSummary(
            id: NoteKey(pluginID: "meetings", id: "m1"), kind: .meeting,
            startedAt: Date(timeIntervalSince1970: 0))
        #expect(summary.deletedAt == nil)
        #expect(summary.purgeAt == nil)
        #expect(summary.taskCount == nil)
        #expect(summary.wordCount == nil)
        #expect(summary.liveSince == nil)

        let layer = NoteLayer(id: "notes", author: .agent, markdown: "Text", version: "v1")
        #expect(layer.writer == nil)
    }

    @Test func theNewRowFieldsAndTheWriterAreKept() {
        let deletedAt = Date(timeIntervalSince1970: 1_000)
        let purgeAt = Date(timeIntervalSince1970: 2_000)
        let summary = NoteSummary(
            id: NoteKey(pluginID: "meetings", id: "m1"), kind: .meeting, startedAt: deletedAt,
            state: .recording, deletedAt: deletedAt, purgeAt: purgeAt, taskCount: 3, wordCount: 118,
            liveSince: purgeAt)
        #expect(summary.deletedAt == deletedAt && summary.purgeAt == purgeAt)
        #expect(summary.taskCount == 3 && summary.wordCount == 118)
        #expect(summary.liveSince == purgeAt)

        let layer = NoteLayer(id: "notes", author: .agent, markdown: "Text", version: "v1", writer: .claude)
        #expect(layer.writer == .claude)
    }

    // MARK: NoteWriter

    @Test func noteWriterIsAClosedSetTheSourceMapsItselfWithoutCodable() {
        #expect(NoteWriter.allCases == [.thisMac, .claude])
        #expect(NoteWriter(rawValue: "thisMac") == .thisMac)
        #expect(NoteWriter(rawValue: "claude") == .claude)
        // The stored provider id of Claude Code is "claude-code"; it is the source that maps it, not the raw value.
        #expect(NoteWriter(rawValue: "claude-code") == nil)
        #expect(NoteWriter(rawValue: "future") == nil)
        #expect(!(NoteWriter.thisMac is any Codable))
    }

    // MARK: Recently deleted

    @Test func trashBatchCarriesTheStampAndBothCounts() {
        let stamp = Date(timeIntervalSince1970: 42)
        let batch = TrashBatch(deletedAt: stamp, moved: 5, stayed: 1)
        #expect(batch.deletedAt == stamp)
        #expect(batch.moved == 5)
        #expect(batch.stayed == 1)
    }

    @Test func trashPagesStartEmpty() {
        let page = TrashPage()
        #expect(page.items.isEmpty && page.next == nil && page.total == 0)
    }

    @Test func aTrashedItemKeepsWhatTheRowDraws() {
        let deletedAt = Date(timeIntervalSince1970: 10)
        let purgeAt = Date(timeIntervalSince1970: 20)
        let item = TrashedItem(
            id: "42", kindLabel: "Clipboard item", title: nil, deletedAt: deletedAt, purgeAt: purgeAt)
        #expect(item.id == "42")
        #expect(item.title == nil)
        #expect(item.deletedAt == deletedAt && item.purgeAt == purgeAt)
        #expect(String(localized: item.kindLabel) == "Clipboard item")
    }

    @Test func aTrashSourceShowsItsTitlesUnlessItHidesContent() async throws {
        let source: any TrashSource = ScriptedTrashList()
        #expect(source.hidesContent == false)
        #expect(try await source.liveCount() == 0)
        #expect(try await source.trashedCount() == 0)
    }

    @Test func aTrashSourceRestoreReportsTheIdsThatAreGone() async throws {
        let source: any TrashSource = ScriptedTrashList()
        #expect(try await source.restore(["1", "2"]).isEmpty)
    }

    @Test func aTrashSourceCanHideContent() async throws {
        let source: any TrashSource = HidingTrashList()
        #expect(source.hidesContent)
    }

    @Test func theTrashRefinementIsFoundThroughTheNoteSource() async throws {
        let trashedKey = NoteKey(pluginID: "meetings", id: "m1")
        let stamp = Date(timeIntervalSince1970: 99)
        let source: any NoteSource = ScriptedTrashSource(trashedKeysValue: [trashedKey: stamp])
        #expect(source as? any NoteSourceTrash != nil)

        let trash = try #require(source as? any NoteSourceTrash)
        #expect(try await trash.trashedCount() == 1)
        #expect(
            try await trash.trashedKeys([trashedKey, NoteKey(pluginID: "meetings", id: "m2")]) == [trashedKey: stamp])
        #expect(try await trash.trash(trashedKey) == Date(timeIntervalSince1970: 7))
        #expect(try await trash.restore([trashedKey]).isEmpty)
        let batch = try await trash.trashAll(at: Date(timeIntervalSince1970: 1))
        #expect(batch.moved == 0 && batch.stayed == 0)
        #expect(try await trash.restoreBatch(deletedAt: Date(timeIntervalSince1970: 1)) == 0)
    }

    @Test func noteSourceErrorsAreTheOnesTheUIMaps() {
        let busy: any Error = NoteSourceError.busy
        #expect(busy as? NoteSourceError == .busy)
        #expect([NoteSourceError.busy, .notFound].map(\.self) == [.busy, .notFound])
    }

    // MARK: Live recording

    @Test func liveRecorderReportsItsStates() async throws {
        let recorder = ScriptedLiveRecorder()
        let key = NoteKey(pluginID: "meetings", id: "m1")
        let since = Date(timeIntervalSince1970: 100)
        recorder.current = .recording(key: key, since: since, hearing: .microphoneOnly, warning: .silence)
        var statuses: [LiveRecordingStatus] = []
        for await status in recorder.status() { statuses.append(status) }
        #expect(statuses == [.recording(key: key, since: since, hearing: .microphoneOnly, warning: .silence)])

        try await recorder.start()
        await recorder.stop(writeNotes: true)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopRequests == [true])

        recorder.startFailure = .microphoneDenied
        await #expect(throws: LiveRecordingFailure.microphoneDenied) { try await recorder.start() }
    }

    @Test func liveRecordingStatusesCompareFieldByField() {
        let key = NoteKey(pluginID: "meetings", id: "m1")
        let since = Date(timeIntervalSince1970: 5)
        #expect(LiveRecordingStatus.idle == .idle)
        #expect(LiveRecordingStatus.starting == .starting)
        #expect(LiveRecordingStatus.processing(key: key, progress: nil) == .processing(key: key, progress: nil))
        #expect(LiveRecordingStatus.processing(key: key, progress: 0.5) != .processing(key: key, progress: nil))
        #expect(LiveRecordingStatus.failed(key: nil, reason: .modelMissing) == .failed(key: nil, reason: .modelMissing))
        #expect(
            LiveRecordingStatus.recording(key: key, since: since, hearing: .everyone, warning: nil)
                != .recording(key: key, since: since, hearing: .everyone, warning: .callAudioMissing))
        #expect(LiveRecordingStatus.Hearing.everyone != .microphoneOnly)
        #expect(LiveRecordingStatus.Warning.microphoneSilent == .microphoneSilent)
    }

    /// No `default`: adding a case to the closed set stops this from compiling until the UI sentence exists.
    private func sentenceKey(_ failure: LiveRecordingFailure) -> String {
        switch failure {
        case .microphoneDenied: "microphoneDenied"
        case .alreadyRecording: "alreadyRecording"
        case .libraryUnavailable: "libraryUnavailable"
        case .modelMissing: "modelMissing"
        case .stillProcessing: "stillProcessing"
        case .noAudioInput: "noAudioInput"
        case .lowDisk: "lowDisk"
        case .modelBusy: "modelBusy"
        case .discarded: "discarded"
        case .other: "other"
        }
    }

    @Test func theFailureSetCoversTheHUDProblems() {
        let all: [LiveRecordingFailure] = [
            .microphoneDenied, .alreadyRecording, .libraryUnavailable, .modelMissing, .stillProcessing,
            .noAudioInput, .lowDisk, .modelBusy, .discarded, .other,
        ]
        #expect(Set(all.map(sentenceKey)).count == all.count)
        // A discarded recording names its meeting, so Notes can keep the user's own writing as a manual note.
        let key = NoteKey(pluginID: "meetings", id: "m1")
        #expect(
            LiveRecordingStatus.failed(key: key, reason: .discarded) != .failed(key: nil, reason: .discarded))
    }

    @Test func hearingAndWarningNameTheCallOnlyAndMicrophoneLostCases() {
        let key = NoteKey(pluginID: "meetings", id: "m1")
        let since = Date(timeIntervalSince1970: 5)
        #expect(LiveRecordingStatus.Hearing.callOnly != .microphoneOnly)
        #expect(LiveRecordingStatus.Warning.microphoneLost != .microphoneSilent)
        #expect(
            LiveRecordingStatus.recording(key: key, since: since, hearing: .callOnly, warning: .microphoneLost)
                == .recording(key: key, since: since, hearing: .callOnly, warning: .microphoneLost))
    }

    // MARK: Routes and sidebar

    @Test func theShellRouteValuesAreNamedAndCarryNoId() {
        #expect(WorkspaceRoute.showDictionary.kind == "showDictionary")
        #expect(WorkspaceRoute.showDictionary.id.isEmpty)
        #expect(WorkspaceRoute.showRecentlyDeleted.kind == "showRecentlyDeleted")
        #expect(WorkspaceRoute.showRecentlyDeleted.id.isEmpty)
        #expect(WorkspaceRoute.Kind.openNote == "openNote")
        #expect(WorkspaceRoute.showDictionary == WorkspaceRoute(kind: "showDictionary", id: ""))
    }

    @Test func theSidebarDefaultsToOneRowAndCanBeReplaced() async {
        let plain = WorkspaceSection(id: "s", title: "S", symbolName: "s.circle", order: 0) {
            AnyView(EmptyView())
        }
        #expect(plain.sidebar == nil)

        let sidebar = WorkspaceSidebar { context in
            context.activate()
            return AnyView(EmptyView())
        }
        let section = WorkspaceSection(
            id: "notes", title: "Notes", symbolName: "note.text", order: 1, sidebar: sidebar
        ) { AnyView(EmptyView()) }
        #expect(section.sidebar != nil)

        let activated = Mutex(false)
        _ = section.sidebar?.makeView(
            WorkspaceSidebarContext(isSelected: false) { activated.withLock { $0 = true } })
        #expect(activated.withLock { $0 })
    }

    @Test func theSidebarContextTellsTheBlockWhetherItsSectionIsSelected() {
        let seen = Mutex<[Bool]>([])
        let sidebar = WorkspaceSidebar { context in
            seen.withLock { $0.append(context.isSelected) }
            return AnyView(EmptyView())
        }
        _ = sidebar.makeView(WorkspaceSidebarContext(isSelected: true) {})
        _ = sidebar.makeView(WorkspaceSidebarContext(isSelected: false) {})
        #expect(seen.withLock { $0 } == [true, false])
    }
}
