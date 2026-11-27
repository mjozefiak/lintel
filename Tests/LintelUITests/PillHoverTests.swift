import AppKit
import LintelTestSupport
import SwiftUI
import Testing

@testable import LintelUI

/// When the pill expands (spec `2026-11-25-minimal-hud`, "Hover"): 300 ms after the pointer enters it, 500 ms after
/// it leaves, at once for keyboard focus. Driven by a manual clock.
@MainActor
@Suite struct PillHoverModelTests {
    private func model() -> (PillHoverModel, TestClock) {
        let clock = TestClock()
        return (PillHoverModel(sleep: clock.sleeper), clock)
    }

    @Test func itExpands300MillisecondsAfterThePointerEnters() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(299))
        #expect(!hover.isExpanded && clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        #expect(await waitForObserved("expanded") { hover.isExpanded })
    }

    @Test func itCollapses500MillisecondsAfterThePointerLeaves() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.expandDelay)
        await waitForObserved("expanded") { hover.isExpanded }
        hover.pointer(inside: false)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(499))
        #expect(hover.isExpanded && clock.sleeperCount == 1)
        clock.advance(by: .milliseconds(1))
        #expect(await waitForObserved("collapsed") { !hover.isExpanded })
    }

    @Test func comingBackBeforeTheCollapseKeepsItOpen() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.expandDelay)
        await waitForObserved("expanded") { hover.isExpanded }
        hover.pointer(inside: false)
        await clock.waitForSleepers(1)
        hover.pointer(inside: true)
        await clock.waitForCancelledSleeps(1)
        clock.advance(by: .seconds(5))
        #expect(hover.isExpanded && clock.sleeperCount == 0)
    }

    @Test func passingOverThePillForLessThanTheDelayNeverExpandsIt() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(200))
        hover.pointer(inside: false)
        await clock.waitForCancelledSleeps(1)
        clock.advance(by: .seconds(5))
        #expect(!hover.isExpanded && clock.sleeperCount == 0)
    }

    @Test func keyboardFocusOnAButtonExpandsAtOnceAndKeepsItOpen() async {
        let (hover, clock) = model()
        hover.keyboardFocus(true)
        #expect(hover.isExpanded && clock.sleeperCount == 0)
        hover.pointer(inside: true)
        hover.pointer(inside: false)
        clock.advance(by: .seconds(5))
        #expect(hover.isExpanded)
        hover.keyboardFocus(false)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.collapseDelay)
        #expect(await waitForObserved("collapsed") { !hover.isExpanded })
    }

    @Test func resetCollapsesAtOnceAndForgetsThePointer() async {
        let (hover, clock) = model()
        hover.keyboardFocus(true)
        hover.reset()
        #expect(!hover.isExpanded && !hover.pointerInside && !hover.keyboardFocus && clock.sleeperCount == 0)
    }

    /// The pointer really is on the pill when the content changes: `reset()` must forget it, so the next move over the
    /// pill is a new entry that starts the delay again (a pill that appears under the pointer expands only after the
    /// pointer moves).
    @Test func resetForgetsAPointerThatWasOnThePillSoTheNextMoveStartsTheDelayAgain() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.expandDelay)
        await waitForObserved("expanded") { hover.isExpanded }
        #expect(hover.pointerInside)
        hover.reset()
        #expect(!hover.pointerInside && !hover.isExpanded && clock.sleeperCount == 0)
        // The pointer has not moved: nothing expands by itself.
        clock.advance(by: .seconds(5))
        #expect(!hover.isExpanded)
        // It moves over the pill: a new entry, a new 300 ms.
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(299))
        #expect(!hover.isExpanded)
        clock.advance(by: .milliseconds(1))
        #expect(await waitForObserved("expanded again") { hover.isExpanded })
    }

    /// While the pointer is on the pill a reset in the middle of the delay does not leave a stale timer behind.
    @Test func resetDuringTheDelayCancelsIt() async {
        let (hover, clock) = model()
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        hover.reset()
        await clock.waitForCancelledSleeps(1)
        clock.advance(by: .seconds(5))
        #expect(!hover.isExpanded)
    }

    @Test func theEventsAreReportedInOrder() async {
        let (hover, clock) = model()
        var events: [PillHoverEvent] = []
        hover.onEvent = { events.append($0) }
        hover.pointer(inside: true)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.expandDelay)
        await waitForObserved("expanded") { hover.isExpanded }
        hover.pointer(inside: false)
        await clock.waitForSleepers(1)
        clock.advance(by: PillHoverModel.collapseDelay)
        await waitForObserved("collapsed") { !hover.isExpanded }
        #expect(events == [.pointerEntered, .expanded, .pointerExited, .collapsed])
    }

    @Test func theDelaysAreTheSpecs() {
        #expect(PillHoverModel.expandDelay == .milliseconds(300))
        #expect(PillHoverModel.collapseDelay == .milliseconds(500))
    }

    /// R3: the panels are non-activating and Lintel is usually in the background, so the tracking area must be
    /// active whatever app is active, and follow the visible rect.
    @Test func theHostTracksThePointerWhateverAppIsActive() {
        let options = PillHoverHost<EmptyViewForTests>.trackingOptions
        #expect(options.contains(.activeAlways))
        #expect(options.contains(.mouseEnteredAndExited))
        #expect(options.contains(.inVisibleRect))
        #expect(options.contains(.mouseMoved))
    }
}

