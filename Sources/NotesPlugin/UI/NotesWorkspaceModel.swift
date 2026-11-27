import Foundation
import LintelCore
import LintelKit
import Observation

/// The state of the Notes section (spec step 3.2, notes explorer phase 3b): the explorer's rows and groups, the note
/// open in the full window and one `NoteDocumentModel` per note on screen. The model never writes anything; the text
/// stays with the sources.
///
/// Everything is keyed by `NoteItemID`: an explorer row, the full window and a route name the same thing, so a note
/// opened from a route and from the explorer is one document.
@MainActor @Observable
final class NotesWorkspaceModel {
    /// What the model needs from the outside, replaced by fakes in tests.
    struct Environment {
        var library: NoteLibrary
        /// Where Copy Markdown writes (the context's pasteboard).
        var pasteboard: any PasteboardClient
        /// Where Save .md asks for a place and writes.
        var saver: any NoteFileSaving = NoteSavePanel()
        /// The context's `noteSourcesChanged`: one stream per call.
        var sourceSetChanges: @Sendable () -> AsyncStream<Void> = { AsyncStream { $0.finish() } }
        var openSettings: @MainActor () -> Void = {}
        /// "Open Models" of the needs-model strip (`PluginContext.openModels`).
        var openModels: @MainActor () -> Void = {}
        /// The plugins whose recordings Notes lists; with none of them active the section says recording is off.
        var recordingPluginIDs: Set<PluginID> = ["meetings", "dictation"]
        var now: @Sendable () -> Date = { Date() }
        var calendar: Calendar = .current
        var locale: Locale = .current
        var pageSize = 100
        /// `plugins.notes.*`, for the inspector's Details toggles; `nil` keeps them in memory (tests).
        var settings: PluginSettings?
        /// The Details toggles shared with Settings → Notes; `nil` makes them from `settings`.
        var preferences: NoteViewPreferences?
        /// The clock and budget of a source's `content(for:)`, like the listing's: a source that does not answer in
        /// time leaves the note "unavailable" and does not hold up the others.
        var clock: any Clock<Duration> = ContinuousClock()
        var contentBudget: Duration = SourceFanOut.defaultBudget
        /// The open documents (one writer each). `nil` until the store is wired (tests, QA without a store).
        var registry: NoteDocumentRegistry?
        /// The overlaid layers of a note, read from `notes.sqlite` when it is opened; empty when there are none or
        /// the store cannot be read.
        var overlayHeads: @Sendable (NoteItemID) async -> [OverlayLayerHead] = { _ in [] }
        /// Reconciles a note's overlays with its source when it is opened.
        var reconcile: @Sendable (NoteKey) async -> Void = { _ in }
        /// Asks for one trash pass now (the sweeps themselves run for the plugin's lifetime, `NotesPlugin`).
        var requestTrashSweep: @Sendable () async -> Void = {}
        /// New notes and editing need the store (and `plugins.notes.readOnly` off); without it ⌘N and the pen are off.
        var canCreateNotes = false
        var canEditNotes = false
        /// Creates a manual note (`notes:<uuid>`) and returns its key; `nil` when it could not be written.
        var createManualNote: @Sendable () async -> NoteKey? = { nil }
        /// "Make note" on a dictation: creates a NEW manual note that starts with this text (a copy, no link back) and
        /// returns its key; `nil` when it could not be written. The text is never logged.
        var createNote: @Sendable (String) async -> NoteKey? = { _ in nil }
        /// Writes a manual note's `title_override` (`nil` clears it); `false` when it could not be written.
        var setTitle: @Sendable (NoteKey, String?) async -> Bool = { _, _ in false }
        /// The editor's session for a layer of a loaded note (its writer and the rules of seeding); `nil` when the
        /// layer cannot be edited now.
        var makeEditingSession: @MainActor (NoteContent, String, NoteDocumentModel) -> NoteEditingSession? = {
            _, _, _ in nil
        }
        /// My notes' session for a loaded recorded note (the `mine` layer, written only by `human`); `nil` when
        /// nothing can write here (no store wired, or Notes is read-only).
        var makeMineSession: @MainActor (NoteContent) -> NoteEditingSession? = { _ in nil }
        /// Writes and forgets one layer document's writer (My notes of a note that left the screen).
        var releaseWriter: @MainActor (NoteDocumentID) async -> Void = { _ in }
        /// `plugins.notes.readOnly` was on when the section was built: My notes says so instead of "unavailable".
        var notesReadOnly = false
        /// The history of a layer (its revisions) from `notes.sqlite`; `.none` when the layer has no overlay.
        var loadHistory: @MainActor (NoteItemID, String) async -> HistoryState = { _, _ in .none }
        /// Restore: a new `human` revision with the text and authors of the revision, through the layer's one
        /// writer. `nil` when it was written, else why nothing was.
        var restoreRevision: @MainActor (NoteItemID, String, Int64) async -> RestoreFailure? = { _, _, _ in
            .other
        }
        /// Apply and Discard of a proposal (step 6.3), through the layer's one writer; `nil` when done, else why not.
        /// Apply takes the head the user compared (compare-and-set).
        var applyProposal: @MainActor (NoteItemID, String, Int64, Int64) async -> RestoreFailure? = { _, _, _, _ in
            .other
        }
        /// Discarding the user's own kept text needs `confirmedRemoval` (the store refuses it otherwise).
        var discardProposal: @MainActor (NoteItemID, String, Int64, Bool) async -> RestoreFailure? = { _, _, _, _ in
            .other
        }
        /// Delete: the owner first, the overlays only after it succeeded (`NoteDeleter`); throws a
        /// `NoteDeleter.Failure`. Off (`canDeleteNotes` false) without the store.
        var canDeleteNotes = false
        var deleteNote: @MainActor (NoteItemID) async throws -> Void = { _ in
            throw NoteDeleter.Failure.sourceUnavailable
        }
        /// The comments of a layer from `notes.sqlite`; `.none` when the layer has no overlay (step 5.2).
        var loadComments: @MainActor (NoteItemID, String) async -> CommentsState = { _, _ in .none }
        /// A reply, a resolve or a reopen on a loaded thread; `nil` when it was written, else why not.
        var writeComment: @MainActor (CommentWrite) async -> CommentFailure? = { _ in .other }
        /// "Revise with N comments" and "Ask agent" (step 6.2): runs the revise service for a layer document and says
        /// how the run ended; `nil` without the store or the agent, and the button stays off.
        var revise: (@MainActor (ReviseCall) async -> ReviseOutcome)?
        /// Cancel in the lock strip, a deleted note: stops the note's run (the document stays as it was). Going back to
        /// the list never cancels a run: it goes on and its result is applied (phase 3b).
        var cancelRevise: @MainActor (NoteItemID) -> Void = { _ in }
        /// Whether "Ask agent" on this thread waits behind a running run.
        var isReviseQueued: @MainActor (NoteItemID, Int64) -> Bool = { _, _ in false }
        /// Renames the title of a recorded note in its owner (`NoteSourceEditing`); `false` when it was not changed.
        var renameTitle: @MainActor (NoteKey, String) async -> Bool = { _, _ in false }
        /// The commands of the active plugins and the shell for the command palette (`PluginContext.availableCommands`).
        var availableCommands: @MainActor () -> [CommandInfo] = { [] }
        /// The dictation shortcut as it is right now (`PluginContext.commandShortcut`), for the empty states.
        var dictationShortcut: @MainActor () -> KeyShortcut? = { nil }
        /// The recorder of the meetings plugin, when it is on: the only way "Try Again" writes the notes again.
        var liveRecorder: @MainActor () -> (any LiveRecorder)? = { nil }
    }

