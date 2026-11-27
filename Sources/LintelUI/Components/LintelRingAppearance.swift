import AppKit
import SwiftUI

/// What the ring says (notes explorer spec `2026-11-24-notes-explorer-main-window`, "The working ring"). It is the one
/// ring component of the notes window and of the minimal HUD (spec `2026-11-25-minimal-hud`, `LintelRing`), whose API
/// is the base: #273's `static` is `.idle`, its `live` is `.listening` (and `.warning`), its `working` is
/// `.processing`. `.error` and the progress of `.processing` are this spec's additive options.
public nonisolated enum LintelRingState: Equatable, Sendable {
    /// The cut ring at rest: the Record button, the type mark of a row.
    case idle
    /// Recording or dictating: a Verdigris ring turning slowly.
    case listening
    /// Still listening, but something is wrong (silence, the call is not heard): the ring keeps turning and only
    /// the dot turns amber. The text that explains it is always beside the ring, never in it.
    case warning
    /// Transcribing or writing: the ring closes with `progress` (0...1); `nil` is an indeterminate sweep.
    case processing(progress: Double?)
    /// A failed recording or notes: an open ring in the error colour (a wider opening than the idle ring, so it
    /// is never colour alone).
    case error
}

/// The note-type mark: a meeting ring has the centre dot, a dictation ring has none (same meaning as the type
/// ring of the notes list).
public nonisolated enum LintelRingMark: Equatable, Sendable {
    case meeting
    case dictation
}

/// How the ring moves. The system's Reduce Motion is read from the environment; the other two are for tests and the
/// design gallery.
public nonisolated enum LintelRingMotion: Equatable, Sendable {
    /// Follows the system's Reduce Motion setting.
    case system
    /// The geometry of the moving look, but no animation (a gallery picture, a snapshot test).
    case frozen
    /// The Reduce Motion look whatever the system says.
    case reduced
}

