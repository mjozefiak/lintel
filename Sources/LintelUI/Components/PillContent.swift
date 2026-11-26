import SwiftUI

/// What a HUD pill says (spec `2026-11-25-minimal-hud`, "The pill family"): a pure value the plugins build from their
/// own state (`HUDState.pill`, `MeetingHUDState.pill`, `SuggestionPrompt.pill`) and `LintelPill` draws. It holds
/// only finished texts, so it never reads the string catalog itself; every action is named, so the pill's one
/// accessibility element can offer each of them, hover-only ones included.
public nonisolated struct PillContent: Equatable, Sendable {
    /// The leading glyph.
    public var glyph: PillGlyph
    /// The amber dot of a problem that lasts (OD-8) or of a replaced microphone (OD-11). Only a live ring carries
    /// it (`LintelRingState.warning`); any other glyph ignores it, because the line beside it already says why.
    public var badge: Bool
    /// What moves while the pill is live, in order: the voice wave, the time, an amber countdown.
    public var live: [PillLive]
    /// A small glyph before `text` when the leading glyph is the live ring (the meeting pill's problem line:
    /// ring · ⚠ line · action · stop). `nil` for a line that is the pill's only content.
    public var lineGlyph: PillGlyph?
    /// The one line. Never wraps; shortened by `truncation` when it does not fit the width limit.
    public var text: String?
    public var truncation: PillTruncation
    /// The one visible button after the line.
    public var action: PillAction?
    /// Hover content (OD-2, OD-5, OD-9, OD-10): a short text, level meters and buttons shown only while the pointer
    /// rests on the pill (or a button inside it has keyboard focus). Never the only place of anything: every one of
    /// them is also an accessibility action or in the label.
    public var hoverText: String?
    public var hoverLevels: [PillLevel]
    public var hoverActions: [PillAction]
    /// The meeting's stop button, always last before the ✕.
    public var stop: PillAction?
    /// The ✕, and when it shows.
    public var close: PillClose?
    /// Everything the pill says, hover-only content included ("Dictation, recording, 0:12. Esc cancels.").
    public var accessibilityLabel: String

    public init(
        glyph: PillGlyph, badge: Bool = false, live: [PillLive] = [], lineGlyph: PillGlyph? = nil,
        text: String? = nil, truncation: PillTruncation = .tail, action: PillAction? = nil,
        hoverText: String? = nil, hoverLevels: [PillLevel] = [], hoverActions: [PillAction] = [],
        stop: PillAction? = nil, close: PillClose? = nil, accessibilityLabel: String
    ) {
        self.glyph = glyph
        self.badge = badge
        self.live = live
        self.lineGlyph = lineGlyph
        self.text = text
        self.truncation = truncation
        self.action = action
        self.hoverText = hoverText
        self.hoverLevels = hoverLevels
        self.hoverActions = hoverActions
        self.stop = stop
        self.close = close
        self.accessibilityLabel = accessibilityLabel
    }

    /// The family member this content is (spec table "The pill family"), derived, never stored.
    public var variant: PillVariant {
        if action?.style == .primary { return .prompt }
        if case .live = glyph, !live.isEmpty || stop != nil { return .live }
        if case .working = glyph, text == nil, live.isEmpty { return .working }
        return .message
    }

    /// The ring the leading glyph draws (`LintelRing`; the pill never draws a ring of its own), or `nil` for a
    /// symbol glyph.
    public var ring: (state: LintelRingState, mark: LintelRingMark)? {
        glyph.ring(badge: badge)
    }

    /// Whether there is anything the hover adds. A pill without hover content never expands.
    public var hasHoverContent: Bool {
        hoverText != nil || !hoverLevels.isEmpty || !hoverActions.isEmpty || close?.visibility == .onHover
    }

    /// The ✕ is drawn: always, or only while expanded.
    public func showsClose(expanded: Bool) -> Bool {
        guard let close else { return false }
        return close.visibility == .always || expanded
    }

    /// The working pill with nothing else in it is a circle (`PillMetrics.height` wide), not a capsule.
    public func isCircle(expanded: Bool) -> Bool {
        variant == .working && action == nil && stop == nil && !showsClose(expanded: expanded)
            && !(expanded && hasHoverContent)
    }

    /// Every action the pill offers, in the order they stand, whether or not they are drawn now: the pill is one
    /// accessibility element, so VoiceOver and Voice Control reach a hover-only button through these.
    public var accessibilityActions: [PillAccessibilityAction] {
        var actions: [PillAccessibilityAction] = []
        if let action { actions.append(PillAccessibilityAction(action)) }
        actions += hoverActions.map(PillAccessibilityAction.init)
        if let stop { actions.append(PillAccessibilityAction(stop)) }
        if let close { actions.append(PillAccessibilityAction(id: close.id, name: close.accessibilityName)) }
        return actions
    }
}

/// The leading glyph (spec "Glyphs"). The three ring glyphs are `LintelRing`.
public nonisolated enum PillGlyph: Equatable, Sendable {
    /// The cut ring turning slowly; `dot` is the meeting's breathing centre dot (the dictation ring has none).
    case live(dot: Bool)
    /// The ring closing (indeterminate). Static part ring with its track under Reduce Motion.
    case working(dot: Bool)
    /// Amber triangle: a problem.
    case attention
    /// Red triangle: something failed.
    case error
    /// `mic.slash` in amber: a microphone problem.
    case microphone
    /// ✓ in the live colour.
    case done
    /// A person: a meeting suggestion.
    case person

    func ring(badge: Bool) -> (state: LintelRingState, mark: LintelRingMark)? {
        switch self {
        case .live(let dot): (badge ? .warning : .listening, dot ? .meeting : .dictation)
        case .working(let dot): (.processing(progress: nil), dot ? .meeting : .dictation)
        case .attention, .error, .microphone, .done, .person: nil
        }
    }
}