    enum LoadState: Equatable {
        case loading
        case loaded
    }

    static let sectionID = "notes"

    let environment: Environment
    let presentation: NoteRowPresentation
    /// The Details toggles (author bars, source quotes, wrapped lines).
    let preferences: NoteViewPreferences
    /// The inspector on the right (Comments, History and Details).
    var inspectorVisible = true
    var inspectorTab: NoteInspectorTab = .comments
    /// "Hide content" (⌘⇧H): the explorer, the document and the inspector are blurred and titles are masked, for
    /// screen sharing. Session-only: never written to a setting, so a new launch shows everything.
    var hidesContent = false
    /// The command palette (⌘P), `nil` while closed.
    var palette: PaletteState?
    /// Whether the section is wide enough for the inspector next to the document (it grows with the text size).
    var inspectorFits = true
    /// A divider drag in progress: the pane and the width shown. Never stored; `endPaneDrag` stores it.
    var paneDrag: (pane: NotesPane, width: CGFloat)?
    /// The section's last measured width (unbounded until the first measure).
    var sectionWidth: CGFloat = .infinity
    /// The inspector was hidden by a narrow section, not by the user: it comes back when the room does.
    var inspectorHiddenForWidth = false
    /// The question the delete sheet shows, `nil` when none is open.
    var pendingDelete: DeleteRequest?
    /// "Try Again" in the preview did not write the notes; the preview says so until the selection changes.
    var previewRetryFailed = false
    /// The tab of a meeting's preview: Notes for every newly selected note (a choice never carries over to the next).
    private(set) var previewTab: PreviewTab = .notes

    private(set) var loadState: LoadState = .loading
    private(set) var rows: [NoteRow] = []
    private(set) var groups: [NoteGroup] = []
    private(set) var total = 0
    private(set) var unavailable: [UnavailableSource] = []
    /// `false` when `notes.sqlite` could not be read: the sources stay listed, writing is off (spec "Edge Cases").
    private(set) var overlaysAvailable = true
    private(set) var activePlugins: Set<PluginID> = []
    private var cursor: NoteListCursor?
    /// Counts every `refresh()`: an answer that arrives after a newer refresh began is dropped.
    private var listEpoch = 0
    private var isLoadingMore = false
    /// Changes whenever the rows or the cursor change; the explorer's "load more" sentinel is keyed on it, so it
    /// asks again while it is still on screen after a page came in.
    private(set) var pageToken = 0
    /// Counts the reads of each open note's content: only the newest read of a note may apply its answer.
    private var contentEpochs: [NoteItemID: Int] = [:]
    private var isSaving = false

    /// What the explorer's search field holds; `runSearch()` lists with it.
    var searchText = ""
    /// The query the rows on screen answer, `nil` while browsing.
    private(set) var searchQuery: NormalizedQuery?
    var collapsed: Set<NoteGroupKey> = []

    /// What the explorer has chosen: the sidebar's collection, its counts and the selected row (phase 3a). Search,
    /// the count, the empty states, paging and the command palette follow the collection.
    let explorer: ExplorerModel

    /// The collection the list shows.
    var collection: NoteCollection { explorer.collection }

    /// Today, Yesterday, the weekday, then dates (spec "Layout"); the old By Time / By Source menu is gone.
    var grouping: NoteGrouping = .day {
        didSet { if grouping != oldValue { regroup() } }
    }

