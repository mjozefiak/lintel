import AppKit
import SwiftUI
import Testing

@testable import LintelUI

/// The pure part of the working ring: which look each state has, the progress, Reduce Motion, the colours.
@Suite struct LintelRingAppearanceTests {
    private func look(_ state: LintelRingState, _ mark: LintelRingMark = .meeting, reduce: Bool = false)
        -> LintelRingAppearance
    {
        LintelRingAppearance(state: state, mark: mark, reduceMotion: reduce)
    }

    @Test func idleIsAStaticQuietCutRingWithTheDotOnlyForAMeeting() {
        let meeting = look(.idle, .meeting)
        #expect(meeting.ringTone == .quiet && meeting.dotTone == .quiet)
        #expect(meeting.sweep == 1 && meeting.cutWidth == LintelRingAppearance.normalCutWidth)
        #expect(!meeting.animates && !meeting.showsTrack)
        #expect(look(.idle, .dictation).dotTone == nil)
    }

    @Test func listeningIsAVerdigrisRingThatTurnsAndAMeetingDotThatBreathes() {
        let meeting = look(.listening, .meeting)
        #expect(meeting.ringTone == .live && meeting.dotTone == .live)
        #expect(meeting.secondsPerTurn == LintelRingAppearance.liveSecondsPerTurn && meeting.dotBreathes)
        let dictation = look(.listening, .dictation)
        #expect(dictation.dotTone == nil && !dictation.dotBreathes)
        #expect(dictation.secondsPerTurn != nil)
    }

    @Test func warningKeepsTheRingTurningAndOnlyTheDotChangesColour() {
        for mark in [LintelRingMark.meeting, .dictation] {
            let warning = look(.warning, mark)
            #expect(warning.ringTone == look(.listening, mark).ringTone)
            #expect(warning.secondsPerTurn == look(.listening, mark).secondsPerTurn)
            #expect(warning.dotTone == .attention)
        }
    }

    @Test func processingClosesWithTheProgressAndSweepsWhenItIsUnknown() {
        let half = look(.processing(progress: 0.5))
        #expect(half.sweep == 0.5 && half.secondsPerTurn == nil && half.showsTrack)
        #expect(look(.processing(progress: -3)).sweep == 0)
        #expect(look(.processing(progress: 7)).sweep == 1)
        for unknown in [nil, Double.nan, .infinity] {
            let sweep = look(.processing(progress: unknown))
            #expect(sweep.sweep == LintelRingAppearance.indeterminateSweep)
            #expect(sweep.secondsPerTurn == LintelRingAppearance.sweepSecondsPerTurn)
        }
        #expect(look(.processing(progress: 0.4), .dictation).dotTone == nil)
        #expect(look(.processing(progress: 0.4), .meeting).dotTone == .quiet)
    }

    @Test func errorIsAnOpenRingInTheErrorColourWithAWiderOpeningAndNoDot() {
        let error = look(.error)
        #expect(error.ringTone == .error && error.dotTone == nil && !error.animates)
        #expect(error.cutWidth > look(.idle).cutWidth)
    }

    @Test func reduceMotionStopsEverythingAndTurnsTheSweepIntoAStaticHalfRing() {
        for state in [LintelRingState.listening, .warning, .processing(progress: nil), .processing(progress: 0.3)] {
            for mark in [LintelRingMark.meeting, .dictation] {
                #expect(!look(state, mark, reduce: true).animates, "\(state) \(mark)")
            }
        }
        #expect(look(.processing(progress: nil), reduce: true).sweep == LintelRingAppearance.reducedIndeterminateSweep)
        // What is shown does not otherwise change.
        #expect(look(.listening, reduce: true).ringTone == .live && look(.listening, reduce: true).dotTone == .live)
    }

    @Test func percentIsWholeAndClamped() {
        #expect(LintelRingAppearance.percent(0.604) == 60)
        #expect(LintelRingAppearance.percent(1.4) == 100)
        #expect(LintelRingAppearance.percent(-1) == 0)
    }

