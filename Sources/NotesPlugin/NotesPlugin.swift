import Foundation
import LintelKit
import SwiftUI

/// The Notes workspace (spec `.ai/specs/2026-11-04-notes-workspace.md`). Step 1.2 is the skeleton: the manifest and
/// a `notesSection` stub. The plugin is registered in `PluginRegistry` only `#if DEBUG` until step 7.1, so users see
/// nothing of it.
///
/// The store (`NotesLibraryOpener`) opens lazily on first need, never in `activate()`; notes, transcripts and
/// dictation text never reach a log. Other plugins are seen only as `any NoteSource` values the shell hands over
/// (`PluginContext.noteSources`); `NotesPlugin` imports no other plugin.
@MainActor
public final class NotesPlugin: LintelPlugin {
    public nonisolated static let manifest = PluginManifest(
        id: "notes",
        displayName: LocalizedStringResource("Notes", comment: "Plugin name of the Notes workspace"),
        symbolName: "note.text",
        order: 5,
        defaultEnabled: true,
        canBeDisabled: false,
        summary: LocalizedStringResource(
            "Read, edit and comment on your recordings and notes.", comment: "Settings → Features: what Notes does")
    )

    let context: PluginContext

    public init(context: PluginContext) {
        self.context = context
    }

    /// The store is opened lazily, by the first thing that needs it (never here, never in a manifest read or a
    /// settings pane). Building the opener touches no file and no Keychain.
    private(set) lazy var library = NotesLibraryOpener(
        directory: context.storageDirectory, keychain: context.keychain, settings: NotesSettings(context.settings))

    /// Activation touches no file and no Keychain: it only starts the trash-sweep task (`startTrashSweeps`), which
    /// reads nothing until `hasLibrary()` says a library exists.
    public func activate() async throws {
        startTrashSweeps()
    }

    /// The open documents: one `RevisionWriter` each, flushed on blur, tab close, window close and here.
    private(set) lazy var documents = NoteDocumentRegistry()

    /// The revise service: one run per document, cancelled on quit.
    private(set) lazy var reviseService = makeReviseService()

    /// A run is cancelled first (the document stays as it was), then typed text is written before the store closes
    /// (spec "Saving": quit loses nothing).
    public func deactivate() async {
        await stopTrashSweeps()
        await reviseService.cancelAll()
        await documents.flushAll()
        library.close()
        trashChanges.finishAll()
    }

    /// The change streams of Notes' own Recently deleted (`ManualNotesTrash.makeChanges()`).
    let trashChanges = TrashChangeBroadcaster()

    /// Recently deleted for the manual notes (Notes is their owner). Reads only an existing library: on a fresh
    /// profile it answers 0 and empty pages without creating the Keychain item or `notes.sqlite`.
    private(set) lazy var manualTrash = ManualNotesTrash(
        store: { [hasLibrary, storeProvider] in hasLibrary() ? storeProvider() : nil }, changes: trashChanges,
        discard: { [documents] ids in await documents.discard(docIDs: ids) })

    public var trashSources: [any TrashSource] { [manualTrash] }

    /// "Erase Data" (Settings → Features): removes the Keychain item and `Plugins/notes/`; never touches the
    /// sources. The same as "Erase Notes Data…": the open documents' writers hold the store that is erased, so they
    /// are dropped too, else the text typed afterwards would go to a closed store and never be saved.
    public func eraseData() async throws {
        try await eraseNotesData()
    }

    /// The Details toggles, shared by the inspector and Settings → Notes (a change shows in both at once).
    private(set) lazy var preferences = NoteViewPreferences(settings: context.settings)

    /// Set when the workspace was built, so Erase Notes Data does not build it only to refresh it.
    private(set) var builtWorkspace: NotesWorkspaceModel?
    var cachedPaneModel: NotesPaneModel?
    /// Catalog models found installed by the pane's last refresh (the Models pane reads it, never the disk).
    var installedModelIDs: Set<String> { cachedPaneModel?.installedIDs ?? [] }

    /// The Notes section's state, built when the section is first shown or a route reaches it.
    private(set) lazy var workspace: NotesWorkspaceModel = makeWorkspace()

    public var workspaceSections: [WorkspaceSection] {
        [notesSection]
    }

