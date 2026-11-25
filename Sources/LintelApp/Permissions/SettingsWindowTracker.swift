import CoreGraphics
import Foundation

/// What Lintel reads about one on-screen window: the owner's process id, the bounds, the layer and whether it is
/// on screen. Never a title or the name of another app (spec 2026-11-24, Risks: Window reading), so no Screen
/// Recording permission is involved.
nonisolated struct WindowSample: Equatable, Sendable {
    let ownerPID: pid_t
    /// In `CGWindowListCopyWindowInfo` coordinates: the origin is the top left of the main display.
    let bounds: CGRect
    let layer: Int
    let isOnScreen: Bool
}

/// Finds the System Settings window the permission helper panel follows. Pure geometry: it gets the window
/// list and returns a frame, so the polling and the system call stay outside and the rules are tested with
/// fixture lists.
nonisolated enum SettingsWindowTracker {
    /// Smaller than this is a sheet, a popover or a stray helper window, not the Settings window.
    static let minimumSize = CGSize(width: 300, height: 300)

    /// The frame of the System Settings window to follow, or `nil` when there is none.
    ///
    /// `windows` is front to back, as the system returns it. A candidate belongs to `settingsPIDs`, is a normal
    /// window (layer 0), is on screen, is large enough, and overlaps one of `displays`. The first candidate wins,
    /// which is the front-most one: after the deep link switches Settings to another pane, that is the window
    /// the user is looking at.
    static func frame(in windows: [WindowSample], settingsPIDs: Set<pid_t>, displays: [CGRect]) -> CGRect? {
        windows.first { window in
            settingsPIDs.contains(window.ownerPID) && window.layer == 0 && window.isOnScreen
                && window.bounds.width >= minimumSize.width && window.bounds.height >= minimumSize.height
                && displays.contains { $0.intersects(window.bounds) }
        }?.bounds
    }
}
