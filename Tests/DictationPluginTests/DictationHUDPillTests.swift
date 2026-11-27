import AppKit
import Foundation
import LintelSpeech
import LintelTestSupport
import LintelUI
import SwiftUI
import Testing

@testable import DictationPlugin

/// The dictation HUD on `LintelPill` (spec `2026-11-25-minimal-hud`, Phase 2): what each `HUDState` maps to, what is
/// hover-only, the 3 s microphone line and where the panel goes. No window, no microphone, no sound.
@MainActor @Suite struct DictationHUDPillTests {
    private let usb = InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")

    private func pill(_ state: HUDState, elapsed: Int = 12, lineVisible: Bool = true) throws -> PillContent {
        try #require(state.pill(elapsed: elapsed, microphoneLineVisible: lineVisible))
    }

    // MARK: Recording

    @Test func recordingIsTheRingAndTheWaveAndNothingElse() throws {
        let content = try pill(.recording(.init(level: 0.6)))
        #expect(content.glyph == .live(dot: false))
        #expect(content.live == [.wave(level: Double(Float(0.6)))])
        #expect(content.text == nil && content.action == nil && content.stop == nil)
        #expect(!content.badge)
        #expect(content.variant == .live)
    }

    @Test func theTimeAndTheCloseAreOnHoverOnly() throws {
        let content = try pill(.recording(.init()))
        #expect(content.hoverText == "0:12")
        #expect(content.close?.visibility == .onHover)
        #expect(!content.showsClose(expanded: false))
        #expect(content.showsClose(expanded: true))
        #expect(content.hasHoverContent)
    }

    @Test func theCloseIsAlwaysThereWhenEscapeCouldNotBeClaimed() throws {
        for recording in [
            HUDState.Recording(escapeCancels: false), .init(secondsLeft: 9, escapeCancels: false),
            .init(escapeCancels: false, fallback: usb), .init(loadingModel: true, escapeCancels: false),
        ] {
            let content = try pill(.recording(recording))
            #expect(content.close?.visibility == .always)
            #expect(content.showsClose(expanded: false))
        }
        #expect(try pill(.recording(.init(escapeCancels: true))).close?.visibility == .onHover)
    }

