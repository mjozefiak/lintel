import AppKit
import LintelUI

/// What the controller needs from the outside, so tests give it a window list, a clock and a grant by hand and the
/// app gives it the real ones (`live`). The helper only ever reads the owner's process id, the bounds and the
/// layer of a window, through `SystemWindowList`; there is no way to ask for a title here.
struct PermissionHelperEnvironment {
    var windows: @MainActor () -> [WindowSample]
    var settingsPIDs: @MainActor () -> Set<pid_t>
    /// The displays in the top-left space of the window bounds.
    var displays: @MainActor () -> [CGRect]
    /// Lintel's own window the panel falls back to, in AppKit coordinates.
    var lintelFrame: @MainActor () -> CGRect?
    /// The height of the primary display, for the conversion between the two coordinate spaces.
    var primaryHeight: @MainActor () -> CGFloat
    /// Whether the permission has been granted by now.
    var isGranted: @MainActor () -> Bool
    var reduceMotion: @MainActor () -> Bool
    /// A monotonic reading, as the time `PermissionHelperSession` works in.
    var now: @MainActor () -> Duration
    var showInFinder: @MainActor () -> Void

    @MainActor static func live(
        isGranted: @escaping @MainActor () -> Bool, bundleURL: URL
    ) -> PermissionHelperEnvironment {
        let start = ContinuousClock.now
        return PermissionHelperEnvironment(
            windows: { SystemWindowList.windows() },
            settingsPIDs: { SystemWindowList.settingsPIDs() },
            displays: { SystemWindowList.displayFrames() },
            lintelFrame: {
                anchorWindow(
                    key: NSApp.keyWindow, main: NSApp.mainWindow, visible: NSApp.windows.filter(\.isVisible)
                )?.frame
            },
            primaryHeight: { NSScreen.screens.first?.frame.height ?? 0 },
            isGranted: isGranted,
            reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion },
            now: { start.duration(to: .now) },
            showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([bundleURL]) })
    }

    /// Lintel's own window to sit beside: the key window, else the main one, else the first visible one, keeping
    /// only titled windows that are not panels. While System Settings is the active app Lintel has no key or main
    /// window, and the status item's untitled `NSStatusBarWindow` is always visible (`DockPresence.appWindowRoles`),
    /// so without the filter the helper would sit next to the menu bar icon. A panel (the launcher, a HUD, the
    /// helper itself) is no anchor either.
    @MainActor static func anchorWindow(key: NSWindow?, main: NSWindow?, visible: [NSWindow]) -> NSWindow? {
        ([key, main].compactMap { $0 } + visible).first { $0.styleMask.contains(.titled) && !($0 is NSPanel) }
    }
}

/// The window the controller drives. `PermissionHelperPanel` is the real one; tests record what it is told.
@MainActor protocol PermissionHelperPresenting: AnyObject {
    var onShowInFinder: (() -> Void)? { get set }
    var onDone: (() -> Void)? { get set }
    /// The size the panel has for `content` at the current text size.
    func size(for content: PermissionHelperContent) -> CGSize
    /// Puts the panel on screen at `frame` (AppKit coordinates).
    func show(content: PermissionHelperContent, frame: CGRect, motion: PermissionHelperMotion)
    /// Swaps the content and puts the panel at `frame`, which the controller computed for the new content's size.
    func update(content: PermissionHelperContent, frame: CGRect)
    func move(to frame: CGRect)
    func close()
}

/// Runs one helper: it polls four times a second while the panel is open, feeds `PermissionHelperSession` what it
/// saw and draws what the session says. All the logic is in `tick()`, which is synchronous, so tests step it by
/// hand; the timer is only a loop around it.
@MainActor final class PermissionHelperController {
    static let pollInterval: Duration = .milliseconds(250)

    private let content: PermissionHelperContent
    private let environment: PermissionHelperEnvironment
    private let panel: any PermissionHelperPresenting
    private let clock: any Clock<Duration>
    private let interval: Duration
    /// Where the panel slides in from (AppKit coordinates): the Allow button the user pressed. `nil` is the
    /// centre of Lintel's window.
    private let slideOrigin: CGRect?
    private let onClose: (PermissionHelperSession.CloseReason) -> Void

    private var session: PermissionHelperSession?
    private var poll: Task<Void, Never>?
    private var isShown = false
    private var shownAllowed = false
    private var lastFrame: CGRect?
    /// The last window seen: the panel stays there while the window is gone but the 3 s grace has not run out.
    private var lastSettingsFrame: CGRect?

    /// How many times the window list was read; polling that stopped shows as a count that stays.
    private(set) var windowReads = 0

    var isOpen: Bool { session != nil && poll != nil }

