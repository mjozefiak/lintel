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

    /// Every state name `--qa-hud dictation:<name>` accepts.
    static let states: [(name: String, state: HUDState)] = [
        ("allow-microphone", .allowMicrophone),
        ("recording", .recording(.init(level: 0.6))),
        (
            "recording-microphone-fallback",
            .recording(
                .init(
                    level: 0.6,
                    fallback: InputFallback(requestedName: "USB MICROPHONE", usingName: "MacBook Pro Microphone")))
        ),
        ("loading-model", .recording(.init(level: 0, loadingModel: true))),
        ("countdown", .recording(.init(level: 0.4, secondsLeft: 10))),
        ("finishing", .finishing),
        ("pasted", .pasted),
        ("pasted-unformatted", .pastedUnformatted(all: true)),
        ("pasted-partly-unformatted", .pastedUnformatted(all: false)),
        ("provider-too-slow", .pastedAsSpoken(.init(.tooSlow, name: "Claude"))),
        ("provider-signed-out", .pastedAsSpoken(.init(.notSignedIn, name: "Claude"))),
        ("provider-limit", .pastedAsSpoken(.init(.rateLimited, name: "Claude"))),
        ("provider-no-network", .pastedAsSpoken(.init(.network, name: "Claude"))),
        ("provider-unavailable", .pastedAsSpoken(.init(.unavailable, name: "Claude"))),
        ("copied-no-accessibility", .copied(.noAccessibility)),
        ("copied", .copied(.targetGone)),
        ("model-missing", .problem(.modelMissing)),
        ("model-unavailable", .problem(.modelUnavailable)),
        ("model-failed", .problem(.modelFailedToLoad)),
        ("speech-model-busy", .problem(.speechModelBusy)),
        ("microphone-denied", .problem(.microphoneDenied)),
        ("no-microphone", .problem(.noMicrophone)),
        ("nothing-heard", .problem(.nothingHeard)),
        ("nothing-to-paste", .problem(.nothingToPaste)),
    ]

    static func state(named name: String) -> HUDState? { states.first { $0.name == name }?.state }

    private let model = HUDModel()
    private var panel: NSPanel?

    /// Shows the state; `false` for a name this HUD does not have.
    @discardableResult
    func show(named name: String) -> Bool {
        guard let state = Self.state(named: name) else { return false }
        model.reducesMotion = true
        model.state = state
        // A fixed running time, so a snapshot is the same every run.
        model.recordingStartedAt = state.offersCancel ? Date().addingTimeInterval(-83) : nil
        let panel = panel ?? makePanel()
        self.panel = panel
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - DictationHUDView.panelSize.width / 2, y: frame.minY + 48))
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
        // cut to the capsule, because it does not draw the glass.
        let host = SnapshotBackdropHostingView(rootView: DictationHUDView(model: model))
        let model = model
        host.backdropShape = { bounds in
            let size = DictationHUDView.size
            let width = DictationHUDView.capsuleWidth(for: model.state)
            let capsule = NSRect(
                x: bounds.midX - width / 2, y: DictationHUDView.bottomInset,
                width: width, height: size.height)
            return SnapshotBackdropHostingView<DictationHUDView>.roundedPath(capsule, radius: size.height / 2)
        }
        panel.contentView = host
        return panel
    }
}
#endif
