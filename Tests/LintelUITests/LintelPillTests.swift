import AppKit
import SwiftUI
import Testing

@testable import LintelUI

/// The pure part of the HUD pill (spec `2026-11-25-minimal-hud`, Phase 1): what it offers to VoiceOver, which family
/// member it is, its sizes and how it follows Reduce Motion.
@Suite struct PillContentTests {
    static let record = PillAction(id: "record", title: "Record", style: .primary)
    static let mute = PillAction(
        id: "mute", title: "Don't ask again", accessibilityName: "Don't ask again for Google Chrome", style: .link)
    static let stop = PillAction(id: "stop", title: "", accessibilityName: "End recording", style: .stop)
    static let end = PillAction(id: "end", title: "End")

    static let suggestion = PillContent(
        glyph: .person, text: "Meeting in Google Chrome", action: record, hoverActions: [mute],
        close: PillClose(id: "notNow", accessibilityName: "Not now"), accessibilityLabel: "Meeting in Google Chrome")
    static let meeting = PillContent(
        glyph: .live(dot: true), live: [.clock("12:34", amber: false)],
        hoverLevels: [PillLevel(name: "You", level: 0.5)], hoverActions: [end], stop: stop,
        accessibilityLabel: "Recording a meeting, 12:34.")
    static let dictation = PillContent(
        glyph: .live(dot: false), live: [.wave(level: 0.4)], hoverText: "0:12",
        close: PillClose(id: "cancel", accessibilityName: "Cancel dictation", visibility: .onHover),
        accessibilityLabel: "Dictation, recording, 0:12. Esc cancels.")