/// The pure part of the ring: which colours, how much of the ring, whether it turns. Everything the view draws
/// comes from here, so the logic is tested without drawing.
public nonisolated struct LintelRingAppearance: Equatable, Sendable {
    /// A colour role. Every role is a `LintelBrand` token; Verdigris (`live`) is only for live states.
    public enum Tone: Equatable, Sendable, CaseIterable {
        /// `LintelBrand.secondaryText`: the idle ring and its dot.
        case quiet
        /// `LintelBrand.ink`: the closing ring of work in progress.
        case ink
        /// `LintelBrand.accent`: live.
        case live
        /// `LintelBrand.statusAttention`: the warning dot.
        case attention
        /// `LintelBrand.statusError`.
        case error
        /// `LintelBrand.onAccent`: the ring on a Verdigris fill (the Record button).
        case onAccent

        /// The colour as plain sRGB (for the contrast tests): the same values `LintelBrand` draws.
        public func hex(dark: Bool) -> UInt32 {
            switch self {
            case .quiet: dark ? BrandPalette.secondaryTextDark : BrandPalette.secondaryTextLight
            case .ink: dark ? BrandPalette.inkDark : BrandPalette.inkLight
            case .live: dark ? BrandPalette.accentDark : BrandPalette.accentLight
            case .attention: dark ? BrandPalette.statusAttentionDark : BrandPalette.statusAttentionLight
            case .error: dark ? BrandPalette.statusErrorDark : BrandPalette.statusErrorLight
            case .onAccent: dark ? BrandPalette.onAccentDark : BrandPalette.onAccentLight
            }
        }

        /// The dynamic colour the layers draw: the same token as `hex(dark:)`, listed beside it so the two stay one switch
        /// apart.
        @MainActor var brandColor: NSColor {
            switch self {
            case .quiet: LintelBrand.secondaryTextColor
            case .ink: LintelBrand.inkColor
            case .live: LintelBrand.accentColor
            case .attention: LintelBrand.statusAttentionColor
            case .error: LintelBrand.statusErrorColor
            case .onAccent: LintelBrand.onAccentColor
            }
        }
    }

    public var ringTone: Tone
    /// The centre dot; `nil` is none (a dictation ring, an error).
    public var dotTone: Tone?
    /// A faint full ring behind a closing arc, so the amount still to come is visible.
    public var showsTrack: Bool
    /// The opening of the ring in degrees (the mark's cut is 60°).
    public var cutWidth: Double
    /// The part of the open ring that is drawn, 0...1, from the clockwise edge of the cut.
    public var sweep: Double
    /// Seconds for one turn; `nil` is a ring that does not turn.
    public var secondsPerTurn: Double?
    public var dotBreathes: Bool

    /// The turning of a live ring: slow.
    public static let liveSecondsPerTurn = 8.0
    /// The indeterminate sweep: quick, so "working" reads at a glance.
    public static let sweepSecondsPerTurn = 1.1
    /// The idle ring's cut, and the wider opening of the error ring.
    public static let normalCutWidth = 60.0
    public static let errorCutWidth = 120.0
    /// The arc of an indeterminate sweep, and what Reduce Motion shows instead of a sweep.
    public static let indeterminateSweep = 0.3
    public static let reducedIndeterminateSweep = 0.5

    /// - Parameters:
    ///   - reduceMotion: nothing turns or breathes; an indeterminate sweep becomes a static half ring.
    ///   - onAccentFill: the ring sits on a Verdigris fill (the Record button): every colour becomes `onAccent`, so it
    ///     stays visible, and there is no track. The amber warning dot and the error colour measure 1.07 to 1.27:1 on
    ///     Verdigris (C16 needs 3:1), so they are never drawn there: a warning keeps its dot and an error its wider
    ///     opening (neither is colour alone) in `onAccent`. The approved sheet does not show them on the fill.
    public init(state: LintelRingState, mark: LintelRingMark, reduceMotion: Bool, onAccentFill: Bool = false) {
        let dotOn = mark == .meeting
        switch state {
        case .idle:
            ringTone = .quiet
            dotTone = dotOn ? .quiet : nil
            showsTrack = false
            cutWidth = Self.normalCutWidth
            sweep = 1
            secondsPerTurn = nil
            dotBreathes = false
        case .listening:
            ringTone = .live
            dotTone = dotOn ? .live : nil
            showsTrack = false
            cutWidth = Self.normalCutWidth
            sweep = 1
            secondsPerTurn = reduceMotion ? nil : Self.liveSecondsPerTurn
            dotBreathes = dotOn && !reduceMotion
        case .warning:
            // The dot is the warning, so a dictation ring gets one too.
            ringTone = .live
            dotTone = .attention
            showsTrack = false
            cutWidth = Self.normalCutWidth
            sweep = 1
            secondsPerTurn = reduceMotion ? nil : Self.liveSecondsPerTurn
            dotBreathes = false
        case .processing(let progress):
            ringTone = .ink
            dotTone = dotOn ? .quiet : nil
            showsTrack = true
            cutWidth = Self.normalCutWidth
            if let progress = Self.clamped(progress) {
                sweep = progress
                secondsPerTurn = nil
            } else {
                sweep = reduceMotion ? Self.reducedIndeterminateSweep : Self.indeterminateSweep
                secondsPerTurn = reduceMotion ? nil : Self.sweepSecondsPerTurn
            }
            dotBreathes = false
        case .error:
            ringTone = .error
            dotTone = nil
            showsTrack = false
            cutWidth = Self.errorCutWidth
            sweep = 1
            secondsPerTurn = nil
            dotBreathes = false
        }
        if onAccentFill {
            ringTone = .onAccent
            dotTone = dotTone.map { _ in .onAccent }
            showsTrack = false
        }
    }

    /// 0...1, or `nil` for a value that is not a progress (indeterminate).
    public static func clamped(_ progress: Double?) -> Double? {
        guard let progress, progress.isFinite else { return nil }
        return min(max(progress, 0), 1)
    }

    /// Whole percent for the spoken label.
    public static func percent(_ progress: Double) -> Int {
        Int((min(max(progress, 0), 1) * 100).rounded())
    }

    public var animates: Bool { secondsPerTurn != nil || dotBreathes }
}

/// The ring's size: a base size in points that follows the app's text size (S and M the same, L and XL larger, as
/// the HUD pill's 16 / 16 / 19 pt glyph), and the small cut for 24 pt and below.
public nonisolated enum LintelRingMetrics {
    public static func points(base: CGFloat, textSize: TextSize) -> CGFloat {
        switch textSize {
        case .small, .medium: base
        case .large: base * 1.1
        case .extraLarge: base * 1.1875
        }
    }

    /// The mark's small cut (a thinner ring so the core stays readable) is for 24 pt and below.
    public static func usesSmallCut(points: CGFloat) -> Bool { points <= 24 }
}
