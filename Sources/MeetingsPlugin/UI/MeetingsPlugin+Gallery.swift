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
    public static var galleryScenes: [GalleryScene] {
        [NotesProviderGallery.scene, SpeakersListGallery.scene, SpeakerNamesSettingsGallery.scene]
    }
}

/// What one state of the pilot scene needs.
@MainActor struct NotesProviderGalleryCase {
    /// The chosen provider and model; `nil` is Local.
    var provider: (id: ProviderID, model: String)?
    var notesEnabled = true
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

// MARK: - Speaker names (spec `2026-11-25-meeting-speaker-names`, step 1.6)

/// The "Speakers" list of the meeting window in each state of the spec's UI/UX: the real `MeetingSpeakersList` over
/// a value, as `MeetingWindowModel.speakerList` builds it. Fictional names only.
@MainActor enum SpeakersListGallery {
    static let width: CGFloat = 420
    private static let window = GalleryPresentation.window(width: width)

    static var scene: GalleryScene {
        GalleryScene(id: "meetings.speakers", title: "Meeting window → Speakers", states: states)
    }

    private static func row(
        _ id: Int64, _ name: String, isSelf: Bool = false, origin: String? = nil,
        suggestion: MeetingSpeakersList.Suggestion? = nil
    ) -> MeetingSpeakersList.Row {
        MeetingSpeakersList.Row(
            id: id, name: name, badge: MeetingWindowModel.badge(for: name), isSelf: isSelf, canMarkSelf: !isSelf,
            origin: origin, suggestion: suggestion)
    }

    private static let anna = row(1, "Anna Kowalska", isSelf: true)
    private static let bartek = row(2, "Bartek Nowak", origin: "Introduced themselves at 02:50")
    private static let marek = MeetingSpeakersList.Suggestion(name: "Marek", heardAt: "03:12", segmentID: 7)

    private static func list(_ id: String, _ summary: String, _ state: MeetingSpeakersList.State) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(
                MeetingSpeakersList(state: state, actions: MeetingSpeakersList.Actions())
                    .padding(16))
        }
    }

    static var states: [GalleryState] {
        [
            list(
                "no-names", "No names yet: the user's own speaker and the default labels, as today.",
                .init(rows: [row(1, "Ja", isSelf: true), row(2, "Mówca 1"), row(3, "Mówca 2"), row(4, "Mówca 3")])),
            list(
                "all-named", "Every speaker has a name; an automatic one has no mark, only a tooltip.",
                .init(rows: [anna, bartek, row(3, "Marek Wiśniewski"), row(4, "Ola Zielińska")])),
            list(
                "mixed-suggestion",
                "Names and one suggestion: \"Marek?\" with the time it was heard, Yes and No (the mockup).",
                .init(rows: [anna, bartek, row(3, "Mówca 2", suggestion: marek), row(4, "Mówca 3")])),
            list(
                "conflict",
                "Two speakers may be Marek: neither gets the name, both show the suggestion.",
                .init(rows: [
                    anna, row(2, "Mówca 1", suggestion: .init(name: "Marek", heardAt: "01:05", segmentID: 3)),
                    row(3, "Mówca 2", suggestion: marek),
                ])),
            list(
                "editing", "A click on a name: the field, Return saves, Escape cancels.",
                .init(
                    rows: [anna, bartek, row(3, "Mówca 2", suggestion: marek), row(4, "Mówca 3")],
                    edit: .init(speakerID: 4, draft: "Ola"))),
            list(
                "merge-offer",
                "A name another speaker has: one line asking to merge, with Merge, Keep Separate and Cancel.",
                .init(
                    rows: [anna, bartek, row(3, "Mówca 2"), row(4, "Mówca 3")],
                    mergeOffer: .init(speakerID: 4, targetID: 2, name: "Bartek Nowak", origin: .rename))),
        ]
    }
}

/// Settings → Meetings → Speaker names: "Your name" and "From the conversation", with notes on and off.
@MainActor @Observable final class GallerySpeakerNames: SpeakerNamesSettings {
    var selfName = "Anna Kowalska"
    var selfNameError: MeetingsSettings.SelfNameError?
    var suggestedSelfName: String?
    var namesFromConversation = true
    var notesEnabledForNames: Bool

    init(notesEnabled: Bool) { notesEnabledForNames = notesEnabled }

    func saveSelfName(_ text: String) -> Bool {
        selfName = text
        return true
    }
}

@MainActor enum SpeakerNamesSettingsGallery {
    private static let window = GalleryPresentation.window(width: SettingsLayout.mainColumnWidth)

    static var scene: GalleryScene {
        GalleryScene(id: "meetings.speaker-names", title: "Settings → Meetings → Speaker names", states: states)
    }

    private static func pane(_ id: String, _ summary: String, notesEnabled: Bool) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(SettingsPane { SpeakerNamesSection(model: GallerySpeakerNames(notesEnabled: notesEnabled)) })
        }
    }

    static var states: [GalleryState] {
        [
            pane("notes-on", "Notes are on: From the conversation is on, with its help line.", notesEnabled: true),
            pane(
                "notes-off", "Notes are off: the switch is inactive with one line saying it needs notes.",
                notesEnabled: false),
        ]
    }
}
#endif
