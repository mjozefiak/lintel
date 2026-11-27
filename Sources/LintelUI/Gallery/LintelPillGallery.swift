#if DEBUG
import SwiftUI

/// DEBUG only: the owner sheet of the minimal HUD's Phase 1 (spec `2026-11-25-minimal-hud`): the real `LintelPill`
/// in every variant of the family over fictional texts. The texts are the spec's copy table in the language of the
/// process (a picture in Polish comes from the app bundle run with `-AppleLanguages "(pl)"`); the pill reads no
/// catalog key itself. The widest strings of the spec are here on purpose, so the XL pictures prove the width limit.
@MainActor enum LintelPillGallery {
    static var scene: GalleryScene {
        GalleryScene(id: "ui.pill", title: "LintelPill: the HUD pill family", states: states)
    }

    /// `en` or `pl`, from the process (`GalleryRenderer.processLanguage`).
    private static func text(_ english: String, _ polish: String) -> String {
        GalleryRenderer.processLanguage == "pl" ? polish : english
    }

    private enum Look {
        case plain
        case reduced
        case contrast
    }

    private static func state(
        _ id: String, _ summary: String, expanded: Bool = false, look: Look = .plain,
        _ content: @escaping @MainActor @Sendable () -> PillContent
    ) -> GalleryState {
        GalleryState(
            id: id, summary: summary, presentation: .hud(shape: .capsule), includesLargeInSheet: true
        ) {
            let pill = LintelPill(content(), expanded: expanded)
            switch look {
            case .plain: return AnyView(pill.environment(\.lintelRingMotion, .frozen))
            case .reduced: return AnyView(pill.environment(\.lintelRingMotion, .reduced))
            case .contrast:
                return AnyView(
                    pill.environment(\.lintelRingMotion, .frozen).environment(\.lintelIncreasedContrast, true))
            }
        }
    }

    // MARK: Fixtures

    private static var cancel: PillClose {
        PillClose(id: "cancel", accessibilityName: text("Cancel dictation", "Anuluj dyktowanie"), visibility: .onHover)
    }

    static var dictation: PillContent {
        PillContent(
            glyph: .live(dot: false), live: [.wave(level: 0.65)], hoverText: "0:12", close: cancel,
            accessibilityLabel: text(
                "Dictation, recording, 0:12. Esc cancels.", "Dyktowanie, nagrywanie, 0:12. Esc anuluje."))
    }

    private static var stop: PillAction {
        PillAction(id: "stop", title: "", accessibilityName: text("End recording", "Zakończ nagrywanie"), style: .stop)
    }

    private static var end: PillAction { PillAction(id: "end", title: text("End", "Zakończ")) }

    private static var levels: [PillLevel] {
        [PillLevel(name: text("You", "Ty"), level: 0.7), PillLevel(name: text("Others", "Rozmówcy"), level: 0.45)]
    }

    static var meeting: PillContent {
        PillContent(
            glyph: .live(dot: true), live: [.clock("12:34", amber: false)], hoverLevels: levels, hoverActions: [end],
            stop: stop,
            accessibilityLabel: text("Recording a meeting, 12:34.", "Nagrywanie spotkania, 12:34."))
    }

    private static var cannotHear: String { text("Can't hear the others", "Nie słychać rozmówców") }

    static var suggestion: PillContent {
        let app = "Google Chrome"
        return PillContent(
            glyph: .person, text: text("Meeting in \(app)", "Spotkanie w \(app)"),
            action: PillAction(id: "record", title: text("Record", "Nagraj"), style: .primary),
            hoverActions: [
                PillAction(
                    id: "mute", title: text("Don't ask again", "Nie pytaj więcej"),
                    accessibilityName: text("Don't ask again for \(app)", "Nie pytaj więcej dla \(app)"), style: .link)
            ],
            close: PillClose(id: "notNow", accessibilityName: text("Not now", "Nie teraz")),
            accessibilityLabel: text("Meeting in \(app)", "Spotkanie w \(app)"))
    }

    // MARK: States

