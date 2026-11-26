#if DEBUG
import Foundation
import Synchronization

/// DEBUG only: the last line of defence of `--qa` mode. A QA run never records the tester's microphone or taps the
/// system audio: the plugins hand the sessions WAV files or silence instead (`docs/qa.md`). This guard backs that up
/// where the real audio objects are created (the `AVAudioEngine` of `MicrophoneCapture`, the Core Audio process tap
/// and the self-test's tone player): once the app has called `forbid()`, they throw `Forbidden` instead of touching
/// the hardware, so a path the plugins missed fails loudly and shows no recording indicator.
///
/// Process-wide on purpose: it is set once, before any plugin starts, by the QA branch of `LintelMain`, never by
/// a test (tests use fakes and read `isForbidden` only). There is no release-build counterpart.
public enum RealAudioGuard {
    public struct Forbidden: Error, CustomStringConvertible {
        public let source: String
        public var description: String { "Real audio is not allowed in QA mode (\(source))" }
    }

    /// The switch itself, as a type so a test can try it on its own copy instead of flipping the process's.
    public final class Gate: Sendable {
        private let state = Mutex(false)

        public init() {}

        public func forbid() { state.withLock { $0 = true } }

        public var isForbidden: Bool { state.withLock { $0 } }

        public func check(_ source: String) throws {
            if isForbidden { throw Forbidden(source: source) }
        }
    }

    /// The process's gate.
    public static let shared = Gate()

    /// From now on this process never opens a real microphone, system-audio tap or tone player.
    public static func forbid() { shared.forbid() }

    public static var isForbidden: Bool { shared.isForbidden }

    /// Throws `Forbidden` when real audio is forbidden. `source` names the caller for the error text only.
    public static func check(_ source: String) throws { try shared.check(source) }
}
#endif
