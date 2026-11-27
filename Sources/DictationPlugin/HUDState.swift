import Foundation
import LintelSpeech
import LintelUI

/// What the dictation HUD shows (spec: UI/UX → HUD). Pure data, so every state, its texts and its
/// accessibility announcements are testable without a window. `pill(…)` maps a state to the `LintelPill` content
/// (spec `2026-11-25-minimal-hud`, "Dictation states"); the cases stay as they were, so the controller, the QA
/// fixtures and the tests keep their names.
enum HUDState: Equatable, Sendable {
    /// The microphone prompt is on screen.
    case allowMicrophone
    case recording(Recording)
    /// Recording ended; the text is being produced.
    case finishing
    case pasted
    /// Pasted, but some or all of the text is the raw transcript because formatting failed.
    case pastedUnformatted(all: Bool)
    case copied(TextPaster.CopyReason)
    case problem(Problem)

    struct Recording: Equatable, Sendable {
        /// 0...1 loudness.
        var level: Float = 0
        /// The model is still loading; recording already runs.
        var loadingModel = false
        /// Seconds until the recording stops by itself, once the countdown has started.
        var secondsLeft: Int?
        /// Whether Esc cancels; otherwise only the ✕ does.
        var escapeCancels = true
        /// The chosen microphone is unplugged and the system's input is used; the HUD says so.
        var fallback: InputFallback?
    }

    enum Problem: Equatable, Sendable {
        case modelMissing
        case modelUnavailable
        case modelFailedToLoad
        /// Another speech model (a meeting's) is in use, so dictation cannot load its own.
        case speechModelBusy
        case microphoneDenied
        case noMicrophone
        case nothingHeard
        /// "Paste the raw version" with nothing dictated yet.
        case nothingToPaste
    }
}

/// The names the pill's buttons call back with (`PillAction.id`, `PillClose.id`).
enum HUDPillAction {
    static let cancel = "cancel"
    /// The Lintel Settings window (the microphone problem's "Allow", as before).
    static let openSettings = "openSettings"
    /// The Models pane for the speech model (`PluginContext.openModels`).
    static let openModels = "openModels"
    /// The system's Accessibility privacy pane (new in Phase 2).
    static let allowAccessibility = "allowAccessibility"
}

extension HUDState {
    /// The pill this state is, or `nil` when the state shows nothing (spec OD-4: a partial cleanup fallback is
    /// invisible). `elapsed` is the running time of the recording in seconds (shown on hover and in the VoiceOver
    /// label); `microphoneLineVisible` is the view model's 3 s window of the replaced-microphone line (OD-11).
    func pill(elapsed: Int = 0, microphoneLineVisible: Bool = true) -> PillContent? {
        switch self {
        case .recording(let recording):
            return recordingPill(recording, elapsed: elapsed, microphoneLineVisible: microphoneLineVisible)
        case .finishing:
            return PillContent(glyph: .working(dot: false), accessibilityLabel: accessibilityLabel(elapsed: elapsed))
        case .pasted:
            return PillContent(glyph: .done, accessibilityLabel: accessibilityLabel(elapsed: elapsed))
        case .pastedUnformatted(all: false):
            return nil
        default:
            guard let line = messageLine else { return nil }
            return PillContent(
                glyph: line.glyph, text: line.text, action: line.action, accessibilityLabel: line.text)
        }
    }

    private func recordingPill(_ recording: Recording, elapsed: Int, microphoneLineVisible: Bool) -> PillContent {
        var live: [PillLive] = [.wave(level: Double(recording.level))]
        if let left = recording.secondsLeft { live.append(.clock(String(left), amber: true)) }
        let fallbackLine = recording.fallback?.pillLine
        let time = Self.clock(elapsed)
        // OD-11: the line for 3 s, then the amber dot; hover (and VoiceOver) give it again.
        let showsLine = fallbackLine != nil && microphoneLineVisible
        return PillContent(
            glyph: .live(dot: false), badge: fallbackLine != nil, live: live,
            text: showsLine ? fallbackLine : nil, truncation: .middle,
            hoverText: fallbackLine != nil && !showsLine ? "\(time) · \(fallbackLine ?? "")" : time,
            close: PillClose(
                id: HUDPillAction.cancel,
                accessibilityName: String(
                    localized: "Cancel dictation", comment: "HUD pill, VoiceOver: the name of the ✕ while dictating"),
                visibility: recording.escapeCancels ? .onHover : .always),
            accessibilityLabel: accessibilityLabel(elapsed: elapsed))
    }

    /// The glyph, line and button of the states that are one line.
    private var messageLine: (glyph: PillGlyph, text: String, action: PillAction?)? {
        switch self {
        case .allowMicrophone:
            return (
                .microphone,
                String(
                    localized: "Allow the microphone in the dialog",
                    comment: "HUD pill: dictation while the system's microphone prompt is on screen"), nil
            )
        case .pastedUnformatted(all: true):
            return (
                .attention,
                String(
                    localized: "Pasted without cleanup",
                    comment: "HUD pill: formatting failed for the whole text and the raw text was pasted"), nil
            )
        case .copied(let reason):
            return (
                .attention,
                String(
                    localized: "Copied, paste with ⌘V",
                    comment: "HUD pill: the text was only copied, the user pastes it"),
                reason == .noAccessibility
                    ? PillAction(
                        id: HUDPillAction.allowAccessibility,
                        title: String(localized: "Allow", comment: "HUD pill: button that opens a privacy pane"))
                    : nil
            )
        case .problem(let problem):
            return Self.messageLine(for: problem)
        case .recording, .finishing, .pasted, .pastedUnformatted(all: false):
            return nil
        }
    }