    /// The Notes section of the main window: the explorer (list and preview) or one note in the full window, and the
    /// status bar. `handleRoute` takes an `openNote` route; `handleClose` (⌘W) leaves the full window before the
    /// window closes.
    var notesSection: WorkspaceSection {
        WorkspaceSection(
            id: NotesWorkspaceModel.sectionID,
            title: LocalizedStringResource("Notes", comment: "Main window section title"),
            symbolName: "note.text",
            order: Self.manifest.order,
            sidebar: WorkspaceSidebar(makeView: { [self] context in
                AnyView(NotesSidebarBlock(model: workspace, context: context))
            }),
            makeView: { [self] in AnyView(NotesSectionView(model: workspace)) },
            handleRoute: { [self] route in workspace.handle(route) },
            willHide: { [self] in await documents.flushAll() },
            handleClose: { [self] in workspace.handleClose() },
            menuItems: [
                // New Note (⌘N) is a menu item of the Notes section, window-only (spec "NotesPlugin").
                CommandInfo(
                    title: LocalizedStringResource("New Note", comment: "Notes menu: creates a note"),
                    shortcut: KeyShortcut(key: "n", modifiers: [.command]),
                    isEnabled: { [self] in workspace.canCreateNote },
                    run: { [self] in Task { await workspace.newNote() } }),
                // Go to Note… (⌘P) opens the command palette; Hide content (⌘⇧H) blurs the section for screen
                // sharing, for this session only (step 7.1).
                CommandInfo(
                    title: LocalizedStringResource("Go to Note…", comment: "Notes menu: opens the command palette"),
                    shortcut: NotesWorkspaceModel.paletteShortcut,
                    run: { [self] in workspace.togglePalette() }),
                CommandInfo(
                    title: LocalizedStringResource(
                        "Toggle Raw Markdown", comment: "Notes menu: switches the editor between Formatted and Raw"),
                    shortcut: NotesWorkspaceModel.editorModeShortcut,
                    isEnabled: { [self] in workspace.canSwitchEditorMode },
                    run: { [self] in workspace.toggleEditorMode() }),
                CommandInfo(
                    title: LocalizedStringResource(
                        "Hide content", comment: "Command palette and menu: blurs the notes for screen sharing"),
                    shortcut: NotesWorkspaceModel.hideContentShortcut,
                    run: { [self] in workspace.toggleHideContent() }),
                // "‹ All notes" (⌘[) of the full window; Esc does the same in the window (phase 3b).
                CommandInfo(
                    title: LocalizedStringResource(
                        "Back to All Notes", comment: "Notes menu: leaves the full window and shows the list"),
                    shortcut: NoteFullWindowBar.backShortcut,
                    isEnabled: { [self] in workspace.isFullWindow },
                    run: { [self] in workspace.closeFullWindow() }),
            ],
            // A note open in the full window fills the whole window: the shell leaves its sidebar out.
            hidesSidebar: { [self] in workspace.isFullWindow }
        )
    }

    /// The store, opened the first time something needs it (the listing, an open note, a sweep).
    var storeProvider: @MainActor @Sendable () -> NotesStore? {
        { [library] in
            library.open()
            return library.store
        }
    }

    /// Whether a library exists to read: the file is there or the store is open. A fresh profile has neither, so
    /// listing, reconciling and loading history or comments answer "nothing" without a Keychain lookup, a key or a
    /// database (the lazy-store rule, spec "Phasing"); only a write opens the library.
    var hasLibrary: @MainActor @Sendable () -> Bool {
        { [library] in library.store != nil || library.storeFileExists }
    }

    /// Whether the real store backs the section. Always, except in a DEBUG QA run that shows fixtures or the locked
    /// state without a QA note of Notes' own.
    private var usesRealStore: Bool {
        #if DEBUG
        let locked = qaState == "locked" || qaState == "locked-rows"
        let fixtures = context.settings.bool(NotesSettingsKey.qaFixtures, default: false)
        let qaManual =
            context.settings.string(NotesSettingsKey.qaManual) != nil
            || context.settings.string(NotesSettingsKey.qaHistory) != nil
            || context.settings.string(NotesSettingsKey.qaDelete) != nil
            || context.settings.string(NotesSettingsKey.qaComments) != nil
            || context.settings.string(NotesSettingsKey.qaMyNotes) != nil
        return !locked && (!fixtures || qaManual)
        #else
        return true
        #endif
    }

    /// One reconciler over an open store: the sweeps and the open note's reconcile share it.
    var makeReconciler: @MainActor @Sendable (NotesStore, NoteLibrary) -> SourceReconciler {
        { [clock = context.clock, trashChanges, documents] store, library in
            SourceReconciler(
                store: store, library: library, detacher: RegistryOverlayDetacher(store: store, registry: documents),
                registry: documents, clock: clock, trashChanged: { trashChanges.signal() })
        }
    }

