import AppKit
import LintelSpeech
import LintelUI
import Observation
import SwiftUI

/// Shows the HUD. The window in the app, a recording fake in tests.
@MainActor
protocol HUDPresenter: AnyObject {
    func show(_ state: HUDState)
    func hide()
}

/// Decides which states VoiceOver hears. The HUD is shown again for every level update while recording, so
/// an announcement is made only when its text differs from the last one spoken.
struct AnnouncementGate {
    private var last: String?

    mutating func announce(_ state: HUDState) -> String? {
        guard let text = state.announcement, text != last else { return nil }
        last = text
        return text
    }

    mutating func reset() {
        last = nil
    }
}

/// The state the HUD's view reads: the dictation state, the pill's hover (spec `2026-11-25-minimal-hud`, "Hover") and
/// the 3 s window of the replaced-microphone line (OD-11). The timers are the model's, not the controller's: the
/// controller only reports states.
@MainActor @Observable
final class HUDModel {
    /// How long the line "Using <microphone>" stays before only the amber dot is left (OD-11, dictation: 3 s).
    static let microphoneLineDuration: Duration = .seconds(3)

    var state = HUDState.finishing
    /// When the recording began, for the running time.
    var recordingStartedAt: Date?
    /// The 3 s line collapses by itself. QA fixtures switch it off: they set the collapsed state directly, so no
    /// fixture changes while a snapshot is taken.
    @ObservationIgnored var lineTimerEnabled = true
    /// How the pill moves: the system's Reduce Motion (the panel reads it on every state) or, for QA, a fixed look.
    var motion: LintelRingMotion = .system
    /// The replaced-microphone line is shown (the first 3 s) or collapsed to the amber dot.
    var microphoneLineVisible = true
    #if DEBUG
    /// QA only: a fixed running time, so a snapshot is the same every run.
    var qaElapsed: Int?
    #endif
    @ObservationIgnored let hover: PillHoverModel
    @ObservationIgnored var onCancel: () -> Void = {}
    @ObservationIgnored var onOpenSettings: () -> Void = {}
    /// The model problems' button: `PluginContext.openModels` for the speech model.
    @ObservationIgnored var onOpenModels: () -> Void = {}
    /// "Allow" on a copy that could not be pasted: the Accessibility privacy pane.
    @ObservationIgnored var onOpenAccessibility: () -> Void = {}

    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var lineTask: Task<Void, Never>?
    @ObservationIgnored private var lineFallback: InputFallback?

    /// - Parameter sleep: the time of the hover (300 / 500 ms) and of the 3 s line; a test passes a manual clock's.
    init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
        hover = PillHoverModel(sleep: sleep)
    }

    /// Shows `new`. A change of state (not a level update inside one recording) collapses the hover, so a pill that
    /// appears under the pointer does not expand until the pointer moves.
    func apply(_ new: HUDState) {
        if !(state.offersCancel && new.offersCancel) { hover.reset() }
        state = new
        followMicrophoneLine(of: new)
    }

    /// The panel went away: forget the hover and the line's timer.
    func clear() {
        hover.reset()
        lineTask?.cancel()
        lineTask = nil
        lineFallback = nil
        microphoneLineVisible = true
    }

    /// A button of the pill was pressed (or its accessibility action ran).
    func perform(_ id: String) {
        switch id {
        case HUDPillAction.cancel: onCancel()
        case HUDPillAction.openSettings: onOpenSettings()
        case HUDPillAction.openModels: onOpenModels()
        case HUDPillAction.allowAccessibility: onOpenAccessibility()
        default: break
        }
    }

    /// The line starts when a recording gets (or changes) its fallback, not on every level update.
    private func followMicrophoneLine(of state: HUDState) {
        var fallback: InputFallback?
        if case .recording(let recording) = state { fallback = recording.fallback }
        guard fallback != lineFallback else { return }
        lineFallback = fallback
        lineTask?.cancel()
        lineTask = nil
        microphoneLineVisible = true
        guard fallback != nil else { return }
        guard lineTimerEnabled else { return }
        let sleep = self.sleep
        lineTask = Task { [weak self] in
            do { try await sleep(Self.microphoneLineDuration) } catch { return }
            guard !Task.isCancelled else { return }
            self?.microphoneLineVisible = false
        }
    }
}

