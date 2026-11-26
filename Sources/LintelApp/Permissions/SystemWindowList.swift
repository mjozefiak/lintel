import AppKit
import CoreGraphics

/// The one place that calls `CGWindowListCopyWindowInfo`. It keeps the owner's process id, the bounds, the layer
/// and the on-screen flag of each window and drops everything else (names included), so the window list leaves
/// this file as `WindowSample` values with nothing identifying inside.
enum SystemWindowList {
    static let settingsBundleID = "com.apple.systempreferences"

    /// The on-screen windows, front to back.
    static func windows() -> [WindowSample] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                let layer = entry[kCGWindowLayer as String] as? Int
            else { return nil }
            let onScreen = (entry[kCGWindowIsOnscreen as String] as? Bool) ?? true
            return WindowSample(ownerPID: pid, bounds: bounds, layer: layer, isOnScreen: onScreen)
        }
    }

    /// The process ids of the running System Settings app.
    @MainActor static func settingsPIDs() -> Set<pid_t> {
        Set(NSRunningApplication.runningApplications(withBundleIdentifier: settingsBundleID).map(\.processIdentifier))
    }

    /// The displays in the same top-left coordinate space as the window bounds.
    @MainActor static func displayFrames() -> [CGRect] {
        NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            else { return nil }
            return CGDisplayBounds(id)
        }
    }
}