    private static func messageLine(for problem: Problem) -> (glyph: PillGlyph, text: String, action: PillAction?) {
        let allow = String(localized: "Allow", comment: "HUD pill: button that opens a privacy pane")
        switch problem {
        case .modelMissing:
            return (
                .error,
                String(localized: "No speech model", comment: "HUD pill: no speech model is installed"),
                PillAction(
                    id: HUDPillAction.openModels,
                    title: String(
                        localized: "Download",
                        comment: "HUD pill: the missing-model pill's button; Models pane: downloads a model"))
            )
        case .modelUnavailable, .modelFailedToLoad:
            return (
                .error,
                String(
                    localized: "Speech model isn't working",
                    comment: "HUD pill: the speech model's folder is gone or loading it failed"),
                PillAction(
                    id: HUDPillAction.openModels,
                    title: String(localized: "Fix", comment: "HUD pill: button that opens the place that fixes it"))
            )
        case .speechModelBusy:
            return (
                .attention,
                String(
                    localized: "Dictation is back after the meeting",
                    comment: "HUD pill: a meeting uses a different speech model, so dictation cannot load its own"),
                nil
            )
        case .microphoneDenied:
            return (
                .microphone,
                String(localized: "No microphone access", comment: "HUD pill: microphone access is denied"),
                PillAction(id: HUDPillAction.openSettings, title: allow)
            )
        case .noMicrophone:
            return (
                .microphone,
                String(localized: "No microphone found", comment: "HUD pill: there is no input device"), nil
            )
        case .nothingHeard:
            return (
                .attention, String(localized: "Nothing heard", comment: "HUD pill: the recording had no speech"), nil
            )
        case .nothingToPaste:
            return (
                .attention,
                String(
                    localized: "Nothing to paste yet",
                    comment: "HUD pill: \"paste the raw version\" with no earlier dictation"), nil
            )
        }
    }

    /// What VoiceOver says about the pill: everything, hover-only content included ("Dictation, recording, 0:12.
    /// Esc cancels.").
    func accessibilityLabel(elapsed: Int = 0) -> String {
        switch self {
        case .recording(let recording):
            var parts = [
                String(
                    localized: "Dictation, recording, \(Self.clock(elapsed))",
                    comment: "HUD pill, VoiceOver: dictation is recording, the placeholder is the running time")
            ]
            if let fallback = recording.fallback { parts.append(fallback.message) }
            if let left = recording.secondsLeft {
                parts.append(
                    String(
                        localized: "Stops in \(left) s",
                        comment: "HUD pill, VoiceOver: countdown before the recording limit"))
            }
            parts.append(
                recording.escapeCancels
                    ? String(localized: "Esc cancels", comment: "HUD pill, VoiceOver: how to cancel the dictation")
                    : String(
                        localized: "✕ cancels",
                        comment: "HUD pill, VoiceOver: how to cancel when Escape could not be claimed"))
            return parts.joined(separator: ". ") + "."
        case .finishing:
            return String(
                localized: "Dictation, finishing",
                comment: "HUD pill, VoiceOver: the text is being produced after the recording")
        case .pasted:
            return String(localized: "Pasted", comment: "HUD pill, VoiceOver: the text was pasted")
        case .pastedUnformatted(all: false):
            return ""
        default:
            return messageLine?.text ?? ""
        }
    }

    /// Whether the HUD shows the recording (a ✕, a running time).
    var offersCancel: Bool {
        if case .recording = self { return true }
        return false
    }

    /// How long a final state stays before the HUD disappears; `nil` while the state is live. The ✓ after a paste
    /// stays 0.6 s (OD-3).
    var hidesAfter: Duration? {
        switch self {
        case .pasted: .milliseconds(600)
        case .pastedUnformatted, .copied, .problem: .seconds(3)
        default: nil
        }
    }

    /// What VoiceOver says when the state appears (spec: announcements on start, stop and pasted). Level changes,
    /// the countdown tick and a partial cleanup (which shows nothing, OD-4) stay silent.
    var announcement: String? {
        switch self {
        case .recording(let recording) where recording.fallback != nil && !recording.loadingModel:
            recording.fallback?.message
        case .recording(let recording) where !recording.loadingModel && recording.secondsLeft == nil:
            String(localized: "Recording started", comment: "VoiceOver announcement when dictation starts")
        case .finishing:
            String(localized: "Recording stopped", comment: "VoiceOver announcement when dictation stops")
        case .pasted:
            accessibilityLabel()
        case .pastedUnformatted(all: false):
            nil
        case .pastedUnformatted, .copied, .problem:
            messageLine?.text
        default:
            nil
        }
    }

    /// "0:12", "12:34".
    static func clock(_ seconds: Int) -> String {
        let total = max(0, seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