    static var states: [GalleryState] {
        [
            state(
                "live-wave",
                "Dictation, recording: the turning ring (no dot) and the voice wave, 88 pt at M. Nothing else (OD-2: the time and the ✕ are on hover; Esc cancels)."
            ) { dictation },
            state(
                "live-wave-hover",
                "Dictation, hovered (300 ms after the pointer enters): the time and the ✕ appear; the wave stays.",
                expanded: true
            ) { dictation },
            state(
                "live-wave-esc-unclaimed",
                "Dictation when Esc could not be claimed: the ✕ is always visible."
            ) {
                var content = dictation
                content.close?.visibility = .always
                return content
            },
            state(
                "live-wave-countdown",
                "Dictation about to stop: the wave plus the amber seconds left. Not a problem line, never collapses."
            ) {
                var content = dictation
                content.live = [.wave(level: 0.5), .clock("9", amber: true)]
                return content
            },
            state(
                "live-wave-fallback-line",
                "Dictation from another microphone (OD-11): the ring with the amber dot, the wave and the device name for 3 s, shortened in the middle when long."
            ) {
                var content = dictation
                content.badge = true
                content.text = text(
                    "Using Logitech BRIO Webcam Microphone Array", "Mikrofon: Logitech BRIO Webcam Microphone Array")
                content.truncation = .middle
                return content
            },
            state(
                "live-wave-amber-dot",
                "Dictation after the 3 s line: the collapsed pill keeps the amber dot on the ring (a dictation ring gets the dot too)."
            ) {
                var content = dictation
                content.badge = true
                return content
            },
            state(
                "live-clock",
                "Meeting, recording: the ring with its breathing dot, the time and the stop button (about 120 pt). No meters, no words (OD-1, OD-5)."
            ) { meeting },
            state(
                "live-clock-hover",
                "Meeting, hovered: the You and Others meters and End appear before the stop button (OD-5, OD-12).",
                expanded: true
            ) { meeting },
            state(
                "live-clock-problem",
                "Meeting with a problem: the time steps aside for one line with its glyph, one action and the stop button."
            ) {
                var content = meeting
                content.live = []
                content.lineGlyph = .attention
                content.text = cannotHear
                content.action = PillAction(id: "fix", title: text("Fix", "Napraw"))
                return content
            },
            state(
                "live-clock-retrying",
                "Meeting reconnecting the microphone: the line's glyph is the working ring (static under Reduce Motion), no action."
            ) {
                var content = meeting
                content.live = []
                content.lineGlyph = .working(dot: false)
                content.text = text("Reconnecting the mic…", "Łączenie z mikrofonem…")
                return content
            },
            state(
                "live-clock-widest",
                "The widest normal line of the spec (Polish: „Mikrofon nie nagrywa · Spróbuj ponownie”), with the stop button."
            ) {
                var content = meeting
                content.live = []
                content.lineGlyph = .microphone
                content.text = text("Your mic isn't recording", "Mikrofon nie nagrywa")
                content.action = PillAction(id: "retry", title: text("Try again", "Spróbuj ponownie"))
                return content
            },
            state(
                "live-clock-amber-dot",
                "Meeting after a problem line's 10 s (OD-8): back to the time with an amber dot on the ring."
            ) {
                var content = meeting
                content.badge = true
                return content
            },
            state(
                "live-clock-amber-dot-hover",
                "The collapsed problem, hovered: the line comes back as hover text before the meters.",
                expanded: true
            ) {
                var content = meeting
                content.badge = true
                content.hoverText = cannotHear
                return content
            },
            state(
                "live-clock-countdown",
                "Meeting about to reach its limit: the amber clock replaces the time; it never collapses."
            ) {
                var content = meeting
                content.live = [.clock(text("Ends in 4:59", "Koniec za 4:59"), amber: true)]
                return content
            },
            state(
                "working",
                "Working (finishing a dictation, processing a meeting): only the closing ring, a 32 pt circle (OD-9)."
            ) {
                PillContent(
                    glyph: .working(dot: true), accessibilityLabel: text("Saving the meeting", "Zapisywanie spotkania"))
            },
            state(
                "working-hover",
                "Working, hovered: what it is doing, in words (OD-9).",
                expanded: true
            ) {
                PillContent(
                    glyph: .working(dot: true), hoverText: text("Transcribing, 3 left", "Transkrybuję, zostały 3"),
                    accessibilityLabel: text("Transcribing, 3 left", "Transkrybuję, zostały 3"))
            },
            state(
                "message-done",
                "A done message: ✓ in the live colour, one word and one button."
            ) {
                PillContent(
                    glyph: .done, text: text("Saved", "Zapisano"),
                    action: PillAction(id: "open", title: text("Open", "Otwórz")),
                    accessibilityLabel: text("Saved", "Zapisano"))
            },
            state(
                "message-error",
                "A failure: the red triangle, one short line and one action."
            ) {
                PillContent(
                    glyph: .error, text: text("No speech model", "Brak modelu mowy"),
                    action: PillAction(id: "download", title: text("Download", "Pobierz")),
                    accessibilityLabel: text("No speech model", "Brak modelu mowy"))
            },
            state(
                "message-widest",
                "The longest line of the copy table (Polish: „Poprzednie spotkanie wciąż się zapisuje”, 39 characters) with the amber triangle and a ✕."
            ) {
                PillContent(
                    glyph: .attention,
                    text: text("Previous meeting still saving", "Poprzednie spotkanie wciąż się zapisuje"),
                    close: PillClose(id: "dismiss", accessibilityName: text("Dismiss", "Zamknij")),
                    accessibilityLabel: text("Previous meeting still saving", "Poprzednie spotkanie wciąż się zapisuje")
                )
            },
            state(
                "message-undo",
                "The notes explorer's UndoToast: a message without ✕ (✓ glyph), one button, the note title shortened in the middle."
            ) {
                let title = text(
                    "Quarterly planning with the design team and finance, follow-up",
                    "Planowanie kwartalne z zespołem projektowym i finansami, ciąg dalszy")
                return PillContent(
                    glyph: .done, text: text("Deleted “\(title)”", "Usunięto „\(title)”"), truncation: .middle,
                    action: PillAction(id: "undo", title: text("Undo", "Cofnij")),
                    accessibilityLabel: text("Deleted “\(title)”", "Usunięto „\(title)”"))
            },
            state(
                "prompt",
                "A suggestion: the person glyph, one line, Record in the live colour and the ✕ (= Not now, OD-10)."
            ) { suggestion },
            state(
                "prompt-hover",
                "The suggestion hovered: \"Don't ask again\" as a link; the widest hovered pill of the spec.",
                expanded: true
            ) { suggestion },
            state(
                "prompt-long-name",
                "A suggestion with a very long app name: the line is shortened at the end, the full name is in VoiceOver."
            ) {
                var content = suggestion
                let app = "Microsoft Teams (work or school) — Quarterly Business Review"
                content.text = text("Meeting in \(app)", "Spotkanie w \(app)")
                content.accessibilityLabel = content.text ?? ""
                return content
            },
            state(
                "reduced-motion-live",
                "Reduce Motion, dictation: the ring does not turn and the wave stays flat at the current level, with no animation.",
                look: .reduced
            ) { dictation },
            state(
                "reduced-motion-working",
                "Reduce Motion, working: the static part ring with its track, no spinner.",
                look: .reduced
            ) {
                PillContent(
                    glyph: .working(dot: true), accessibilityLabel: text("Saving the meeting", "Zapisywanie spotkania"))
            },
            state(
                "increased-contrast",
                "Increase Contrast: the 1 pt border around the meeting pill.",
                look: .contrast
            ) { meeting },
            state(
                "increased-contrast-message",
                "Increase Contrast on a message with a button.",
                look: .contrast
            ) {
                var content = meeting
                content.live = []
                content.lineGlyph = .attention
                content.text = cannotHear
                content.action = PillAction(id: "fix", title: text("Fix", "Napraw"))
                return content
            },
        ]
    }
}
#endif
