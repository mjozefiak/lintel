#if DEBUG
import LintelKit
import LintelUI
import SwiftUI

/// DEBUG only: the design gallery scenes of `DictationPlugin` (spec `2026-11-25-dictation-cleanup-levels`, Phase 1). The
/// scene draws the real `TidyUpRow` (the popup, the help line and the example of the chosen value) on the settings
/// template, over a fixed choice. Nothing starts: no server probe, no model, no file. The sentences are invented.
extension DictationPlugin: GalleryProviding {
    public static var galleryScenes: [GalleryScene] { [TidyUpGallery.scene] }
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
#endif
