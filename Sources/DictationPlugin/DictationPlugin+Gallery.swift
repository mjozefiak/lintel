#if DEBUG
import LintelKit
import LintelProviders
import LintelSpeech
import LintelUI
import SwiftUI

/// DEBUG only: the design gallery scenes of `DictationPlugin` (spec `2026-11-25-dictation-cleanup-levels`, Phase 1). The
/// scene draws the real `TidyUpRow` (the popup, the help line and the example of the chosen value) on the settings
/// template, over a fixed choice. Nothing starts: no server probe, no model, no file. The sentences are invented.
extension DictationPlugin: GalleryProviding {
    public static var galleryScenes: [GalleryScene] { [TidyUpGallery.scene, TidySourceGallery.scene] }
}

/// The pane a state draws: only the row of "Tidy up my text", like in Settings → Dictation → Basics.
private struct TidyUpGalleryPane: View {
    @State var choice: FormattingSettingsModel.TidyChoice
    /// The line "Works best with the Recommended assistant." (Full on the smallest built-in model).
    var showsSmallModelHint = false
    /// The host dims the pane of a plugin that is off and makes it inactive (`SettingsHost.bodyOpacity`).
    var dimmed = false

    var body: some View {
        SettingsPane {
            Section {
                TidyUpRow(choice: $choice, showsSmallModelHint: showsSmallModelHint)
            }
        }
        .opacity(dimmed ? 0.5 : 1)
        .disabled(dimmed)
    }
}

@MainActor enum TidyUpGallery {
    private static let window = GalleryPresentation.window(width: SettingsLayout.mainColumnWidth)

    static var scene: GalleryScene {
        GalleryScene(id: "dictation.tidy-up", title: "Settings → Dictation → Tidy up my text", states: states)
    }

    private static func state(
        _ id: String, _ summary: String, _ choice: FormattingSettingsModel.TidyChoice, dimmed: Bool = false,
        smallModelHint: Bool = false
    ) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(TidyUpGalleryPane(choice: choice, showsSmallModelHint: smallModelHint, dimmed: dimmed))
        }
    }

    static var states: [GalleryState] {
        [
            state("off", "Off: the text is pasted as spoken; the help line and no example.", .off),
            state(
                "light", "Light: removes “um” and “uh”, never changes a word; the example shows a filler going.",
                .light),
            state(
                "standard",
                "Standard: also keeps only the corrections and makes lists; the example shows a correction.",
                .standard),
            state(
                "full",
                "Full: also lays out emails and long texts and smooths the style; the example shows a message in paragraphs.",
                .full),
            state(
                "full-small-model",
                "Full on the smallest built-in model: the extra line “Works best with the Recommended assistant.”.",
                .full, smallModelHint: true),
            state(
                "standard-dimmed",
                "Dictation is off: the row dimmed and inactive, as every row of a plugin that is switched off.",
                .standard, dimmed: true),
        ]
    }
}

/// The pane a source state draws: the two rows of "Tidy up my text" and "Tidy up with" and, with Claude chosen, what
/// belongs to it. The model is built over an in-memory store with no probe: the state is set by hand.
private struct TidySourceGalleryPane: View {
    @State var formatting: FormattingSettingsModel
    var offered: Set<DictationSettings.CleanupLevel> = ProviderLevels.offered

    var body: some View {
        SettingsPane {
            Section {
                TidyUpRow(choice: $formatting.choice, showsSmallModelHint: false)
                TidySourceRows(formatting: formatting, offered: offered)
            }
        }
    }
}

/// Spec `2026-11-25-dictation-cleanup-levels`, Phase 5: Settings → Dictation → "Tidy up with" for every source at the
/// levels that use a model, the provider's states (ready, signed out, not installed, checking), the heavier model's note,
/// and the line that says what runs instead when a level is not served by the provider.
@MainActor enum TidySourceGallery {
    private static let window = GalleryPresentation.window(width: SettingsLayout.mainColumnWidth)

    static var scene: GalleryScene {
        GalleryScene(
            id: "dictation.tidy-source", title: "Settings → Dictation → Tidy up with", states: states)
    }