    #if DEBUG
    /// QA (`plugins.notes.qaOpen`): the layer a note shows once its content has been read.
    var preferredLayers: [NoteItemID: String] = [:]
    /// QA (`plugins.notes.qaState=loading`): `run()` never reads, so the loading screen stays.
    var holdsLoading = false
    /// QA (`plugins.notes.qaSearch`): the text typed into the search field once the first list is in.
    var initialSearch: String?
    /// QA (`plugins.notes.qaSelect`): the row selected once the first list is in, and the preview's tab.
    var initialSelection: (id: NoteItemID, tab: PreviewTab?)?
    /// `plugins.notes.qaEditor`: `on` or `readonly` shows the open note in the editor.
    var qaEditor: String?
    /// `plugins.notes.qaAttribution=mixed`.
    var qaMixedAuthors = false
    #endif

    /// Formatted or Raw for every editor of this window. Kept in memory for the session only: no setting, so a new
    /// window or launch starts in Formatted. Switching never touches a note (`NoteEditorMode`).
    var editorMode: NoteEditorMode = .formatted

    /// QA runs (`--qa-notes`) show no animation, so a snapshot never catches one half way (`NotesMotion`).
    var animationsDisabled = false

    private(set) var documents: [NoteItemID: NoteDocumentModel] = [:]

    init(environment: Environment) {
        self.environment = environment
        presentation = NoteRowPresentation(calendar: environment.calendar, locale: environment.locale)
        preferences = environment.preferences ?? NoteViewPreferences(settings: environment.settings)
        explorer = ExplorerModel(settings: environment.settings)
    }

    // MARK: Listing

    var hasMore: Bool { cursor != nil }

    /// Lists the first page again (the first read, or a source said its notes changed) and refreshes the tabs'
    /// titles and the open documents. While a search is on, it is the search's first page.
    func refresh() async {
        listEpoch += 1
        let epoch = listEpoch
        let query = searchQuery
        let shown = collection
        let listing = await environment.library.list(
            matching: query, after: nil, limit: environment.pageSize, collection: shown)
        let plugins = Set(await environment.library.activePluginIDs)
        guard epoch == listEpoch, query == searchQuery, shown == collection else { return }
        rows = listing.rows
        cursor = listing.next
        total = listing.total
        unavailable = listing.unavailable
        overlaysAvailable = listing.overlaysAvailable
        activePlugins = plugins
        loadState = .loaded
        pageToken += 1
        regroup()
        reconcileSelection()
        await refreshCounts()
        await reloadOpenDocuments()
    }

    /// The sidebar's numbers: browse counts only. A search leaves them as they were (its totals are hit counts).
    func refreshCounts() async {
        guard searchQuery == nil else { return }
        explorer.setCounts(await environment.library.counts())
    }

    func loadMore() async {
        guard let cursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let epoch = listEpoch
        let query = searchQuery
        let shown = collection
        let listing = await environment.library.list(
            matching: query, after: cursor, limit: environment.pageSize, collection: shown)
        // A refresh (or another query or view) began meanwhile: its rows and cursor are newer than this page.
        guard epoch == listEpoch, query == searchQuery, shown == collection else { return }
        guard listing.restarted == false else {
            await refresh()
            return
        }
        let known = Set(rows.map(\.id))
        rows += listing.rows.filter { !known.contains($0.id) }
        self.cursor = listing.next
        total = listing.total
        unavailable = listing.unavailable
        pageToken += 1
        regroup()
        reconcileSelection()
    }

    // MARK: Collections

    /// A click on a sidebar row: shows that collection's list with the same search text and remembers the choice
    /// (`plugins.notes.explorer.collection`).
    func setCollection(_ next: NoteCollection) async {
        guard prepareCollection(next, persist: true) else { return }
        await refresh()
    }

    /// The switch itself, without the read; `false` when nothing changes. The rows are dropped at once, so a
    /// dictation never flashes in the Meetings list. A note open in the full window stays open.
    @discardableResult
    func prepareCollection(_ next: NoteCollection, persist: Bool = false) -> Bool {
        guard explorer.setCollection(next, persist: persist) else { return false }
        listEpoch += 1
        rows = []
        groups = []
        total = 0
        cursor = nil
        unavailable = []
        loadState = .loading
        pageToken += 1
        return true
    }

    /// Opening a note (a route, ⌘O of the dictation history) that the shown collection does not list moves the list
    /// to All notes at once (the setting is not rewritten: it was not a choice of the user) and reads it in the
    /// background; the note is selected once it is listed.
    private func showCollection(of id: NoteItemID) {
        explorer.select(id)
        guard !collection.contains(id) else { return }
        guard prepareCollection(.all) else { return }
        Task { await refresh() }
    }

    /// "Search All Notes": the search stays, the list widens to All notes (not stored).
    func searchAllNotes() async {
        guard prepareCollection(.all) else { return }
        await refresh()
    }

    // MARK: Selection and preview

    /// The rows in the order the list draws them (groups first, or the flat search answer).
    var visibleRows: [NoteRow] {
        isSearching ? rows : groups.filter { !collapsed.contains($0.key) }.flatMap(\.rows)
    }

    private func reconcileSelection() {
        // The note in the full window stays selected while it is open, even when the list no longer shows it (a
        // search, another collection): the list gets it back when the user goes back.
        guard openedID == nil else { return }
        let previous = explorer.selection
        let next = explorer.reconcile(order: visibleRows.map(\.id))
        guard next != previous else { return }
        previewTab = .notes
        previewRetryFailed = false
        // The row that was selected left the list: its preview goes. The view that shows the new selection reads it
        // (`loadPreview`).
        if let previous { dropPreview(previous) }
    }

