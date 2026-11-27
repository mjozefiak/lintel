#if DEBUG
import LintelKit
import LintelProviders
import LintelSpeech
import LintelUI
import SwiftUI

/// DEBUG only: the design gallery scenes of `MeetingsPlugin` (spec `2026-11-23-swiftui-design-gallery`, pilot: Settings →
/// Meetings → "Notes are written by"). The scenes draw the real views (`NotesWrittenBySections`, `ChoiceMenuList`) over
/// the real models, with a fake notes service, fake probes and an in-memory settings store: nothing starts a process,
/// reaches the Keychain, a model, the network or a file outside a temporary folder. The data is invented.
extension MeetingsPlugin: GalleryProviding {
    public static var galleryScenes: [GalleryScene] { [NotesProviderGallery.scene] }
}

/// What one state of the pilot scene needs.
@MainActor struct NotesProviderGalleryCase {
    /// The chosen provider and model; `nil` is Local.
    var provider: (id: ProviderID, model: String)?
    var notesEnabled = true
    /// The place of the built-in notes model; `installed` keeps the older states as they were.
    var notesModel = NotesDownloadQAState.installed
    /// What the fake probe finds; `nil` is a probe that never answers ("Checking…").
    var probe: ProviderStatusReport? = ProviderStatusReport(status: .ready, version: "2.1.329")
    var failure: ProviderJobFailure.Reason?
    var jobRunning = false
    var confirmUseLocal = false
    var detailsExpanded = false
    var earlierMark = false
    var manualBinary: String?
    /// What "Test" finds, started when the state is made; `nil` leaves the row alone.
    var tryOut: NotesProviderGalleryTryOut?
}

enum NotesProviderGalleryTryOut {
    case running
    case worked
    case failed
}

/// The fake models of one state, built the way the plugin builds them in `MeetingsUI`, over fakes.
@MainActor struct NotesProviderGalleryRig {
    let provider: ProviderChoiceModel
    let notes: NotesSettingsModel
    let control: GalleryNotesControl
    let settings: MeetingsSettings

    /// A fixed moment, so no text carries "2 min ago" or today's date.
    static let now = Date(timeIntervalSince1970: 1_730_635_200)
    /// Fixed, so the built-in models on offer do not depend on the Mac the gallery runs on.
    static let physicalMemory: UInt64 = 32 * 1_024 * 1_024 * 1_024
    static let meetingTitle = "Orchard weekly sync"

    init(_ scenario: NotesProviderGalleryCase) {
        let store = GallerySettingsStore()
        let settings = MeetingsSettings(
            PluginSettings(pluginID: MeetingsPlugin.manifest.id, store: store), physicalMemory: Self.physicalMemory)
        settings.setNotesEnabled(scenario.notesEnabled)
        if let chosen = scenario.provider {
            settings.setNotesProvider(NotesProviderSelection(provider: chosen.id, model: chosen.model))
        }
        settings.setNotesProviderBinary(scenario.manualBinary)
        let failure = scenario.failure.map {
            ProviderJobFailure(
                reason: $0, meetingID: 1, title: Self.meetingTitle,
                startedAt: Date(timeIntervalSince1970: 1_730_635_200))
        }
        let control = GalleryNotesControl(jobRunning: scenario.jobRunning || scenario.confirmUseLocal, failure: failure)
        let probe = scenario.probe
        let tryOut = scenario.tryOut
        let provider = ProviderChoiceModel(
            settings: settings, service: control,
            probe: { _ in
                if let probe { return probe }
                // "Checking…" stays: a probe that does not come back during the render.
                try? await Task.sleep(for: .seconds(600))
                return ProviderStatusReport(status: .notInstalled, version: nil)
            },
            tryOut: { _, _ in
                switch tryOut {
                case .worked: return .worked
                case .failed: return .failed(.network)
                case .running, nil:
                    try? await Task.sleep(for: .seconds(600))
                    return .unavailable
                }
            },
            openURL: { _ in }, copyText: { _ in }, chooseFile: { nil }, changed: {},
            now: { Self.now },
            lastMarked: {
                scenario.earlierMark
                    ? ProviderChoiceModel.EarlierMark(
                        title: Self.meetingTitle, chip: "Sent to: Claude · Sonnet", provider: "Claude Code") : nil
            })
        let notes = NotesSettingsModel(
            settings: settings, service: control,
            manager: ModelManager(
                directory: FileManager.default.temporaryDirectory.appending(
                    path: "lintel-gallery-models", directoryHint: .isDirectory),
                downloader: GalleryDownloader()))
        self.settings = settings
        self.control = control
        self.provider = provider
        self.notes = notes
        notes.showQAState(scenario.notesModel)
        // What the pane's `.task` does when it appears (`MeetingsSettingsModel.refresh`).
        provider.reload()
        if scenario.confirmUseLocal { provider.useLocal() }
        provider.detailsExpanded = scenario.detailsExpanded
        provider.refreshStatus()
        if scenario.tryOut != nil { provider.testProvider() }
    }
}