    @Test func loadingTheModelIsTheSamePillAsRecording() throws {
        for elapsed in [0, 12] {
            for visible in [true, false] {
                #expect(
                    try pill(.recording(.init(level: 0.6, loadingModel: true)), elapsed: elapsed, lineVisible: visible)
                        == pill(.recording(.init(level: 0.6)), elapsed: elapsed, lineVisible: visible))
            }
        }
        let withFallback = HUDState.Recording(level: 0.2, fallback: usb)
        var loading = withFallback
        loading.loadingModel = true
        #expect(try pill(.recording(loading)) == pill(.recording(withFallback)))
    }

    @Test func theCountdownIsTheWavePlusTheAmberSecondsAndNeverCollapses() throws {
        let content = try pill(.recording(.init(level: 0.4, secondsLeft: 9)))
        #expect(content.live == [.wave(level: Double(Float(0.4))), .clock("9", amber: true)])
        // Not a line: the amber dot is for the microphone only.
        #expect(!content.badge && content.text == nil)
        #expect(content.accessibilityLabel.contains("Stops in 9 s"))
        #expect(
            try pill(.recording(.init(level: 0.4, secondsLeft: 9)), lineVisible: false)
                == pill(.recording(.init(level: 0.4, secondsLeft: 9)), lineVisible: true))
    }

    @Test func aReplacedMicrophoneShowsItsNameThenOnlyTheAmberDot() throws {
        let line = try pill(.recording(.init(fallback: usb)), lineVisible: true)
        #expect(line.text == "Using MacBook Pro Microphone")
        #expect(line.truncation == .middle)
        #expect(line.badge)
        let collapsed = try pill(.recording(.init(fallback: usb)), lineVisible: false)
        #expect(collapsed.text == nil)
        #expect(collapsed.badge)
        // Hover and VoiceOver give the line again.
        #expect(collapsed.hoverText == "0:12 · Using MacBook Pro Microphone")
        #expect(collapsed.accessibilityLabel.contains("USB MICROPHONE"))
        #expect(collapsed.accessibilityLabel.contains("MacBook Pro Microphone"))
    }

    @Test func aMicrophoneWithoutANameIsTheDefaultMic() throws {
        let fallback = InputFallback(requestedName: "USB MICROPHONE", usingName: nil)
        #expect(fallback.pillLine == "Using the default mic")
        #expect(try pill(.recording(.init(fallback: fallback))).text == "Using the default mic")
        #expect(usb.pillLine == "Using MacBook Pro Microphone")
        // The missing device is never in the pill's line, only in the VoiceOver text.
        #expect(!usb.pillLine.contains("USB"))
    }

    @Test func aRecordingWithoutAFallbackHasNoDotAndNoLine() throws {
        let content = try pill(.recording(.init()), lineVisible: false)
        #expect(!content.badge && content.text == nil)
        #expect(content.hoverText == "0:12")
    }

    // MARK: Accessibility

    @Test func theHoverOnlyCloseIsAnAccessibilityAction() throws {
        let content = try pill(.recording(.init()))
        #expect(content.accessibilityActions.map(\.id) == [HUDPillAction.cancel])
        #expect(content.accessibilityActions.first?.name == "Cancel dictation")
        #expect(!content.showsClose(expanded: false))
    }

    @Test func theLabelCarriesEverything() throws {
        #expect(try pill(.recording(.init())).accessibilityLabel == "Dictation, recording, 0:12. Esc cancels.")
        #expect(
            try pill(.recording(.init(escapeCancels: false))).accessibilityLabel
                == "Dictation, recording, 0:12. ✕ cancels.")
        #expect(try pill(.finishing).accessibilityLabel == "Dictation, finishing")
        #expect(try pill(.copied(.noAccessibility)).accessibilityLabel == "Copied, paste with ⌘V")
    }

    @Test func aButtonOfAMessageIsAnAccessibilityActionToo() throws {
        let cases: [(HUDState, String)] = [
            (.copied(.noAccessibility), HUDPillAction.allowAccessibility),
            (.problem(.modelMissing), HUDPillAction.openModels),
            (.problem(.modelUnavailable), HUDPillAction.openModels),
            (.problem(.modelFailedToLoad), HUDPillAction.openModels),
            (.problem(.microphoneDenied), HUDPillAction.openSettings),
        ]
        for (state, id) in cases {
            let content = try pill(state)
            #expect(content.action?.id == id)
            #expect(content.accessibilityActions.map(\.id) == [id])
        }
    }

    @Test func announcementsAreTheOnesOfBeforeWithTheNewTexts() {
        #expect(HUDState.recording(.init()).announcement == "Recording started")
        #expect(HUDState.recording(.init(loadingModel: true)).announcement == nil)
        #expect(HUDState.recording(.init(secondsLeft: 9)).announcement == nil)
        #expect(
            HUDState.recording(.init(fallback: usb)).announcement
                == "“USB MICROPHONE” unavailable – using “MacBook Pro Microphone”")
        #expect(HUDState.finishing.announcement == "Recording stopped")
        #expect(HUDState.pasted.announcement == "Pasted")
        #expect(HUDState.pastedUnformatted(all: true).announcement == "Pasted without cleanup")
        #expect(HUDState.copied(.noAccessibility).announcement == "Copied, paste with ⌘V")
        #expect(HUDState.problem(.modelUnavailable).announcement == "Speech model isn't working")
        #expect(HUDState.problem(.nothingHeard).announcement == "Nothing heard")
        #expect(HUDState.allowMicrophone.announcement == nil)
    }

    // MARK: The other states

    @Test func theOneLineStatesMapPerTheSpecTable() throws {
        struct Row {
            var state: HUDState
            var glyph: PillGlyph
            var text: String
            var action: String?
        }
        let rows = [
            Row(state: .allowMicrophone, glyph: .microphone, text: "Allow the microphone in the dialog"),
            Row(state: .pastedUnformatted(all: true), glyph: .attention, text: "Pasted without cleanup"),
            Row(
                state: .copied(.noAccessibility), glyph: .attention, text: "Copied, paste with ⌘V",
                action: "Allow"),
            Row(state: .copied(.targetGone), glyph: .attention, text: "Copied, paste with ⌘V"),
            Row(state: .copied(.secureEventInput), glyph: .attention, text: "Copied, paste with ⌘V"),
            Row(state: .problem(.modelMissing), glyph: .error, text: "No speech model", action: "Download"),
            Row(
                state: .problem(.modelUnavailable), glyph: .error, text: "Speech model isn't working", action: "Fix"),
            Row(
                state: .problem(.modelFailedToLoad), glyph: .error, text: "Speech model isn't working", action: "Fix"),
            Row(state: .problem(.speechModelBusy), glyph: .attention, text: "Dictation is back after the meeting"),
            Row(state: .problem(.microphoneDenied), glyph: .microphone, text: "No microphone access", action: "Allow"),
            Row(state: .problem(.noMicrophone), glyph: .microphone, text: "No microphone found"),
            Row(state: .problem(.nothingHeard), glyph: .attention, text: "Nothing heard"),
            Row(state: .problem(.nothingToPaste), glyph: .attention, text: "Nothing to paste yet"),
        ]
        for row in rows {
            let content = try pill(row.state)
            #expect(content.glyph == row.glyph, "\(row.state)")
            #expect(content.text == row.text, "\(row.state)")
            #expect(content.action?.title == row.action, "\(row.state)")
            #expect(content.close == nil && content.live.isEmpty && !content.hasHoverContent, "\(row.state)")
            #expect(content.accessibilityLabel == row.text, "\(row.state)")
        }
    }

    @Test func finishingIsTheClosingRingAndPastedIsAGlyphOnly() throws {
        let finishing = try pill(.finishing)
        #expect(finishing.glyph == .working(dot: false))
        #expect(finishing.variant == .working)
        let pasted = try pill(.pasted)
        #expect(pasted.glyph == .done)
        #expect(pasted.text == nil && pasted.action == nil)
    }

    @Test func aPartialCleanupShowsNothingAndSaysNothing() {
        let state = HUDState.pastedUnformatted(all: false)
        #expect(state.pill() == nil)
        #expect(state.announcement == nil)
    }

    @Test func theStatesThatEndGoAfterTheirTime() {
        #expect(HUDState.pasted.hidesAfter == .milliseconds(600))
        #expect(HUDState.pastedUnformatted(all: true).hidesAfter == .seconds(3))
        #expect(HUDState.copied(.noAccessibility).hidesAfter == .seconds(3))
        #expect(HUDState.problem(.nothingHeard).hidesAfter == .seconds(3))
        #expect(HUDState.recording(.init()).hidesAfter == nil)
        #expect(HUDState.finishing.hidesAfter == nil)
        #expect(HUDState.allowMicrophone.hidesAfter == nil)
    }

    // MARK: The model: the 3 s line, the hover, the buttons

    private func model() -> (HUDModel, TestClock) {
        let clock = TestClock()
        return (HUDModel(sleep: clock.sleeper), clock)
    }

    @Test func theMicrophoneLineGoesAfterThreeSeconds() async {
        let (model, clock) = model()
        model.apply(.recording(.init(level: 0.1, fallback: usb)))
        #expect(model.microphoneLineVisible)
        await clock.waitForSleepers(1)
        clock.advance(by: .milliseconds(2999))
        #expect(model.microphoneLineVisible)
        clock.advance(by: .milliseconds(1))
        #expect(await waitForObserved("collapsed") { !model.microphoneLineVisible })
        #expect(HUDModel.microphoneLineDuration == .seconds(3))
    }

    @Test func aLevelUpdateDoesNotRestartTheLineAndAnotherMicrophoneDoes() async {
        let (model, clock) = model()
        model.apply(.recording(.init(level: 0.1, fallback: usb)))
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(2))
        // Levels arrive about ten times a second.
        for level in stride(from: Float(0.2), to: 0.9, by: 0.1) {
            model.apply(.recording(.init(level: level, fallback: usb)))
        }
        #expect(clock.sleeperCount == 1 && clock.cancelledSleeps == 0)
        clock.advance(by: .seconds(1))
        #expect(await waitForObserved("collapsed") { !model.microphoneLineVisible })
        // A different input is a new notice: the line comes back for another 3 s.
        let other = InputFallback(requestedName: "USB MICROPHONE", usingName: "Studio Display Microphone")
        model.apply(.recording(.init(fallback: other)))
        #expect(model.microphoneLineVisible)
        await clock.waitForSleepers(1)
        clock.advance(by: .seconds(3))
        #expect(await waitForObserved("collapsed again") { !model.microphoneLineVisible })
    }

    @Test func aRecordingWithoutAFallbackStartsNoTimer() {
        let (model, clock) = model()
        model.apply(.recording(.init(level: 0.5)))
        model.apply(.finishing)
        #expect(clock.sleeperCount == 0 && clock.sleepCalls == 0)
        #expect(model.microphoneLineVisible)
    }

    @Test func leavingTheRecordingCancelsTheLineAndClearForgetsIt() async {
        let (model, clock) = model()
        model.apply(.recording(.init(fallback: usb)))
        await clock.waitForSleepers(1)
        model.apply(.finishing)
        await clock.waitForCancelledSleeps(1)
        clock.advance(by: .seconds(10))
        #expect(model.microphoneLineVisible)
        model.apply(.recording(.init(fallback: usb)))
        await clock.waitForSleepers(1)
        model.clear()
        await clock.waitForCancelledSleeps(2)
        #expect(model.microphoneLineVisible)
        #expect(clock.sleeperCount == 0)
    }

    @Test func aNewStateCollapsesTheHoverButALevelUpdateKeepsIt() {
        let (model, _) = model()
        model.apply(.recording(.init(level: 0.1)))
        model.hover.settle(expanded: true)
        model.apply(.recording(.init(level: 0.8)))
        #expect(model.hover.isExpanded)
        model.apply(.finishing)
        #expect(!model.hover.isExpanded)
        model.hover.settle(expanded: true)
        model.clear()
        #expect(!model.hover.isExpanded)
    }

    @Test func eachButtonCallsItsOwnCallback() {
        let (model, _) = model()
        var calls: [String] = []
        model.onCancel = { calls.append("cancel") }
        model.onOpenSettings = { calls.append("settings") }
        model.onOpenModels = { calls.append("models") }
        model.onOpenAccessibility = { calls.append("accessibility") }
        for id in [
            HUDPillAction.cancel, HUDPillAction.openSettings, HUDPillAction.openModels,
            HUDPillAction.allowAccessibility, "nothing",
        ] {
            model.perform(id)
        }
        #expect(calls == ["cancel", "settings", "models", "accessibility"])
    }

    @Test func everyPillButtonOfTheMappingIsOneTheModelHandles() throws {
        let handled: Set = [
            HUDPillAction.cancel, HUDPillAction.openSettings, HUDPillAction.openModels,
            HUDPillAction.allowAccessibility,
        ]
        for fixture in DictationHUDQA.states {
            guard let content = fixture.state.pill() else { continue }
            for action in content.accessibilityActions { #expect(handled.contains(action.id), "\(fixture.name)") }
        }
    }

    // MARK: QA fixtures

    @Test func aQAFixtureNeverChangesByItself() async throws {
        let (model, clock) = model()
        let fixture = try #require(DictationHUDQA.fixture(named: "recording-microphone-fallback"))
        DictationHUDQA.configure(model, fixture: fixture, hover: false, reduceMotion: false)
        #expect(model.microphoneLineVisible)
        // The fixture's line has no timer: nothing sleeps, and no time makes it collapse.
        #expect(clock.sleepCalls == 0)
        clock.advance(by: .seconds(60))
        #expect(model.microphoneLineVisible)
        // A fixture that is collapsed is collapsed from the start, whatever follows.
        let collapsed = try #require(DictationHUDQA.fixture(named: "recording-microphone-fallback-collapsed"))
        DictationHUDQA.configure(model, fixture: collapsed, hover: false, reduceMotion: false)
        #expect(!model.microphoneLineVisible)
        #expect(clock.sleepCalls == 0)
    }

    @Test func aQAFixtureShowsTheNormalLookUnlessReduceMotionIsAsked() throws {
        let (model, _) = model()
        let fixture = try #require(DictationHUDQA.fixture(named: "recording"))
        DictationHUDQA.configure(model, fixture: fixture, hover: false, reduceMotion: false)
        #expect(model.motion == .frozen)
        DictationHUDQA.configure(model, fixture: fixture, hover: false, reduceMotion: true)
        #expect(model.motion == .reduced)
    }

    @Test func theHoverFixtureSettlesTheHoverAtOnce() throws {
        let (model, clock) = model()
        let fixture = try #require(DictationHUDQA.fixture(named: "recording"))
        DictationHUDQA.configure(model, fixture: fixture, hover: true, reduceMotion: false)
        #expect(model.hover.isExpanded)
        #expect(model.qaElapsed == 83)
        #expect(clock.sleepCalls == 0)
        DictationHUDQA.configure(model, fixture: fixture, hover: false, reduceMotion: false)
        #expect(!model.hover.isExpanded)
    }

    // MARK: The panel

    @Test func thePanelIsTheFixedTransparentFrame() {
        #expect(DictationHUDView.panelSize == CGSize(width: 580, height: 56))
        #expect(DictationHUDView.panelSize == PillMetrics.panelSize)
    }

    @Test func thePillSitsFortyEightPointsAboveTheVisibleFrame() {
        let visible = CGRect(x: 100, y: 40, width: 1440, height: 800)
        for size in TextSize.allCases {
            let height = PillMetrics.height(size)
            let origin = HUDPlacement.origin(
                visibleFrame: visible, panelSize: PillMetrics.panelSize, pillHeight: height)
            // The pill is centred in the panel, so its bottom edge is (56 − height) / 2 above the panel's.
            let pillBottom = origin.y + (PillMetrics.panelSize.height - height) / 2
            #expect(pillBottom == visible.minY + 48)
            #expect(origin.x + PillMetrics.panelSize.width / 2 == visible.midX)
        }
        #expect(
            HUDPlacement.origin(visibleFrame: visible, panelSize: PillMetrics.panelSize, pillHeight: 32).y
                == visible.minY + 48 - 12)
    }

    @Test func theViewReportsThePillsFrameForEveryFixtureThatHasAPill() {
        for fixture in DictationHUDQA.states {
            let model = HUDModel()
            DictationHUDQA.configure(model, fixture: fixture, hover: false, reduceMotion: false)
            let host = PillHoverHost(rootView: DictationHUDView(model: model), hover: model.hover)
            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: DictationHUDView.panelSize), styleMask: [.borderless],
                backing: .buffered, defer: true)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let frame = model.hover.pillFrame
            if fixture.state.pill() == nil {
                #expect(frame.isEmpty, "\(fixture.name)")
            } else {
                #expect(!frame.isEmpty, "\(fixture.name)")
                #expect(frame.height == PillMetrics.height(.default), "\(fixture.name)")
                #expect(frame.width <= PillMetrics.maxWidth(.default, expanded: false), "\(fixture.name)")
            }
        }
    }
}
