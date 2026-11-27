#if DEBUG
import AppKit
import LintelSpeech
import LintelUI
import SwiftUI

/// DEBUG only, `--qa-hud dictation:<state>` (`plugins.dictation.qaHUD`): draws the real `DictationHUDView` in the given
/// state in a QA panel, without a microphone, a model or any permission, so `--qa-snapshot` can write it to a file.
/// The panel has the identifier the shell looks for (`QAHUDRequest.identifier`). Not a contract.
@MainActor
final class DictationHUDQA {
    static let settingName = "qaHUD"
    static let panelIdentifier = "lintel.qa.hud"
    /// `plugins.dictation.qaHUDHover` (DEBUG): the pill is drawn in its hover state.
    static let hoverSettingName = "qaHUDHover"
    /// `plugins.dictation.qaHUDReduceMotion` (DEBUG): the pill in its Reduce Motion look.
    static let reduceMotionSettingName = "qaHUDReduceMotion"

    /// A state to draw. `lineCollapsed` is the replaced-microphone line after its 3 s (the amber dot only), set directly
    /// in the model: a fixture never waits for a timer.
    struct Fixture {
        let name: String
        let state: HUDState
        var lineCollapsed = false
    }

    private static let usb = InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")

    /// Every state name `--qa-hud dictation:<name>` accepts.
    static let states: [Fixture] = [
        Fixture(name: "allow-microphone", state: .allowMicrophone),
        Fixture(name: "recording", state: .recording(.init(level: 0.6))),
        Fixture(name: "recording-escape-unclaimed", state: .recording(.init(level: 0.6, escapeCancels: false))),
        Fixture(name: "recording-microphone-fallback", state: .recording(.init(level: 0.6, fallback: usb))),
        Fixture(
            name: "recording-microphone-fallback-unnamed",
            state: .recording(
                .init(level: 0.6, fallback: InputFallback(requestedName: "USB MICROPHONE", usingName: nil)))),
        Fixture(
            name: "recording-microphone-fallback-collapsed",
            state: .recording(.init(level: 0.6, fallback: usb)), lineCollapsed: true),
        Fixture(name: "loading-model", state: .recording(.init(level: 0.6, loadingModel: true))),
        Fixture(name: "countdown", state: .recording(.init(level: 0.4, secondsLeft: 10))),
        Fixture(name: "finishing", state: .finishing),
        Fixture(name: "pasted", state: .pasted),
        Fixture(name: "pasted-unformatted", state: .pastedUnformatted(all: true)),
        Fixture(name: "pasted-partly-unformatted", state: .pastedUnformatted(all: false)),
        Fixture(name: "copied-no-accessibility", state: .copied(.noAccessibility)),
        Fixture(name: "copied", state: .copied(.targetGone)),
        Fixture(name: "model-missing", state: .problem(.modelMissing)),
        Fixture(name: "model-unavailable", state: .problem(.modelUnavailable)),
        Fixture(name: "model-failed", state: .problem(.modelFailedToLoad)),
        Fixture(name: "speech-model-busy", state: .problem(.speechModelBusy)),
        Fixture(name: "microphone-denied", state: .problem(.microphoneDenied)),
        Fixture(name: "no-microphone", state: .problem(.noMicrophone)),
        Fixture(name: "nothing-heard", state: .problem(.nothingHeard)),
        Fixture(name: "nothing-to-paste", state: .problem(.nothingToPaste)),
    ]

    static func state(named name: String) -> HUDState? { fixture(named: name)?.state }

    static func fixture(named name: String) -> Fixture? { states.first { $0.name == name } }

    private let model = HUDModel()
    private var panel: NSPanel?

    /// Puts `model` in the state of `fixture`. No fixture depends on a timer: the 3 s line's own timer is off (a
    /// collapsed fixture is set directly) and the hover is the settled one (`hover`) or the real pointer's
    /// (`PillHoverHost`). `reduceMotion` is the Reduce Motion look; otherwise the normal look frozen at one frame, so a
    /// snapshot is the same every run.
    static func configure(_ model: HUDModel, fixture: Fixture, hover: Bool, reduceMotion: Bool) {
        model.lineTimerEnabled = false
        model.motion = reduceMotion ? .reduced : .frozen
        model.apply(fixture.state)
        model.microphoneLineVisible = !fixture.lineCollapsed
        // A fixed running time, so a snapshot is the same every run.
        model.qaElapsed = fixture.state.offersCancel ? 83 : nil
        model.hover.settle(expanded: hover)
    }

    /// Shows the state; `false` for a name this HUD does not have. `hover` draws the pill in its hover state
    /// (`plugins.dictation.qaHUDHover`); `reduceMotion` its Reduce Motion look (`plugins.dictation.qaHUDReduceMotion`).
    @discardableResult
    func show(named name: String, hover: Bool = false, reduceMotion: Bool = false) -> Bool {
        guard let fixture = Self.fixture(named: name) else { return false }
        Self.configure(model, fixture: fixture, hover: hover, reduceMotion: reduceMotion)
        let panel = panel ?? makePanel()
        self.panel = panel
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(
                HUDPlacement.origin(
                    visibleFrame: frame, panelSize: panel.frame.size,
                    pillHeight: PillMetrics.height(AppTextSize.current())))
        }
        panel.orderFrontRegardless()
        return true
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: DictationHUDView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.identifier = NSUserInterfaceItemIdentifier(Self.panelIdentifier)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        // The panel is transparent like the real one. Only `cacheDisplay` (the `--qa-snapshot` PNG) gets a backdrop,
        // cut to the pill (its frame, which the hover model keeps), because it does not draw the glass. A state with
        // no pill has no backdrop either.
        let hover = model.hover
        let host = PillHoverHost(rootView: DictationHUDView(model: model), hover: hover)
        host.backdropShape = { [weak host] bounds in
            let frame = hover.pillFrame
            guard !frame.isEmpty else { return NSBezierPath() }
            let flipped = host?.isFlipped ?? true
            let rect = NSRect(
                x: frame.minX, y: flipped ? frame.minY : bounds.height - frame.maxY, width: frame.width,
                height: frame.height)
            return SnapshotBackdropHostingView<DictationHUDView>.roundedPath(rect, radius: rect.height / 2)
        }
        panel.contentView = host
        return panel
    }
}
#endif