    private static func model(
        level: String, source: String, providerModel: String? = nil, server: Bool = false,
        check: FormattingSettingsModel.ProviderCheck, builtInInstalled: Bool = true
    ) -> FormattingSettingsModel {
        var values: [String: SettingValue] = [
            "plugins.dictation.mode": .string("cleanup"), "plugins.dictation.cleanupLevel": .string(level),
            "plugins.dictation.llmSource": .string(source),
        ]
        if source == "provider" {
            values["plugins.dictation.provider"] = .string("claude-code")
            values["plugins.dictation.providerModel"] = .string(providerModel ?? "sonnet")
        }
        if server {
            values["plugins.dictation.llmEndpoint"] = .string("http://127.0.0.1:11434")
            values["plugins.dictation.llmModel"] = .string("qwen")
        }
        let settings = DictationSettings(
            PluginSettings(pluginID: DictationPlugin.manifest.id, store: GallerySettingsStore(values)),
            offersFull: true)
        let model = FormattingSettingsModel(
            settings: settings, transport: GalleryTransport(),
            llmModels: ModelManager(
                directory: FileManager.default.temporaryDirectory.appending(
                    path: "lintel-gallery-dictation-models", directoryHint: .isDirectory)),
            providerStatus: { _ in ProviderStatusReport(status: .ready, version: nil) })
        model.galleryShow(
            providerCheck: check, version: check == .known(.ready) ? "2.1.329" : nil,
            builtInInstalled: builtInInstalled)
        return model
    }

    private static func state(
        _ id: String, _ summary: String, offered: Set<DictationSettings.CleanupLevel> = ProviderLevels.offered,
        _ make: @escaping @MainActor () -> FormattingSettingsModel
    ) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: window) {
            AnyView(TidySourceGalleryPane(formatting: make(), offered: offered))
        }
    }

    static var states: [GalleryState] {
        [
            state(
                "this-mac-standard",
                "This Mac at Standard, Claude ready: the menu lists This Mac, My server and Claude."
            ) { model(level: "standard", source: "builtIn", check: .known(.ready)) },
            state(
                "my-server-no-provider",
                "My server at Standard, no provider ready: the menu has “Add a provider…” disabled and no Claude."
            ) { model(level: "standard", source: "server", server: true, check: .known(.notInstalled)) },
            state(
                "claude-standard",
                "Claude at Standard: the model menu, the fixed sentence about what is sent, the status line."
            ) { model(level: "standard", source: "provider", check: .known(.ready)) },
            state(
                "claude-full", "Claude at Full: the same rows; Full is offered on Claude."
            ) { model(level: "full", source: "provider", check: .known(.ready)) },
            state(
                "claude-heavier-model",
                "Claude with Opus: the note that the model is slower and uses more of the plan."
            ) { model(level: "standard", source: "provider", providerModel: "opus", check: .known(.ready)) },
            state(
                "claude-signed-out",
                "Claude chosen but signed out: the status line says how to sign in, with Check Again."
            ) { model(level: "standard", source: "provider", check: .known(.notSignedIn)) },
            state(
                "claude-not-installed", "Claude chosen but not installed: the status line, with Check Again."
            ) { model(level: "standard", source: "provider", check: .known(.notInstalled)) },
            state(
                "claude-checking",
                "Claude chosen while the check runs: a small progress indicator in place of the button."
            ) { model(level: "standard", source: "provider", check: .checking) },
            state(
                "claude-full-falls-back-to-this-mac",
                "If Claude did not serve Full: the line says Full runs on this Mac (the mechanism, not today's constant).",
                offered: [.standard]
            ) { model(level: "full", source: "provider", check: .known(.ready), builtInInstalled: true) },
            state(
                "claude-full-falls-back-to-nothing",
                "If Claude did not serve Full and nothing local is set up: the line says the text is pasted untidied.",
                offered: [.standard]
            ) { model(level: "full", source: "provider", check: .known(.ready), builtInInstalled: false) },
        ]
    }
}

/// The gallery never reaches a server: an answer that nothing asks for.
private struct GalleryTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { throw TransportError.notLoopback }
}
#endif