    /// Grows on every click on a row; the list takes the keyboard focus when it changes, so ↑ / ↓ and Return work
    /// right after a click instead of going to the search field (QA of #348, M-B).
    private(set) var listFocusRequests = 0

    /// A click on a row: selects it and asks the list for the keyboard focus.
    func click(row id: NoteItemID) {
        select(row: id)
        listFocusRequests += 1
    }

    /// A click or an arrow key: the preview shows this note. It does not open the full window.
    func select(row id: NoteItemID) {
        let previous = explorer.selection
        guard previous != id else { return }
        previewRetryFailed = false
        previewTab = .notes
        explorer.select(id)
        if let previous { dropPreview(previous) }
    }

    /// A click on the preview's Notes, My notes or Transcript tab. A tab whose layer the note does not have stays
    /// on and says what is missing (`PreviewNotice`).
    func selectPreviewTab(_ tab: PreviewTab) {
        let leavesMine = previewTab == .mine && tab != .mine
        previewTab = tab
        guard let document = previewDocument else { return }
        if leavesMine { flushMyNotes(document) }
        if tab == .mine { prepareMyNotes(document) }
        document.preferredLayerID = tab.layerID ?? document.preferredLayerID
        if let layer = tab.layerID { document.selectLayer(layer) }
    }

    /// What the Notes tab of the selected meeting says instead of the notes; `nil` when the notes (or another tab)
    /// are shown, and always `nil` for a dictation or a note you wrote.
    func previewNotice(_ document: NoteDocumentModel) -> PreviewNotice? {
        guard Self.isMeeting(document) else { return nil }
        return PreviewNotice.make(
            tab: previewTab, state: document.state, hasNotes: document.layers.contains { $0.id == "notes" },
            canRetry: canRetryNotes(document.id))
    }

    /// A meeting has the three preview tabs; a dictation and a note you wrote have none.
    static func isMeeting(_ document: NoteDocumentModel) -> Bool {
        if let summary = document.summary {
            return NoteCollection.meetings.contains(key: summary.id, kind: summary.kind)
        }
        return NoteCollection.meetings.contains(document.id)
    }

    /// ↑ / ↓ in the list.
    func moveSelection(by step: Int) {
        let order = visibleRows.map(\.id)
        guard let next = explorer.neighbour(of: explorer.selection, in: order, step: step) else { return }
        select(row: next)
    }

    /// The model of the note the preview shows; `nil` while nothing is selected.
    var previewDocument: NoteDocumentModel? { explorer.selection.flatMap { documents[$0] } }

    /// Reads the selected note once for the preview (its document is the one the full window uses). The preview view calls
    /// it for the selection it shows, so no read runs in the background of a model nobody looks at.
    ///
    /// One read per note at a time: a second caller (the gallery host, a second `.task`) waits for the running one,
    /// so whoever awaits this sees the note loaded.
    func loadPreview(_ id: NoteItemID) async {
        guard explorer.selection == id else { return }
        if documents[id] == nil {
            let document = makeDocument(id)
            document.preferredLayerID = previewTab.layerID ?? "notes"
            documents[id] = document
        }
        if let running = previewReads[id] {
            await running.value
            return
        }
        guard documents[id]?.phase == .loading else { return }
        let read = Task { await self.loadContent(id) }
        previewReads[id] = read
        await read.value
        previewReads[id] = nil
    }

    @ObservationIgnored private var previewReads: [NoteItemID: Task<Void, Never>] = [:]

    /// Forgets a preview nobody sees. The note open in the full window keeps its document, and so does a note whose
    /// agent run is going on: the run is never cancelled by a click elsewhere, and its document is dropped once the
    /// run has ended (`runRevise`).
    func dropPreview(_ id: NoteItemID) {
        guard id != openedID, id != explorer.selection, let document = documents[id] else { return }
        guard !document.lock.isActive else { return }
        if document.isEditing { document.leaveEditing() }
        closeMyNotes(document)
        documents[id] = nil
        contentEpochs[id] = nil
    }

    // MARK: Search

