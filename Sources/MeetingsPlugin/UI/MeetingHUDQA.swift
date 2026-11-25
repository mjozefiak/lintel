#if DEBUG
import AppKit
import LintelUI
import SwiftUI

/// DEBUG only, `--qa-hud meeting:<state>` (`plugins.meetings.qaHUD`): draws the real `MeetingHUDView` in the given
/// state in a QA panel, without a microphone, system audio, a model or any permission, so `--qa-snapshot` can write
/// it to a file. The panel has the identifier the shell looks for (`QAHUDRequest.identifier`). Not a contract.
@MainActor
final class MeetingHUDQA {
    static let settingName = "qaHUD"
    static let panelIdentifier = "lintel.qa.hud"

    private static func recording(_ change: (inout MeetingHUDState.Recording) -> Void = { _ in })
        -> MeetingHUDState
    {
        var value = MeetingHUDState.Recording(elapsedSeconds: 754, micLevel: 0.55, systemLevel: 0.35)
        change(&value)
        return .recording(value)
    }

    /// Every state name `--qa-hud meeting:<name>` accepts.
    static let states: [(name: String, state: MeetingHUDState)] = [
        ("allow-microphone", .allowMicrophone),
        ("recording", recording()),
        ("recording-consent", recording { $0.showsConsent = true }),
        ("recording-loading-model", recording { $0.loadingModel = true }),
        ("recording-model-unavailable", recording { $0.modelUnavailable = false }),
        ("recording-countdown", recording { $0.secondsLeft = 120 }),
        ("recording-no-system-audio", recording { $0.noSystemAudio = true }),
        ("recording-no-microphone-audio", recording { $0.noMicrophoneAudio = true }),
        ("recording-low-disk", recording { $0.lowDisk = true }),
        ("recording-write-problem", recording { $0.writeProblem = true }),
        ("recording-device-disconnected", recording { $0.lost = [.mic] }),
        ("recording-microphone-not-recorded", recording { $0.unavailable = [.mic] }),
        (
            "recording-microphone-retrying",
            recording {
                $0.unavailable = [.mic]
                $0.retryingMicrophone = true
            }
        ),
        ("recording-system-audio-lost", recording { $0.lost = [.system] }),
        ("recording-microphone-only", recording { $0.recordsSystem = false }),
        ("finishing", .finishing),
        ("processing-transcribing", .processing(.transcribing(remaining: 12))),
        ("processing-speakers", .processing(.recognisingSpeakers)),
        ("processing-closing", .processing(.closing)),
        ("saved", .saved),
        ("saved-incomplete", .savedIncomplete),
        ("model-missing", .problem(.modelMissing)),
        ("model-unavailable", .problem(.modelUnavailable)),
        ("library-unavailable", .problem(.libraryUnavailable)),
        ("microphone-denied", .problem(.microphoneDenied(offersSystemOnly: false))),
        ("microphone-denied-system-only", .problem(.microphoneDenied(offersSystemOnly: true))),
        ("no-audio-input", .problem(.noAudioInput)),
        ("low-disk-at-start", .problem(.lowDiskAtStart)),
        ("still-processing", .problem(.stillProcessing)),
        ("model-being-removed", .problem(.modelBeingRemoved)),
        ("nothing-heard", .problem(.nothingHeard)),
        ("could-not-start", .problem(.couldNotStart)),
        ("failed", .problem(.failed)),
    ]

    static func state(named name: String) -> MeetingHUDState? { states.first { $0.name == name }?.state }

    /// The suggestion pill ("Looks like a meeting in …", "End the recording?") with a fixture app name, so QA can
    /// look at it without a call app that uses the microphone. `--qa-hud meeting:suggestion-meeting`.
    static let suggestions: [(name: String, prompt: SuggestionPrompt)] = [
        ("suggestion-meeting", .meeting(bundleID: "com.google.Chrome", appName: "Google Chrome")),
        ("suggestion-end-recording", .endRecording(appName: "Google Chrome")),
    ]

    static func suggestion(named name: String) -> SuggestionPrompt? { suggestions.first { $0.name == name }?.prompt }

    private let model = MeetingHUDModel()
    private let suggestionModel = SuggestionHUDModel()
    private var panel: NSPanel?

    /// Shows the state; `false` for a name this HUD does not have.
    @discardableResult
    func show(named name: String) -> Bool {
        if let prompt = Self.suggestion(named: name) { return showSuggestion(prompt) }
        guard let state = Self.state(named: name) else { return false }
        model.reducesMotion = true
        model.state = state
        let height: CGFloat = state.hasDetailLine ? 68 : 44
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.setContentSize(NSSize(width: 400, height: height))
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - 200, y: frame.maxY - height - 8))
        }
        panel.orderFrontRegardless()
        return true
    }

    private func showSuggestion(_ prompt: SuggestionPrompt) -> Bool {
        suggestionModel.reducesMotion = true
        suggestionModel.prompt = prompt
        let size = NSSize(width: 440, height: 78)
        let panel = panel ?? makeSuggestionPanel(size)
        self.panel = panel
        panel.setContentSize(size)
        if let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 8))
        }
        panel.orderFrontRegardless()
        return true
    }

    private func makeSuggestionPanel(_ size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.identifier = NSUserInterfaceItemIdentifier(Self.panelIdentifier)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        let host = SnapshotBackdropHostingView(rootView: SuggestionHUDView(model: suggestionModel))
        host.backdropShape = { SnapshotBackdropHostingView<SuggestionHUDView>.roundedPath($0, radius: 22) }
        panel.contentView = host
        return panel
    }

    func hide() { panel?.orderOut(nil) }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 44),
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
        // cut to the glass's rounded rectangle, because it does not draw the glass.
        let host = SnapshotBackdropHostingView(rootView: MeetingHUDView(model: model))
        host.backdropShape = {
            SnapshotBackdropHostingView<MeetingHUDView>.roundedPath($0, radius: MeetingHUDView.cornerRadius)
        }
        panel.contentView = host
        return panel
    }
}
#endif
