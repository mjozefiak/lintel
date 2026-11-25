import AVFoundation
import ApplicationServices
import LintelKit

/// Asks macOS for a permission it can ask for (spec `2026-11-04-lintel-main-window`, D5). The microphone and
/// Accessibility have a system prompt; it is shown on a user click and never otherwise. The other permissions
/// are granted in System Settings, so `request` does nothing for them.
@MainActor
protocol PermissionRequester {
    func request(_ permission: Permission) async
}

/// The real requester: `AVCaptureDevice.requestAccess` for the microphone, and the Accessibility prompt, which
/// adds Lintel to the list with its switch off (spec 2026-11-24, section 3).
struct SystemPermissionRequester: PermissionRequester {
    func request(_ permission: Permission) async {
        switch permission {
        case .microphone:
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .accessibility:
            // `kAXTrustedCheckOptionPrompt` is a mutable global the Swift 6 checker rejects; its value is this
            // string.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .fullDiskAccess, .pasteboard, .systemAudioRecording:
            break
        }
    }
}