/// Where the pointer counts as on the pill: only inside the pill's frame, never in the transparent rest of the panel.
/// The pill reports its frame in SwiftUI's top-left coordinates, so the host flips the point of a view that is not
/// flipped.
@MainActor
@Suite struct PillHoverHostTests {
    private static let panel = CGRect(origin: .zero, size: PillMetrics.panelSize)
    /// An asymmetric frame (not centred vertically), so a missing or doubled flip shows.
    private static let pill = CGRect(x: 200, y: 2, width: 180, height: 32)

    @Test func onlyThePillsFrameCountsNotTheTransparentRestOfThePanel() {
        func on(_ point: CGPoint, flipped: Bool) -> Bool {
            PillHoverHost<EmptyViewForTests>.isOnPill(
                point, pillFrame: Self.pill, bounds: Self.panel, isFlipped: flipped)
        }
        // Flipped: the point is already top-left (the pill spans 2 to 34 from the top).
        #expect(on(CGPoint(x: 290, y: 10), flipped: true))
        #expect(!on(CGPoint(x: 50, y: 10), flipped: true), "left of the pill, inside the panel")
        #expect(!on(CGPoint(x: 290, y: 46), flipped: true), "below the pill, inside the panel")
        // Not flipped: y measures from the bottom (the panel is 56 high).
        #expect(on(CGPoint(x: 290, y: 56 - 10), flipped: false))
        #expect(!on(CGPoint(x: 290, y: 10), flipped: false), "the mirror image of a point on the pill is off it")
        #expect(!on(CGPoint(x: 50, y: 56 - 10), flipped: false))
    }

    @Test func beforeThePillHasReportedItsFrameTheWholeViewCounts() {
        func on(_ point: CGPoint) -> Bool {
            PillHoverHost<EmptyViewForTests>.isOnPill(point, pillFrame: .zero, bounds: Self.panel, isFlipped: true)
        }
        #expect(on(CGPoint(x: 10, y: 10)))
        #expect(!on(CGPoint(x: 700, y: 10)))
    }

    /// The same through the host and its hover model: a pointer in the transparent part does not start the delay.
    @Test func theHostPassesThePointerToTheModelOnlyOverThePill() async {
        let clock = TestClock()
        let hover = PillHoverModel(sleep: clock.sleeper)
        let host = PillHoverHost(rootView: EmptyViewForTests(), hover: hover)
        host.frame = Self.panel
        hover.pillFrame = Self.pill
        // A point inside the pill in the host's own coordinates, whether or not the host is flipped.
        let inside = host.isFlipped ? CGPoint(x: 290, y: 10) : CGPoint(x: 290, y: 56 - 10)
        let outside = CGPoint(x: 50, y: inside.y)
        host.track(at: outside)
        #expect(!hover.pointerInside && clock.sleeperCount == 0)
        host.track(at: inside)
        #expect(hover.pointerInside)
        await clock.waitForSleepers(1)
        host.track(at: outside)
        #expect(!hover.pointerInside)
    }
}

struct EmptyViewForTests: View {
    var body: some View { EmptyView() }
}