    @Test func everyButtonIsAnAccessibilityActionInTheOrderItStandsHoverOnlyOnesIncluded() {
        #expect(
            Self.suggestion.accessibilityActions == [
                PillAccessibilityAction(id: "record", name: "Record"),
                PillAccessibilityAction(id: "mute", name: "Don't ask again for Google Chrome"),
                PillAccessibilityAction(id: "notNow", name: "Not now"),
            ])
        #expect(Self.meeting.accessibilityActions.map(\.id) == ["end", "stop"])
        #expect(Self.meeting.accessibilityActions.last?.name == "End recording")
        // The dictation ✕ is drawn only on hover, but VoiceOver always has it.
        #expect(!Self.dictation.showsClose(expanded: false))
        #expect(
            Self.dictation.accessibilityActions == [PillAccessibilityAction(id: "cancel", name: "Cancel dictation")])
        #expect(PillContent(glyph: .done, text: "Saved", accessibilityLabel: "Saved").accessibilityActions.isEmpty)
    }

    @Test func anActionWithoutItsOwnAccessibilityNameIsCalledByItsTitle() {
        #expect(PillAction(id: "fix", title: "Fix").accessibilityName == "Fix")
        #expect(Self.mute.accessibilityName == "Don't ask again for Google Chrome")
    }

    @Test func theCloseButtonShowsAlwaysOrOnlyWhileExpanded() {
        #expect(Self.suggestion.showsClose(expanded: false) && Self.suggestion.showsClose(expanded: true))
        #expect(!Self.dictation.showsClose(expanded: false) && Self.dictation.showsClose(expanded: true))
        #expect(!Self.meeting.showsClose(expanded: true))
    }

    @Test func hoverContentIsKnownSoAPillWithoutItNeverExpands() {
        #expect(Self.dictation.hasHoverContent && Self.meeting.hasHoverContent && Self.suggestion.hasHoverContent)
        #expect(!PillContent(glyph: .done, text: "Saved", accessibilityLabel: "Saved").hasHoverContent)
        #expect(PillContent(glyph: .working(dot: true), hoverText: "Saving", accessibilityLabel: "").hasHoverContent)
    }

    @Test func theVariantFollowsTheSpecsFamilyTable() {
        #expect(Self.dictation.variant == .live)
        #expect(Self.meeting.variant == .live)
        #expect(Self.suggestion.variant == .prompt)
        #expect(PillContent(glyph: .working(dot: true), accessibilityLabel: "").variant == .working)
        #expect(PillContent(glyph: .error, text: "No speech model", accessibilityLabel: "").variant == .message)
        let undo = PillContent(
            glyph: .done, text: "Deleted “A long title”", truncation: .middle,
            action: PillAction(id: "undo", title: "Undo"), accessibilityLabel: "Deleted “A long title”")
        #expect(undo.variant == .message && undo.close == nil && undo.truncation == .middle)
    }

    @Test func onlyAWorkingPillWithNothingElseIsACircle() {
        let working = PillContent(glyph: .working(dot: true), hoverText: "Transcribing, 3 left", accessibilityLabel: "")
        #expect(working.isCircle(expanded: false))
        #expect(!working.isCircle(expanded: true))
        #expect(!Self.dictation.isCircle(expanded: false))
    }

    @Test func theGlyphsDrawLintelRingAndOnlyALiveRingCarriesTheAmberDot() {
        #expect(PillGlyph.live(dot: true).ring(badge: false)! == (.listening, .meeting))
        #expect(PillGlyph.live(dot: false).ring(badge: false)! == (.listening, .dictation))
        #expect(PillGlyph.live(dot: false).ring(badge: true)! == (.warning, .dictation))
        #expect(PillGlyph.live(dot: true).ring(badge: true)! == (.warning, .meeting))
        #expect(PillGlyph.working(dot: true).ring(badge: true)! == (.processing(progress: nil), .meeting))
        for glyph in [PillGlyph.attention, .error, .microphone, .done, .person] {
            #expect(glyph.ring(badge: true) == nil, "\(glyph)")
        }
    }

    @Test func theSizesFollowTheTextSize() {
        #expect(TextSize.allCases.map(PillMetrics.height) == [28, 32, 35, 38])
        #expect(TextSize.allCases.map(PillMetrics.fontSize) == [12, 13, 14, 15])
        #expect(TextSize.allCases.map(PillMetrics.glyph) == [16, 16, 17.6, 19])
        #expect(TextSize.allCases.map { PillMetrics.maxWidth($0, expanded: false) } == [380, 380, 420, 450])
        #expect(TextSize.allCases.map { PillMetrics.maxWidth($0, expanded: true) } == [500, 500, 540, 570])
        // The widest hovered pill still fits the fixed panel.
        #expect(PillMetrics.maxWidth(.extraLarge, expanded: true) <= PillMetrics.panelSize.width)
        #expect(PillMetrics.height(.extraLarge) <= PillMetrics.panelSize.height)
    }

    @Test func reduceMotionComesFromTheRingsKnobOrTheSystem() {
        #expect(PillMotion.reduces(.reduced, system: false))
        #expect(PillMotion.reduces(.system, system: true))
        #expect(!PillMotion.reduces(.system, system: false))
        #expect(!PillMotion.reduces(.frozen, system: true))
        #expect(!PillMotion.animates(.frozen, system: false))
        #expect(!PillMotion.animates(.reduced, system: false))
        #expect(PillMotion.animates(.system, system: false))
    }

    /// Under `LintelRingMotion.reduced` every ring the pill draws is the Reduce Motion look: nothing turns or breathes
    /// and the working ring is the static part ring with its track.
    @Test func underReducedMotionNoRingOfThePillMoves() throws {
        for glyph in [PillGlyph.live(dot: true), .live(dot: false), .working(dot: true), .working(dot: false)] {
            for badge in [false, true] {
                let ring = try #require(glyph.ring(badge: badge))
                let reduce = PillMotion.reduces(.reduced, system: false)
                let look = LintelRingAppearance(state: ring.state, mark: ring.mark, reduceMotion: reduce)
                #expect(!look.animates, "\(glyph) badge \(badge)")
            }
        }
        let working = LintelRingAppearance(
            state: .processing(progress: nil), mark: .meeting, reduceMotion: PillMotion.reduces(.reduced, system: false)
        )
        #expect(working.showsTrack && working.sweep == LintelRingAppearance.reducedIndeterminateSweep)
    }

    @Test func theWaveFollowsTheLevelAndStaysFlatUnderReduceMotion() {
        let quiet = PillWave.height(level: 0, profile: 1, reduced: false)
        let loud = PillWave.height(level: 1, profile: 1, reduced: false)
        #expect(loud > quiet && loud <= PillWave.maxHeight)
        let flat = PillWave.profile.map { PillWave.height(level: 0.8, profile: $0, reduced: true) }
        #expect(Set(flat).count == 1)
        #expect(PillWave.height(level: .nan, profile: 1, reduced: false) == quiet)
        #expect(PillWave.height(level: 7, profile: 1, reduced: false) == loud)
    }
}