    init(
        content: PermissionHelperContent, environment: PermissionHelperEnvironment,
        panel: any PermissionHelperPresenting, clock: any Clock<Duration> = ContinuousClock(),
        interval: Duration = PermissionHelperController.pollInterval, slideOrigin: CGRect? = nil,
        onClose: @escaping (PermissionHelperSession.CloseReason) -> Void = { _ in }
    ) {
        self.content = content
        self.environment = environment
        self.panel = panel
        self.clock = clock
        self.interval = interval
        self.slideOrigin = slideOrigin
        self.onClose = onClose
    }

    /// Opens the helper and starts the poll. The panel itself appears with the first reading that tells where it
    /// goes, so it never flashes at a wrong place.
    func start() {
        guard session == nil else { return }
        session = PermissionHelperSession(openedAt: environment.now())
        panel.onShowInFinder = { [environment] in environment.showInFinder() }
        panel.onDone = { [weak self] in self?.doneTapped() }
        tick()
        guard session != nil else { return }
        let clock = clock
        let interval = interval
        poll = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) } catch { return }
                guard let self else { return }
                self.tick()
            }
        }
    }

    /// One reading: Settings running, its window, the grant; then the panel follows.
    func tick() {
        guard var current = session else { return }
        let now = environment.now()
        let pids = environment.settingsPIDs()
        windowReads += 1
        let displays = environment.displays()
        let frame = SettingsWindowTracker.frame(
            in: environment.windows(), settingsPIDs: pids, displays: displays)

        current.apply(.settingsRunning(!pids.isEmpty), at: now)
        current.apply(.settingsWindow(found: frame != nil), at: now)
        if environment.isGranted() { current.apply(.granted, at: now) }
        session = current
        if finishIfClosed() { return }
        draw(current, settingsFrame: frame, displays: displays)
    }

    /// The Done button.
    func doneTapped() {
        guard var current = session else { return }
        current.apply(.doneTapped, at: environment.now())
        session = current
        _ = finishIfClosed()
    }

    /// Closes the panel and stops the poll without a reason: another helper took its place.
    func stop() {
        guard session != nil else { return }
        session = nil
        poll?.cancel()
        poll = nil
        panel.close()
    }

    private func draw(_ session: PermissionHelperSession, settingsFrame: CGRect?, displays: [CGRect]) {
        let showsAllowed = session.showsAllowed
        let shown = showsAllowed ? PermissionHelperContent.allowed : content
        // Nothing to show before the first sighting of the window (or the 3 s fallback), unless a grant is
        // already being shown: then the panel appears where it can.
        guard session.placement != .searching || showsAllowed || isShown else { return }
        let size = panel.size(for: shown)
        let primaryHeight = environment.primaryHeight()
        if let settingsFrame { lastSettingsFrame = settingsFrame }
        let target: CGRect
        if session.placement == .followingSettings, let anchor = settingsFrame ?? lastSettingsFrame {
            let frame = PermissionHelperGeometry.frame(size: size, beside: anchor, displays: displays)
            target = PermissionHelperGeometry.flipped(frame, primaryHeight: primaryHeight)
        } else {
            target = besideLintel(size: size, displays: displays, primaryHeight: primaryHeight)
        }
        if !isShown {
            isShown = true
            shownAllowed = showsAllowed
            lastFrame = target
            let from = slideOrigin ?? environment.lintelFrame()
            let origin = from.map { start in
                CGRect(
                    x: start.midX - size.width / 2, y: start.midY - size.height / 2, width: size.width,
                    height: size.height)
            }
            panel.show(
                content: shown, frame: target,
                motion: .choose(reduceMotion: environment.reduceMotion(), origin: origin))
            return
        }
        if showsAllowed != shownAllowed {
            // One call puts the new content at the frame computed for its size, so the panel does not resize
            // in one place and move in another.
            shownAllowed = showsAllowed
            lastFrame = target
            panel.update(content: shown, frame: target)
            return
        }
        if lastFrame != target {
            lastFrame = target
            panel.move(to: target)
        }
    }

    private func besideLintel(size: CGSize, displays: [CGRect], primaryHeight: CGFloat) -> CGRect {
        let cg: CGRect
        if let lintel = environment.lintelFrame() {
            cg = PermissionHelperGeometry.frame(
                size: size, beside: PermissionHelperGeometry.flipped(lintel, primaryHeight: primaryHeight),
                displays: displays)
        } else {
            cg = PermissionHelperGeometry.cornerFrame(size: size, displays: displays)
        }
        return PermissionHelperGeometry.flipped(cg, primaryHeight: primaryHeight)
    }

    /// Closes the panel and reports when the session ended. Returns whether it did.
    private func finishIfClosed() -> Bool {
        guard let current = session, case .closed(let reason) = current.phase else { return false }
        session = nil
        poll?.cancel()
        poll = nil
        panel.close()
        onClose(reason)
        return true
    }
}
