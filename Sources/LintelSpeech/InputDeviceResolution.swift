import Foundation

/// The microphone Settings stored (a Core Audio UID) is not always there: a USB microphone that is unplugged,
/// a headset that is off. Recording then goes on with the system's default input and says so, and the stored
/// choice stays, so the next recording uses it again when the device is back.
public struct InputFallback: Equatable, Sendable {
    /// The name of the stored device when it is known (stored with the choice, or read from the UID of a USB
    /// device); `nil` when it is not.
    public let requestedName: String?
    /// The name of the default input that is used instead; `nil` when even that is unknown.
    public let usingName: String?

    public init(requestedName: String?, usingName: String?) {
        self.requestedName = requestedName
        self.usingName = usingName
    }
}

extension InputFallback {
    /// The sentence both HUDs show (meetings and dictation); device names only, never a UID.
    public var message: String {
        switch (requestedName, usingName) {
        case (let requested?, let using?):
            String(
                localized: "Microphone “\(requested)” is unavailable – recording from “\(using)”",
                comment: "HUD notice: the chosen microphone is unplugged, the placeholders are device names")
        case (let requested?, nil):
            String(
                localized: "Microphone “\(requested)” is unavailable – recording from the system input",
                comment: "HUD notice: the chosen microphone is unplugged, the placeholder is its name")
        case (nil, let using?):
            String(
                localized: "The chosen microphone is unavailable – recording from “\(using)”",
                comment: "HUD notice: the chosen microphone is unplugged, the placeholder is the name of the input used"
            )
        case (nil, nil):
            String(
                localized: "The chosen microphone is unavailable – recording from the system input",
                comment: "HUD notice: the chosen microphone is unplugged")
        }
    }
}

/// An input that can tell the session it did not get the device the user chose.
public protocol InputFallbackReporting: AudioInput {
    /// Set while the last `start` used the default input because the chosen device was not available.
    var fallback: InputFallback? { get }
    /// Called when the fallback changes after `start` (the capture moved to the default input because the chosen
    /// device went away, or back to it). `nil` is "no longer a fallback". The default does nothing.
    func setFallbackHandler(_ handler: (@Sendable (InputFallback?) -> Void)?)
}

extension InputFallbackReporting {
    public func setFallbackHandler(_ handler: (@Sendable (InputFallback?) -> Void)?) {}
}

/// Decides which input a capture uses. Pure: the devices that exist are an argument, so it is tested without
/// Core Audio.
public enum InputDeviceResolution: Equatable, Sendable {
    /// No device chosen: the system's input.
    case systemDefault
    /// The chosen device is there.
    case chosen(uid: String)
    /// The chosen device is not there: the system's input is used instead.
    case fallback(InputFallback)

    public static func resolve(
        requestedUID: String?, requestedName: String?, available: [MicrophoneCapture.InputDevice],
        defaultInputName: String?
    ) -> InputDeviceResolution {
        guard let uid = requestedUID, !uid.isEmpty else { return .systemDefault }
        if available.contains(where: { $0.uid == uid }) { return .chosen(uid: uid) }
        return .fallback(
            InputFallback(
                requestedName: requestedName ?? displayName(ofUID: uid), usingName: defaultInputName))
    }

    /// A readable name for a device that is gone, from its UID, when the UID has one: a USB audio device's UID
    /// is `AppleUSBAudioEngine:<vendor>:<product>:<serial>:<n>`. `nil` for any other shape (a Bluetooth address, a
    /// virtual device): the message then does not name it.
    public static func displayName(ofUID uid: String) -> String? {
        let parts = uid.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, parts[0] == "AppleUSBAudioEngine" else { return nil }
        let product = parts[2].trimmingCharacters(in: .whitespaces)
        return product.isEmpty ? nil : product
    }
}