    /// Lists with the text in the search field: every source's `list(matching:)` merged newest first, paged like
    /// the browse list. An empty (or blank) field goes back to the browse list. Notes' own manual notes and the
    /// full-text hits of `notes.sqlite` join a query with the store (step 4.0).
    func runSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.isEmpty ? nil : TextNormalizer.query(trimmed)
        let next = (query?.isEmpty == false) ? query : nil
        if next == searchQuery { return }
        searchQuery = next
        await refresh()
    }

    /// The field's clear button and Escape.
    func clearSearch() async {
        searchText = ""
        await runSearch()
    }

    var isSearching: Bool { searchQuery != nil }

    /// While a search is on: the first matched layer's snippet (plain text; the view marks the query's words).
    func snippetText(of row: NoteRow) -> String? {
        // Hide content: a snippet is the note's own text, so it is not drawn at all (blur alone is not enough).
        guard searchQuery != nil, !hidesContent else { return nil }
        let text = row.summary.matches.first?.snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }

    /// The section's lifetime: reads the list, then again whenever a source (or the set of sources) changes.
    /// Returns when cancelled.
    func run() async {
        #if DEBUG
        if holdsLoading { return }
        #endif
        let sweeps = Task { await environment.requestTrashSweep() }
        defer { sweeps.cancel() }
        await refresh()
        #if DEBUG
        if let text = initialSearch {
            initialSearch = nil
            searchText = text
            await runSearch()
        }
        if let (id, tab) = initialSelection {
            initialSelection = nil
            select(row: id)
            if let tab { selectPreviewTab(tab) }
        }
        #endif
        for await _ in environment.library.changes(sourceSetChanges: environment.sourceSetChanges()) {
            if Task.isCancelled { return }
            await refresh()
        }
    }

    private func regroup() {
        // A search answer is one flat list, best newest first, so the groups would only get in the way.
        guard searchQuery == nil else {
            groups = []
            return
        }
        groups = NoteGroupingRules.group(
            rows, by: grouping, now: environment.now(), calendar: environment.calendar)
    }

    func row(for id: NoteItemID) -> NoteRow? { rows.first { $0.id == id } }

    /// The explorer shows the date next to the time outside today and yesterday.
    func showsDate(_ row: NoteRow) -> Bool {
        switch NoteGroupingRules.timeKey(row.startedAt, now: environment.now(), calendar: environment.calendar) {
        case .today, .yesterday: false
        default: true
        }
    }

    func title(of row: NoteRow) -> String { presentation.title(row.summary) }

    /// The row's title as the explorer draws it: masked while Hide content is on.
    func shownTitle(of row: NoteRow) -> String { shown(title(of: row)) }

    func title(of group: NoteGroup) -> String {
        switch group.key {
        case .today: String(localized: "Today", comment: "Explorer: group of today's notes")
        case .yesterday: String(localized: "Yesterday", comment: "Explorer: group of yesterday's notes")
        case .previousSevenDays:
            String(localized: "Previous 7 Days", comment: "Explorer: group of the last week's notes")
        case .previousThirtyDays:
            String(localized: "Previous 30 Days", comment: "Explorer: group of the last month's notes")
        case .earlier: String(localized: "Earlier", comment: "Explorer: group of older notes")
        case .day: ExplorerRowText(presentation: presentation).title(of: group.key, now: environment.now())
        case .source(let id):
            switch id.rawValue {
            case "meetings": String(localized: "Meetings", comment: "Explorer: group of meeting notes")
            case "dictation": String(localized: "Dictation", comment: "Explorer: group of dictations")
            case "notes": String(localized: "Notes", comment: "Explorer: group of manual notes")
            default: id.rawValue
            }
        }
    }

    // MARK: Full window

    /// The note shown in the full window (Open, a double click, Return, a route, the palette), `nil` while the
    /// explorer's list and preview are shown. One note at a time: the tab bar of the workspace is gone (notes explorer
    /// spec, phase 3b). The note stays selected in the list, so going back shows it there.
    private(set) var openedID: NoteItemID?

    /// The shell hides its sidebar and the section hides its list while a note fills the window.
    var isFullWindow: Bool { openedID != nil }

    var currentID: NoteItemID? { openedID }
    var currentDocument: NoteDocumentModel? { openedID.flatMap { documents[$0] } }

    /// Opens a note in the full window: it is selected in the list (the list moves to All notes when the shown
    /// collection does not have it) and its document is the one the preview used. The text is read by
    /// `loadContent`. A note that was open before is left the way "‹ All notes" leaves it: its typing is written
    /// and an agent run on it goes on.
    func open(_ id: NoteItemID) {
        if let previous = openedID, previous != id {
            leave(previous)
            openedID = nil
        }
        let previousSelection = explorer.selection
        if previousSelection != id {
            // A note opened from a route, the palette or "Make note" starts on its Notes, like a new selection.
            previewTab = .notes
            previewRetryFailed = false
        }
        showCollection(of: id)
        if let previousSelection, previousSelection != id { dropPreview(previousSelection) }
        let document = documents[id] ?? makeDocument(id)
        documents[id] = document
        // The full window shows what the preview's tab showed (My notes included); after that the layer is the
        // user's choice, so a reload never switches it back.
        document.showsMine = previewTab == .mine
        if document.showsMine { prepareMyNotes(document) }
        if let layer = previewTab.layerID, document.phase == .loaded { document.selectLayer(layer) }
        document.preferredLayerID = nil
        openedID = id
    }

    /// A document model whose editor, when it ends, writes what is typed and reads the note again.
    private func makeDocument(_ id: NoteItemID) -> NoteDocumentModel {
        let document = NoteDocumentModel(id: id)
        document.onEditingEnded = { [weak self] session in
            Task { @MainActor in await self?.finishEditing(id, session) }
        }
        return document
    }

    /// "‹ All notes" (⌘[, Esc) and ⌘W: back to the list with the note still selected and its preview on the tab it
    /// showed. What is typed is written first; an agent run on the note is NOT cancelled (it goes on, the lock strip
    /// shows again when the note is opened, and its result is applied).
    func closeFullWindow() {
        guard let id = openedID else { return }
        leave(id)
        openedID = nil
        listFocusRequests += 1
    }

    /// Leaves the full window of `id`: the editor ends (which writes), a comparison closes, and the preview's tab
    /// follows what was shown.
    private func leave(_ id: NoteItemID) {
        guard let document = documents[id] else { return }
        if document.isEditing { document.leaveEditing() }
        if document.compare != nil { document.setCompare(nil) }
        flushMyNotes(document)
        guard explorer.selection == id else { return }
        previewTab =
            document.showsMine
            ? .mine : (document.layerID == NoteDocumentModel.transcriptLayerID ? .transcript : .notes)
        document.preferredLayerID = previewTab.layerID ?? document.layerID
    }

    /// A detach re-keyed an open note: its document moves from `.live(key)` to `.detached(key, startedAtMs:)` and
    /// is labelled "Recording removed". A new live note with the same key (a recreated store's row 1) is a
    /// different identity.
    @discardableResult
    func rekeyDetached(key: NoteKey, startedAtMs: Int64) -> Bool {
        let old = NoteItemID.live(key)
        let new = NoteItemID.detached(key, startedAtMs: startedAtMs)
        guard openedID == old || explorer.selection == old, documents[new] == nil else { return false }
        documents[new] = documents.removeValue(forKey: old).map { _ in makeDocument(new) }
        contentEpochs[old] = nil
        if openedID == old { openedID = new }
        if explorer.selection == old { explorer.select(new) }
        Task { await loadContent(new) }
        return true
    }

    /// ⌘W (`WorkspaceSection.handleClose`): leaves the full window and keeps the window open (`true`); in the list
    /// it does nothing, so the window closes.
    @discardableResult
    func handleClose() -> Bool {
        guard isFullWindow else { return false }
        closeFullWindow()
        return true
    }

    /// `WorkspaceSection.handleRoute`: an `openNote` route selects the note and opens it in the full window. Any
    /// other route, or an id that is not a note key, is not handled.
    func handle(_ route: WorkspaceRoute) -> Bool {
        guard let id = NoteRoute.itemID(for: route) else { return false }
        open(id)
        return true
    }

    // MARK: Documents

    /// Reads a note's content from its source. A source that is off or slow leaves the note "unavailable"; only
    /// an answer of "no such note" makes it gone.
    func loadContent(_ id: NoteItemID) async {
        guard let document = documents[id] else { return }
        let epoch = (contentEpochs[id] ?? 0) + 1
        contentEpochs[id] = epoch
        if case .detached = id {
            // A detached note shows only its overlaid layers; the source is never asked (it would answer with
            // the text of another recording, or of none).
            let heads = await environment.overlayHeads(id)
            guard isCurrent(epoch, id, document) else { return }
            if let content = NoteOverlayContent.compose(
                item: id, source: nil, heads: heads, summary: row(for: id)?.summary)
            {
                document.apply(
                    content, attributions: NoteOverlayContent.attributions(heads: heads),
                    proposals: NoteOverlayContent.proposals(heads: heads))
                document.mineMarkdown = NoteOverlayContent.mine(heads: heads)
                document.setActions([])
                prepareMyNotesIfShown(document)
                await refreshPanes(id)
            } else {
                document.markUnavailable()
            }
            return
        }
        if document.isManual {
            // A manual note has no source: its text is the head of its own document.
            let heads = await environment.overlayHeads(id)
            guard isCurrent(epoch, id, document) else { return }
            if let content = NoteOverlayContent.compose(
                item: id, source: nil, heads: heads, summary: row(for: id)?.summary)
            {
                document.apply(
                    content, attributions: NoteOverlayContent.attributions(heads: heads),
                    proposals: NoteOverlayContent.proposals(heads: heads))
                document.setActions([])
                if document.wantsEditing { beginEditing(id) }
                await refreshPanes(id)
            } else {
                document.markUnavailable()
            }
            return
        }
        guard let source = await environment.library.source(for: id.key) else {
            if isCurrent(epoch, id, document) { document.markUnavailable() }
            return
        }
        let key = id.key
        await environment.reconcile(key)
        guard isCurrent(epoch, id, document) else { return }
        let outcome = await SourceFanOut.call(budget: environment.contentBudget, clock: environment.clock) {
            try await source.content(for: key)
        }
        // The note was left, or a newer read of this note began: its answer wins.
        guard isCurrent(epoch, id, document) else { return }
        switch outcome {
        case .value(let read):
            let heads = await environment.overlayHeads(id)
            guard isCurrent(epoch, id, document) else { return }
            document.apply(
                NoteOverlayContent.compose(item: id, source: read, heads: heads, summary: nil),
                attributions: NoteOverlayContent.attributions(heads: heads),
                proposals: NoteOverlayContent.proposals(heads: heads))
            document.mineMarkdown = NoteOverlayContent.mine(heads: heads)
            document.setActions(source.actions(for: key))
            document.canRenameTitle = source is any NoteSourceEditing
            prepareMyNotesIfShown(document)
            await refreshPanes(id)
            #if DEBUG
            if qaMixedAuthors { document.qaMixAuthors() }
            if let layer = preferredLayers.removeValue(forKey: id) { document.selectLayer(layer) }
            #endif
        case .failed, .timedOut:
            document.markUnavailable()
        case .cancelled:
            break
        }
    }

    /// The note is gone (deleted): the full window goes back to the list and the document goes without writing
    /// anything again (the registry already discarded the writers).
    func dropDocument(_ id: NoteItemID) {
        environment.cancelRevise(id)
        if openedID == id {
            openedID = nil
            listFocusRequests += 1
        }
        documents[id] = nil
        contentEpochs[id] = nil
    }

    private func isCurrent(_ epoch: Int, _ id: NoteItemID, _ document: NoteDocumentModel) -> Bool {
        contentEpochs[id] == epoch && documents[id] === document
    }

    /// Every document on screen (the full window, the preview, a note whose agent run goes on) is read on its own,
    /// so a source that does not answer holds up only its own note.
    private func reloadOpenDocuments() async {
        let ids = documents.keys.sorted { $0.key.rawValue < $1.key.rawValue }
        let reads = ids.map { id in Task { await loadContent(id) } }
        for read in reads { await read.value }
    }

    // MARK: New notes (step 4.4)

    /// ⌘N and the explorer's "New note" button: possible with the store open for writing.
    var canCreateNote: Bool { environment.canCreateNotes && overlaysAvailable && !isCreatingNote }

    private var isCreatingNote = false

    /// Creates a manual note, lists it, and opens it in the full window with the editor ready. A search in the
    /// explorer is cleared first, so the new row is visible.
    func newNote() async {
        guard canCreateNote else { return }
        isCreatingNote = true
        defer { isCreatingNote = false }
        guard let key = await environment.createManualNote() else {
            show(.createFailed)
            return
        }
        if isSearching { await clearSearch() } else { await refresh() }
        let id = NoteItemID.live(key)
        open(id)
        documents[id]?.wantsEditing = true
        await loadContent(id)
    }

    // MARK: Make note (owner feedback H)

    /// The dictation layers whose text a made note starts with: the cleaned text, else (no cleaned text was kept)
    /// the transcript the dictation was pasted with. The raw transcript of an entry that has a cleaned text stays
    /// in the dictation only.
    static let dictationTextLayers = ["cleaned", "original"]

    /// "Make note" is running: the action is off until it ends, so one tap makes one note.
    private(set) var isMakingNote = false

    static func dictationText(in content: NoteContent) -> String? {
        for id in dictationTextLayers {
            guard let layer = content.layers.first(where: { $0.id == id }) else { continue }
            let text = MarkdownText.strippingBidiAndControls(layer.markdown)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        }
        return nil
    }

    /// Offered for a live dictation while notes can be written (not with `plugins.notes.readOnly`, not without the
    /// store) and no other "Make note" is running.
    func canMakeNote(_ id: NoteItemID) -> Bool {
        guard environment.canCreateNotes, environment.canEditNotes, overlaysAvailable, !isMakingNote else {
            return false
        }
        if case .detached = id { return false }
        return NoteCollection.isDictation(id)
    }

    /// Copies the dictation's text into a NEW manual note, opens it in the editor in the full window and shows the
    /// Notes list. The note is independent: no link back, so deleting either never touches the other, and the dictation
    /// gets no overlay, revision or comment. A second call after this one ended makes a second note. When the note
    /// cannot be written nothing changes and a strip says so; the dictation still holds the text.
    func makeNote(from id: NoteItemID) async {
        guard canMakeNote(id) else { return }
        isMakingNote = true
        defer { isMakingNote = false }
        guard let text = await dictationText(of: id) else {
            show(.makeNoteFailed)
            return
        }
        guard let key = await environment.createNote(text) else {
            show(.makeNoteFailed)
            return
        }
        prepareCollection(.all)
        if isSearching { await clearSearch() } else { await refresh() }
        let made = NoteItemID.live(key)
        open(made)
        documents[made]?.wantsEditing = true
        await loadContent(made)
        show(.noteMade)
    }

    /// The text of a dictation: from its open document, else from its source (under the content budget).
    private func dictationText(of id: NoteItemID) async -> String? {
        if let content = documents[id]?.content { return Self.dictationText(in: content) }
        guard let source = await environment.library.source(for: id.key) else { return nil }
        let key = id.key
        let outcome = await SourceFanOut.call(budget: environment.contentBudget, clock: environment.clock) {
            try await source.content(for: key)
        }
        guard case .value(.some(let content)) = outcome else { return nil }
        return Self.dictationText(in: content)
    }

    /// Whether the title of a recorded note is a field: its owner supports renaming and the note is still there.
    func canRenameTitle(_ document: NoteDocumentModel) -> Bool {
        if case .detached = document.id { return false }
        return document.canRenameTitle && !document.isManual
    }

    /// Whether the title field accepts typing: a manual note needs the store; a recorded one only its owner.
    func canEditTitle(_ document: NoteDocumentModel) -> Bool {
        document.isManual ? environment.canEditNotes : canRenameTitle(document)
    }

    /// A manual note's title: the line above its text. Trimmed and cleaned like `NotesStore.cleanTitle`; an empty
    /// one clears it. Nothing happens when it did not change.
    func setTitle(_ id: NoteItemID, to text: String) async {
        guard let document = documents[id] else { return }
        await setTitle(of: document, to: text)
    }

    /// The same for the document the title field belongs to, which may already be gone: the field writes its last
    /// draft when it disappears (⌘W, "‹ All notes", the window), after the document was left.
    func setTitle(of document: NoteDocumentModel, to text: String) async {
        guard document.isManual || canRenameTitle(document) else { return }
        let id = document.id
        let clean = NotesStore.cleanTitle(text)
        let current = NotesStore.cleanTitle(row(for: id)?.summary.title ?? document.summary?.title)
        guard clean != current else { return }
        // A manual note's title is Notes' own (`title_override`); a recorded note's belongs to its owner and is
        // renamed through `NoteSourceEditing`, never in `notes.sqlite`.
        let written =
            document.isManual
            ? await environment.setTitle(id.key, clean) : await environment.renameTitle(id.key, clean ?? "")
        guard written else {
            show(.titleFailed)
            return
        }
        await refresh()
    }

    // MARK: Editing (step 4.4)

    /// The most that opens in the editor; a longer layer (a 3-hour transcript) stays read-only with Export.
    static let editableLimit = 200_000

    /// Whether the pen is on for the open layer (spec: seeding only in the states it allows, an overlay or a manual
    /// note always, never with `plugins.notes.readOnly`, never beyond the size limit or on a detached note).
    func canEdit(_ document: NoteDocumentModel) -> Bool {
        guard environment.canEditNotes, document.phase == .loaded, !document.showsMine, let content = document.content,
            let layer = document.selectedLayer
        else { return false }
        if case .detached = document.id { return false }
        if layer.markdown.utf16.count > Self.editableLimit { return false }
        if document.isManual || document.attributions[layer.id] != nil { return true }
        return OverlaySeeder.canSeed(state: content.summary.state, layer: layer)
    }

    /// The pen of the full window's bar: the editor for the shown layer, or back to reading.
    func toggleEditing() {
        guard let id = currentID, let document = documents[id] else { return }
        if document.isEditing {
            document.leaveEditing()
        } else {
            beginEditing(id)
        }
    }

    func beginEditing(_ id: NoteItemID) {
        guard let document = documents[id], !document.isEditing, canEdit(document), let content = document.content,
            let layerID = document.layerID,
            let session = environment.makeEditingSession(content, layerID, document), session.isEditable
        else { return }
        document.startEditing(session)
    }

    /// Editing ended: what is typed is written, the layers show the head again and the note is read once more.
    func finishEditing(_ id: NoteItemID, _ session: NoteEditingSession) async {
        _ = await session.flush(closingSession: true)
        guard let document = documents[id] else { return }
        document.unfreezeAll()
        await loadContent(id)
    }

    // MARK: Status bar

    /// "27 notes · 1 writing".
    var statusSummary: String {
        let notes =
            switch collection {
            case .dictations:
                String(
                    localized: "\(total) dictations", comment: "Notes status bar: how many dictations the list holds")
            case .meetings:
                String(localized: "\(total) meetings", comment: "Notes status bar: how many meetings the list holds")
            case .all:
                String(localized: "\(total) notes", comment: "Notes status bar: how many notes the list holds")
            }
        let writing = writingCount
        guard writing > 0 else { return notes }
        let active = String(
            localized: "\(writing) writing", comment: "Notes status bar: how many notes are being written")
        return "\(notes) · \(active)"
    }

    var writingCount: Int {
        rows.filter { if case .writing = $0.badge { true } else { false } }.count
    }

    // MARK: Copy and save

    /// Why a restore wrote nothing.
    enum RestoreFailure: Equatable, Sendable {
        case changed, readOnly, badTarget, other
        /// Discard of the user's own kept text without the confirmation.
        case needsConfirmation
    }

    /// What the full window's bar just did, in words for the screen and for VoiceOver.
    enum Feedback: Equatable {
        case copied
        case saved
        case saveFailed
        case createFailed
        /// "Make note" made a note / could not (the dictation is unchanged either way).
        case noteMade
        case makeNoteFailed
        case titleFailed
        case restored
        case restoreFailed
        /// The note changed under the restore (the head moved): nothing was written.
        case restoreChanged
        case restoreReadOnly
        /// The version is not an earlier applied version of this note.
        case restoreTargetInvalid
        /// A proposal was applied or discarded (a short message on the bar).
        case proposalApplied
        case proposalDiscarded
        /// The note changed after the comparison: nothing was applied.
        case proposalChanged
        case proposalFailed
        case deleted
        case deleteFailed
        case copyNotRemoved
        /// A comment could not be written; the text is still in the popover or the reply field.
        case commentFailed
        /// Comments are read-only (`plugins.notes.readOnly`, a newer database).
        case commentReadOnly
        /// The selected text is not in the saved note, so it cannot be commented on.
        case commentChanged
        /// The comment is longer than `NotesStore.commentLimit`; nothing was cut or written.
        case commentTooLong
        /// The selected passage is longer than `CommentAnchors.maxQuoteLength`.
        case commentSelectionTooLong
        /// The selection is empty, blank or no longer inside the note.
        case commentSelectionInvalid

        /// A message that stays as a strip until dismissed, instead of fading from the bar.
        var isStrip: Bool {
            switch self {
            case .saveFailed, .makeNoteFailed, .restoreFailed, .restoreChanged, .restoreReadOnly, .restoreTargetInvalid,
                .proposalChanged,
                .proposalFailed, .deleteFailed,
                .copyNotRemoved, .commentFailed, .commentReadOnly, .commentChanged, .commentTooLong,
                .commentSelectionTooLong, .commentSelectionInvalid:
                true
            default: false
            }
        }
    }

    private(set) var feedback: Feedback?
    /// Changes with every `feedback`, so the view can clear a message after a moment and announce it.
    private(set) var feedbackSerial = 0

    #if DEBUG
    /// QA (`plugins.notes.qaState=saveError`): shows the save-error strip without writing anything.
    func qaShow(_ feedback: Feedback) { show(feedback) }
    #endif

    func show(_ feedback: Feedback?) {
        self.feedback = feedback
        feedbackSerial += 1
    }

    func dismissFeedback() {
        if feedback != nil { show(nil) }
    }

    /// ⌘⇧C: the Markdown of the layer on screen goes to the pasteboard with the transient and concealed markers,
    /// for this Mac only.
    func copyMarkdown() {
        guard let document = currentDocument, let text = shownMarkdown(document), !text.isEmpty else { return }
        NoteClipboard.copy(text, to: environment.pasteboard)
        show(.copied)
    }

    /// Save .md…: a save panel, then the file. A cancelled panel says nothing; a failed write says so. `retry`
    /// writes to the place that just failed instead of asking again ("Try again" of the save-error strip).
    func saveMarkdown(retry: Bool = false) async {
        guard let document = currentDocument, let text = shownMarkdown(document), let summary = document.summary else {
            return
        }
        // One save panel at a time: a second ⌘S while the panel is open would stack another.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let name = NoteMarkdownExport.fileName(summary)
        do {
            let saved =
                retry
                ? try await environment.saver.retry(text, suggestedName: name)
                : try await environment.saver.save(text, suggestedName: name)
            show(saved ? .saved : nil)
        } catch {
            show(.saveFailed)
        }
    }

    // MARK: Chrome

    func openSettings() { environment.openSettings() }
}