    /// C19: Verdigris is for live states only.
    @Test func verdigrisAppearsOnlyInLiveStates() {
        let others: [LintelRingState] = [.idle, .processing(progress: 0.5), .processing(progress: nil), .error]
        for state in others {
            for mark in [LintelRingMark.meeting, .dictation] {
                let appearance = look(state, mark)
                #expect(appearance.ringTone != .live && appearance.dotTone != .live, "\(state) \(mark)")
            }
        }
    }

    /// C16: the ring's colours are graphics, so 3:1 against the surfaces it is drawn on in both themes: the window, the
    /// card, the sidebar and the selected row.
    @Test func everyColourOfTheRingHasThreeToOneOnTheSurfaces() {
        let light: [UInt32] = [
            BrandPalette.windowLight, BrandPalette.cardLight, BrandPalette.sidebarLight,
            BrandPalette.blend(
                BrandPalette.accentLight, alpha: BrandPalette.windowSelectionTintAlpha.light,
                over: BrandPalette.windowLight),
        ]
        let dark: [UInt32] = [
            BrandPalette.windowDark, BrandPalette.cardDark, BrandPalette.sidebarDark,
            BrandPalette.blend(
                BrandPalette.accentDark, alpha: BrandPalette.windowSelectionTintAlpha.dark,
                over: BrandPalette.windowDark),
        ]
        for tone in LintelRingAppearance.Tone.allCases where tone != .onAccent {
            for background in light {
                #expect(BrandPalette.contrast(tone.hex(dark: false), background) >= 3, "\(tone) light")
            }
            for background in dark {
                #expect(BrandPalette.contrast(tone.hex(dark: true), background) >= 3, "\(tone) dark")
            }
        }
    }

    /// The Record button: the ring on the Verdigris fill needs 3:1 against it in both themes, and every tone the
    /// on-accent look uses is `onAccent`.
    @Test func theRingOnAVerdigrisFillIsVisible() {
        #expect(
            BrandPalette.contrast(LintelRingAppearance.Tone.onAccent.hex(dark: false), BrandPalette.accentLight) >= 3)
        #expect(BrandPalette.contrast(LintelRingAppearance.Tone.onAccent.hex(dark: true), BrandPalette.accentDark) >= 3)
        let states: [LintelRingState] = [
            .idle, .listening, .warning, .processing(progress: 0.5), .processing(progress: nil), .error,
        ]
        for state in states {
            for mark in [LintelRingMark.meeting, .dictation] {
                let appearance = LintelRingAppearance(state: state, mark: mark, reduceMotion: false, onAccentFill: true)
                #expect(appearance.ringTone == .onAccent && !appearance.showsTrack, "\(state) \(mark)")
                #expect(appearance.dotTone == nil || appearance.dotTone == .onAccent, "\(state) \(mark)")
            }
        }
    }

    /// C16 on the fill: the amber dot and the error ring are 1.07 to 1.27:1 on Verdigris, so the fill never draws them.
    /// A warning keeps its dot and an error its wider opening (the signal is not colour alone), both in `onAccent`.
    @Test func aWarningOrAnErrorOnAVerdigrisFillStaysReadable() {
        for mark in [LintelRingMark.meeting, .dictation] {
            let warning = LintelRingAppearance(state: .warning, mark: mark, reduceMotion: false, onAccentFill: true)
            #expect(warning.dotTone == .onAccent, "a warning keeps its dot, \(mark)")
            let error = LintelRingAppearance(state: .error, mark: mark, reduceMotion: false, onAccentFill: true)
            #expect(error.cutWidth == LintelRingAppearance.errorCutWidth && error.dotTone == nil, "\(mark)")
        }
        let tones: [LintelRingState] = [.idle, .listening, .warning, .processing(progress: 0.3), .error]
        for dark in [false, true] {
            let fill = dark ? BrandPalette.accentDark : BrandPalette.accentLight
            for state in tones {
                let look = LintelRingAppearance(state: state, mark: .meeting, reduceMotion: false, onAccentFill: true)
                for tone in [look.ringTone] + [look.dotTone].compactMap({ $0 }) {
                    #expect(BrandPalette.contrast(tone.hex(dark: dark), fill) >= 3, "\(state) dark=\(dark)")
                }
            }
        }
    }

    @Test func theSizeFollowsTheTextSizeAndTheSmallCutIsFor24PointsAndBelow() {
        #expect(LintelRingMetrics.points(base: 16, textSize: .small) == 16)
        #expect(LintelRingMetrics.points(base: 16, textSize: .medium) == 16)
        #expect(LintelRingMetrics.points(base: 16, textSize: .extraLarge) == 19)
        #expect(LintelRingMetrics.usesSmallCut(points: 24))
        #expect(!LintelRingMetrics.usesSmallCut(points: 24.5))
    }

    @Test func everyStateHasItsOwnSpokenName() {
        let states: [LintelRingState] = [
            .idle, .listening, .warning, .processing(progress: nil), .processing(progress: 0.6), .error,
        ]
        let names = states.map { LintelRingLabels.label(state: $0, mark: .meeting) }
        #expect(Set(names).count == states.count, "\(names)")
        #expect(names[4].contains("60"))
        #expect(
            LintelRingLabels.label(state: .idle, mark: .meeting)
                != LintelRingLabels.label(state: .idle, mark: .dictation))
    }
}