/// Where the panel goes: the pill's bottom edge 48 pt above the visible frame's bottom edge (spec "The pill family":
/// the distances are the pill's, not the panel's), so the 56 pt tall transparent panel sits (56 − pill height) / 2
/// lower than its own bottom would.
enum HUDPlacement {
    static let bottomInset: CGFloat = 48

    static func origin(visibleFrame: CGRect, panelSize: CGSize, pillHeight: CGFloat) -> CGPoint {
        CGPoint(
            x: visibleFrame.midX - panelSize.width / 2,
            y: visibleFrame.minY + bottomInset - (panelSize.height - pillHeight) / 2)
    }
}

/// A small pill at the bottom of the screen with the mouse cursor. A non-activating panel: it never takes the focus
/// from the app the user is dictating into. The panel is a fixed transparent 580 × 56 pt frame with the pill centred in
/// it; only the pill's pixels take the mouse (the hover and its buttons), the rest passes clicks through.
@MainActor
final class DictationHUDPanel: HUDPresenter {
    private let model = HUDModel()
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?
    private var announcements = AnnouncementGate()
    private let reducesMotion: () -> Bool

    init(
        onCancel: @escaping () -> Void, onOpenSettings: @escaping () -> Void,
        onOpenModels: @escaping () -> Void = {}, onOpenAccessibility: @escaping () -> Void = {},
        reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.reducesMotion = reducesMotion
        model.onCancel = onCancel
        model.onOpenSettings = onOpenSettings
        model.onOpenModels = onOpenModels
        model.onOpenAccessibility = onOpenAccessibility
    }

    func show(_ state: HUDState) {
        hideTask?.cancel()
        hideTask = nil
        let wasRecording = model.state.offersCancel
        model.motion = reducesMotion() ? .reduced : .system
        if state.offersCancel, !wasRecording || model.recordingStartedAt == nil {
            model.recordingStartedAt = Date()
        }
        model.apply(state)
        // A state with no pill (a partial cleanup, OD-4) shows nothing.
        guard state.pill() != nil else { return hide() }
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
        if let announcement = announcements.announce(state) {
            announce(announcement, from: panel)
        }
        if let delay = state.hidesAfter {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        model.recordingStartedAt = nil
        model.clear()
        announcements.reset()
        panel?.orderOut(nil)
    }

    /// Whether the window was built. It is built lazily on the first state that has a pill and never for a state
    /// without one (a partial cleanup, OD-4), so a test can check that the second never shows an empty panel.
    var hasPanel: Bool { panel != nil }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: DictationHUDView.panelSize),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = PillHoverHost(rootView: DictationHUDView(model: model), hover: model.hover)
        return panel
    }

    /// Bottom centre of the screen the mouse is on.
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let origin = HUDPlacement.origin(
            visibleFrame: frame, panelSize: panel.frame.size, pillHeight: PillMetrics.height(AppTextSize.current()))
        panel.setFrameOrigin(origin)
    }

    private func announce(_ text: String, from panel: NSPanel) {
        NSAccessibility.post(
            element: panel, notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: text,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high.rawValue,
            ])
    }
}

struct DictationHUDView: View {
    /// The panel: a fixed transparent frame larger than the widest hovered pill (`PillMetrics.panelSize`).
    static let panelSize = PillMetrics.panelSize

    let model: HUDModel

    var body: some View {
        LintelTextSizeScope(size: AppTextSize.current) {
            if model.state.offersCancel, let started = model.recordingStartedAt {
                // The running time is on hover and in the VoiceOver label, so the view redraws each second while
                // recording and never otherwise.
                TimelineView(.periodic(from: started, by: 1)) { context in
                    pill(elapsed: Int(context.date.timeIntervalSince(started)))
                }
            } else {
                pill(elapsed: 0)
            }
        }
    }

    @ViewBuilder private func pill(elapsed: Int) -> some View {
        #if DEBUG
        let elapsed = model.qaElapsed ?? elapsed
        #endif
        if let content = model.state.pill(elapsed: elapsed, microphoneLineVisible: model.microphoneLineVisible) {
            PillHoverRoot(content, hover: model.hover, onAction: { model.perform($0) })
                .environment(\.lintelRingMotion, model.motion)
        }
    }
}
