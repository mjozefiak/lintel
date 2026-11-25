import LintelKit

/// What "Accessibility is granted" means for Lintel (issue #71), as pure functions so a test covers both
/// callers.
///
/// The state shown in Settings and read by plugins is `AXIsProcessTrusted()`: it is the check the window
/// engine itself passes before it touches another app's windows, so the banner and the work agree.
/// `CGPreflightPostEventAccess()` is the narrower "may post events" check; issue #71 suspects (unconfirmed) that
/// it keeps answering "no" after a grant until a restart, so it no longer decides what the user sees.
nonisolated enum AccessibilityAccess {
    /// The state of the Accessibility permission: granted exactly when the process is trusted.
    static func status(axTrusted: Bool) -> PermissionStatus {
        axTrusted ? .granted : .denied
    }

    /// Whether Command-V may be posted into the previous app. Either answer is enough here. Note that the paste
    /// callers (Clipboard, Dictation) first check `PermissionsReader.status(of: .accessibility)`, which is
    /// Accessibility only, so a Mac that holds only a Post Event grant (a managed profile or an old grant) is
    /// offered copy-only until Accessibility is granted.
    static func canPostEvents(axTrusted: Bool, postEvent: Bool) -> Bool {
        axTrusted || postEvent
    }
}