/// A downloader that is never asked: a scene downloads nothing.
private struct GalleryDownloader: FileDownloading {
    func download(_ url: URL, to file: URL, progress: @escaping @Sendable (Int) -> Void) async throws {
        throw URLError(.notConnectedToInternet)
    }
}

/// The pane the pilot draws: the "Notes are written by" sections on the settings template, like in Settings → Meetings.
private struct NotesProviderGalleryPane: View {
    let rig: NotesProviderGalleryRig

    var body: some View {
        SettingsPane {
            NotesWrittenBySections(provider: rig.provider, notes: rig.notes)
        }
    }
}

@MainActor enum NotesProviderGallery {
    static let paneWidth = SettingsLayout.mainColumnWidth
    static let claude = ProviderID.claudeCode
    private static let window = GalleryPresentation.window(width: paneWidth)

    static var scene: GalleryScene {
        GalleryScene(id: "meetings.notes-provider", title: "Settings → Meetings → Notes are written by", states: states)
    }

    private static func pane(
        _ id: String, _ summary: String, _ scenario: NotesProviderGalleryCase
    ) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(NotesProviderGalleryPane(rig: NotesProviderGalleryRig(scenario)))
        }
    }

    private static func chosen(_ model: String = "sonnet") -> (id: ProviderID, model: String) { (claude, model) }

    private static func failed(
        _ id: String, _ reason: ProviderJobFailure.Reason, _ what: String
    ) -> GalleryState {
        pane(
            "failed-\(id)",
            "Claude Code is chosen and the last job failed: \(what). \(Self.failedNote)",
            NotesProviderGalleryCase(provider: chosen(), failure: reason))
    }

    private static func menu(
        _ id: String, _ summary: String, _ scenario: NotesProviderGalleryCase,
        content: @escaping @MainActor @Sendable (NotesProviderGalleryRig) -> AnyView
    ) -> GalleryState {
        GalleryState(
            id: id, summary: summary, presentation: .popover(width: 270)
        ) {
            content(NotesProviderGalleryRig(scenario))
        }
    }

    /// The six failed-* states: the pane shows the Failed · Last meeting row, but the reason itself is only in the host's
    /// banner (issue #280), so they draw the same picture until its scenes exist (`GalleryScenesTests` lists them).
    private static let failedNote =
        "The pane shows the Failed · Last meeting row; the reason is only in the host's banner (issue #280), so the six failed-* states draw one picture."

    /// `job-running`: its difference is the host's banner (`StatusBanner`, issue #280), so until its scenes exist the
    /// pane looks as in `ready-sonnet`.
    private static let bannerOnly =
        "The pane looks as in ready-sonnet; the host's banner (issue #280) shows the difference."

    static var states: [GalleryState] {
        [
            pane(
                "local", "Local is chosen and notes are on: the two menus, nothing leaves the Mac.",
                NotesProviderGalleryCase()),
            pane(
                "local-model-missing",
                "Local is chosen, notes are on and the notes model is not on this Mac: the Model row says \"not installed\" with Get it in Models (#298).",
                NotesProviderGalleryCase(notesModel: .missing)),
            pane(
                "local-model-downloading",
                "Local is chosen and the notes model is downloading: the Model row says \"downloading\" with Manage in Models.",
                NotesProviderGalleryCase(notesModel: .downloading)),
            pane(
                "local-notes-off",
                "Local is chosen and notes are off: the section is hidden (nothing to show).",
                NotesProviderGalleryCase(notesEnabled: false)),
            pane(
                "ready-sonnet",
                "Claude Code with Sonnet is chosen, found and signed in: the notice with Details closed.",
                NotesProviderGalleryCase(provider: chosen("sonnet"))),
            pane(
                "ready-opus", "Claude Code with Opus is chosen: the note that the model uses more of the limit.",
                NotesProviderGalleryCase(provider: chosen("opus"))),
            pane(
                "not-installed", "Claude Code is chosen but not found.",
                NotesProviderGalleryCase(
                    provider: chosen(), probe: ProviderStatusReport(status: .notInstalled, version: nil))),
            pane(
                "not-signed-in", "Claude Code is found but not signed in: the sign-in command and Copy Command.",
                NotesProviderGalleryCase(
                    provider: chosen(), probe: ProviderStatusReport(status: .notSignedIn, version: nil))),
            pane(
                "incompatible-version", "Claude Code is older than this Lintel supports.",
                NotesProviderGalleryCase(
                    provider: chosen(), probe: ProviderStatusReport(status: .incompatibleVersion, version: nil))),
            pane(
                "newer-version",
                "Claude Code is newer than this Lintel supports. The status row reads as in incompatible-version; the banner (#280) tells them apart.",
                NotesProviderGalleryCase(
                    provider: chosen(), probe: ProviderStatusReport(status: .newerVersion, version: nil))),
            pane(
                "checking", "The status of Claude Code is being checked.",
                NotesProviderGalleryCase(provider: chosen(), probe: nil)),
            pane(
                "job-running",
                "A provider job is running: Use Local is the banner's action. \(Self.bannerOnly)",
                NotesProviderGalleryCase(provider: chosen(), jobRunning: true)),
            pane(
                "confirm-use-local", "Use Local was pressed while a job runs: the question, asked once.",
                NotesProviderGalleryCase(provider: chosen(), confirmUseLocal: true)),
            pane(
                "details-expanded", "The notice's Details are open: what leaves the Mac, when, and what to know.",
                NotesProviderGalleryCase(provider: chosen(), detailsExpanded: true)),
            pane(
                "earlier-mark", "After Use Local: notes a provider wrote earlier stay, with their mark.",
                NotesProviderGalleryCase(earlierMark: true)),
            failed("timed-out", .timedOut, "it took too long"),
            failed("network", .network, "no network"),
            failed("rate-limited", .rateLimited, "the plan's limit was reached"),
            failed("other", .other, "an unknown error"),
            failed("too-long", .tooLong, "the meeting is too long for the model"),
            failed("model-not-available", .modelNotAvailable, "the plan does not include the model"),
            pane(
                "manual-binary", "Claude Code was picked by hand: the file row with Restore Default.",
                NotesProviderGalleryCase(provider: chosen(), manualBinary: "/opt/lintel-qa/bin/claude")),
            pane(
                "try-running", "Test is running.", NotesProviderGalleryCase(provider: chosen(), tryOut: .running)),
            pane(
                "try-worked", "Test worked: \"It worked.\"",
                NotesProviderGalleryCase(provider: chosen(), tryOut: .worked)),
            pane(
                "try-failed", "Test failed: \"It didn’t work.\"",
                NotesProviderGalleryCase(provider: chosen(), tryOut: .failed)),
            menu(
                "provider-menu", "The provider menu: Local first, then the tools on a subscription.",
                NotesProviderGalleryCase()
            ) {
                rig in
                AnyView(
                    ChoiceMenuList(
                        groups: NotesWrittenByMenus.providerGroups(rig.provider), selection: "local",
                        footer: NotesWrittenByMenus.providerFooter, onSelect: { _ in }))
            },
            menu("model-menu", "The model menu of Claude Code.", NotesProviderGalleryCase(provider: chosen())) { rig in
                AnyView(
                    ChoiceMenuList(
                        groups: NotesWrittenByMenus.modelGroups(provider: rig.provider, notes: rig.notes),
                        selection: "sonnet", footer: nil, onSelect: { _ in }))
            },
        ]
    }
}
#endif