/// What moves in a live pill.
public nonisolated enum PillLive: Equatable, Sendable {
    /// The voice wave at `level` (0...1).
    case wave(level: Double)
    /// A time ("12:34") or a countdown ("9", "Ends in 4:59"); `amber` is the text-grade attention colour.
    case clock(String, amber: Bool)
}

public nonisolated enum PillTruncation: Equatable, Sendable {
    /// "Meeting in Google Chr…" (an app name).
    case tail
    /// "Using Logitech…Microphone" (a device name, a note title in the undo toast).
    case middle
}

/// A button of the pill. `id` is the consumer's own name for it; the pill calls back with it.
public nonisolated struct PillAction: Equatable, Sendable, Identifiable {
    public enum Style: Equatable, Sendable {
        /// A text button on the neutral fill ("Fix", "Open", "Undo").
        case button
        /// The prompt's one primary button in the live colour ("Record", "End").
        case primary
        /// A text link without a fill (hover "Don't ask again").
        case link
        /// The meeting's stop button: a circle with a square, no text.
        case stop
    }

    public var id: String
    /// What the button shows (`stop` shows no text).
    public var title: String
    /// What VoiceOver says, when it needs more than the title ("Don't ask again for Google Chrome").
    public var accessibilityName: String
    public var style: Style

    public init(id: String, title: String, accessibilityName: String? = nil, style: Style = .button) {
        self.id = id
        self.title = title
        self.accessibilityName = accessibilityName ?? title
        self.style = style
    }
}

/// The ✕ (cancel dictation, Not now, Keep recording, dismiss a message).
public nonisolated struct PillClose: Equatable, Sendable {
    public enum Visibility: Equatable, Sendable {
        case always
        /// OD-2: the dictation ✕ shows on hover while Esc cancels.
        case onHover
    }

    public var id: String
    public var accessibilityName: String
    public var visibility: Visibility

    public init(id: String, accessibilityName: String, visibility: Visibility = .always) {
        self.id = id
        self.accessibilityName = accessibilityName
        self.visibility = visibility
    }
}

/// A named level meter shown on hover ("You", "Others"; OD-5, OD-12).
public nonisolated struct PillLevel: Equatable, Sendable {
    public var name: String
    /// 0...1.
    public var level: Double

    public init(name: String, level: Double) {
        self.name = name
        self.level = level
    }
}

/// One accessibility action of the pill.
public nonisolated struct PillAccessibilityAction: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(_ action: PillAction) {
        self.init(id: action.id, name: action.accessibilityName)
    }
}

/// The family members of the spec's table.
public nonisolated enum PillVariant: Equatable, Sendable {
    case live
    case working
    case message
    case prompt
}

/// The pill's sizes (spec "The pill family", OD-13): everything follows the app's text size.
public nonisolated enum PillMetrics {
    /// The fixed transparent panel every pill is centred in, larger than the widest hovered pill, so expanding
    /// never moves or resizes the window.
    public static let panelSize = CGSize(width: 580, height: 56)
    public static let leadingPadding: CGFloat = 10
    public static let trailingPadding: CGFloat = 12
    public static let spacing: CGFloat = 8
    /// What hover may add to the width limit, so hover content never shortens the line.
    public static let hoverAllowance: CGFloat = 120

    /// 28 / 32 / 35 / 38 pt. L is M × 1.1 (the factor of `LintelRingMetrics`) rounded down to whole points.
    public static func height(_ size: TextSize) -> CGFloat {
        switch size {
        case .small: 28
        case .medium: 32
        case .large: 35
        case .extraLarge: 38
        }
    }

    /// 12 / 13 / 14 / 15 pt, medium weight.
    public static func fontSize(_ size: TextSize) -> CGFloat {
        switch size {
        case .small: 12
        case .medium: 13
        case .large: 14
        case .extraLarge: 15
        }
    }

    /// The glyph: 16 / 16 / 17.6 / 19 pt, the ring's own sizes.
    public static func glyph(_ size: TextSize) -> CGFloat {
        LintelRingMetrics.points(base: 16, textSize: size)
    }

    /// The ✕ and the stop button: 22 pt at S and M, growing with the glyph at L and XL.
    public static func control(_ size: TextSize) -> CGFloat {
        LintelRingMetrics.points(base: 22, textSize: size)
    }

    /// The width limit: 380 pt at S and M, 420 at L, 450 at XL, plus `hoverAllowance` while expanded.
    public static func maxWidth(_ size: TextSize, expanded: Bool) -> CGFloat {
        let base: CGFloat =
            switch size {
            case .small, .medium: 380
            case .large: 420
            case .extraLarge: 450
            }
        return base + (expanded ? hoverAllowance : 0)
    }

    /// The scale of the wave and the meters (the glyph's factor).
    public static func scale(_ size: TextSize) -> CGFloat {
        glyph(size) / 16
    }
}

/// Whether the pill moves: the same knob as the ring (`lintelRingMotion`), so a gallery picture or a test that asks
/// for `.reduced` gets the Reduce Motion look of the pill and of its ring together.
public nonisolated enum PillMotion {
    /// Reduce Motion is in effect: no turning, no breathing, no wave animation, instant expand and collapse.
    public static func reduces(_ motion: LintelRingMotion, system: Bool) -> Bool {
        motion == .reduced || (motion == .system && system)
    }

    /// Anything animates at all (`.frozen` is a picture: the moving look, no animation).
    public static func animates(_ motion: LintelRingMotion, system: Bool) -> Bool {
        motion != .frozen && !reduces(motion, system: system)
    }
}