/// The pill drawn: it hugs its content, never grows past the width limit, never wraps, and its rings follow the motion
/// it is given.
@MainActor
@Suite(.serialized)
struct LintelPillLayoutTests {
    private func size(
        _ content: PillContent, _ textSize: TextSize = .medium, expanded: Bool = false
    ) -> CGSize {
        let host = NSHostingView(
            rootView: LintelPill(content, expanded: expanded).lintelTextSize(textSize)
                .environment(\.lintelRingMotion, .frozen))
        return host.fittingSize
    }

    private static let long = PillContent(
        glyph: .attention,
        text: String(repeating: "A very long line that would never fit ", count: 4),
        action: PillAction(id: "fix", title: "Fix"),
        close: PillClose(id: "dismiss", accessibilityName: "Dismiss"),
        accessibilityLabel: "long")

    @Test func aLongLineIsShortenedAtTheWidthLimitAndStaysOneLine() {
        for textSize in TextSize.allCases {
            let drawn = size(Self.long, textSize)
            #expect(drawn.width <= PillMetrics.maxWidth(textSize, expanded: false) + 0.5, "\(textSize)")
            // A shortened line ends on a whole glyph, so the pill may stop a few points short of the limit.
            #expect(drawn.width >= PillMetrics.maxWidth(textSize, expanded: false) - 30, "\(textSize): \(drawn.width)")
            #expect(abs(drawn.height - PillMetrics.height(textSize)) < 0.5, "\(textSize): \(drawn.height)")
        }
    }

    @Test func aShortLineHugsItsContent() {
        let saved = PillContent(glyph: .done, text: "Saved", accessibilityLabel: "Saved")
        #expect(size(saved).width < 120)
    }

    @Test func theDictationPillIsAbout88PointsAndTheWorkingPillACircle() {
        #expect(abs(size(PillContentTests.dictation).width - 88) <= 2, "\(size(PillContentTests.dictation))")
        let working = size(PillContent(glyph: .working(dot: true), accessibilityLabel: "Working"))
        #expect(abs(working.width - 32) < 0.5 && abs(working.height - 32) < 0.5, "\(working)")
    }

    @Test func expandingAddsTheHoverContentWithinTheWiderLimit() {
        let collapsed = size(PillContentTests.meeting)
        let expanded = size(PillContentTests.meeting, expanded: true)
        #expect(expanded.width > collapsed.width)
        #expect(expanded.width <= PillMetrics.maxWidth(.medium, expanded: true))
        // Content without hover content does not change.
        let saved = PillContent(glyph: .done, text: "Saved", accessibilityLabel: "Saved")
        #expect(size(saved, expanded: true) == size(saved))
    }

    private func rings(_ content: PillContent, motion: LintelRingMotion) throws -> [RingLayerView] {
        let host = NSHostingView(rootView: LintelPill(content).environment(\.lintelRingMotion, motion))
        let window = NSWindow(
            contentRect: NSRect(x: -20_000, y: -20_000, width: 300, height: 60), styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer {
            window.contentView = nil
            window.close()
        }
        host.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        host.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> [RingLayerView] {
            (view as? RingLayerView).map { [$0] } ?? view.subviews.flatMap(find)
        }
        let found = find(host)
        try #require(!found.isEmpty)
        return found
    }

    @Test func theRingIsLintelRingAndUnderReducedMotionItIsStill() throws {
        let live = try rings(PillContentTests.meeting, motion: .reduced)
        #expect(live.allSatisfy { $0.look?.animates == false && $0.runningAnimationKeys.isEmpty })
        let working = try rings(PillContent(glyph: .working(dot: true), accessibilityLabel: ""), motion: .reduced)
        #expect(working.allSatisfy { $0.look?.sweep == LintelRingAppearance.reducedIndeterminateSweep })
        // Without Reduce Motion the same ring turns (the system setting of the test machine is off).
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let moving = try rings(PillContentTests.meeting, motion: .system)
            #expect(moving.allSatisfy { $0.look?.animates == true })
        }
    }
}
