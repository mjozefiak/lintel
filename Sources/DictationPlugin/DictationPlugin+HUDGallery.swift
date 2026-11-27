#if DEBUG
import LintelKit
import LintelSpeech
import LintelUI
import SwiftUI

/// DEBUG only: the owner sheet of the minimal HUD's Phase 2 (spec `2026-11-25-minimal-hud`): the real `LintelPill`
/// drawn from the real `HUDState.pill(…)` mapping, over invented data (a fixed running time, a made-up microphone
/// name). Nothing starts: no microphone, no model, no panel. A partial cleanup (`pastedUnformatted(all: false)`)
/// shows nothing (OD-4), so it has no picture; the picture of `loading-model` is the one of `recording` and the scene
/// proves it by drawing both from their own state.
@MainActor enum HUDPillGallery {
    static var scene: GalleryScene {
        GalleryScene(id: "dictation.hud-pills", title: "Dictation HUD pills (minimal HUD, Phase 2)", states: states)
    }

    /// A made-up running time and the microphone of the fixtures.
    private static let elapsed = 12
    private static let usb = InputFallback(requestedName: "USB Microphone", usingName: "MacBook Pro Microphone")

    private enum Look {
        case plain
        case reduced
        case contrast
    }

    private static func state(
        _ id: String, _ summary: String, _ hud: HUDState, expanded: Bool = false, lineCollapsed: Bool = false,
        look: Look = .plain
    ) -> GalleryState {
        GalleryState(id: id, summary: summary, presentation: .hud(shape: .capsule), includesLargeInSheet: true) {
            guard let content = hud.pill(elapsed: elapsed, microphoneLineVisible: !lineCollapsed) else {
                return AnyView(EmptyView())
            }
            let pill = LintelPill(content, expanded: expanded)
            switch look {
            case .plain: return AnyView(pill.environment(\.lintelRingMotion, .frozen))
            case .reduced: return AnyView(pill.environment(\.lintelRingMotion, .reduced))
            case .contrast:
                return AnyView(
                    pill.environment(\.lintelRingMotion, .frozen).environment(\.lintelIncreasedContrast, true))
            }
        }
    }

    private static func recording(
        level: Float = 0.65, loadingModel: Bool = false, secondsLeft: Int? = nil, escapeCancels: Bool = true,
        fallback: InputFallback? = nil
    ) -> HUDState {
        .recording(
            .init(
                level: level, loadingModel: loadingModel, secondsLeft: secondsLeft, escapeCancels: escapeCancels,
                fallback: fallback))
    }

    static var states: [GalleryState] {
        [
            state(
                "recording",
                "Recording: the turning ring (no dot) and the voice wave, nothing else. The time and the ✕ are on hover (OD-2); Esc cancels.",
                recording()),
            state(
                "recording-hover",
                "Recording, hovered: the running time and the ✕ appear; the wave stays.", recording(), expanded: true),
            state(
                "recording-loading-model",
                "Recording while the speech model loads: the same pill as recording, on hover too (OD-7, Q3 (a)).",
                recording(loadingModel: true)),
            state(
                "recording-escape-unclaimed",
                "Esc could not be claimed: the ✕ is always visible.", recording(escapeCancels: false)),
            state(
                "recording-countdown",
                "About to stop: the wave plus the amber seconds left. Not a problem line, never collapses.",
                recording(level: 0.4, secondsLeft: 9)),
            state(
                "recording-microphone-fallback",
                "The chosen microphone is missing (OD-11): the ring with the amber dot, the wave and the name of the input used for 3 s.",
                recording(fallback: usb)),
            state(
                "recording-microphone-fallback-unnamed",
                "Same, when the default input has no name: “Using the default mic”.",
                recording(fallback: InputFallback(requestedName: "USB Microphone", usingName: nil))),
            state(
                "recording-microphone-fallback-long-name",
                "A long input name is shortened in the middle; the full name is in VoiceOver.",
                recording(
                    fallback: InputFallback(
                        requestedName: "USB Microphone", usingName: "Logitech BRIO Webcam Microphone Array"))),
            state(
                "recording-microphone-fallback-collapsed",
                "After the 3 s: the collapsed pill keeps the amber dot on the ring.",
                recording(fallback: usb), lineCollapsed: true),
            state(
                "recording-microphone-fallback-hover",
                "The collapsed pill, hovered: the line comes back next to the time.",
                recording(fallback: usb), expanded: true, lineCollapsed: true),
            state("finishing", "Finishing: only the closing ring, a circle.", .finishing),
            state("pasted", "Pasted: a ✓ for 0.6 s, then gone (OD-3).", .pasted),
            state(
                "pasted-unformatted",
                "The whole text is raw because cleanup failed: one line, 3 s, no hint (OD-4).",
                .pastedUnformatted(all: true)),
            state("copied", "Copied but not pasted: one line, 3 s.", .copied(.targetGone)),
            state(
                "copied-no-accessibility",
                "Copied because Accessibility is missing: the same line with Allow, which opens the Accessibility pane.",
                .copied(.noAccessibility)),
            state(
                "allow-microphone", "The system's microphone prompt is on screen.", .allowMicrophone),
            state("model-missing", "No speech model installed: red triangle, Download.", .problem(.modelMissing)),
            state(
                "model-unavailable", "The model's folder is gone or it failed to load: red triangle, Fix.",
                .problem(.modelUnavailable)),
            state(
                "speech-model-busy", "A meeting holds a different speech model.", .problem(.speechModelBusy)),
            state(
                "microphone-denied", "Microphone access denied: Allow.", .problem(.microphoneDenied)),
            state("no-microphone", "No input device.", .problem(.noMicrophone)),
            state("nothing-heard", "The recording had no speech.", .problem(.nothingHeard)),
            state("nothing-to-paste", "Paste the raw version with no earlier dictation.", .problem(.nothingToPaste)),
            state(
                "reduced-motion-recording",
                "Reduce Motion, recording: the ring does not turn and the wave stays flat at the current level.",
                recording(), look: .reduced),
            state(
                "reduced-motion-finishing",
                "Reduce Motion, finishing: the static part ring with its track, no spinner.", .finishing,
                look: .reduced),
            state(
                "increased-contrast-recording", "Increase Contrast: the 1 pt border around the pill.", recording(),
                look: .contrast),
            state(
                "increased-contrast-message", "Increase Contrast on a line with a button.",
                .copied(.noAccessibility), look: .contrast),
        ]
    }
}
#endif
