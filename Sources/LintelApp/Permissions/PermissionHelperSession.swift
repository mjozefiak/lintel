import Foundation

/// When the floating permission helper follows System Settings, where it sits and when it closes (spec
/// 2026-11-24, "Floating helper panel"), as a pure state machine. The panel feeds it what it observed and the
/// current time, and draws what the state says; nothing here touches AppKit, so every rule is tested without a
/// window.
///
/// Time is a `Duration` since an arbitrary start (a monotonic clock reading), so a test steps it by hand.
nonisolated struct PermissionHelperSession: Equatable, Sendable {
    /// How long the helper waits for a System Settings window before it sits beside Lintel's own window.
    static let findWindowTimeout: Duration = .seconds(3)
    /// How long the "Allowed" state stays before the panel closes.
    static let allowedDisplay: Duration = .seconds(1)
    /// The longest the helper stays open without a grant.
    static let lifetime: Duration = .seconds(600)

    /// Where the panel sits.
    enum Placement: Equatable, Sendable {
        /// Waiting for the first sighting of the Settings window (up to `findWindowTimeout`).
        case searching
        /// At the edge of the System Settings window.
        case followingSettings
        /// No Settings window found: next to Lintel's own window, with the same content.
        case besideLintel
    }

    enum CloseReason: Equatable, Sendable {
        /// The permission was granted and the "Allowed" state has been shown.
        case granted
        /// System Settings was running and has quit.
        case settingsQuit
        /// The user pressed Done.
        case done
        /// `lifetime` passed with no grant.
        case timedOut
    }

    enum Phase: Equatable, Sendable {
        case open
        /// The grant was detected at this time; shown for `allowedDisplay`.
        case allowed(since: Duration)
        case closed(CloseReason)
    }

    /// What the panel observed since the last call.
    enum Event: Equatable, Sendable {
        /// Only time passed.
        case tick
        /// The poll found (or did not find) a System Settings window to follow.
        case settingsWindow(found: Bool)
        /// The System Settings app is (not) running.
        case settingsRunning(Bool)
        /// The permission turned out to be granted.
        case granted
        /// The user pressed Done.
        case doneTapped
    }

    let openedAt: Duration
    private(set) var phase: Phase = .open
    private(set) var placement: Placement = .searching
    /// The last time a Settings window was seen, or the open time before the first sighting. A window that is gone
    /// for `findWindowTimeout` moves the panel beside Lintel, and a new sighting moves it back.
    private var lastSeen: Duration
    private var sawSettingsRunning = false

    init(openedAt: Duration) {
        self.openedAt = openedAt
        self.lastSeen = openedAt
    }

    var isClosed: Bool {
        if case .closed = phase { return true }
        return false
    }

    /// True while the panel shows its "Allowed ✓" state.
    var showsAllowed: Bool {
        if case .allowed = phase { return true }
        return false
    }

    /// Applies one observation made at `now`. A closed session ignores everything.
    mutating func apply(_ event: Event, at now: Duration) {
        guard !isClosed else { return }
        switch event {
        case .tick:
            break
        case .settingsWindow(let found):
            if found {
                lastSeen = now
                placement = .followingSettings
            }
        case .settingsRunning(let running):
            if running {
                sawSettingsRunning = true
            } else if sawSettingsRunning {
                // Closing wins over everything but a grant already being shown.
                if !showsAllowed { phase = .closed(.settingsQuit) }
                return
            }
        case .granted:
            if case .open = phase { phase = .allowed(since: now) }
        case .doneTapped:
            phase = .closed(.done)
            return
        }
        advance(to: now)
    }

    /// Time-based rules: the end of the "Allowed" state, the 10-minute limit and the beside-Lintel fallback.
    private mutating func advance(to now: Duration) {
        switch phase {
        case .allowed(let since):
            if now - since >= Self.allowedDisplay { phase = .closed(.granted) }
            return
        case .closed:
            return
        case .open:
            break
        }
        if now - openedAt >= Self.lifetime {
            phase = .closed(.timedOut)
            return
        }
        if now - lastSeen >= Self.findWindowTimeout {
            placement = .besideLintel
        }
    }
}
