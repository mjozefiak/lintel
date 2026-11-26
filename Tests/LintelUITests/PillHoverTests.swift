import AppKit
import LintelTestSupport
import SwiftUI
import Testing

@testable import LintelUI

/// When the pill expands (spec `2026-11-25-minimal-hud`, "Hover"): 300 ms after the pointer rests on it, 500 ms after
/// it leaves, at once for keyboard focus. Driven by a manual clock.
@MainActor
@Suite struct PillHoverModelTests {
    private func model() -> (PillHoverModel, TestClock) {
        let clock = TestClock()
        return (PillHoverModel(sleep: clock.sleeper), clock)
    }

    @Test func itExpands300MillisecondsAfterThePointerComesToRest() async {
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

    @Test func passingOverThePillWithoutRestingNeverExpandsIt() async {
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

struct EmptyViewForTests: View {
    var body: some View { EmptyView() }
}