@Suite struct LintelRingShapeTests {
    private let rect = CGRect(x: 0, y: 0, width: 256, height: 256)

    private func point(radius: CGFloat, degrees: Double) -> CGPoint {
        CGPoint(
            x: 128 + radius * CGFloat(cos(degrees * .pi / 180)), y: 128 + radius * CGFloat(sin(degrees * .pi / 180)))
    }

    @Test func theMarksGeometryIsKept() {
        let ring = LintelRingShape().path(in: rect)
        let middle = (LintelRingShape.outerRadius + LintelRingShape.innerRadius) / 2
        #expect(ring.contains(point(radius: middle, degrees: 45)))
        #expect(!ring.contains(point(radius: middle, degrees: -135)), "the 60 degree cut")
        #expect(!ring.contains(point(radius: LintelRingShape.innerRadius - 4, degrees: 45)))
        #expect(!ring.contains(point(radius: LintelRingShape.outerRadius + 4, degrees: 45)))
    }

    @Test func aWiderCutOpensTheRingWhereTheIdleRingIsClosed() {
        let middle = (LintelRingShape.outerRadius + LintelRingShape.innerRadius) / 2
        let idle = LintelRingShape().path(in: rect)
        let error = LintelRingShape(cutWidth: LintelRingAppearance.errorCutWidth).path(in: rect)
        // 50 degrees from the cut's centre: inside the error ring's opening, outside the idle ring's.
        #expect(idle.contains(point(radius: middle, degrees: -135 + 50)))
        #expect(!error.contains(point(radius: middle, degrees: -135 + 50)))
    }

    @Test func theSweepDrawsFromTheClockwiseEdgeOfTheCut() {
        let middle = (LintelRingShape.outerRadius + LintelRingShape.innerRadius) / 2
        #expect(LintelRingShape(sweep: 0).path(in: rect).isEmpty)
        let half = LintelRingShape(sweep: 0.5).path(in: rect)
        // The cut's clockwise edge is at -105 degrees; the open ring is 300 degrees, so half ends at +45.
        #expect(half.contains(point(radius: middle, degrees: -90)))
        #expect(half.contains(point(radius: middle, degrees: 30)))
        #expect(!half.contains(point(radius: middle, degrees: 60)))
        #expect(!half.contains(point(radius: middle, degrees: 180)))
    }
}

