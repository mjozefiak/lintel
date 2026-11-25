import CoreAudio
import Foundation
import LintelSpeech

/// Tells when the system's default input device changes (a Bluetooth headset connecting, a profile switch, a
/// USB microphone plugged in): event-driven through one Core Audio property listener, no polling. It reads
/// nothing about the device and opens nothing. Compiled but never run by tests, which give the session a
/// scripted stream instead.
enum DefaultInputObserver {
    /// A stream that yields once per change until it is cancelled or dropped.
    static func changes() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let listener = Listener(continuation: continuation)
            guard listener.install() else {
                continuation.finish()
                return
            }
            continuation.onTermination = { _ in listener.remove() }
        }
    }

    private final class Listener: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.lintelapp.meetings.default-input", qos: .utility)
        private var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        private var block: AudioObjectPropertyListenerBlock?
        private let continuation: AsyncStream<Void>.Continuation

        init(continuation: AsyncStream<Void>.Continuation) {
            self.continuation = continuation
        }

        func install() -> Bool {
            let continuation = continuation
            let block: AudioObjectPropertyListenerBlock = { _, _ in continuation.yield() }
            guard
                AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
                    == noErr
            else { return false }
            self.block = block
            return true
        }

        func remove() {
            guard let block else { return }
            self.block = nil
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    /// The default input as a log line, for the microphone's diagnostics.
    static func diagnostics() -> String {
        MicrophoneCapture.defaultInputInfo()?.logDescription ?? "none"
    }
}