    // MARK: Trash sweeps

    /// The sweeps live as long as the plugin is active (spec "Deletion lifecycle": Notes' trash sweep runs at
    /// activation), not as long as the section is on screen: the main window is built lazily, so without this a
    /// recording deleted in the launcher would stay unmarked, and its overlay would turn into a kept copy when its
    /// owner purges it. One task, started by `activate()`, ended by `deactivate()`.
    private var trashSweepTask: Task<Void, Never>?

    /// Called after every pass of the sweep task, whether or not a library existed (a test seam: it lets a test wait
    /// for a pass without polling).
    var trashSweepPassFinished: (@MainActor @Sendable () -> Void)?

    /// Called when the task's source-change listener has ended (a test seam, like `trashSweepPassFinished`).
    var trashSweepListenerEnded: (@MainActor @Sendable () -> Void)?

    /// Starts the one sweep task (a second activation replaces it). Nothing is read here: the task asks
    /// `hasLibrary()` first, on every pass, so a fresh profile creates no file and no Keychain item, and a
    /// library created later by a first write is swept from the next pass on.
    func startTrashSweeps() {
        trashSweepTask?.cancel()
        trashSweepTask = nil
        guard usesRealStore else { return }
        let hasLibrary = hasLibrary
        let storeProvider = storeProvider
        let makeReconciler = makeReconciler
        let sweepLibrary = NoteLibrary(
            sources: noteSourceProvider,
            overlays: LazyStoreOverlays(store: storeProvider, registry: documents, exists: hasLibrary),
            detacher: LazyStoreOverlays(store: storeProvider, registry: documents, exists: hasLibrary),
            clock: context.clock)
        let sourceSetChanges = context.noteSourcesChanged
        let clock = context.clock
        trashSweepTask = Task { @MainActor [weak self] in
            // A source's change (a trash, a restore, a purge in its own store, a plugin switched on or off) runs
            // the trash sweep at once, so a note deleted in the launcher's panel leaves Notes' search before the
            // next full sweep.
            let changes = Task { @MainActor [weak self] in
                defer { self?.trashSweepListenerEnded?() }
                for await _ in sweepLibrary.changes(sourceSetChanges: sourceSetChanges()) {
                    if Task.isCancelled { return }
                    guard hasLibrary(), let store = storeProvider() else { continue }
                    await makeReconciler(store, sweepLibrary).trashSweep()
                }
            }
            // The first sweep after activation never purges Recently deleted: the purge starts with the second,
            // 10 minutes later, after the trash sweep has marked the overlays.
            var first = true
            while !Task.isCancelled {
                if hasLibrary(), let store = storeProvider() {
                    // Notes activates before the plugins whose recordings it sweeps, and a change of the set may
                    // be signalled before the listener above subscribed: read the active sources again, so a
                    // set the library cached while those plugins were still off never outlives one pass.
                    await sweepLibrary.refreshSources()
                    await makeReconciler(store, sweepLibrary).sweep(purgesTrash: !first)
                    first = false
                }
                self?.trashSweepPassFinished?()
                do { try await clock.sleep(for: SourceReconciler.sweepInterval) } catch { break }
            }
            // The listener may be mid-sweep: end it and wait, so nothing writes after `deactivate()` closes the store.
            changes.cancel()
            await changes.value
        }
    }

    /// Ends the sweep task and waits for it, so no sweep touches the store that `deactivate()` closes.
    func stopTrashSweeps() async {
        guard let task = trashSweepTask else { return }
        trashSweepTask = nil
        task.cancel()
        await task.value
    }