/// The Core Animation layers: the turning and the breathing are layer animations, and none runs when the look says so.
@MainActor @Suite struct LintelRingLayerTests {
    private func hosted(
        _ state: LintelRingState, _ mark: LintelRingMark = .meeting, reduce: Bool = false, animates: Bool = true
    ) -> (RingLayerView, NSWindow) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless], backing: .buffered,
            defer: true)
        let view = RingLayerView(frame: NSRect(x: 0, y: 0, width: 64, height: 64))
        window.contentView = view
        view.configure(
            appearance: LintelRingAppearance(state: state, mark: mark, reduceMotion: reduce), small: false,
            animates: animates)
        return (view, window)
    }

    @Test func aLiveMeetingRingTurnsAndItsDotBreathesOnTheLayers() {
        let (view, window) = hosted(.listening)
        #expect(view.runningAnimationKeys == [RingLayerView.turnKey, RingLayerView.breatheKey])
        withExtendedLifetime(window) {}
    }

    @Test func aDictationRingTurnsWithoutADot() {
        let (view, window) = hosted(.listening, .dictation)
        #expect(view.runningAnimationKeys == [RingLayerView.turnKey])
        withExtendedLifetime(window) {}
    }

    @Test func aClosingRingAndAnErrorDoNotAnimate() {
        for state in [LintelRingState.processing(progress: 0.5), .idle, .error] {
            let (view, window) = hosted(state)
            #expect(view.runningAnimationKeys.isEmpty, "\(state)")
            withExtendedLifetime(window) {}
        }
        let (sweep, window) = hosted(.processing(progress: nil))
        #expect(sweep.runningAnimationKeys == [RingLayerView.turnKey])
        withExtendedLifetime(window) {}
    }

    @Test func reduceMotionAndAFrozenRingHaveNoAnimationAtAll() {
        for state in [LintelRingState.listening, .warning, .processing(progress: nil)] {
            let (reduced, window1) = hosted(state, reduce: true)
            #expect(reduced.runningAnimationKeys.isEmpty, "reduced \(state)")
            let (frozen, window2) = hosted(state, animates: false)
            #expect(frozen.runningAnimationKeys.isEmpty, "frozen \(state)")
            withExtendedLifetime((window1, window2)) {}
        }
    }

    @Test func anAnimationStartsAgainWhenTheViewComesBackToAWindowAndStopsWhenAStateChanges() {
        let (view, window) = hosted(.listening)
        window.contentView = NSView()
        view.removeFromSuperview()
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 64, height: 64), styleMask: [.borderless], backing: .buffered,
            defer: true)
        other.contentView = view
        #expect(view.runningAnimationKeys == [RingLayerView.turnKey, RingLayerView.breatheKey])
        view.configure(
            appearance: LintelRingAppearance(state: .error, mark: .meeting, reduceMotion: false), small: false,
            animates: true)
        #expect(view.runningAnimationKeys.isEmpty)
        withExtendedLifetime((window, other)) {}
    }

    /// A layout pass or a theme change rebuilds the shapes but must not start the turn from zero again.
    @Test func aLayoutPassOrAThemeChangeDoesNotRestartTheAnimation() {
        let (view, window) = hosted(.listening)
        let restarts = view.animationRestarts
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        view.layout()
        view.viewDidChangeEffectiveAppearance()
        view.configure(
            appearance: LintelRingAppearance(state: .listening, mark: .meeting, reduceMotion: false), small: false,
            animates: true)
        #expect(view.animationRestarts == restarts)
        #expect(view.runningAnimationKeys == [RingLayerView.turnKey, RingLayerView.breatheKey])
        // A different state does restart (here: the breathing dot goes, the turn stays).
        view.configure(
            appearance: LintelRingAppearance(state: .warning, mark: .meeting, reduceMotion: false), small: false,
            animates: true)
        #expect(view.animationRestarts == restarts + 1)
        #expect(view.runningAnimationKeys == [RingLayerView.turnKey])
        withExtendedLifetime(window) {}
    }
}
