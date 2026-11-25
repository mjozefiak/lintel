import AppKit
import LintelKit
import Observation

/// The shell's one place for permission state and for asking (spec 2026-11-24, section 3).
///
/// - **Live state.** `statuses` is re-read when someone is watching (every `pollInterval`) and when Lintel
///   becomes the active app, so a grant given in System Settings shows without a restart (#71). It is
///   `@Observable`: views that read `status(of:)` redraw on a change. `PermissionsReader` stays pull-only and
///   unchanged; plugins keep reading it when their status is drawn.
/// - **Asking.** `allow(_:)` follows `PermissionGrantPlan`: the system prompt where there is one, then the
///   permission's page in System Settings.
///
/// Watching is reference counted (`beginWatching` / `endWatching`), so the Permissions pane, a banner and the
/// helper panel can each ask for the one-second re-read and it stops when the last one leaves.
@MainActor
@Observable
final class PermissionGrantService {
    static let defaultPollInterval: Duration = .seconds(1)

    /// The last read state of every readable permission.
    private(set) var statuses: [Permission: PermissionStatus] = [:]
    /// Counts the reads that changed something; a plain value for code that cannot observe `statuses`.
    private(set) var changes = 0

    @ObservationIgnored private let reader: any PermissionsReader
    @ObservationIgnored private let requester: any PermissionRequester
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var watchers = 0
    @ObservationIgnored private var poll: Task<Void, Never>?
    @ObservationIgnored private var activationObserver: (any NSObjectProtocol)?
    @ObservationIgnored private let notificationCenter: NotificationCenter?
    /// Called with a permission whose state just changed (for example to refresh a banner).
    @ObservationIgnored var onChange: (Permission, PermissionStatus) -> Void = { _, _ in }

    init(
        reader: any PermissionsReader,
        requester: any PermissionRequester = SystemPermissionRequester(),
        openURL: @escaping (URL) -> Void,
        clock: any Clock<Duration> = ContinuousClock(),
        pollInterval: Duration = defaultPollInterval,
        notificationCenter: NotificationCenter? = NotificationCenter.default
    ) {
        self.reader = reader
        self.requester = requester
        self.openURL = openURL
        self.clock = clock
        self.pollInterval = pollInterval
        self.notificationCenter = notificationCenter
        if let notificationCenter {
            activationObserver = notificationCenter.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { _ = self?.refresh() }
            }
        }
        // No read here: models built for one banner redraw create a service each, and `status(of:)` reads on demand.
        // The first `refresh()` (the pane appearing, an activation, `beginWatching()`) fills `statuses`.
    }

    isolated deinit {
        poll?.cancel()
        if let activationObserver { notificationCenter?.removeObserver(activationObserver) }
    }

    /// The state of `permission`: the last read, or a fresh read of a readable one that was never read.
    func status(of permission: Permission) -> PermissionStatus {
        statuses[permission] ?? (permission.isReadable ? reader.status(of: permission) : .notDetermined)
    }

    /// Re-reads every readable permission. Returns the permissions whose state changed.
    @discardableResult
    func refresh() -> [Permission] {
        var result: [Permission: PermissionStatus] = [:]
        for permission in Permission.allCases where permission.isReadable {
            result[permission] = reader.status(of: permission)
        }
        let changed = result.filter { statuses[$0.key] != $0.value }.map(\.key)
        guard !changed.isEmpty else { return [] }
        let first = statuses.isEmpty
        statuses = result
        changes += 1
        // The first read has nothing to compare with; it is not a change.
        if !first {
            for permission in Permission.allCases where changed.contains(permission) {
                if let status = result[permission] { onChange(permission, status) }
            }
        }
        return first ? [] : changed
    }

    /// Starts the one-second re-read, or joins it when it already runs. Pair with `endWatching()`.
    func beginWatching() {
        watchers += 1
        guard poll == nil else { return }
        refresh()
        let clock = clock
        let interval = pollInterval
        poll = Task { [weak self] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: interval) } catch { return }
                guard let self else { return }
                self.refresh()
                self.ticks += 1
            }
        }
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        poll?.cancel()
        poll = nil
    }

    var isWatching: Bool { poll != nil }

    /// How many poll reads have run (tests wait on it).
    @ObservationIgnored private(set) var ticks = 0

    /// "Allow": asks the system where it can, opens the permission's page when that is still needed, and reads
    /// the states again. Always the user's click; nothing calls this on its own.
    func allow(_ permission: Permission) async {
        let plan = PermissionGrantPlan.plan(for: permission, status: status(of: permission))
        if plan.asksSystem { await requester.request(permission) }
        refresh()
        if plan.opensSettings, !(permission.isReadable && status(of: permission) == .granted) {
            openURL(permission.settingsURL)
        }
    }

    /// Opens the permission's page without asking the system first.
    func openSettings(for permission: Permission) {
        openURL(permission.settingsURL)
    }
}