    private func makeWorkspace() -> NotesWorkspaceModel {
        let context = context
        let provider = noteSourceProvider
        let registry = documents
        let storeProvider = storeProvider
        let hasLibrary = hasLibrary
        registry.cleanup = { open in
            guard await hasLibrary(), let store = await storeProvider() else { return }
            _ = try? store.deleteUnkeptDetached(excluding: open)
        }
        #if DEBUG
        // QA fixtures stand in for the sources and have no overlays, unless `qaManual` asks for notes of Notes' own
        // (they need the store); `locked` shows the locked state.
        let locked = qaState == "locked" || qaState == "locked-rows"
        let usesStore = usesRealStore
        let overlays: any OverlayIndex & OverlayDetacher
        if locked {
            overlays = NotesQALockedOverlays()
        } else if usesStore {
            overlays = LazyStoreOverlays(store: storeProvider, registry: registry, exists: hasLibrary)
        } else {
            overlays = NoOverlays()
        }
        #else
        let usesStore = true
        let overlays: any OverlayIndex & OverlayDetacher = LazyStoreOverlays(
            store: storeProvider, registry: registry, exists: hasLibrary)
        #endif
        let library = NoteLibrary(sources: provider, overlays: overlays, detacher: overlays)
        var environment = NotesWorkspaceModel.Environment(
            library: library, pasteboard: context.pasteboard, sourceSetChanges: context.noteSourcesChanged,
            openSettings: context.openSettings, openModels: { context.openModels(nil) })
        environment.settings = context.settings
        environment.availableCommands = context.availableCommands
        environment.dictationShortcut = { context.commandShortcut("dictation.record") }
        environment.liveRecorder = context.liveRecorder
        environment.preferences = preferences
        // A recorded note's title is renamed in its owner (`NoteSourceEditing`), never in `notes.sqlite`.
        environment.renameTitle = { key, title in
            guard let editing = await library.source(for: key) as? any NoteSourceEditing else { return false }
            do {
                try await editing.renameTitle(key, to: title)
                return true
            } catch {
                return false
            }
        }
        if usesStore && !NotesSettings(context.settings).readOnly {
            environment.installWriting(
                store: storeProvider, registry: registry, settings: context.settings, clock: context.clock,
                exists: hasLibrary)
        }
        if usesStore {
            environment.notesReadOnly = NotesSettings(context.settings).readOnly
            environment.registry = registry
            environment.installHistory(store: storeProvider, exists: hasLibrary)
            environment.installComments(store: storeProvider, exists: hasLibrary)
            if !NotesSettings(context.settings).readOnly {
                environment.installRevise(
                    service: reviseService, store: storeProvider, registry: registry, clock: context.clock)
            }
            // Delete (also with `plugins.notes.readOnly`: export, copy and delete keep working): the owner first,
            // the overlays only after it succeeded.
            environment.canDeleteNotes = true
            environment.deleteNote = { item in
                guard let store = storeProvider() else { throw NoteDeleter.Failure.sourceUnavailable }
                try await NoteDeleter(library: library, store: store, registry: registry).delete(item)
            }
            environment.overlayHeads = { item in
                guard await hasLibrary(), let store = await storeProvider() else { return [] }
                return (try? NoteOverlayContent.heads(for: item, in: store)) ?? []
            }
            let makeReconciler = makeReconciler
            environment.reconcile = { key in
                guard await hasLibrary(), let store = await storeProvider() else { return }
                await makeReconciler(store, library).reconcile(key)
            }
            // The sweeps themselves belong to the plugin (`startTrashSweeps`), not to this view: the section only
            // asks for a trash pass when it is shown.
            environment.requestTrashSweep = {
                guard await hasLibrary(), let store = await storeProvider() else { return }
                await makeReconciler(store, library).trashSweep()
            }
        }
        let model = NotesWorkspaceModel(environment: environment)
        builtWorkspace = model
        registry.onRekey = { [weak model] key, started in model?.rekeyDetached(key: key, startedAtMs: started) ?? false
        }
        registry.onDiscard = { [weak model] items in model?.documentsDiscarded(items) }
        #if DEBUG
        openQAFixtureNotes(in: model)
        applyQAState(to: model)
        if let raw = context.settings.string(NotesSettingsKey.qaSelect) {
            let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
            if let raw = parts.first, let id = NoteRoute.itemID(for: WorkspaceRoute(kind: NoteRoute.kind, id: raw)) {
                model.initialSelection = (id, parts.count == 2 ? PreviewTab(rawValue: parts[1]) : nil)
            }
        }
        #endif
        return model
    }

    #if DEBUG
    private var qaState: String { context.settings.string(NotesSettingsKey.qaState) ?? "" }

    /// `plugins.notes.qaState` and `plugins.notes.qaSearch`: whole-section states and a typed search for QA.
    private func applyQAState(to model: NotesWorkspaceModel) {
        switch qaState {
        case "loading": model.holdsLoading = true
        case "save-error": model.qaShow(.saveFailed)
        default: break
        }
        if let text = context.settings.string(NotesSettingsKey.qaSearch), !text.isEmpty { model.initialSearch = text }
        if context.settings.string(NotesSettingsKey.qaView) == "dictations" { model.prepareCollection(.dictations) }
        model.qaEditor = context.settings.string(NotesSettingsKey.qaEditor)
        model.editorMode = NoteEditorMode.qa(context.settings.string(NotesSettingsKey.qaEditorMode))
        if context.settings.bool(NotesSettingsKey.qaFixtures, default: false) { model.animationsDisabled = true }
        model.qaMixedAuthors = context.settings.string(NotesSettingsKey.qaAttribution) == "mixed"
        if let manual = context.settings.string(NotesSettingsKey.qaManual) { qaCreateManualNote(manual, in: model) }
        if let history = context.settings.string(NotesSettingsKey.qaHistory) { qaCreateHistory(history, in: model) }
        if let comments = context.settings.string(NotesSettingsKey.qaComments) {
            qaCreateComments(comments, in: model)
        }
        if let delete = context.settings.string(NotesSettingsKey.qaDelete) { qaRequestDelete(delete, in: model) }
        if context.settings.string(NotesSettingsKey.qaMyNotes) == "written" { qaWriteMyNotes(in: model) }
        if context.settings.string(NotesSettingsKey.qaHidden) == "on" { model.hidesContent = true }
        if let typed = context.settings.string(NotesSettingsKey.qaPalette) {
            Task { @MainActor in
                await model.refresh()
                model.showPalette()
                model.setPaletteQuery(typed == "open" ? "" : typed)
            }
        }
    }

    /// `plugins.notes.qaManual`: `new` makes a note with no title and opens it in the editor (what ⌘N does);
    /// `written` makes one with a title and some text and opens it for reading. The store is the QA one.
    private func qaCreateManualNote(_ mode: String, in model: NotesWorkspaceModel) {
        let storeProvider = storeProvider
        Task { @MainActor in
            guard let store = storeProvider() else { return }
            if mode == "written", let key = try? store.createManualNote(now: Date()) {
                try? store.setTitleOverride(key: key, title: "Release checklist", now: Date())
                let body =
                    "## Before Friday\n\n- Update the changelog\n- Ask Marek about the pricing copy\n\nShip it when both are done."
                if let docID = try? store.liveDocument(key: key, layer: NotesStore.manualLayer)?.id {
                    let blocks = BlockAttribution().stored(body: body, author: "human", previous: [])
                    _ = try? store.appendRevision(
                        NewNoteRevision(
                            docID: docID, author: "human", state: .applied, body: body, blocksJSON: blocks.json,
                            now: Date(), expectedHeadID: (try? store.headRevision(of: docID))?.id))
                }
                await model.refresh()
                model.handle(NoteRoute.route(for: key))
            } else if mode == "new" {
                await model.refresh()
                await model.newNote()
            }
        }
    }

    /// `plugins.notes.qaMyNotes=written`: types some text into the first My notes pad that appears (the preview's
    /// or the full window's) and writes it, the way the user would: the real writer seeds the `mine` document.
    private func qaWriteMyNotes(in model: NotesWorkspaceModel) {
        Task { @MainActor in
            for _ in 0..<50 {
                if let pad = (model.currentDocument ?? model.previewDocument)?.myNotes, pad.isEditable {
                    let text = "Ask Ola for the budget numbers before Friday.\n\n- Send Marek the export deck"
                    pad.edit(
                        NoteEditorEdit(text: text, range: 0..<text.utf16.count, changeInLength: text.utf16.count))
                    await pad.flush()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// `plugins.notes.qaOpen`: opens the named notes in the full window, one after another (the last one stays).
    private func openQAFixtureNotes(in model: NotesWorkspaceModel) {
        let list = context.settings.string(NotesSettingsKey.qaOpen) ?? ""
        for entry in list.split(separator: ",") {
            let parts = entry.split(separator: "@", maxSplits: 1).map(String.init)
            guard let raw = parts.first else { continue }
            let route = WorkspaceRoute(kind: NoteRoute.kind, id: raw)
            guard model.handle(route), let id = NoteRoute.itemID(for: route) else { continue }
            // `@mine` opens the full window on My notes (it is not a layer of the source).
            if parts.count == 2, parts[1] == NotesStore.mineLayer, let document = model.documents[id] {
                document.showsMine = true
            } else if parts.count == 2 {
                model.preferredLayers[id] = parts[1]
            }
        }
    }
    #endif

    /// The sources the library reads: the active plugins' (`PluginContext.noteSources`); with `--qa-notes` the
    /// fixture sources come first, so they win over a real plugin of the same id.
    var noteSourceProvider: @MainActor @Sendable () -> [any NoteSource] {
        let real = context.noteSources
        #if DEBUG
        if context.settings.bool(NotesSettingsKey.qaFixtures, default: false) {
            switch qaState {
            case "off", "locked":
                return { [] }
            default:
                let fixtures = NotesQAFixtureSource.all(empty: qaState == "empty")
                return { fixtures + real() }
            }
        }
        #endif
        return real
    }
}
